import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:okf/src/cli.dart';
import 'package:path/path.dart' as p;

/// Writes a concept document at [relativePath] under [root].
///
/// [frontmatter] holds extra YAML lines appended to the generated block.
Future<void> writeConcept(
  Directory root,
  String relativePath, {
  bool includeType = true,
  String type = 'Reference',
  String title = 'Alpha',
  String body = '# Alpha',
  List<String> frontmatter = const <String>[],
}) => writeBundleFile(
  root,
  relativePath,
  <String>[
    '---',
    if (includeType) 'type: $type',
    'title: $title',
    ...frontmatter,
    '---',
    '',
    body,
    '',
  ].join('\n'),
);

/// Writes [content] at the bundle-relative [relativePath] under [root].
Future<void> writeBundleFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = _bundleFile(root, relativePath);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

/// Reads the bundle-relative [relativePath] under [root].
Future<String> readBundleFile(Directory root, String relativePath) =>
    _bundleFile(root, relativePath).readAsString();

/// Resolves a bundle-relative POSIX path against [root] for this platform.
File _bundleFile(Directory root, String relativePath) =>
    File(p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]));

/// Reads every bundle file under [root], keyed by bundle-relative path.
///
/// Comparing two snapshots is how a test proves a refused write left the
/// bundle untouched. Coordination metadata is excluded.
Future<Map<String, String>> snapshotBundle(Directory root) async {
  final files = <String, String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relativePath = p.relative(entity.path, from: root.path);
    if (entity is File && p.basename(relativePath) != okfBundleLockFileName) {
      files[relativePath] = await entity.readAsString();
    }
  }
  return files;
}

/// Runs the CLI in process and collects its streams.
Future<CliResult> runCli(
  List<String> arguments,
  String workingDirectory,
) async {
  final output = <String>[];
  final errors = <String>[];
  final exitCode = await runOkfCli(
    arguments,
    workingDirectory: workingDirectory,
    out: output.add,
    err: errors.add,
  );
  return CliResult(exitCode, output.join('\n'), errors.join('\n'));
}

/// One completed CLI invocation.
final class CliResult {
  /// Creates a result from the streams a CLI run produced.
  const CliResult(this.exitCode, this.stdout, this.stderr);

  /// The process exit code the run returned.
  final int exitCode;

  /// Every standard output line, joined by newlines.
  final String stdout;

  /// Every standard error line, joined by newlines.
  final String stderr;
}

/// Whether [left] and [right] are the same YAML data: mappings compare
/// without regard to key order, an integer never equals a double, and NaN
/// equals NaN.
///
/// Stricter than `equals`, which takes `1` for `1.0`, so tests use it where
/// they check that written frontmatter reads back as the requested values.
bool sameYamlData(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in left.entries) {
      final matches = right.keys.where((other) => sameYamlData(key, other));
      if (matches.length != 1 || !sameYamlData(value, right[matches.single])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!sameYamlData(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is double && right is double && left.isNaN && right.isNaN) {
    return true;
  }
  if (left is num && right is num) {
    return left == right && (left is int) == (right is int);
  }
  return left == right;
}
