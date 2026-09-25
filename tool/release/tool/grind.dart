import 'dart:io';

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;

const _packageName = 'okf';

// This must always name the account that *canonically* owns the repository,
// never an account that merely redirects to it. GitHub keeps redirects alive
// after a repository moves, and cli_pkg does not follow redirects on POST, so
// a stale owner here fails only at release creation, after every check passed.
const _owner = 'btwld';

final Directory _releaseToolRoot = Directory.current;
final Directory _repoRoot = Directory(
  p.normalize(p.join(_releaseToolRoot.path, '..', '..')),
);

void main(List<String> args) {
  final enableVersionedFormula = args.contains('--versioned-formula');

  pkg.name.value = _packageName;
  pkg.humanName.value = _packageName;
  pkg.standaloneName.value = _packageName;
  // Dart defaults a null executable mapping to bin/<name>.dart. cli_pkg does
  // not, so preserve the root pubspec's intended entrypoint explicitly.
  pkg.executables.value = <String, String>{'okf': 'bin/okf.dart'};
  // Keep every published platform asset self-contained.
  pkg.useExe.value = (_) => true;
  pkg.githubUser.value = _owner;
  pkg.githubRepo.value = '$_owner/$_packageName';
  pkg.githubBearerToken.value = Platform.environment['GITHUB_TOKEN'];
  pkg.homebrewRepo.value = '$_owner/homebrew-tap';
  // The tap is shared, so name the formula rather than letting cli_pkg infer
  // the single .rb file it happens to hold today.
  pkg.homebrewFormula.value = 'Formula/okf.rb';
  if (enableVersionedFormula) {
    pkg.homebrewCreateVersionedFormula.value = true;
  }

  // cli_pkg expects pubspec.yaml, bin/, and lib/ in the current working
  // directory. This grind.dart lives under tool/release, so move to the
  // repository root before registering the tasks.
  Directory.current = _repoRoot;

  // cli_pkg interpolates this straight into
  // "https://github.com/<repo>/archive/<tag>.tar.gz". Its default is the bare
  // version, which names a ref this repository never creates, and Homebrew's
  // FormulaAudit/Urls rule wants the explicit "refs/tags" form besides. Only
  // readable once the working directory holds the package pubspec.
  pkg.homebrewTag.value = 'refs/tags/v${pkg.version}';

  pkg.addAllTasks();
  grind(args);
}
