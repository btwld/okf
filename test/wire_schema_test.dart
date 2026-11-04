import 'package:okf/okf.dart';
import 'package:test/test.dart';

void main() {
  for (final (name, schema, json, field) in [
    (
      'OkfLegacyCitationSchema.wireSchema',
      OkfLegacyCitationSchema.wireSchema,
      <String, Object?>{
        'number': 7,
        'title': 'Policy',
        'target': '../references/policy.md',
        'raw': '[7] [Policy](../references/policy.md)',
      },
      'title',
    ),
    (
      'OkfIndexEntrySchema.wireSchema',
      OkfIndexEntrySchema.wireSchema,
      <String, Object?>{
        'type': 'Reference',
        'title': 'Policy',
        'link': 'policy.md',
        'description': 'Original.',
      },
      'title',
    ),
    (
      'OkfLogEntrySchema.wireSchema',
      OkfLogEntrySchema.wireSchema,
      <String, Object?>{
        'date': '2026-08-14',
        'action': 'Creation',
        'description': 'Added [Policy](policy.md).',
      },
      'description',
    ),
  ]) {
    group(name, () {
      for (final (operation, convert) in [
        ('parse', schema.parse),
        ('encode', schema.encode),
      ]) {
        test('$operation returns a detached, unmodifiable map', () {
          final input = Map<String, Object?>.from(json);
          final result = convert(input)!;

          expect(result, json);
          expect(identical(result, input), isFalse);

          input[field] = 'Changed input';
          expect(result[field], json[field]);
          expect(
            () => result[field] = 'Changed result',
            throwsUnsupportedError,
          );

          final editable = Map<String, Object?>.from(result);
          editable[field] = 'Changed copy';
          expect(editable[field], 'Changed copy');
          expect(result[field], json[field]);
        });
      }
    });
  }
}
