import 'package:okf/okf.dart';

/// Uses the portable library and nothing else.
///
/// `test/ci/portable_entry_test.dart` compiles this file to JavaScript and,
/// where `node` is on `PATH`, runs the output, so [main] throws when the
/// library misbehaves there. dart2js stubs `dart:io` instead of rejecting it,
/// so the compile alone would accept a native import: the import walk in that
/// test is what fails when `okf.dart` reaches one.
void main() {
  final document = OkfDocument.parse('---\r\ntype: Metric\r\n---\r\n\r\nBody');
  final bundle = OkfBundle.fromDocuments(<String, OkfDocument>{
    'metrics/revenue.md': document,
  });
  final validation = const OkfSpecValidator().validate(bundle);
  final indexes = const OkfIndexGenerator().generate(bundle);
  if (!validation.isConformant ||
      indexes.isEmpty ||
      document.bodyStartLine != 5 ||
      document.sourceText != '---\r\ntype: Metric\r\n---\r\n\r\nBody' ||
      okfVersion.isEmpty ||
      okfIndexGeneratorRevision.isEmpty) {
    throw StateError('The portable library did not run.');
  }
}
