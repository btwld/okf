import 'package:ack/ack.dart';

import '../concept_id.dart';

part 'inputs.g.dart';

// The wire schema owns presence: optional arguments may be omitted, but may
// not be null. Defaults belong to the tool implementation, especially for
// partial updates where omission must leave the existing value alone.

final _conceptIdSchema = Ack.string()
    .minLength(1)
    .describe('Bundle-relative concept ID, without the .md suffix.')
    .codec<OkfConceptId>(decode: OkfConceptId.new, encode: (id) => id.value);
final _conceptTypeSchema = Ack.string()
    .minLength(1)
    .describe('OKF concept type, such as Reference, Metric, or Note.');
final _titleSchema = Ack.string().minLength(1).describe('Display name.');
final _descriptionSchema = Ack.string().describe('One-line summary.');
final _tagsSchema = Ack.list(
  Ack.string().minLength(1),
).unique().describe('Cross-cutting category tags.');
final _bodySchema = Ack.string().describe(
  'Markdown body below the frontmatter.',
);

@Schemable()
final listConceptsInputSchema = Ack.object({
  'prefix': Ack.string()
      .minLength(1)
      .describe(
        'Bundle area to list: a concept whose ID is the '
        'prefix or lives under it as a directory matches.',
      )
      .optional(),
  'type': Ack.string()
      .minLength(1)
      .describe(
        'Exact concept type to keep, spelled as the bundle '
        'spells it; an empty result reports the types the bundle '
        'actually holds.',
      )
      .optional(),
  'query': Ack.string()
      .minLength(1)
      .describe(
        'Case-insensitive substring matched against each concept ID and title.',
      )
      .optional(),
});

@Schemable()
final lookupConceptInputSchema = Ack.object({'id': _conceptIdSchema});

@Schemable()
final validateInputSchema = Ack.object({
  'strict': Ack.boolean()
      .describe('Fail on advisories, as `--warnings-as-errors` does.')
      .optional(),
});

@Schemable()
final createConceptInputSchema = Ack.object({
  'id': _conceptIdSchema,
  'type': _conceptTypeSchema,
  'title': _titleSchema.optional(),
  'description': _descriptionSchema.optional(),
  'tags': _tagsSchema.optional(),
  'body': _bodySchema.optional(),
});

@Schemable()
final updateConceptInputSchema = Ack.object({
  'id': _conceptIdSchema,
  'type': _conceptTypeSchema.optional(),
  'title': _titleSchema.optional(),
  'description': _descriptionSchema.optional(),
  'tags': _tagsSchema.optional(),
  'body': _bodySchema.optional(),
});

@Schemable()
final linkConceptsInputSchema = Ack.object({
  'source': _conceptIdSchema,
  'target': _conceptIdSchema,
  'relationship': Ack.string()
      .minLength(1)
      .matches(r'\S')
      .describe('Producer-defined relationship type.'),
});

@Schemable()
final deprecateConceptInputSchema = Ack.object({
  'id': _conceptIdSchema,
  'note': Ack.string()
      .describe('Context recorded with the lifecycle change.')
      .optional(),
});
