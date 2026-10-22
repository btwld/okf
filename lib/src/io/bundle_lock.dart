import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The reserved coordination file at a bundle root.
///
/// Bundle inventories exclude this file.
const String okfBundleLockFileName = '.okf.lock';

/// Coordinates bundle operations within one isolate and across processes.
///
/// An isolate-local FIFO queue prevents local operations from interleaving.
/// Processes coordinate through an advisory lock on `<root>/.okf.lock`:
/// [read] takes a shared lock and [write] takes an exclusive lock. Keeping the
/// file inside the bundle gives every process the same path and does not
/// require write access to the bundle's parent directory.
///
/// The loader, writer and change applier already take these claims; callers
/// use them directly to run their own reads or writes under the same lock.
/// Claims nest: an action may run further operations on the same bundle, and
/// a shared claim cannot be upgraded to an exclusive one. A claim is carried
/// by the action's zone, so await every bundle operation inside the action:
/// work that outlives it, such as an unawaited future, a timer or a stream
/// listener, still counts as holding the claim, so it skips the queue while
/// no lock is held.
///
/// On POSIX the lock is an `fcntl` record lock, which belongs to the process
/// rather than to an isolate. Isolates in one process do not exclude each
/// other, and closing any descriptor of the lock file releases every claim
/// the process holds on it, so a read finishing in one isolate can silently
/// drop a write's lock in another. Run every operation on a bundle in one
/// isolate per process.
///
/// A missing or invalid root is left for the operation itself to report.
final class OkfBundleLock {
  OkfBundleLock._();

  static final Map<String, Future<void>> _tails = <String, Future<void>>{};
  static final Object _zoneKey = Object();

  /// Runs [action] with a shared claim on the bundle at [rootPath].
  ///
  /// [action] must be safe to repeat: it runs again under a shared lock if the
  /// first writer creates the lock file during an initially unlocked read.
  static Future<T> read<T>(String rootPath, Future<T> Function() action) =>
      _synchronized(rootPath, action, exclusive: false);

  /// Runs [action] with an exclusive claim on the bundle at [rootPath].
  static Future<T> write<T>(String rootPath, Future<T> Function() action) =>
      _synchronized(rootPath, action, exclusive: true);

  static Future<T> _synchronized<T>(
    String rootPath,
    Future<T> Function() action, {
    required bool exclusive,
  }) async {
    final root = await _canonicalRoot(rootPath);
    final held = Zone.current[_zoneKey];
    if (held is _HeldClaim && held.key == root.key) {
      if (exclusive && !held.exclusive) {
        throw StateError(
          'A shared bundle claim cannot be upgraded to an exclusive one: '
          '${root.path}',
        );
      }
      return action();
    }

    final previous = _tails[root.key] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _tails[root.key] = tail;

    await previous;
    _HeldLock? lock;
    try {
      lock = await _acquire(root.path, exclusive: exclusive);
      Future<T> runAction() => runZoned(
        action,
        zoneValues: <Object, Object>{
          _zoneKey: _HeldClaim(key: root.key, exclusive: exclusive),
        },
      );
      if (exclusive || lock != null) {
        return await runAction();
      }

      // Reads stay non-mutating. If the first writer creates the lock while
      // this action runs, acquire it and repeat the action.
      late T result;
      try {
        result = await runAction();
      } catch (error, stackTrace) {
        lock = await _acquire(root.path, exclusive: false);
        if (lock != null) {
          return await runAction();
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      lock = await _acquire(root.path, exclusive: false);
      return lock == null ? result : await runAction();
    } finally {
      try {
        await lock?.release();
      } finally {
        release.complete();
        if (identical(_tails[root.key], tail)) {
          unawaited(_tails.remove(root.key));
        }
      }
    }
  }
}

Future<_HeldLock?> _acquire(String rootPath, {required bool exclusive}) async {
  if (await FileSystemEntity.type(rootPath, followLinks: false) !=
      FileSystemEntityType.directory) {
    return null;
  }

  final path = p.join(rootPath, okfBundleLockFileName);
  final initialType = await FileSystemEntity.type(path, followLinks: false);
  if (initialType == FileSystemEntityType.link) {
    throw FileSystemException('Bundle lock must not be a symbolic link', path);
  }
  if (initialType != FileSystemEntityType.notFound &&
      initialType != FileSystemEntityType.file) {
    throw FileSystemException('Bundle lock must be a regular file', path);
  }

  final RandomAccessFile file;
  try {
    file = await File(
      path,
    ).open(mode: exclusive ? FileMode.append : FileMode.read);
  } on FileSystemException catch (error) {
    if (!exclusive &&
        initialType == FileSystemEntityType.notFound &&
        await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.notFound) {
      return null;
    }
    throw FileSystemException(
      'Could not lock the bundle for '
      '${exclusive ? 'writing' : 'reading'}: ${error.message}',
      rootPath,
      error.osError,
    );
  }

  try {
    await file.lock(
      exclusive ? FileLock.blockingExclusive : FileLock.blockingShared,
    );
  } catch (_) {
    await file.close();
    rethrow;
  }
  return _HeldLock(file);
}

final class _HeldLock {
  _HeldLock(this._file);

  final RandomAccessFile _file;

  Future<void> release() async {
    try {
      await _file.unlock();
    } finally {
      await _file.close();
    }
  }
}

final class _HeldClaim {
  const _HeldClaim({required this.key, required this.exclusive});

  final String key;
  final bool exclusive;
}

/// The real directory a bundle path denotes, plus its comparison key.
///
/// [path] locates the lock file and must stay case-exact. [key] identifies the
/// in-isolate queue and is case-folded where the filesystem is.
Future<({String path, String key})> _canonicalRoot(String rootPath) async {
  final normalized = p.normalize(p.absolute(rootPath));
  var existingPath = normalized;
  final missingSegments = <String>[];
  while (await FileSystemEntity.type(existingPath) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(existingPath);
    if (parent == existingPath) {
      break;
    }
    missingSegments.insert(0, p.basename(existingPath));
    existingPath = parent;
  }

  final resolved = await Directory(existingPath).resolveSymbolicLinks();
  final canonical = missingSegments.isEmpty
      ? resolved
      : p.joinAll(<String>[resolved, ...missingSegments]);
  return (
    path: canonical,
    key: Platform.isWindows ? canonical.toLowerCase() : canonical,
  );
}
