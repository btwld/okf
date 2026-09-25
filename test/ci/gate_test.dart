import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the published composite action pins its actions to commits', () {
    // Workflows follow upstream's movable tags, but action.yml runs in other
    // repositories, where a movable reference is a supply-chain hazard.
    final source = File('action.yml').readAsStringSync();
    expect(
      source,
      isNot(contains(RegExp(r'uses:\s+[^@\s]+@(?![0-9a-f]{40}(?:\s|$))'))),
      reason: 'action.yml contains a movable action reference',
    );
  });

  test('the version is declared once and mirrored everywhere', () {
    // Nothing generates these any more: the release is cut by editing the
    // pubspec and pushing a tag, so a stale mirror ships a lying binary.
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final version = pubspec['version'] as String;

    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(
      File('lib/src/version.dart').readAsStringSync(),
      contains("'$version';"),
    );
    expect(File('README.md').readAsStringSync(), contains('okf@v$version'));
    expect(
      // Normalized: a Windows runner checks the tree out with CRLF.
      File('CHANGELOG.md').readAsStringSync().replaceAll('\r\n', '\n'),
      startsWith('## $version\n'),
      reason:
          'cli_pkg scans CHANGELOG.md from offset 0 for "## <version>", '
          'so no title heading may precede the first entry',
    );
    expect(File('package.json').existsSync(), false);
    expect(Directory('.changeset').existsSync(), false);
    expect(File('.github/workflows/release-pr.yml').existsSync(), false);
  });

  test('cli_pkg release tooling isolates its effective SDK floor', () {
    final releasePubspecFile = File('tool/release/pubspec.yaml');
    expect(releasePubspecFile.existsSync(), isTrue);

    final packagePubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final releasePubspec =
        loadYaml(releasePubspecFile.readAsStringSync()) as YamlMap;
    final releaseEnvironment = releasePubspec['environment'] as YamlMap;
    final releaseDependencies = releasePubspec['dependencies'] as YamlMap;

    final packageSdk = (packagePubspec['environment'] as YamlMap)['sdk'];
    expect(packageSdk, '>=3.11.0 <4.0.0');
    expect(releasePubspec['name'], 'okf_release');
    expect(releasePubspec['publish_to'], 'none');
    expect(releaseEnvironment['sdk'], '>=3.11.0 <4.0.0');
    expect(releaseDependencies['cli_pkg'], '2.15.2');
    expect(releaseDependencies['grinder'], '0.10.1');
    expect(
      (packagePubspec['dev_dependencies'] as YamlMap),
      isNot(contains('cli_pkg')),
    );
    // grinder resolves the entrypoint as tool/grind.dart of its own package.
    expect(File('tool/release/tool/grind.dart').existsSync(), true);
    final releaseLock =
        loadYaml(File('tool/release/pubspec.lock').readAsStringSync())
            as YamlMap;
    final releasePackages = releaseLock['packages'] as YamlMap;
    expect((releasePackages['cli_pkg'] as YamlMap)['version'], '2.15.2');
    expect((releaseLock['sdks'] as YamlMap)['dart'], '>=3.11.0 <4.0.0');
  });

  test('every deployment runs through a cli_pkg task', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();
    final workflow = loadYaml(source) as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final release = jobs['release'] as YamlMap;
    final macos = jobs['deploy-macos'] as YamlMap;

    expect((jobs['test'] as YamlMap)['uses'], './.github/workflows/test.yml');
    expect(release['needs'], 'test');
    expect(macos['needs'], 'release');
    expect(
      release.toString(),
      allOf(
        contains('dart run grinder pkg-github-release'),
        contains('dart run grinder pkg-github-linux'),
        // cli_pkg's pkg-pub-deploy can only publish from a durable
        // PUB_CREDENTIALS file, so pub.dev goes through OIDC instead.
        contains('dart pub publish --force'),
        contains('id-token: write'),
      ),
    );
    expect(
      macos.toString(),
      allOf(
        contains('dart run grinder pkg-github-macos'),
        contains('dart run grinder pkg-homebrew-update --versioned-formula'),
        // The script reads GITHUB_TOKEN; the tap needs a token with write
        // access to a different repository than the release itself.
        contains(r'GITHUB_TOKEN: ${{ secrets.HOMEBREW_TAP_GH_TOKEN }}'),
      ),
    );

    // Every pkg-github-* task uploads assets to the release, which the
    // automatic token may only do with contents: write. deploy-macos shipped
    // once with contents: read and failed after pub.dev had already published.
    for (final name in const <String>['release', 'deploy-macos']) {
      final job = jobs[name] as YamlMap;
      expect(
        (job['permissions'] as YamlMap)['contents'],
        'write',
        reason: '$name uploads release assets',
      );
    }
    // Against the parsed workflow, not the source: comments legitimately name
    // the mechanisms this asserts the workflow no longer runs.
    expect(
      workflow.toString(),
      isNot(
        anyOf(
          contains('tool/ci/publish-release.sh'),
          contains('tool/ci/publish-homebrew.sh'),
          contains('pkg-pub-deploy'),
          contains('PUB_CREDENTIALS'),
          contains('changesets/action'),
        ),
      ),
    );
    expect((workflow['on'] as YamlMap)['push'].toString(), contains('v*'));
    // cli_pkg hardcodes the release's tag_name to the bare version. Without
    // this tag, GitHub creates it at the default branch head instead.
    expect(release.toString(), contains('git push origin "\$version"'));

    final grind = File('tool/release/tool/grind.dart').readAsStringSync();
    expect(
      grind,
      allOf(
        contains('pkg.addAllTasks()'),
        contains("pkg.githubRepo.value = '\$_owner/\$_packageName'"),
        contains("pkg.homebrewRepo.value = '\$_owner/homebrew-tap'"),
        contains("pkg.homebrewFormula.value = 'Formula/okf.rb'"),
        // cli_pkg defaults the tag to the bare version, which points the
        // formula at an archive ref this repository never creates.
        contains("pkg.homebrewTag.value = 'refs/tags/v\${pkg.version}'"),
      ),
    );
    expect(grind, isNot(contains('addStandaloneTasks()')));

    // cli_pkg rewrites exactly one url/sha256 pair, so a formula with
    // per-platform blocks would keep every block but the first one stale.
    final formula = File('tool/release/homebrew/okf.rb').readAsStringSync();
    expect(
      RegExp(r'^ *url "', multiLine: true).allMatches(formula),
      hasLength(1),
    );
    expect(
      RegExp(r'^ *sha256 "', multiLine: true).allMatches(formula),
      hasLength(1),
    );
    expect(formula, contains('class Okf < Formula'));
    // The vendored SDK belongs in buildpath. Installing it into the keg
    // instead would leave ~620MB behind for a 10MB executable.
    expect(formula, contains('(buildpath/"dart-sdk").install'));
    expect(formula, isNot(contains(RegExp(r'^ *libexec', multiLine: true))));
    expect(
      formula,
      contains(
        RegExp(r'url "https://github\.com/btwld/okf/archive/refs/tags/v'),
      ),
      reason: "the ref must be the tag form Homebrew's url audit accepts",
    );
    expect(
      formula,
      isNot(contains(RegExp('sha256 "0+"'))),
      reason: 'a placeholder digest breaks the tap until the next release',
    );
  });

  test('the release workflow reuses the test workflow verbatim', () {
    final test =
        loadYaml(File('.github/workflows/test.yml').readAsStringSync())
            as YamlMap;
    final triggers = test['on'] as YamlMap;
    final jobs = test['jobs'] as YamlMap;

    expect(triggers, contains('workflow_call'));
    expect(triggers, contains('pull_request'));
    expect(jobs, contains('test'));
    // pubspec.yaml promises >=3.11.0 and only this job holds it to that.
    expect(
      (jobs['sdk-floor'] as YamlMap).toString(),
      contains('sdk-version: 3.11.0'),
    );
    expect(
      (jobs['test'] as YamlMap).toString(),
      allOf(
        contains('dart format --output=none --set-exit-if-changed'),
        contains('dart analyze --fatal-infos'),
        contains('dart test'),
        contains('dart pub publish --dry-run'),
        contains('working-directory: tool/release'),
      ),
    );

    final dependabot =
        loadYaml(File('.github/dependabot.yml').readAsStringSync()) as YamlMap;
    final updates = (dependabot['updates'] as YamlList).cast<YamlMap>();
    expect(
      updates.any(
        (update) =>
            update['package-ecosystem'] == 'pub' &&
            update['directory'] == '/tool/release',
      ),
      true,
    );
    expect(
      updates.any((update) => update['package-ecosystem'] == 'npm'),
      false,
      reason: 'the Node release tooling is gone',
    );
  });

  test('composite action checks out and validates with zero configuration', () {
    final source = File('action.yml').readAsStringSync();
    final action = loadYaml(source) as YamlMap;
    final inputs = action['inputs'] as YamlMap;
    final steps = (action['runs'] as YamlMap)['steps'] as YamlList;

    final checkout = steps[1] as YamlMap;
    expect(
      checkout['uses'],
      'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1',
    );
    expect(checkout['if'], "steps.workspace.outputs.checkout == 'true'");
    expect((checkout['with'] as YamlMap)['clean'], false);
    expect((checkout['with'] as YamlMap)['persist-credentials'], false);
    expect((inputs['bundle'] as YamlMap)['default'], '.');
    expect((inputs['strict'] as YamlMap)['default'], 'false');
    expect(source, contains(r'inputs.engine-version || github.action_ref'));
    expect(source, contains('tool/ci/install-engine.sh'));
    expect(source, contains('tool/ci/validate-engine.sh'));
    expect(
      RegExp(r'tool/ci/validate-engine\.sh').allMatches(source),
      hasLength(1),
    );
    expect(
      File('README.md').readAsStringSync(),
      isNot(contains('uses: actions/checkout@v4')),
    );
  });

  group('supported runner behavior', () {
    test('checkout is requested only for an empty workspace', () async {
      final temporary = Directory.systemTemp.createTempSync('okf-workspace-');
      addTearDown(() => temporary.deleteSync(recursive: true));

      final empty = await _checkoutDecision(temporary.path);
      expect(empty.exitCode, 0, reason: '${empty.stderr}');
      expect((empty.stdout as String).trim(), 'true');

      File('${temporary.path}/unrelated.txt').writeAsStringSync('unrelated');
      final unsafe = await _checkoutDecision(temporary.path);
      expect(unsafe.exitCode, 1);

      File('${temporary.path}/unrelated.txt').deleteSync();
      expect(
        (await Process.run('git', <String>[
          'init',
        ], workingDirectory: temporary.path)).exitCode,
        0,
      );
      await Process.run('git', <String>[
        '-c',
        'user.name=OKF Test',
        '-c',
        'user.email=okf@example.invalid',
        'commit',
        '--allow-empty',
        '-m',
        'fixture',
      ], workingDirectory: temporary.path);
      File('${temporary.path}/generated.md').writeAsStringSync('generated');
      final prepared = await _checkoutDecision(temporary.path);
      expect(prepared.exitCode, 0, reason: '${prepared.stderr}');
      expect((prepared.stdout as String).trim(), 'false');
    });

    test('the manifest names the assets cli_pkg actually publishes', () async {
      for (final platform in _platforms()) {
        final lookup = await Process.run('bash', <String>[
          'tool/ci/platform-asset.sh',
          'v1.2.3',
          platform.runnerOs,
          platform.runnerArch,
        ]);
        expect(lookup.exitCode, 0, reason: '${lookup.stderr}');
        expect(
          (lookup.stdout as String).trim(),
          'okf-1.2.3-${platform.platform}.tar.gz',
        );
      }

      final unsupported = await Process.run('bash', <String>[
        'tool/ci/platform-asset.sh',
        'v1.2.3',
        'Plan9',
        'RISCV',
      ]);
      expect(unsupported.exitCode, 1);
      expect(unsupported.stderr, contains('no released binary'));
    });

    test('the engine install keeps the whole archive tree', () async {
      final temporary = Directory.systemTemp.createTempSync('okf-engine-');
      addTearDown(() => temporary.deleteSync(recursive: true));

      // A cross-compiled cli_pkg archive is a launcher plus a snapshot beside
      // it, so extracting the entrypoint alone would install a broken engine.
      final staging = Directory('${temporary.path}/staging/okf/src')
        ..createSync(recursive: true);
      File('${staging.parent.path}/okf').writeAsStringSync(
        '#!/usr/bin/env bash\nexec cat "\$(dirname "\$0")/src/okf.snapshot"\n',
      );
      File('${staging.path}/okf.snapshot').writeAsStringSync('okf 1.2.3\n');
      final asset = 'okf-1.2.3-linux-x64.tar.gz';
      final archive = await Process.run('tar', <String>[
        '--create',
        '--gzip',
        '--file',
        '../$asset',
        'okf',
      ], workingDirectory: '${temporary.path}/staging');
      expect(archive.exitCode, 0, reason: '${archive.stderr}');

      final fakeBin = Directory('${temporary.path}/bin')..createSync();
      final curlLog = File('${temporary.path}/curl.log');
      final curl = File('${fakeBin.path}/curl')
        ..writeAsStringSync('''#!/usr/bin/env bash
set -euo pipefail
while (( \$# )); do
  case "\$1" in
    --output) output="\$2"; shift 2 ;;
    https://*) url="\$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\\n' "\$url" > "\$FAKE_CURL_LOG"
cp "\$FAKE_ASSET" "\$output"
''');
      await Process.run('chmod', <String>['+x', curl.path]);
      final environment = <String, String>{
        'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
        'FAKE_CURL_LOG': curlLog.path,
        'FAKE_ASSET': '${temporary.path}/$asset',
      };

      final install = await Process.run('bash', <String>[
        'tool/ci/install-engine.sh',
        'v1.2.3',
        'Linux',
        'X64',
        '${temporary.path}/install',
      ], environment: environment);
      expect(install.exitCode, 0, reason: '${install.stderr}');
      // cli_pkg names the release after the bare version, so the assets hang
      // off "1.2.3" even though the action is referenced by the "v1.2.3" tag.
      expect(curlLog.readAsStringSync().trim(), endsWith('/1.2.3/$asset'));

      final engine = (install.stdout as String).trim();
      expect(engine, '${temporary.path}/install/okf/okf');
      expect(File(engine).existsSync(), true);
      expect(
        File('${temporary.path}/install/okf/src/okf.snapshot').existsSync(),
        true,
        reason: 'the launcher cannot run without the snapshot beside it',
      );
      final run = await Process.run('bash', <String>[engine]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('okf 1.2.3'));

      final invalidVersion = await Process.run('bash', <String>[
        'tool/ci/install-engine.sh',
        '../mutable',
        'Linux',
        'X64',
        '${temporary.path}/install',
      ], environment: environment);
      expect(invalidVersion.exitCode, 2);
    });

    test('validation script omits strict and propagates verdicts', () async {
      final temporary = Directory.systemTemp.createTempSync('okf-ci-verdict-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final engineLog = File('${temporary.path}/engine.log');
      final engine = File('${temporary.path}/okf')
        ..writeAsStringSync('''#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\$FAKE_ENGINE_LOG"
exit "\${FAKE_ENGINE_EXIT:-0}"
''');
      await Process.run('chmod', <String>['+x', engine.path]);

      final result = await Process.run(
        'bash',
        <String>['tool/ci/validate-engine.sh', engine.path, '.', 'false'],
        environment: <String, String>{
          'FAKE_ENGINE_LOG': engineLog.path,
          'FAKE_ENGINE_EXIT': '1',
        },
      );
      expect(result.exitCode, 1);
      expect(engineLog.readAsLinesSync(), <String>['validate', '.']);

      final strict = await Process.run(
        'bash',
        <String>[
          'tool/ci/validate-engine.sh',
          engine.path,
          'bundle with spaces',
          'true',
        ],
        environment: <String, String>{'FAKE_ENGINE_LOG': engineLog.path},
      );
      expect(strict.exitCode, 0, reason: '${strict.stderr}');
      expect(engineLog.readAsLinesSync(), <String>[
        'validate',
        'bundle with spaces',
        '--strict',
      ]);

      final invalid = await Process.run('bash', <String>[
        'tool/ci/validate-engine.sh',
        engine.path,
        '.',
        'sometimes',
      ]);
      expect(invalid.exitCode, 2);
    });

    test('CI shell scripts parse as Bash', () async {
      final scripts = Directory('tool/ci')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sh'))
          .map((file) => file.path)
          .toList();
      final result = await Process.run('bash', <String>['-n', ...scripts]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
  }, skip: Platform.isWindows ? 'the action has no Windows binary' : false);
}

Future<ProcessResult> _checkoutDecision(String workspace) =>
    Process.run('bash', <String>['tool/ci/needs-checkout.sh', workspace]);

List<({String runnerOs, String runnerArch, String platform})> _platforms() =>
    File('tool/ci/platforms.tsv')
        .readAsLinesSync()
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map((line) {
          final fields = line.split('\t');
          return (
            runnerOs: fields[0],
            runnerArch: fields[1],
            platform: fields[2],
          );
        })
        .toList();
