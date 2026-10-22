import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../bundle_path.dart';
import '../document.dart';
import '../utf8_text.dart';
import '../yaml_emitter.dart';
import 'bundle_lock.dart';

/// The outcome of writing or checking a set of bundle files.
final class OkfWriteResult {
  OkfWriteResult(Iterable<String> changedPaths)
    : changedPaths = List<String>.unmodifiable(changedPaths);

  /// Paths whose desired content differed from the filesystem.
  final List<String> changedPaths;

  /// Whether at least one file differed.
  bool get hasChanges => changedPaths.isNotEmpty;
}

/// A write failed and one or more compensating filesystem operations failed.
final class OkfWriteRollbackException implements Exception {
  /// Creates a rollback failure that retains both the write and recovery
  /// errors.
  OkfWriteRollbackException({
    required this.writeError,
    required Iterable<Object> rollbackErrors,
  }) : rollbackErrors = List<Object>.unmodifiable(rollbackErrors);

  /// The error that interrupted the original write.
  final Object writeError;

  /// Errors encountered while restoring files and directories.
  final List<Object> rollbackErrors;

  @override
  String toString() =>
      'OkfWriteRollbackException: $writeError; rollback errors: '
      '${rollbackErrors.join('; ')}';
}

/// Writes files beneath an explicit OKF bundle root.
///
/// Each file uses a temporary sibling followed by the strongest replacement
/// operation available on the platform. A multi-file call is not
/// transactional, and replacement does not promise to preserve filesystem
/// metadata such as modes, ACLs, or extended attributes. Existing symbolic
/// links in the destination path are rejected. These checks assume the bundle
/// is not being concurrently replaced by an adversarial process.
///
/// Files are written as UTF-8, so [writeAll] refuses a text that holds an
/// unpaired surrogate, which UTF-8 cannot encode, and [writeDocument] refuses
/// frontmatter that holds one.
final class OkfBundleWriter {
  /// Creates a bundle writer.
  const OkfBundleWriter();

  /// Serializes and writes [document] beneath [rootPath].
  ///
  /// Frontmatter the YAML emitter cannot represent, such as a string that
  /// holds an unpaired surrogate, fails with [OkfYamlEncodeException] before
  /// the filesystem is touched.
  Future<OkfWriteResult> writeDocument(
    String rootPath,
    String relativePath,
    OkfDocument document, {
    bool checkOnly = false,
  }) async => writeAll(rootPath, <String, String>{
    relativePath: document.serialize(),
  }, checkOnly: checkOnly);

  /// Writes all [files], keyed by bundle-relative path.
  ///
  /// When [checkOnly] is true the filesystem is not changed; the returned
  /// paths identify files that would be written.
  ///
  /// [expectedSources] maps paths to the text the caller read. A mismatch fails
  /// the call instead of writing or reporting against stale content.
  ///
  /// In both modes, an invalid or repeated path, or a text that holds an
  /// unpaired surrogate, throws [ArgumentError] before the filesystem is
  /// touched.
  Future<OkfWriteResult> writeAll(
    String rootPath,
    Map<String, String> files, {
    bool checkOnly = false,
    Map<String, String> expectedSources = const <String, String>{},
  }) async {
    final normalizedFiles = _normalizeFiles(files);
    if (checkOnly) {
      final root = await _validatedRoot(rootPath, createIfMissing: false);
      return _writeAll(root, normalizedFiles, expectedSources, checkOnly: true);
    }
    await _createRoot(rootPath);
    return OkfBundleLock.write(rootPath, () async {
      final root = await _validatedRoot(rootPath, createIfMissing: true);
      return _writeAll(
        root,
        normalizedFiles,
        expectedSources,
        checkOnly: false,
      );
    });
  }

