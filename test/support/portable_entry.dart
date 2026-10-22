import 'package:okf/okf.dart';

/// Uses the portable library and nothing else, so a web compile of this file
/// fails as soon as `okf.dart` reaches `dart:io`.
///
/// Compiled by `test/ci/portable_entry_test.dart`.
void main() {
  final bundle = OkfBundle.fromDocuments(<String, OkfDocument>{
    'metrics/revenue.md': OkfDocument.parse('---\ntype: Metric\n---\n'),
  });
  final validation = const OkfSpecValidator().validate(bundle);
  final indexes = const OkfIndexGenerator().generate(bundle);
  if (!validation.isConformant ||
      indexes.isEmpty ||
      okfVersion.isEmpty ||
      okfIndexGeneratorRevision.isEmpty) {
    throw StateError('The portable library did not run.');
  }
}
