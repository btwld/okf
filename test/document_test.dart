import 'package:okf/okf.dart';
import 'package:test/test.dart';

void main() {
  group('OkfDocument.parse', () {
    test('reads ordered YAML frontmatter and Markdown body', () {
      const source = '''
---
type: BigQuery Table
title: Customer Orders
tags: [sales, orders]
custom:
  enabled: true
  weights: [1, 2]
---

# Customer Orders

One row per order.
''';

      final document = OkfDocument.parse(source);

      expect(document.hasFrontmatter, isTrue);
      expect(
        document.frontmatter.keys,
        orderedEquals(<String>['type', 'title', 'tags', 'custom']),
      );
      expect(document.type, 'BigQuery Table');
      expect(document.tags, <String>['sales', 'orders']);
      expect(document.frontmatter['custom'], <Object?, Object?>{
        'enabled': true,
        'weights': <Object?>[1, 2],
      });
      expect(document.body, startsWith('# Customer Orders'));
      expect(document.body, endsWith('\n'));
    });

    test('treats a body-only file as syntactically consumable', () {
      const source = '# Hello\r\n\r\nNo frontmatter here.';

      final document = OkfDocument.parse(source);

      expect(document.hasFrontmatter, isFalse);
      expect(document.frontmatter, isEmpty);
      expect(document.body, '# Hello\n\nNo frontmatter here.');
      expect(document.serialize(), '# Hello\n\nNo frontmatter here.\n');
    });

    test('accepts whitespace around delimiter lines', () {
      final document = OkfDocument.parse(
        '  ---  \r\ntype: Reference\r\n  ---\r\n\r\nBody\r\n',
      );

      expect(document.type, 'Reference');
      expect(document.body, 'Body\n');
    });

    test('rejects unterminated frontmatter with source context', () {
      expect(
        () => OkfDocument.parse(
          '---\ntype: Reference\n',
          sourcePath: 'concepts/example.md',
        ),
        throwsA(
          isA<OkfDocumentException>()
              .having(
                (error) => error.message,
                'message',
                contains('Unterminated'),
              )
              .having(
                (error) => error.sourcePath,
                'sourcePath',
                'concepts/example.md',
              ),
        ),
      );
    });

    test('rejects malformed YAML and reports a source position', () {
      try {
        OkfDocument.parse(
          '---\ntype: [unterminated\n---\n',
          sourcePath: 'bad.md',
        );
        fail('Expected malformed YAML to throw.');
      } on OkfDocumentException catch (error) {
        expect(error, isA<FormatException>());
        expect(error.message, contains('Invalid YAML'));
        expect(error.sourcePath, 'bad.md');
        expect(error.line, isNotNull);
        expect(error.column, isNotNull);
      }
    });

    test('rejects a non-mapping frontmatter value', () {
      expect(
        () => OkfDocument.parse('---\n- one\n- two\n---\n'),
        throwsA(
          isA<OkfDocumentException>().having(
            (error) => error.message,
            'message',
            contains('YAML mapping'),
          ),
        ),
      );
    });
  });

  group('OkfDocument serialization', () {
    test('uses preferred keys then preserves extension insertion order', () {
      final document = OkfDocument(
        frontmatter: <String, Object?>{
          'z_extension': 'last-ish',
          'sources': <Object?>[],
          'title': 'Orders',
          'type': 'BigQuery Table',
          'runtime': 'bigquery',
          'a_extension': <String, Object?>{'answer': 42},
        },
        body: '# Orders',
      );

      final serialized = document.serialize();

      expect(
        serialized,
        startsWith(
          '---\n'
          'type: BigQuery Table\n'
          'title: Orders\n'
          'sources: []\n'
          'runtime: bigquery\n'
          'z_extension: last-ish\n'
          'a_extension:\n'
          '  answer: 42\n'
          '---\n\n',
        ),
      );
      expect(serialized, endsWith('# Orders\n'));

      final reparsed = OkfDocument.parse(serialized);
      expect(reparsed.frontmatter, document.frontmatter);
      expect(reparsed.body, '# Orders\n');
    });

    test('quotes ambiguous strings without changing semantic values', () {
      final document = OkfDocument(
        frontmatter: <String, Object?>{
          'type': 'Reference',
          'looks_boolean': 'true',
          'looks_null': 'null',
          'date': '2026-07-27',
          'unicode': 'Conhecimento útil',
          'multiline': 'first\nsecond',
          'colon_space': 'BigQuery Table: votes',
          'trailing_colon': 'Label:',
        },
      );

      final serialized = document.serialize();
      final reparsed = OkfDocument.parse(serialized);

      expect(reparsed.frontmatter, document.frontmatter);
      expect(serialized, contains('looks_boolean: "true"'));
      expect(serialized, contains('date: "2026-07-27"'));
      expect(serialized, contains('unicode: "Conhecimento útil"'));
      expect(serialized, contains('colon_space: "BigQuery Table: votes"'));
      expect(serialized, contains('trailing_colon: "Label:"'));
    });

    test('rejects unsupported values and cyclic Dart collections', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);

      expect(
        () => OkfDocument(
          frontmatter: <String, Object?>{
            'type': 'Reference',
            'unsupported': const Duration(seconds: 1),
          },
        ).serialize(),
        throwsA(isA<OkfYamlEncodeException>()),
      );
      expect(
        () => OkfDocument(
          frontmatter: <String, Object?>{'type': 'Reference', 'cyclic': cyclic},
        ).serialize(),
        throwsA(isA<OkfYamlEncodeException>()),
      );
    });

    test('round-trips nested source and verification structures', () {
      const source = '''
---
type: Metric
verified: {by: "human:ana", at: "2026-07-20T12:00:00Z"}
sources:
  - id: policy
    resource: https://example.com/policy
    custom_signal:
      confidence: 0.8
unknown_top: [one, {two: 2}]
---

Body.
''';
      final first = OkfDocument.parse(source);
      final second = OkfDocument.parse(first.serialize());

      expect(second.frontmatter, first.frontmatter);
      expect(second.body, first.body);
      expect(second.trustTier, OkfTrustTier.humanReviewed);
    });

    test('serializes an explicitly empty frontmatter block', () {
      final document = OkfDocument();

      expect(document.serialize(), '---\n---\n\n');
      final reparsed = OkfDocument.parse(document.serialize());
      expect(reparsed.hasFrontmatter, isTrue);
      expect(reparsed.frontmatter, isEmpty);
      expect(reparsed.body, isEmpty);
    });

    test('copyWith preserves unknown values', () {
      final original = OkfDocument(
        frontmatter: <String, Object?>{
          'type': 'Reference',
          'vendor': <String, Object?>{'flag': true},
        },
        body: 'Old',
      );

      final updated = original.copyWith(body: 'New');

      expect(updated.frontmatter['vendor'], <String, Object?>{'flag': true});
      expect(updated.body, 'New');
      expect(original.body, 'Old');
    });
  });

  group('OkfDocument.bodyStartLine', () {
    test('is line 1 without frontmatter', () {
      const source = '# Title\n\nText\n';

      final document = OkfDocument.parse(source);

      expect(document.hasFrontmatter, isFalse);
      expect(document.bodyStartLine, 1);
      _expectBodyLinesMatchSource(source, document);
      expect(OkfDocument.parse('').bodyStartLine, 1);
    });

    test('is the line after the separator blank line', () {
      const source = '---\ntype: Note\n---\n\n# Title\n\nText\n';

      final document = OkfDocument.parse(source);

      expect(document.body, '# Title\n\nText\n');
      expect(document.bodyStartLine, 5);
      _expectBodyLinesMatchSource(source, document);
      expect(
        OkfDocument.parse('---\ntype: Note\n---\n# Title\n').bodyStartLine,
        4,
      );
    });

    test('puts an empty body one line past the last line', () {
      for (final MapEntry(key: source, value: line) in const <String, int>{
        '---\ntype: Note\n---': 4,
        '---\ntype: Note\n---\n': 4,
        '---\ntype: Note\n---\n\n': 5,
        '---\n---\n': 3,
      }.entries) {
        final document = OkfDocument.parse(source);

        expect(document.body, isEmpty, reason: source);
        expect(document.bodyStartLine, line, reason: source);
        expect(document.bodyStartLine, _lineCount(source) + 1, reason: source);
      }
    });

    test('counts CRLF and lone CR line endings as one line each', () {
      for (final source in const <String>[
        '---\r\ntype: Note\r\n---\r\n\r\n# Title\r\n\r\nText\r\n',
        '---\rtype: Note\r---\r\r# Title\r\rText\r',
        '---\r\ntype: Note\n---\r\r\n# Title\n\rText\r\n',
      ]) {
        final document = OkfDocument.parse(source);

        expect(document.body, '# Title\n\nText\n', reason: source);
        expect(document.bodyStartLine, 5, reason: source);
        _expectBodyLinesMatchSource(source, document);
      }
    });

    test('adds no line for a byte order mark', () {
      const source = '﻿---\ntype: Note\n---\n\n# Title\n';

      final document = OkfDocument.parse(source);

      expect(document.type, 'Note');
      expect(document.bodyStartLine, 5);
      _expectBodyLinesMatchSource(source, document);

      const bodyOnly = '﻿# Title\r\nText\r\n';
      final plain = OkfDocument.parse(bodyOnly);
      expect(plain.hasFrontmatter, isFalse);
      expect(plain.bodyStartLine, 1);
      _expectBodyLinesMatchSource(bodyOnly, plain);
    });

    test('counts blank lines around the frontmatter', () {
      const inside = '---\ntype: Note\n\n\n---\n\n# Title\n';
      const after = '---\ntype: Note\n---\n\n\n\n# Title\n';
      const whitespaceSeparator = '---\ntype: Note\n---\n  \n# Title\n';

      final insideDocument = OkfDocument.parse(inside);
      final afterDocument = OkfDocument.parse(after);
      final whitespaceDocument = OkfDocument.parse(whitespaceSeparator);

      expect(insideDocument.body, '# Title\n');
      expect(insideDocument.bodyStartLine, 7);
      _expectBodyLinesMatchSource(inside, insideDocument);
      // Only one separator line is dropped; the rest belong to the body.
      expect(afterDocument.body, '\n\n# Title\n');
      expect(afterDocument.bodyStartLine, 5);
      _expectBodyLinesMatchSource(after, afterDocument);
      // A whitespace-only line is body text, not the separator.
      expect(whitespaceDocument.body, '  \n# Title\n');
      expect(whitespaceDocument.bodyStartLine, 4);
      _expectBodyLinesMatchSource(whitespaceSeparator, whitespaceDocument);
    });

    test('does not confuse a body that repeats the frontmatter', () {
      const source =
          '---\ntype: Note\ntitle: Same\n---\n\n'
          'title: Same\n---\ntype: Note\ntitle: Same\n---\n';

      final document = OkfDocument.parse(source);

      expect(document.title, 'Same');
      expect(document.body, 'title: Same\n---\ntype: Note\ntitle: Same\n---\n');
      // A search for the body's first line finds the frontmatter's line 3.
      final firstBodyLine = document.body.split('\n').first;
      expect(_sourceLines(source).indexOf(firstBodyLine) + 1, 3);
      expect(document.bodyStartLine, 6);
      _expectBodyLinesMatchSource(source, document);
    });

    test('is null for documents built in memory', () {
      final parsed = OkfDocument.parse('---\ntype: Note\n---\n\nBody\n');

      expect(OkfDocument(body: 'Body\n').bodyStartLine, isNull);
      expect(parsed.copyWith().bodyStartLine, isNull);
      expect(parsed.copyWith(body: 'Other\n').bodyStartLine, isNull);
      expect(OkfDocument.parse(parsed.serialize()).bodyStartLine, 5);
    });
  });

  group('legacy citations', () {
    test('citation JSON preserves the original Markdown spelling', () {
      const raw = '[7] [Policy](../references/policy.md)';
      final citation = OkfDocument(
        body: '# Citations\n\n$raw\n',
      ).legacyCitations.single;
      final json = <String, Object?>{
        'number': 7,
        'title': 'Policy',
        'target': '../references/policy.md',
        'raw': raw,
      };

      expect(citation.toJson(), json);
      final decoded = OkfLegacyCitationSchema.fromJson(json);
      expect(<OkfLegacyCitation>{citation, decoded}, hasLength(1));
      expect(decoded.raw, raw);
    });

    test('extracts numbered links only from top-level Citations sections', () {
      final document = OkfDocument(
        frontmatter: <String, Object?>{'type': 'Reference'},
        body: '''
# Context

[9] [Not a citation](https://example.com/no)

# Citations

[1] [Policy](https://example.com/policy)
[2] [Runbook](../references/runbook.md)

# Other

[3] [Outside](https://example.com/outside)
''',
      );

      expect(document.legacyCitations, <OkfLegacyCitation>[
        const OkfLegacyCitation(
          number: 1,
          title: 'Policy',
          target: 'https://example.com/policy',
          raw: '[1] [Policy](https://example.com/policy)',
        ),
        const OkfLegacyCitation(
          number: 2,
          title: 'Runbook',
          target: '../references/runbook.md',
          raw: '[2] [Runbook](../references/runbook.md)',
        ),
      ]);
      expect(document.hasLegacyCitations, isTrue);
      expect(document.citations, document.legacyCitations);
    });

    test('extracts the bullet-list form shown by the v0.1 specification', () {
      final document = OkfDocument(
        frontmatter: <String, Object?>{'type': 'Reference'},
        body: '''
# Citations

- https://wiki.example/fpa-handbook
* [Revenue policy](https://wiki.example/revenue_(policy))
''',
      );

      expect(
        document.legacyCitations.map((citation) => citation.target).toList(),
        <String>[
          'https://wiki.example/fpa-handbook',
          'https://wiki.example/revenue_(policy)',
        ],
      );
    });
  });

  test('rejects cyclic YAML aliases without overflowing the stack', () {
    expect(
      () => OkfDocument.parse('''
---
type: Reference
cycle: &cycle [*cycle]
---
'''),
      throwsA(
        isA<OkfDocumentException>().having(
          (error) => error.message,
          'message',
          anyOf(
            contains('Cyclic YAML aliases'),
            contains('Self-referential collections'),
          ),
        ),
      ),
    );
  });
}

