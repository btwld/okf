// Compiling to JavaScript can outlast the default 30-second timeout.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `lib/okf.dart` promises the APIs without `dart:io`, so web and other
/// non-native hosts can use them.
///
/// `dart compile js` alone does not hold it to that: dart2js accepts a
/// `dart:io` import and stubs it out, deferring the failure to run time. The
/// compile keeps the portable graph compilable and, where `node` is available,
/// the run catches a stub reached at run time; the import walk is what fails
/// whenever that graph reaches a native library.
void main() {
  group('test/support/portable_entry.dart', () {
    late String script;
    late ProcessResult compile;

    setUpAll(() async {
      final output = await Directory.systemTemp.createTemp('okf-portable-');
      addTearDown(() => output.delete(recursive: true));
      script = p.join(output.path, 'portable_entry.js');
      compile = await Process.run(Platform.resolvedExecutable, <String>[
        'compile',
        'js',
        '--output=$script',
        p.join('test', 'support', 'portable_entry.dart'),
      ]);
    });

    test('compiles to JavaScript', () {
      final output = '${compile.stdout}${compile.stderr}';
      expect(compile.exitCode, 0, reason: output);
    });

    test('runs as JavaScript', () async {
      expect(compile.exitCode, 0, reason: 'the compile failed');
      final run = await Process.run('node', <String>[script]);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
    }, skip: _hasNode ? false : 'node is not on PATH');
  });

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

  test('the import walk follows every URI of a conditional import', () {
    expect(
      _directiveUris('''
import 'package:path/path.dart' as p;
import 'src/portable.dart'
    if (dart.library.io) 'src/native.dart'
    if (dart.library.js_interop) "src/web.dart";
export 'src/stub.dart' if (dart.library.io) 'src/io.dart' show Thing;
'''),
      <String>[
        'package:path/path.dart',
        'src/portable.dart',
        'src/native.dart',
        'src/web.dart',
        'src/stub.dart',
        'src/io.dart',
      ],
    );
  });
}

final bool _hasNode = () {
  try {
    return Process.runSync('node', const <String>['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

const String _ownPackage = 'package:okf/';

/// An import or export directive: its URI, then the URIs a configurable
/// directive adds with `if (condition) 'uri'`.
final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]((?:\s*if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);

final RegExp _conditionalUri = RegExp(r'''if\s*\([^)]*\)\s*['"]([^'"]+)['"]''');

/// Every URI the import and export directives of [source] name, in order.
List<String> _directiveUris(String source) => <String>[
  for (final match in _directive.allMatches(source)) ...<String>[
    match.group(1)!,
    for (final condition in _conditionalUri.allMatches(match.group(2)!))
      condition.group(1)!,
  ],
];

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
    for (final uri in _directiveUris(File(current).readAsStringSync())) {
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
