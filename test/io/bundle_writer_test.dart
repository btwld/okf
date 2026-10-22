import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:okf/src/io/bundle_writer.dart' show OkfBundleWriteTransaction;
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

  group('OkfBundleWriter', () {
    test('recursively creates a missing bundle root', () async {
      final root = p.join(sandbox.path, 'missing', 'bundle');

      final result = await const OkfBundleWriter().writeAll(
        root,
        <String, String>{'a.md': 'a\n'},
      );

      expect(result.changedPaths, <String>['a.md']);
      expect(await File(p.join(root, 'a.md')).readAsString(), 'a\n');
    });

    test('writes deterministically and supports non-mutating checks', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      const writer = OkfBundleWriter();

      final first = await writer.writeAll(root.path, <String, String>{
        'zeta.md': 'zeta\n',
        'nested/alpha.md': 'alpha\n',
      });
      expect(
        first.changedPaths,
        orderedEquals(<String>['nested/alpha.md', 'zeta.md']),
      );
      expect(
        await File(p.join(root.path, 'nested/alpha.md')).readAsString(),
        'alpha\n',
      );

      final unchanged = await writer.writeAll(root.path, <String, String>{
        'zeta.md': 'zeta\n',
      }, checkOnly: true);
      expect(unchanged.hasChanges, isFalse);

      final check = await writer.writeAll(root.path, <String, String>{
        'zeta.md': 'changed\n',
      }, checkOnly: true);
      expect(check.changedPaths, orderedEquals(<String>['zeta.md']));
      expect(await File(p.join(root.path, 'zeta.md')).readAsString(), 'zeta\n');

      await writer.writeAll(root.path, <String, String>{
        'zeta.md': 'changed\n',
      });
      expect(
        await File(p.join(root.path, 'zeta.md')).readAsString(),
        'changed\n',
      );
      expect(
        await root
            .list(recursive: true, followLinks: false)
            .where((entity) => p.basename(entity.path).contains('.okf-'))
            .isEmpty,
        isTrue,
      );
    });

    test('writes serialized documents', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      final document = OkfDocument(
        frontmatter: <String, Object?>{'type': 'Reference', 'title': 'Example'},
        body: '# Example\n',
      );

      final result = await const OkfBundleWriter().writeDocument(
        root.path,
        'example.md',
        document,
      );

      expect(result.changedPaths, orderedEquals(<String>['example.md']));
      expect(
        await File(p.join(root.path, 'example.md')).readAsString(),
        document.serialize(),
      );
    });

    test(
      'refuses a text UTF-8 cannot encode before touching the filesystem',
      () async {
        // utf8.encode would write U+FFFD for each lone surrogate, so the bytes
        // on disk would not be the text the caller passed.
        final root = Directory(p.join(sandbox.path, 'missing'));
        const writer = OkfBundleWriter();

        for (final text in <String>[
          'lead \uD800 alone\n',
          'trail \uDC00 alone\n',
          'reversed \uDC00\uD800 pair\n',
          'ends on a lead \uD800',
        ]) {
          for (final checkOnly in <bool>[false, true]) {
            await expectLater(
              writer.writeAll(root.path, <String, String>{
                // Sorted first, so a per-file write would have written it.
                'a.md': 'valid\n',
                'b.md': text,
              }, checkOnly: checkOnly),
              throwsA(
                isA<ArgumentError>()
                    .having((error) => error.name, 'name', 'files')
                    .having(
                      (error) => '${error.message}',
                      'message',
                      contains('b.md holds an unpaired surrogate'),
                    ),
              ),
              reason: '$text (checkOnly: $checkOnly)',
            );
          }
          await expectLater(
            const OkfBundleWriteTransaction().writeAll(
              root.path,
              <String, String>{'a.md': 'valid\n', 'b.md': text},
            ),
            throwsA(isA<ArgumentError>()),
            reason: text,
          );
        }
        // Neither the root, its lock file nor the valid file was created.
        expect(await root.exists(), isFalse);

        final paired = await writer.writeAll(root.path, <String, String>{
          'b.md': 'paired \uD83D\uDE00\n',
        });
        expect(paired.changedPaths, <String>['b.md']);
        expect(await File(p.join(root.path, 'b.md')).readAsBytes(), <int>[
          ...utf8.encode('paired '),
          0xF0,
          0x9F,
          0x98,
          0x80,
          0x0A,
        ]);
      },
    );

    test('refuses a serialized document UTF-8 cannot encode', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      final document = OkfDocument(
        frontmatter: <String, Object?>{'type': 'Reference', 'title': 'Example'},
        body: '# Example \uD800\n',
      );

      await expectLater(
        const OkfBundleWriter().writeDocument(
          root.path,
          'example.md',
          document,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await root.list().isEmpty, isTrue);
    });

    test('refuses frontmatter YAML cannot represent', () async {
      // The emitter would write the surrogate as a `\ud800` escape, which the
      // loader rejects, so the written concept would not load.
      final root = Directory(p.join(sandbox.path, 'missing'));
      final document = OkfDocument(
        frontmatter: <String, Object?>{
          'type': 'Reference',
          'title': 'Example \uD800',
        },
        body: '# Example\n',
      );

      for (final checkOnly in <bool>[false, true]) {
        await expectLater(
          const OkfBundleWriter().writeDocument(
            root.path,
            'example.md',
            document,
            checkOnly: checkOnly,
          ),
          throwsA(isA<OkfYamlEncodeException>()),
          reason: 'checkOnly: $checkOnly',
        );
      }
      expect(await root.exists(), isFalse);
    });

    test('transactional writes restore the exact original bytes', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      final original = File(p.join(root.path, 'a.md'));
      await original.writeAsBytes(<int>[0xff], flush: true);
      await Directory(p.join(root.path, 'z.md')).create();

      await expectLater(
        const OkfBundleWriteTransaction().writeAll(root.path, <String, String>{
          'a.md': 'changed\n',
          'z.md': 'cannot replace a directory\n',
        }),
        throwsA(isA<FileSystemException>()),
      );

      expect(await original.readAsBytes(), <int>[0xff]);
    });

    test('rejects absolute and escaping paths', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      const writer = OkfBundleWriter();

      await expectLater(
        writer.writeAll(root.path, <String, String>{'../escape.md': 'no'}),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        writer.writeAll(root.path, <String, String>{
          p.join(sandbox.path, 'absolute.md'): 'no',
        }),
        throwsA(isA<ArgumentError>()),
      );
      for (final path in <String>[
        'nested/../normalized-away.md',
        'nested/./dot.md',
        r'nested\backslash.md',
        'nested/\u001bescape.md',
        'nested/\u0085escape.md',
      ]) {
        await expectLater(
          writer.writeAll(root.path, <String, String>{path: 'no'}),
          throwsA(isA<ArgumentError>()),
          reason: path,
        );
      }
      expect(await File(p.join(sandbox.path, 'escape.md')).exists(), isFalse);
    });

    test('check-only does not create a missing bundle root', () async {
      final root = Directory(p.join(sandbox.path, 'missing'));

      final result = await const OkfBundleWriter().writeAll(
        root.path,
        <String, String>{'concept.md': 'would change\n'},
        checkOnly: true,
      );

      expect(result.changedPaths, <String>['concept.md']);
      expect(await root.exists(), isFalse);
    });

    test('refuses a stale expected source in check and write modes', () async {
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      await _write(root, 'concept.md', 'read\n');

      await expectLater(
        const OkfBundleWriter().writeAll(
          root.path,
          <String, String>{'concept.md': 'formatted\n'},
          checkOnly: true,
          expectedSources: const <String, String>{'concept.md': 'stale\n'},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File(p.join(root.path, 'concept.md')).readAsString(),
        'read\n',
      );

      await expectLater(
        const OkfBundleWriter().writeAll(
          root.path,
          <String, String>{'concept.md': 'formatted\n'},
          expectedSources: const <String, String>{'concept.md': 'stale\n'},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File(p.join(root.path, 'concept.md')).readAsString(),
        'read\n',
      );

      final result = await const OkfBundleWriter().writeAll(
        root.path,
        <String, String>{'concept.md': 'formatted\n'},
        expectedSources: const <String, String>{'concept.md': 'read\n'},
      );

      expect(result.changedPaths, <String>['concept.md']);
      expect(
        await File(p.join(root.path, 'concept.md')).readAsString(),
        'formatted\n',
      );
    });

    test('refuses to write through a symbolic link', () async {
      if (Platform.isWindows) {
        return;
      }
      final root = await Directory(p.join(sandbox.path, 'bundle')).create();
      final outside = await Directory(p.join(sandbox.path, 'outside')).create();
      await Link(p.join(root.path, 'linked')).create(outside.path);

      await expectLater(
        const OkfBundleWriter().writeAll(root.path, <String, String>{
          'linked/escape.md': 'no',
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(p.join(outside.path, 'escape.md')).exists(), isFalse);
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