/// Splits [source] where [OkfDocument.parse] ends a line: LF, CRLF or a lone
/// CR. A final line break leaves an empty last element.
List<String> _sourceLines(String source) => source.split(RegExp('\r\n|\r|\n'));

/// The number of lines in [source], where a final line break ends the last
/// line rather than starting another.
int _lineCount(String source) {
  if (source.isEmpty) {
    return 0;
  }
  final lines = _sourceLines(source);
  return lines.last.isEmpty ? lines.length - 1 : lines.length;
}

/// Expects line `n` of [document]'s body to be line `bodyStartLine + n - 1`
/// of [source], through to the source's end, and the body's last line, counted
/// as [OkfDocument.bodyStartLine] documents, to be the source's last line.
void _expectBodyLinesMatchSource(String source, OkfDocument document) {
  final sourceLines = _sourceLines(source);
  final bodyLines = document.body.split('\n');
  final start = document.bodyStartLine!;

  expect(
    start + _lineCount(document.body) - 1,
    _lineCount(source),
    reason: source,
  );
  expect(start + bodyLines.length - 1, sourceLines.length, reason: source);
  for (var line = 1; line <= bodyLines.length; line++) {
    expect(
      sourceLines[start + line - 2],
      bodyLines[line - 1],
      reason: 'body line $line of $source',
    );
  }
}
