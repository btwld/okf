import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

void main() {
  late Directory sandbox;
  late Directory bundle;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('okf-cli-test-');
    bundle = await Directory(p.join(sandbox.path, 'bundle')).create();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('shows help and version', () async {
    final help = await runCli(<String>['--help'], sandbox.path);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('Usage: okf <command>'));

    final commandHelp = await runCli(<String>[
      'validate',
      '--help',
    ], sandbox.path);
    expect(commandHelp.exitCode, 0);
    expect(commandHelp.stdout, contains('Usage: okf validate <bundle>'));

    final version = await runCli(<String>['--version'], sandbox.path);
    expect(version.exitCode, 0);
    expect(version.stdout, 'okf $okfVersion');

    final pubspec =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(okfVersion, pubspec['version']);
  });

  test('usage and filesystem errors return exit code 2', () async {
    final missingCommand = await runCli(const <String>[], sandbox.path);
    expect(missingCommand.exitCode, 2);
    expect(missingCommand.stderr, contains('A command is required'));

    final extraOperand = await runCli(<String>[
      'validate',
      'one',
      'two',
    ], sandbox.path);
    expect(extraOperand.exitCode, 2);
    expect(extraOperand.stderr, contains('exactly one'));

    final missingBundle = await runCli(<String>[
      'validate',
      'missing',
    ], sandbox.path);
    expect(missingBundle.exitCode, 2);
    expect(missingBundle.stderr, contains('not a directory'));
  });

  test('validation works on a bundle nothing may be written beside', () async {
    if (Platform.isWindows) {
      return;
    }
    final readOnlyParent = await Directory(
      p.join(sandbox.path, 'read-only'),
    ).create();
    final readOnlyBundle = await Directory(
      p.join(readOnlyParent.path, 'bundle'),
    ).create();

    final restricted = await Process.run('chmod', <String>[
      '0555',
      readOnlyParent.path,
    ]);
    expect(restricted.exitCode, 0, reason: '${restricted.stderr}');
    late final CliResult result;
    try {
      result = await runCli(<String>[
        'validate',
        readOnlyBundle.path,
      ], sandbox.path);
    } finally {
      final restored = await Process.run('chmod', <String>[
        '0755',
        readOnlyParent.path,
      ]);
      expect(restored.exitCode, 0, reason: '${restored.stderr}');
    }

    expect(result.exitCode, 0, reason: result.stderr);
    expect(
      await Directory(readOnlyParent.path).list().toList(),
      hasLength(1),
      reason: 'no coordination file may appear beside the bundle',
    );
  });

  test('validation works on a bundle that cannot be written at all', () async {
    if (Platform.isWindows) {
      return;
    }
    await writeConcept(bundle, 'alpha.md');
    final restricted = await Process.run('chmod', <String>[
      '0555',
      bundle.path,
    ]);
    expect(restricted.exitCode, 0, reason: '${restricted.stderr}');
    late final CliResult result;
    try {
      result = await runCli(<String>['validate', 'bundle'], sandbox.path);
    } finally {
      final restored = await Process.run('chmod', <String>[
        '0755',
        bundle.path,
      ]);
      expect(restored.exitCode, 0, reason: '${restored.stderr}');
    }

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('1 concept(s) validated'));
  });

  test('validates bundles in text and JSON formats', () async {
    await writeConcept(bundle, 'alpha.md');

    final text = await runCli(<String>['validate', 'bundle'], sandbox.path);
    expect(text.exitCode, 0);
    expect(text.stdout, 'OK: 1 concept(s) validated.');

    final json = await runCli(<String>[
      'validate',
      'bundle',
      '--output=json',
    ], sandbox.path);
    final payload = jsonDecode(json.stdout) as Map<String, Object?>;
    expect(json.exitCode, 0);
    expect(payload['findings'], isEmpty);
    expect(payload.keys, <String>{'findings'});
  });

  test('reports conformance and load failures with exit code 1', () async {
    await writeConcept(bundle, 'missing_type.md', includeType: false);
    await File(
      p.join(bundle.path, 'empty_type.md'),
    ).writeAsString('---\ntype: ""\n---\n');
    await File(
      p.join(bundle.path, 'broken.md'),
    ).writeAsString('---\ntype: Reference\nbroken: [\n');

    final result = await runCli(<String>[
      'validate',
      'bundle',
      '--output=json',
    ], sandbox.path);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final findings = (payload['findings']! as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(result.exitCode, 1);
    expect(
      (findings.singleWhere(
            (item) => item['id'] == 'okf/invalid-document',
          )['location']!
          as Map<String, Object?>)['line'],
      isNotNull,
    );
    expect(
      findings.map((item) => item['id']),
      orderedEquals(<String>[
        'okf/invalid-document',
        'okf/missing-type',
        'okf/missing-type',
      ]),
    );
  });

  test('strict mode promotes advisories to a failing exit status', () async {
    await writeConcept(bundle, 'café.md');

    final ordinary = await runCli(<String>['validate', 'bundle'], sandbox.path);
    expect(ordinary.exitCode, 0);
    expect(ordinary.stdout, contains('advisory okf/non-portable-concept-id'));

    final strict = await runCli(<String>[
      'validate',
      'bundle',
      '--strict',
    ], sandbox.path);
    expect(strict.exitCode, 1);

    final alias = await runCli(<String>[
      'validate',
      'bundle',
      '--warnings-as-errors',
    ], sandbox.path);
    expect(alias.exitCode, 1);
  });

  test('format check is non-mutating and format is idempotent', () async {
    final file = File(p.join(bundle.path, 'alpha.md'));
    const original = '---\ntitle: Alpha\ntype: Reference\n---\n\n# Alpha';
    await file.writeAsString(original);

    final check = await runCli(<String>[
      'format',
      'bundle',
      '--check',
    ], sandbox.path);
    expect(check.exitCode, 1);
    expect(check.stdout, contains('Would format alpha.md'));
    expect(await file.readAsString(), original);

    final formatted = await runCli(<String>['format', 'bundle'], sandbox.path);
    expect(formatted.exitCode, 0);
    expect(formatted.stdout, 'Formatted 1 file(s).');
    expect(await file.readAsString(), isNot(original));

    final secondCheck = await runCli(<String>[
      'format',
      'bundle',
      '--check',
    ], sandbox.path);
    expect(secondCheck.exitCode, 0);
    expect(secondCheck.stdout, 'Already formatted.');
  });

  test('format migrates date-only timestamps only when asked', () async {
    final file = File(p.join(bundle.path, 'alpha.md'));
    await file.writeAsString(
      '---\ntype: Reference\nstale_after: 2026-09-23\n---\n\n# Alpha\n',
    );

    final plain = await runCli(<String>['format', 'bundle'], sandbox.path);
    expect(plain.exitCode, 0);
    expect(await file.readAsString(), isNot(contains('T00:00:00Z')));

    final check = await runCli(<String>[
      'format',
      'bundle',
      '--migrate-timestamps',
      '--check',
    ], sandbox.path);
    expect(check.exitCode, 1);
    expect(
      check.stdout,
      contains(
        'Would migrate alpha.md: stale_after 2026-09-23 -> '
        '2026-09-23T00:00:00Z',
      ),
    );

    final migrated = await runCli(<String>[
      'format',
      'bundle',
      '--migrate-timestamps',
    ], sandbox.path);
    expect(migrated.exitCode, 0);
    expect(migrated.stdout, contains('Migrated alpha.md: stale_after'));
    expect(
      await file.readAsString(),
      contains('stale_after: "2026-09-23T00:00:00Z"'),
    );
  });

  for (final command in <String>['format', 'index']) {
    // The bundle lock queues claims in arrival order inside one isolate, so
    // this reproduces the exact interleaving that used to lose the update:
    // the command's read, then the concurrent write, then the command's own
    // write. It only passes while the command holds a single claim across
    // both halves.
    test('$command keeps a concurrent accepted change', () async {
      await writeConcept(bundle, 'alpha.md', title: 'Before');
      final lockAcquired = Completer<void>();
      final releaseLock = Completer<void>();
      final holdingLock = OkfBundleLock.write(bundle.path, () async {
        lockAcquired.complete();
        await releaseLock.future;
      });
      await lockAcquired.future;

      var cliDone = false;
      final cli = runCli(<String>[
        command,
        'bundle',
      ], sandbox.path).whenComplete(() => cliDone = true);
      await pumpEventQueue();
      var changeDone = false;
      final concurrentChange = const OkfBundleChangeApplier()
          .apply(
            bundle.path,
            OkfBundleChangeSet(<OkfBundleChange>[
              OkfUpdateConceptChange(
                id: OkfConceptId('alpha'),
                frontmatterChanges: const <String, Object?>{
                  'title': 'Concurrent',
                },
              ),
            ]),
          )
          .whenComplete(() => changeDone = true);
      await pumpEventQueue();
      expect(cliDone, isFalse, reason: 'the held claim must block $command');
      expect(changeDone, isFalse, reason: 'the held claim must block the fix');

      releaseLock.complete();
      final cliResult = await cli.timeout(const Duration(seconds: 10));
      final application = await concurrentChange.timeout(
        const Duration(seconds: 10),
      );
      await holdingLock.timeout(const Duration(seconds: 10));
      expect(cliResult.exitCode, 0, reason: cliResult.stderr);
      expect(application, isA<OkfBundleApplied>());

      final document = OkfDocument.parse(
        await readBundleFile(bundle, 'alpha.md'),
      );
      final index = OkfIndexDocument.parse(
        await readBundleFile(bundle, 'index.md'),
      );
      expect(document.title, 'Concurrent');
      expect(index.entries.single.title, 'Concurrent');
    });
  }

  test(
    'formats a nested file without touching the rest of the bundle',
    () async {
      await writeConcept(bundle, 'alpha.md');
      await writeBundleFile(
        bundle,
        'nested/beta.md',
        '---\ntype: Reference\ntitle: Beta\n---\n\n# Beta',
      );
      final before = await snapshotBundle(bundle);

      final result = await runCli(<String>[
        'format',
        p.join('bundle', 'nested', 'beta.md'),
      ], sandbox.path);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, 'Formatted 1 file(s).');
      expect(
        await readBundleFile(bundle, 'nested/beta.md'),
        '---\ntype: Reference\ntitle: Beta\n---\n\n# Beta\n',
      );
      expect(await readBundleFile(bundle, 'alpha.md'), before['alpha.md']);
      expect(
        await File(
          p.join(bundle.path, 'nested', okfBundleLockFileName),
        ).exists(),
        isTrue,
        reason: 'a file operand locks its own directory',
      );
    },
  );

  test('read-only commands leave no lock file in the bundle', () async {
    await writeConcept(bundle, 'alpha.md');
    final lockFile = File(p.join(bundle.path, okfBundleLockFileName));

    for (final arguments in <List<String>>[
      <String>['validate', 'bundle'],
      <String>['graph', 'bundle'],
      <String>['format', '--check', 'bundle'],
      <String>['index', '--check', 'bundle'],
    ]) {
      await runCli(arguments, sandbox.path);
      expect(await lockFile.exists(), isFalse, reason: arguments.join(' '));
    }
  });

  test('format refuses malformed input without partial writes', () async {
    final valid = File(p.join(bundle.path, 'valid.md'));
    const unformatted = '---\ntitle: Valid\ntype: Reference\n---\n\n# Valid';
    await valid.writeAsString(unformatted);
    await File(
      p.join(bundle.path, 'broken.md'),
    ).writeAsString('---\ntype: Reference\nbroken: [\n');

    final result = await runCli(<String>['format', 'bundle'], sandbox.path);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('okf/invalid-document'));
    expect(await valid.readAsString(), unformatted);
  });

  test('format rejects non-Markdown files', () async {
    await File(p.join(bundle.path, 'query.sql')).writeAsString('select 1');

    final result = await runCli(<String>[
      'format',
      'bundle/query.sql',
    ], sandbox.path);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('only .md files'));
  });

  test('generates and checks deterministic indexes', () async {
    await writeConcept(bundle, 'alpha.md');

    final firstCheck = await runCli(<String>[
      'index',
      'bundle',
      '--check',
    ], sandbox.path);
    expect(firstCheck.exitCode, 1);
    expect(firstCheck.stdout, contains('Index is stale: index.md'));
    expect(await File(p.join(bundle.path, 'index.md')).exists(), isFalse);

    final generated = await runCli(<String>[
      'index',
      'bundle',
      '--declare-version=0.2',
    ], sandbox.path);
    expect(generated.exitCode, 0);
    expect(generated.stdout, 'Generated 1 index file(s).');
    final index = await File(p.join(bundle.path, 'index.md')).readAsString();
    expect(index, contains('okf_version: "0.2"'));
    expect(index, contains('[Alpha](alpha.md)'));

    final current = await runCli(<String>[
      'index',
      'bundle',
      '--check',
    ], sandbox.path);
    expect(current.exitCode, 0);
    expect(current.stdout, 'Indexes are current.');
  });

  test('renders JSON, DOT, and Mermaid graphs', () async {
    await writeConcept(bundle, 'alpha.md');

    final json = await runCli(<String>[
      'graph',
      'bundle',
      '--output=json',
    ], sandbox.path);
    expect(json.exitCode, 0);
    expect(jsonDecode(json.stdout), isA<Map<String, Object?>>());

    final dot = await runCli(<String>[
      'graph',
      'bundle',
      '--output=dot',
    ], sandbox.path);
    expect(dot.exitCode, 0);
    expect(dot.stdout, contains('digraph'));

    final mermaid = await runCli(<String>[
      'graph',
      'bundle',
      '--output=mermaid',
    ], sandbox.path);
    expect(mermaid.exitCode, 0);
    expect(mermaid.stdout, anyOf(contains('flowchart'), contains('graph')));
  });

  test('composes graph filters for every output format', () async {
    await writeConcept(
      bundle,
      'analytics/primary.md',
      type: 'Metric',
      body: '[peer](peer.md) [missing](missing.md)',
    );
    await writeConcept(bundle, 'analytics/peer.md', type: 'Metric');
    await writeConcept(bundle, 'analytics/reference.md');
    await writeConcept(bundle, 'other/metric.md', type: 'Metric');
    const filters = <String>[
      '--type=Metric',
      '--type=Unknown',
      '--path-prefix=unused/',
      '--path-prefix=analytics/',
      '--resolution=unresolved',
    ];

    final json = await runCli(<String>[
      'graph',
      'bundle',
      '--output=json',
      ...filters,
    ], sandbox.path);
    expect(json.exitCode, 0, reason: json.stderr);
    final payload = jsonDecode(json.stdout) as Map<String, Object?>;
    final nodes = (payload['nodes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final edges = (payload['edges']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(nodes.map((node) => node['id']), <String>[
      'analytics/peer',
      'analytics/primary',
    ]);
    expect(edges.single['raw_target'], 'missing.md');

    for (final format in <String>['dot', 'mermaid']) {
      final rendered = await runCli(<String>[
        'graph',
        'bundle',
        '--output=$format',
        ...filters,
      ], sandbox.path);
      expect(rendered.exitCode, 0, reason: rendered.stderr);
      expect(rendered.stdout, contains('analytics/primary'));
      expect(rendered.stdout, contains('missing.md'));
      expect(rendered.stdout, isNot(contains('analytics/reference')));
      expect(rendered.stdout, isNot(contains('other/metric')));
    }
  });

  test('preserves commas in free-form graph filters', () async {
    await writeConcept(bundle, 'sales,ops/primary.md', type: 'Metric, Derived');

    final result = await runCli(<String>[
      'graph',
      'bundle',
      '--type=Metric, Derived',
      '--path-prefix=sales,ops/',
    ], sandbox.path);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final nodes = (payload['nodes']! as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(result.exitCode, 0, reason: result.stderr);
    expect(nodes.map((node) => node['id']), <String>['sales,ops/primary']);
  });

  test('surfaces malformed indexes that will not be regenerated', () async {
    await writeConcept(bundle, 'alpha.md');
    final orphan = await Directory(p.join(bundle.path, 'assets')).create();
    await File(
      p.join(orphan.path, 'index.md'),
    ).writeAsString('---\nnot: [valid\n');

    final result = await runCli(<String>['index', 'bundle'], sandbox.path);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('okf/invalid-reserved-document'));
  });

  test(
    'reports mcp usage errors before stdout becomes a JSON-RPC channel',
    () async {
      final rootHelp = await runCli(<String>['--help'], sandbox.path);
      expect(rootHelp.stdout, contains('mcp        Serve'));

      final help = await runCli(<String>['mcp', '--help'], sandbox.path);
      expect(help.exitCode, 0);
      expect(help.stdout, contains('Usage: okf mcp <bundle>'));

      final missingOperand = await runCli(<String>['mcp'], sandbox.path);
      expect(missingOperand.exitCode, 2);
      expect(missingOperand.stderr, contains('exactly one'));

      final missingBundle = await runCli(<String>[
        'mcp',
        'missing',
      ], sandbox.path);
      expect(missingBundle.exitCode, 2);
      expect(missingBundle.stdout, isEmpty);
      expect(missingBundle.stderr, contains('not a directory'));
    },
  );

  test('escapes control characters in terminal findings', () async {
    if (Platform.isWindows) {
      return;
    }
    await File(
      p.join(bundle.path, 'bad\u001b.md'),
    ).writeAsString('---\ntype: Reference\n---\n');

    final result = await runCli(<String>['validate', 'bundle'], sandbox.path);

    expect(result.exitCode, 1);
    expect(result.stdout, isNot(contains('\u001b')));
    expect(result.stdout, contains(r'\u{001b}'));
  });
}
