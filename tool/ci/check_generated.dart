import 'dart:io';

/// The Ack parts that `dart run build_runner build` writes.
const _generatedPaths = <String>[
  'lib/src/document.g.dart',
  'lib/src/index_log.g.dart',
  'lib/src/mcp/inputs.g.dart',
];

/// Regenerates the Ack models and compares them with the committed parts.
///
/// The comparison is against `HEAD` rather than the working tree, so a staged
/// or an untracked generated part fails here even though an ordinary
/// `git diff` reports it as clean. Use `dart run build_runner build` while
/// developing a model or schema change, and commit all parts before running this.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('usage: dart run tool/ci/check_generated.dart');
    exitCode = 2;
    return;
  }

  final untracked = <String>[
    for (final path in _generatedPaths)
      if (!_isTracked(path)) path,
  ];
  if (untracked.isNotEmpty) {
    stderr.writeln('okf: Git does not track ${untracked.join(', ')}');
    exitCode = 1;
    return;
  }

  final generated = await _run(Platform.resolvedExecutable, <String>[
    'run',
    'build_runner',
    'build',
  ]);
  if (generated != 0) {
    stderr.writeln('okf: build_runner failed with exit code $generated');
    exitCode = generated;
    return;
  }

  final missing = <String>[
    for (final path in _generatedPaths)
      if (!File(path).existsSync()) path,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('okf: build_runner wrote no ${missing.join(', ')}');
    exitCode = 1;
    return;
  }

  final unchanged = await _run('git', <String>[
    'diff',
    '--exit-code',
    'HEAD',
    '--',
    ..._generatedPaths,
  ]);
  if (unchanged != 0) {
    stderr.writeln(
      'okf: the committed generated models are not current; run '
      '`dart run build_runner build` and commit all parts',
    );
    exitCode = 1;
  }
}

/// Whether Git tracks [path], which `git diff` requires to report a change.
bool _isTracked(String path) =>
    Process.runSync('git', <String>[
      'ls-files',
      '--error-unmatch',
      '--',
      path,
    ]).exitCode ==
    0;

/// Runs [executable] against the current console and returns its exit code.
Future<int> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
