import 'dart:async';
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

  group('OkfBundleLock', () {
    late Directory root;
    late File lockFile;

    setUp(() async {
      root = await Directory(p.join(sandbox.path, 'bundle')).create();
      lockFile = File(p.join(root.path, okfBundleLockFileName));
    });

    test('a writer in another process blocks writes and reads', () async {
      final held = await _holdBundleLock(sandbox, root.path, 'write');

      var written = false;
      final write = const OkfBundleWriter()
          .writeAll(root.path, <String, String>{'held.md': 'held\n'})
          .whenComplete(() => written = true);
      var inspected = false;
      final read = const OkfBundleLoader()
          .inspect(root.path)
          .whenComplete(() => inspected = true);
      final probe = await _probeBundleLock(sandbox, root.path, 'read');

      expect(await probe.acquiredWithinWindow, isFalse);
      expect(written, isFalse);
      expect(inspected, isFalse);
      expect(await File(p.join(root.path, 'held.md')).exists(), isFalse);

      await held.release();
      await write.timeout(const Duration(seconds: 10));
      await read.timeout(const Duration(seconds: 10));
      await probe.done.timeout(const Duration(seconds: 10));
      expect(await File(p.join(root.path, 'held.md')).readAsString(), 'held\n');
    });

    test('readers in separate processes share the lock', () async {
      // A reader can only take a shared claim on a lock file that exists.
      await const OkfBundleWriter().writeAll(root.path, <String, String>{
        'seed.md': 'seed\n',
      });
      final held = await _holdBundleLock(sandbox, root.path, 'read');
      final probe = await _probeBundleLock(sandbox, root.path, 'read');

      expect(await probe.acquiredWithinWindow, isTrue);
      await probe.done.timeout(const Duration(seconds: 10));
      await held.release();
    });

    test(
      'processes disagreeing about TMPDIR still exclude each other',
      () async {
        if (Platform.isWindows) {
          return;
        }
        final held = await _holdBundleLock(
          sandbox,
          root.path,
          'write',
          environment: <String, String>{
            'TMPDIR': (await Directory(
              p.join(sandbox.path, 'tmp-a'),
            ).create()).path,
          },
        );
        final probe = await _probeBundleLock(
          sandbox,
          root.path,
          'write',
          environment: <String, String>{
            'TMPDIR': (await Directory(
              p.join(sandbox.path, 'tmp-b'),
            ).create()).path,
          },
        );

        expect(await probe.acquiredWithinWindow, isFalse);
        await held.release();
        await probe.done.timeout(const Duration(seconds: 10));
      },
    );

    test(
      'a symbolically linked root shares one lock with its real path',
      () async {
        if (Platform.isWindows) {
          return;
        }
        final alias = p.join(sandbox.path, 'alias');
        await Link(alias).create(root.path);
        final held = await _holdBundleLock(sandbox, alias, 'write');
        final probe = await _probeBundleLock(sandbox, root.path, 'write');

        expect(await probe.acquiredWithinWindow, isFalse);
        await held.release();
        await probe.done.timeout(const Duration(seconds: 10));
        expect(await lockFile.exists(), isTrue);
      },
    );

    test('inspection never creates the lock file', () async {
      await const OkfBundleLoader().inspect(root.path);

      expect(await lockFile.exists(), isFalse);
    });

    for (final firstAttemptFails in <bool>[false, true]) {
      final firstOutcome = firstAttemptFails ? 'failed' : 'completed';
      test(
        'retries a $firstOutcome read when the first writer creates the lock',
        () async {
          final state = await File(
            p.join(root.path, 'state.txt'),
          ).writeAsString('before');
          final firstRead = Completer<void>();
          final releaseRead = Completer<void>();
          var attempts = 0;

          final read = OkfBundleLock.read(root.path, () async {
            attempts++;
            final value = await state.readAsString();
            if (attempts == 1) {
              firstRead.complete();
              await releaseRead.future;
              if (firstAttemptFails) {
                throw StateError('read overlapped the first write');
              }
            }
            return value;
          });
          await firstRead.future;

          final writer = await _startLockHelper(
            'write_bundle_file.dart',
            <String>[root.path, 'state.txt', 'after'],
          );
          expect(await writer.exitCode.timeout(const Duration(seconds: 10)), 0);
          releaseRead.complete();

          expect(await read.timeout(const Duration(seconds: 10)), 'after');
          expect(attempts, 2);
        },
      );
    }

    test('does not ignore an invalid existing lock file', () async {
      await Directory(lockFile.path).create();
      var actionRan = false;

      await expectLater(
        OkfBundleLock.read(root.path, () async => actionRan = true),
        throwsA(isA<FileSystemException>()),
      );
      expect(actionRan, isFalse);
    });

    test('does not ignore an unreadable existing lock file', () async {
      if (Platform.isWindows) {
        return;
      }
      await lockFile.create();
      final restricted = await Process.run('chmod', <String>[
        '0000',
        lockFile.path,
      ]);
      expect(restricted.exitCode, 0, reason: '${restricted.stderr}');
      var actionRan = false;

      try {
        await expectLater(
          OkfBundleLock.read(root.path, () async => actionRan = true),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        final restored = await Process.run('chmod', <String>[
          '0600',
          lockFile.path,
        ]);
        expect(restored.exitCode, 0, reason: '${restored.stderr}');
      }
      expect(actionRan, isFalse);
    });

    test('lock files are not part of the bundle inventory', () async {
      await const OkfBundleWriter().writeAll(root.path, <String, String>{
        'concept.md': '---\ntype: Reference\n---\n\n# C\n',
      });
      final nestedRoot = p.join(root.path, 'nested');
      await const OkfBundleWriter().writeAll(nestedRoot, <String, String>{
        'concept.md': '---\ntype: Reference\n---\n\n# N\n',
      });
      expect(await lockFile.exists(), isTrue);
      expect(
        await File(p.join(nestedRoot, okfBundleLockFileName)).exists(),
        isTrue,
      );

      final result = await const OkfBundleLoader().inspect(root.path);

      expect(result.assets, isEmpty);
      expect(result.paths, <String>['concept.md', 'nested/concept.md']);
      expect(result.report.findings, isEmpty);
    });

    test('a failing action releases the lock', () async {
      await expectLater(
        OkfBundleLock.write(
          root.path,
          () => Future<void>.error(StateError('boom')),
        ),
        throwsStateError,
      );

      var reacquired = false;
      await OkfBundleLock.write(root.path, () async => reacquired = true);
      expect(reacquired, isTrue);
      final probe = await _probeBundleLock(sandbox, root.path, 'write');
      expect(await probe.acquiredWithinWindow, isTrue);
      await probe.done.timeout(const Duration(seconds: 10));
    });

    test('a shared claim cannot be upgraded to an exclusive one', () async {
      await expectLater(
        OkfBundleLock.read(
          root.path,
          () => OkfBundleLock.write(root.path, () async {}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses a lock file that is a symbolic link', () async {
      if (Platform.isWindows) {
        return;
      }
      await Link(lockFile.path).create(p.join(sandbox.path, 'elsewhere.lock'));

      await expectLater(
        OkfBundleLock.write(root.path, () async {}),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

final class _HeldBundleLock {
  _HeldBundleLock(this._process, this._releasePath);

  final Process _process;
  final String _releasePath;

  Future<void> release() async {
    await File(_releasePath).writeAsString('release');
    await _process.exitCode.timeout(const Duration(seconds: 10));
  }
}

final class _BundleLockProbe {
  _BundleLockProbe(this.done, this._acquired);

  final Future<void> done;

  final File _acquired;

  Future<bool> get acquiredWithinWindow async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (await _acquired.exists()) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return false;
  }
}

Future<_HeldBundleLock> _holdBundleLock(
  Directory sandbox,
  String rootPath,
  String mode, {
  Map<String, String>? environment,
}) async {
  final readyPath = p.join(sandbox.path, 'hold-$mode-ready');
  final releasePath = p.join(sandbox.path, 'hold-$mode-release');
  final process = await _startLockHelper('hold_bundle_lock.dart', <String>[
    rootPath,
    mode,
    readyPath,
    releasePath,
  ], environment: environment);
  await _waitForFile(File(readyPath));
  return _HeldBundleLock(process, releasePath);
}

Future<_BundleLockProbe> _probeBundleLock(
  Directory sandbox,
  String rootPath,
  String mode, {
  Map<String, String>? environment,
}) async {
  final startedPath = p.join(sandbox.path, 'probe-$mode-started');
  final acquiredPath = p.join(sandbox.path, 'probe-$mode-acquired');
  final process = await _startLockHelper('acquire_bundle_lock.dart', <String>[
    rootPath,
    mode,
    startedPath,
    acquiredPath,
  ], environment: environment);
  await _waitForFile(File(startedPath));
  return _BundleLockProbe(process.exitCode, File(acquiredPath));
}

Future<Process> _startLockHelper(
  String script,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>['run', p.join('test', 'support', script), ...arguments],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
  addTearDown(() async {
    process.kill();
    await process.exitCode;
  });
  return process;
}

Future<void> _waitForFile(File file) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (await file.exists()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Timed out waiting for ${file.path}');
}