  Future<OkfWriteResult> _writeAllTransactionally(
    String rootPath,
    Map<String, String> files,
  ) async {
    final normalizedFiles = _normalizeFiles(files);
    final root = await _validatedRoot(rootPath, createIfMissing: true);
    final captured = await _capture(root, normalizedFiles.keys);
    final staged = <_StagedFile>[];
    var applying = false;

    try {
      for (final entry in normalizedFiles.entries) {
        final destination = File(_destinationPath(root, entry.key));
        await _rejectLinks(root, entry.key);
        final desiredBytes = utf8.encode(entry.value);
        final currentBytes = await destination.exists()
            ? await destination.readAsBytes()
            : null;
        if (_bytesEqual(currentBytes, desiredBytes)) {
          continue;
        }

        await destination.parent.create(recursive: true);
        await _rejectLinks(root, entry.key);
        staged.add(
          _StagedFile(
            path: entry.key,
            destination: destination,
            temporary: await _stageWrite(destination, desiredBytes),
          ),
        );
      }

      applying = true;
      for (final file in staged) {
        await _rejectLinks(root, file.path);
        await _replace(file.temporary, file.destination);
      }
      return OkfWriteResult(staged.map((file) => file.path));
    } catch (error, stackTrace) {
      final rollbackErrors = <Object>[
        ...await _discardStaged(staged),
        if (applying)
          ...await _restore(root, captured)
        else
          ...await _removeAbsentDirectories(root, captured.absentDirectories),
      ];
      if (rollbackErrors.isNotEmpty) {
        Error.throwWithStackTrace(
          OkfWriteRollbackException(
            writeError: error,
            rollbackErrors: rollbackErrors,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  SplayTreeMap<String, String> _normalizeFiles(Map<String, String> files) {
    final normalizedFiles = SplayTreeMap<String, String>();
    for (final entry in files.entries) {
      final relativePath = _validateRelativePath(entry.key);
      if (normalizedFiles.containsKey(relativePath)) {
        throw ArgumentError.value(
          entry.key,
          'files',
          'Duplicate bundle path: $relativePath',
        );
      }
      // utf8.encode would write U+FFFD in its place, so the bytes on disk
      // would not be the text the caller passed or validated.
      if (hasUnpairedSurrogate(entry.value)) {
        throw ArgumentError.value(
          entry.key,
          'files',
          'Bundle path $relativePath holds an unpaired surrogate, which UTF-8 '
              'cannot encode',
        );
      }
      normalizedFiles[relativePath] = entry.value;
    }
    return normalizedFiles;
  }

  Future<OkfWriteResult> _writeAll(
    Directory root,
    SplayTreeMap<String, String> normalizedFiles,
    Map<String, String> expectedSources, {
    required bool checkOnly,
  }) async {
    final changed = <String>[];
    for (final entry in normalizedFiles.entries) {
      final destination = File(
        p.joinAll(<String>[root.path, ...p.posix.split(entry.key)]),
      );
      await _rejectLinks(root, entry.key);

      final desiredBytes = utf8.encode(entry.value);
      final currentBytes = await destination.exists()
          ? await destination.readAsBytes()
          : null;
      final expected = expectedSources[entry.key];
      if (expected != null &&
          !_bytesEqual(currentBytes, utf8.encode(expected))) {
        throw FileSystemException(
          'File changed after it was read; re-run the command',
          destination.path,
        );
      }
      if (_bytesEqual(currentBytes, desiredBytes)) {
        continue;
      }

      changed.add(entry.key);
      if (!checkOnly) {
        await destination.parent.create(recursive: true);
        await _rejectLinks(root, entry.key);
        await _atomicWrite(destination, desiredBytes);
      }
    }

    return OkfWriteResult(changed);
  }

  Future<_CapturedFiles> _capture(
    Directory root,
    Iterable<String> paths,
  ) async {
    final files = <String, List<int>?>{};
    final absentDirectories = <String>{};

    for (final path in paths) {
      await _rejectLinks(root, path);
      final destination = File(_destinationPath(root, path));
      files[path] = await destination.exists()
          ? await destination.readAsBytes()
          : null;

      var directory = p.posix.dirname(path);
      while (directory != '.') {
        final local = Directory(_destinationPath(root, directory));
        final type = await FileSystemEntity.type(
          local.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          absentDirectories.add(directory);
        }
        directory = p.posix.dirname(directory);
      }
    }

    return _CapturedFiles(files: files, absentDirectories: absentDirectories);
  }

  Future<List<Object>> _restore(Directory root, _CapturedFiles captured) async {
    final errors = <Object>[];

    for (final entry in captured.files.entries.toList().reversed) {
      try {
        await _rejectLinks(root, entry.key);
        final destination = File(_destinationPath(root, entry.key));
        final original = entry.value;
        if (original == null) {
          if (await destination.exists()) {
            await destination.delete();
          }
        } else {
          await destination.parent.create(recursive: true);
          await _rejectLinks(root, entry.key);
          await _atomicWrite(destination, original);
        }
      } catch (error) {
        errors.add(error);
      }
    }

    errors.addAll(
      await _removeAbsentDirectories(root, captured.absentDirectories),
    );

    return errors;
  }

  Future<List<Object>> _removeAbsentDirectories(
    Directory root,
    Set<String> absentDirectories,
  ) async {
    final errors = <Object>[];
    final directories = absentDirectories.toList()
      ..sort((left, right) => _pathDepth(right).compareTo(_pathDepth(left)));
    for (final path in directories) {
      try {
        final directory = Directory(_destinationPath(root, path));
        if (await directory.exists() && await directory.list().isEmpty) {
          await directory.delete();
        }
      } catch (error) {
        errors.add(error);
      }
    }

    return errors;
  }

  Future<List<Object>> _discardStaged(List<_StagedFile> staged) async {
    final errors = <Object>[];
    for (final file in staged) {
      try {
        if (await file.temporary.exists()) {
          await file.temporary.delete();
        }
      } catch (error) {
        errors.add(error);
      }
    }
    return errors;
  }

  Future<Directory> _validatedRoot(
    String rootPath, {
    required bool createIfMissing,
  }) async {
    if (rootPath.trim().isEmpty) {
      throw const FileSystemException('Bundle root must not be empty');
    }

    final root = Directory(p.normalize(p.absolute(rootPath)));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'Bundle root must not be a symbolic link',
        root.path,
      );
    }
    if (type == FileSystemEntityType.notFound) {
      if (createIfMissing) {
        await root.create(recursive: true);
      }
    } else if (type != FileSystemEntityType.directory) {
      throw FileSystemException('Bundle root is not a directory', root.path);
    }
    return root;
  }

  Future<void> _rejectLinks(Directory root, String relativePath) async {
    var currentPath = root.path;
    for (final segment in p.posix.split(relativePath)) {
      currentPath = p.join(currentPath, segment);
      final type = await FileSystemEntity.type(currentPath, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'Refusing to write through a symbolic link',
          currentPath,
        );
      }
    }
  }

  Future<void> _atomicWrite(File destination, List<int> bytes) async {
    final temporary = await _stageWrite(destination, bytes);
    try {
      await _replace(temporary, destination);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<File> _stageWrite(File destination, List<int> bytes) async {
    final random = Random.secure();
    File? temporary;
    for (var attempt = 0; attempt < 16; attempt++) {
      final suffix =
          '${pid.toRadixString(16)}-${random.nextInt(1 << 32).toRadixString(16)}';
      final candidate = File(
        p.join(
          destination.parent.path,
          '.${p.basename(destination.path)}.okf-$suffix.tmp',
        ),
      );
      try {
        await candidate.create(exclusive: true);
        temporary = candidate;
        break;
      } on FileSystemException {
        // A colliding temporary name is harmless; try another one.
      }
    }
    if (temporary == null) {
      throw FileSystemException(
        'Could not allocate a temporary file',
        destination.path,
      );
    }

    try {
      final sink = temporary.openWrite(mode: FileMode.writeOnly);
      sink.add(bytes);
      await sink.flush();
      await sink.close();
      return temporary;
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  Future<void> _replace(File temporary, File destination) async {
    try {
      await temporary.rename(destination.path);
      return;
    } on FileSystemException {
      if (!await destination.exists()) {
        rethrow;
      }
    }

    final backup = File('${destination.path}.okf-${pid.toRadixString(16)}.bak');
    if (await backup.exists()) {
      throw FileSystemException(
        'Could not allocate a replacement backup',
        backup.path,
      );
    }

    await destination.rename(backup.path);
    try {
      await temporary.rename(destination.path);
      await backup.delete();
    } on FileSystemException {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    } finally {
      if (await backup.exists() && await destination.exists()) {
        await backup.delete();
      }
    }
  }
}

/// Creates a missing bundle root before its in-bundle lock is opened.
Future<void> _createRoot(String rootPath) async {
  if (rootPath.trim().isEmpty) {
    throw const FileSystemException('Bundle root must not be empty');
  }
  final root = Directory(p.normalize(p.absolute(rootPath)));
  if (await FileSystemEntity.type(root.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    await root.create(recursive: true);
  }
}

/// Package-internal transaction boundary used by the prepared write path.
///
/// Kept out of the public IO library so rollback-backed multi-file writes
/// cannot bypass prospective validation. Every payload is checked, as
/// [OkfBundleWriter.writeAll] checks it, and staged before the first
/// destination is replaced.
final class OkfBundleWriteTransaction {
  const OkfBundleWriteTransaction();

  Future<OkfWriteResult> writeAll(String rootPath, Map<String, String> files) =>
      const OkfBundleWriter()._writeAllTransactionally(rootPath, files);
}

final class _CapturedFiles {
  const _CapturedFiles({required this.files, required this.absentDirectories});

  final Map<String, List<int>?> files;
  final Set<String> absentDirectories;
}

final class _StagedFile {
  const _StagedFile({
    required this.path,
    required this.destination,
    required this.temporary,
  });

  final String path;
  final File destination;
  final File temporary;
}

String _destinationPath(Directory root, String relativePath) =>
    p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]);

int _pathDepth(String path) => p.posix.split(path).length;

String _validateRelativePath(String value) {
  if (p.windows.isAbsolute(value)) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Path must be a non-empty relative POSIX path',
    );
  }
  try {
    return validateBundlePath(value);
  } on FormatException catch (error) {
    throw ArgumentError.value(value, 'relativePath', error.message);
  }
}

bool _bytesEqual(List<int>? left, List<int> right) {
  if (left == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
