import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('okf-io-test-');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('OkfBundleLoader', () {
    test('loads a sorted inventory without following links', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      await _write(
        root,
        'zeta.md',
        '---\ntype: Reference\ntitle: Zeta\n---\n\n# Zeta\n',
      );
      await _write(
        root,
        'nested/alpha.md',
        '---\ntype: Metric\ntitle: Alpha\n---\n\n# Alpha\n',
      );
      await _write(root, 'index.md', '# Index\n');
      await _write(root, 'nested/log.md', '# Log\n\n## 2026-01-01\n');
      await _write(root, 'assets/query.sql', 'select 1;\n');

      if (!Platform.isWindows) {
        final outside = await File(
          p.join(sandbox.path, 'outside.md'),
        ).writeAsString('---\ntype: Reference\n---\n');
        await Link(p.join(root.path, 'linked.md')).create(outside.path);
      }

      final result = await const OkfBundleLoader().inspect(root.path);

      expect(
        result.documents.keys,
        orderedEquals(<String>['nested/alpha.md', 'zeta.md']),
      );
      expect(result.indexes.keys, orderedEquals(<String>['index.md']));
      expect(result.logs.keys, orderedEquals(<String>['nested/log.md']));
      expect(result.assets, orderedEquals(<String>['assets/query.sql']));
      expect(
        result.paths,
        orderedEquals(<String>[
          'assets/query.sql',
          'index.md',
          'nested/alpha.md',
          'nested/log.md',
          'zeta.md',
        ]),
      );
      expect(result.bundle.concepts.length, 2);
      expect(result.bundle.assetPaths, contains('assets/query.sql'));
      expect(result.hasFindings, isFalse);
    });

    test(
      'reports every malformed concept and returns a partial bundle',
      () async {
        final root = await Directory(p.join(sandbox.path, 'bundle')).create();
        await _write(root, 'valid.md', '---\ntype: Reference\n---\n\nValid\n');
        await _write(
          root,
          'broken.md',
          '---\ntype: Reference\nunterminated: [\n',
        );
        final invalidUtf8 = File(p.join(root.path, 'invalid.md'));
        await invalidUtf8.writeAsBytes(<int>[0xff], flush: true);

        final result = await const OkfBundleLoader().inspect(root.path);

        expect(result.bundle.concepts.length, 1);
        expect(
          result.report.findings.map((finding) => finding.location?.path),
          orderedEquals(<String>['broken.md', 'invalid.md']),
        );
        expect(
          result.report.findings.map((finding) => finding.id.value),
          orderedEquals(<String>['okf/invalid-document', 'okf/invalid-utf8']),
        );
        expect(result.report.findings.first.location?.line, isNotNull);
        expect(result.report.findings.first.location?.column, isNotNull);
        expect(
          result.paths,
          containsAll(<String>['broken.md', 'invalid.md', 'valid.md']),
        );
        await expectLater(
          const OkfBundleLoader().load(root.path),
          throwsA(
            isA<OkfBundleLoadException>().having(
              (error) => error.result.report.findings.length,
              'finding count',
              2,
            ),
          ),
        );
      },
    );

    test('records where each loaded concept body starts in its file', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      await _write(root, 'plain.md', '---\ntype: Note\n---\n\n# Plain\n');
      const windowsText = '---\r\ntype: Note\r\n\r\n---\r\n\r\n# Windows\r\n';
      await File(p.join(root.path, 'windows.md')).writeAsBytes(<int>[
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(windowsText),
      ], flush: true);

      final bundle = await const OkfBundleLoader().load(root.path);
      final windows = bundle.conceptAtPath('windows.md')!;

      expect(bundle.conceptAtPath('plain.md')!.bodyStartLine, 5);
      expect(windows.body, '# Windows\n');
      expect(windows.bodyStartLine, 6);
      expect(
        windowsText.split('\r\n')[windows.bodyStartLine! - 1],
        '# Windows',
      );
    });

    test('validate merges load findings with fixed Spec findings', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      await _write(root, 'valid.md', '---\ntype: Reference\n---\n\nValid\n');
      await _write(root, 'broken.md', '---\ntype: Reference\nbad: [\n');
      await _write(root, 'untyped.md', '---\ntitle: Untyped\n---\n');

      final result = await const OkfBundleLoader().inspect(root.path);
      final validation = result.validate();
      final report = validation.report;

      expect(
        report.findings.map((finding) => '${finding.id}'),
        orderedEquals(<String>['okf/invalid-document', 'okf/missing-type']),
      );
      expect(report.findings.last.location?.path, 'untyped.md');
      expect(validation.isConformant, isFalse);
      expect(OkfVerdict.of(report).exitCode, 1);
    });

    test('reports bundle paths containing C1 control characters', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      const invalidPath = 'invalid\u0085asset.txt';
      await _write(root, invalidPath, 'invalid path\n');

      final result = await const OkfBundleLoader().inspect(root.path);

      expect(result.bundle.allPaths, isEmpty);
      expect(result.report.findings, hasLength(1));
      expect(result.report.findings.single.id.value, 'okf/invalid-path');
      expect(result.report.findings.single.location?.path, invalidPath);
    });

    test('rejects a symbolic-link root', () async {
      if (Platform.isWindows) {
        return;
      }
      final root = await Directory(p.join(sandbox.path, 'real')).create();
      final link = await Link(p.join(sandbox.path, 'linked')).create(root.path);

      await expectLater(
        const OkfBundleLoader().inspect(link.path),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

Future<void> _write(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(
    p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, encoding: utf8, flush: true);
}
