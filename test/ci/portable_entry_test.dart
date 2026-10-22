import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `lib/okf.dart` promises the APIs without `dart:io`, so web and other
/// non-native hosts can use them.
///
/// `dart compile js` alone does not hold it to that: dart2js accepts a
/// `dart:io` import and stubs it out, deferring the failure to run time. The
/// compile keeps the portable graph compilable; the import walk is what fails
/// when that graph reaches a native library.
void main() {
  test('okf.dart compiles to JavaScript', () async {
    final output = await Directory.systemTemp.createTemp('okf-portable-');
    addTearDown(() => output.delete(recursive: true));

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'compile',
      'js',
      '--output=${p.join(output.path, 'portable_entry.js')}',
      p.join('test', 'support', 'portable_entry.dart'),
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('okf.dart never reaches a native library', () {
    expect(
      _nativeReaches(_reachableExternalLibraries('lib/okf.dart')),
      isEmpty,
      reason: 'move native code behind lib/okf_io.dart instead',
    );
  });

  test('the import walk detects the native libraries okf_io.dart uses', () {
    // If this stops holding, the walk above is no longer proving anything.
    expect(
      _nativeReaches(_reachableExternalLibraries('lib/okf_io.dart')),
      containsAll(<String>['dart:io', 'package:mcp_dart/mcp_dart.dart']),
    );
  });
}

const String _ownPackage = 'package:okf/';

final RegExp _directive = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Every `dart:` library and third-party `package:` URI reachable from
/// [entryPoint] through this package's own import and export directives.
Set<String> _reachableExternalLibraries(String entryPoint) {
  final external = <String>{};
  final visited = <String>{};
  final queue = <String>[p.normalize(entryPoint)];

  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!visited.add(current)) {
      continue;
    }
    final source = File(current).readAsStringSync();
    for (final match in _directive.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith(_ownPackage)) {
        queue.add(
          p.normalize(p.join('lib', uri.substring(_ownPackage.length))),
        );
      } else if (uri.contains(':')) {
        external.add(uri);
      } else {
        queue.add(p.normalize(p.join(p.dirname(current), uri)));
      }
    }
  }
  return external;
}

Set<String> _nativeReaches(Set<String> libraries) => <String>{
  for (final uri in libraries)
    if (const <String>{
          'dart:ffi',
          'dart:io',
          'dart:isolate',
          'dart:mirrors',
        }.contains(uri) ||
        uri.startsWith('package:mcp_dart/'))
      uri,
};
