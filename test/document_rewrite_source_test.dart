import 'dart:io';

import 'package:okf/okf.dart';
import 'package:okf/src/frontmatter_rewriter.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the rewriter stays out of the public libraries', () {
    // Its layout rules are not a contract: hosts read the text a change
    // writes from its candidate (ADR-0010).
    for (final library in <String>['lib/okf.dart', 'lib/okf_io.dart']) {
      expect(
        File(library).readAsStringSync(),
        isNot(contains('frontmatter_rewriter')),
        reason: library,
      );
    }
  });

  group('OkfDocumentSourceRewrite.rewriteSource', () {
    test('returns the source unchanged when nothing changes', () {
      for (final MapEntry(key: name, value: source) in _fixtures.entries) {
        final document = OkfDocument.parse(source);

        expect(document.rewriteSource(), source, reason: name);
        expect(
          document.rewriteSource(
            frontmatter: Map<String, Object?>.of(document.frontmatter),
            body: document.body,
          ),
          source,
          reason: name,
        );
      }
    });

    test('keeps flow collections the change does not touch', () {
      expect(
        _rewrite(_styled, (frontmatter) => frontmatter['title'] = 'Net'),
        _styled.replaceFirst("title: 'Revenue'", 'title: Net'),
      );
    });

    test('edits a changed flow collection by spans', () {
      expect(
        _rewrite(_styled, (frontmatter) {
          frontmatter['tags'] = <Object?>['finance', 'monthly', 'q3 close'];
          frontmatter['generated'] = <String, Object?>{
            'by': 'agent:okf',
            'at': '2026-09-01T00:00:00Z',
          };
          frontmatter['verified'] = <String, Object?>{
            'by': 'human:reviewer',
            'at': '2026-09-02T00:00:00Z',
            'note': <Object?>[
              'ledger',
              <String, Object?>{'tie': 'out'},
            ],
          };
        }),
        _styled
            .replaceFirst(
              'tags: [finance, monthly]',
              'tags: [finance, monthly, q3 close]',
            )
            .replaceFirst(
              'generated: { by: agent:okf, at: 2026-08-01T00:00:00Z }',
              'generated: { by: agent:okf, at: "2026-09-01T00:00:00Z" }',
            )
            .replaceFirst(
              'verified: { by: "human:reviewer", at: "2026-08-02T00:00:00Z" }',
              'verified: { by: "human:reviewer", at: "2026-09-02T00:00:00Z", '
                  'note: [ledger, {tie: out}] }',
            ),
      );

      const source = '''
---
type: Metric
owners: [ana , bo]  # by seniority
review: {cadence: quarterly, steps: [draft, sign]}
aliases: [
  revenue,
  sales
]
---
''';
      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['owners'] = <Object?>['cy', 'bo', 'di'];
          frontmatter['review'] = <String, Object?>{
            'cadence': 'monthly',
            'steps': <Object?>['draft', 'sign', 'publish'],
          };
          frontmatter['aliases'] = <Object?>['revenue', 'sales', 'income'];
        }),
        '''
---
type: Metric
owners: [cy , bo, di]  # by seniority
review: {cadence: monthly, steps: [draft, sign, publish]}
aliases: [
  revenue,
  sales, income
]
---
''',
      );
    });

    test('rewrites a flow collection whole when it loses an entry', () {
      expect(
        _rewrite(
          '''
---
type: Metric
verified: { by: "human:reviewer", at: "2026-08-02T00:00:00Z" }  # kept
tags: [finance, monthly]
owner: {name}
---
''',
          (frontmatter) {
            frontmatter['verified'] = <String, Object?>{'by': 'human:reviewer'};
            frontmatter['tags'] = <Object?>['finance'];
            frontmatter['owner'] = <String, Object?>{'name': 'ana'};
          },
        ),
        '''
---
type: Metric
verified: {by: human:reviewer}  # kept
tags: [finance]
owner: {name: ana}
---
''',
        reason:
            'a removed entry or an omitted value is written whole, with '
            'OkfYamlEmitter.scalar spellings',
      );
    });

    test('keeps a changed block scalar a literal block', () {
      const source = '''
---
type: Metric
description: |
  Recognized revenue.
  # Not a comment.
summary: >-  # folded
    Folded
    text.
steps:
  - |
    Draft.
  - Sign.
owner: finance
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['description'] = 'Recognized revenue.\n\n  Indented.\n';
          frontmatter['summary'] = 'Folded\ntext';
          frontmatter['steps'] = <Object?>['Draft.\nReview.\n\n', 'Sign.'];
        }),
        '''
---
type: Metric
description: |
  Recognized revenue.

    Indented.
summary: |-  # folded
    Folded
    text
steps:
  - |+
    Draft.
    Review.

  - Sign.
owner: finance
---
''',
      );
    });

    test('writes a block scalar as a scalar when a literal block cannot '
        'hold it', () {
      const source = '''
---
type: Metric
a: |
  old
b: |
  old
c: |
  old
d: |
  old
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['a'] = 'one line';
          frontmatter['b'] = '  leading space\n';
          frontmatter['c'] = 'closes\n---\nthe block\n';
          frontmatter['d'] = 'tab\u0007bell\n';
        }),
        '''
---
type: Metric
a: one line
b: "  leading space\\n"
c: "closes\\n---\\nthe block\\n"
d: "tab\\u0007bell\\n"
---
''',
      );
    });

    test('keeps key order and does not move tags', () {
      const source = '''
---
title: Revenue
owner: finance-team
tags: [finance]
type: Metric
---
''';

      final rewritten = _rewrite(source, (frontmatter) {
        frontmatter['description'] = 'Monthly revenue.';
        frontmatter['owner'] = 'controller';
      });

      expect(rewritten, '''
---
title: Revenue
owner: controller
tags: [finance]
type: Metric
description: Monthly revenue.
---
''');
      expect(
        OkfDocument.parse(rewritten).serialize(),
        startsWith('---\ntype: Metric\ntitle: Revenue\n'),
        reason: 'the canonical form would have moved type and tags',
      );
    });

    test('keeps quoting and multi-line strings', () {
      const source = '''
---
type: Metric
single: 'it''s quoted'
double: "with \\"escapes\\""
literal: |
  First line.
  # Not a comment.
folded: >-
  Folded
  text.
plain: one
  continued
status: draft
---
''';

      expect(
        _rewrite(source, (frontmatter) => frontmatter['status'] = 'stable'),
        source.replaceFirst('status: draft', 'status: stable'),
      );
    });

    test('replaces a changed scalar where it stands, keeping its comment', () {
      const source = '''
---
type: Metric
title: 'Revenue'   # shown in indexes
description: |
  Old text.
stale_after: 2026-08-01
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['title'] = 'Net revenue: monthly';
          frontmatter['description'] = 'New text.';
          frontmatter['stale_after'] = DateTime.utc(2026, 9);
        }),
        '''
---
type: Metric
title: "Net revenue: monthly"   # shown in indexes
description: New text.
stale_after: "2026-09-01T00:00:00.000Z"
---
''',
      );
    });

    test('keeps comments and blank lines', () {
      const source = '''
---
# Maintained by hand.
type: Metric

# Display fields
title: Revenue  # short
owner: finance-team
# Review metadata
review:
  # How often
  cadence: quarterly

# end of metadata
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter.remove('owner');
          frontmatter['review'] = <String, Object?>{'cadence': 'monthly'};
        }),
        source
            .replaceFirst('owner: finance-team\n', '')
            .replaceFirst('cadence: quarterly', 'cadence: monthly'),
      );
    });

    test('keeps CRLF line endings and a byte order mark', () {
      const source =
          '﻿---\r\n'
          'type: Metric\r\n'
          'tags: [finance]\r\n'
          'review:\r\n'
          '  cadence: quarterly\r\n'
          '---\r\n'
          '\r\n'
          '# Revenue\r\n';

      final rewritten = _rewrite(source, (frontmatter) {
        frontmatter['tags'] = <Object?>['finance', 'monthly'];
        frontmatter['review'] = <String, Object?>{
          'cadence': 'quarterly',
          'owners': <Object?>['ana', 'bo'],
        };
        frontmatter['status'] = 'stable';
      }, body: '# Revenue\n\nRewritten.\n');

      expect(
        rewritten,
        '﻿---\r\n'
        'type: Metric\r\n'
        'tags: [finance, monthly]\r\n'
        'review:\r\n'
        '  cadence: quarterly\r\n'
        '  owners:\r\n'
        '    - ana\r\n'
        '    - bo\r\n'
        'status: stable\r\n'
        '---\r\n'
        '\r\n'
        '# Revenue\r\n'
        '\r\n'
        'Rewritten.\r\n',
      );
      expect(rewritten.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('edits nested mappings entry by entry', () {
      const source = '''
---
type: Metric
generated:
  by: agent:okf  # the producer
  at: "2026-08-01T00:00:00Z"
  # model is optional
  model: opus
relationships:
  owner: finance
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['generated'] = <String, Object?>{
            'model': 'opus',
            'by': 'agent:okf',
            'at': '2026-09-01T00:00:00Z',
            'run': 7,
          };
          frontmatter['relationships'] = <String, Object?>{'reviewer': 'audit'};
        }),
        '''
---
type: Metric
generated:
  by: agent:okf  # the producer
  at: "2026-09-01T00:00:00Z"
  # model is optional
  model: opus
  run: 7
relationships:
  reviewer: audit
---
''',
      );
    });

    test('appends sequence items in the style of the last item', () {
      const source = '''
---
type: Metric
sources:
  - resource: a.md
    relationship: depends-on
verified:
  -
    by: human:ana
    at: "2026-08-01T00:00:00Z"
tags:
- finance
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['sources'] = <Object?>[
            ...frontmatter['sources']! as List<Object?>,
            <String, Object?>{'resource': 'b.md', 'relationship': 'mentions'},
          ];
          frontmatter['verified'] = <Object?>[
            ...frontmatter['verified']! as List<Object?>,
            <String, Object?>{'by': 'human:bo', 'at': '2026-09-01T00:00:00Z'},
          ];
          frontmatter['tags'] = <Object?>['finance', 'monthly'];
        }),
        '''
---
type: Metric
sources:
  - resource: a.md
    relationship: depends-on
  - resource: b.md
    relationship: mentions
verified:
  -
    by: human:ana
    at: "2026-08-01T00:00:00Z"
  -
    by: human:bo
    at: "2026-09-01T00:00:00Z"
tags:
- finance
- monthly
---
''',
      );
    });

    test('edits a changed sequence item in place', () {
      const source = '''
---
type: Metric
sources:
  - resource: a.md  # first
    relationship: depends-on
  - resource: b.md
    relationship: mentions
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['sources'] = <Object?>[
            <String, Object?>{'resource': 'a.md', 'relationship': 'depends-on'},
            <String, Object?>{'resource': 'c.md', 'relationship': 'mentions'},
          ];
        }),
        source.replaceFirst('resource: b.md', 'resource: c.md'),
      );
    });

    test('removes only the lines of a removed key', () {
      const source = '''
---
type: Metric
# The description is long.
description: |
  Line one.
  Line two.
# Kept after the removal.
owner: finance-team
review:
  cadence: quarterly
  owners: [ana]
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter.remove('description');
          frontmatter.remove('review');
        }),
        '''
---
type: Metric
# The description is long.
# Kept after the removal.
owner: finance-team
---
''',
      );
    });

    test('adds new keys after the last entry of their mapping', () {
      const source = '''
---
type: Metric
title: Revenue

# Owned by finance.
---

# Revenue
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['status'] = 'stable';
          frontmatter['tags'] = <Object?>['finance'];
          frontmatter['sources'] = <Object?>[
            <String, Object?>{'resource': 'a.md', 'relationship': 'uses'},
          ];
        }),
        '''
---
type: Metric
title: Revenue
status: stable
tags:
  - finance
sources:
  -
    resource: a.md
    relationship: uses

# Owned by finance.
---

# Revenue
''',
      );
      expect(
        _rewrite(
          '---\n# Nothing yet.\n---\nBody\n',
          (frontmatter) => frontmatter['type'] = 'Metric',
        ),
        '---\n# Nothing yet.\ntype: Metric\n---\nBody\n',
      );
    });

    test('keeps a canonical block canonical', () {
      // The block holds exactly what the emitter writes for it, as after
      // `okf format`, so new keys go to their preferred place and a filled
      // empty collection is written in block style.
      const canonical = '''
---
type: Metric
title: Revenue
tags: []
sources:
  -
    resource: ledger.md
    relationship: derived-from
owner: finance-team
---

# Revenue
''';

      expect(
        _rewrite(canonical, (frontmatter) {
          frontmatter['status'] = 'deprecated';
          frontmatter['description'] = 'Monthly.';
          frontmatter['x_added'] = 1;
        }),
        canonical
            .replaceFirst('tags: []\n', 'description: Monthly.\ntags: []\n')
            .replaceFirst('sources:\n', 'status: deprecated\nsources:\n')
            .replaceFirst(
              'owner: finance-team\n',
              'owner: finance-team\nx_added: 1\n',
            ),
      );
      expect(
        _rewrite(
          canonical,
          (frontmatter) => frontmatter['tags'] = <Object?>['finance'],
        ),
        canonical.replaceFirst('tags: []\n', 'tags:\n  - finance\n'),
      );
      expect(
        _rewrite(
          canonical.replaceAll('\n', '\r\n'),
          (frontmatter) => frontmatter['status'] = 'deprecated',
        ),
        canonical
            .replaceFirst('sources:\n', 'status: deprecated\nsources:\n')
            .replaceAll('\n', '\r\n'),
        reason: 'line breaks do not count, and stay',
      );

      // One respelled line makes the block hand-written, which keeps the
      // in-place rules.
      final quoted = canonical.replaceFirst(
        'title: Revenue',
        'title: "Revenue"',
      );
      expect(
        _rewrite(quoted, (frontmatter) => frontmatter['status'] = 'deprecated'),
        quoted.replaceFirst(
          'owner: finance-team\n',
          'owner: finance-team\nstatus: deprecated\n',
        ),
      );
      expect(
        _rewrite(
          quoted,
          (frontmatter) => frontmatter['tags'] = <Object?>['finance'],
        ),
        quoted.replaceFirst('tags: []', 'tags: [finance]'),
      );
    });

    test('keeps every fixture canonical once it is formatted', () {
      var edits = 0;
      for (final MapEntry(key: name, value: fixture) in _fixtures.entries) {
        final String source;
        try {
          source = OkfDocument.parse(fixture).serialize();
        } on OkfYamlEncodeException {
          continue;
        }
        final document = OkfDocument.parse(source);
        final original = document.frontmatter;
        for (final (label, frontmatter) in <(String, Map<String, Object?>)>[
          for (final key in okfPreferredFrontmatterKeyOrder)
            if (!original.containsKey(key))
              ('add $key', <String, Object?>{...original, key: 'added'}),
          (
            'add tags',
            <String, Object?>{
              ...original,
              'tags': <Object?>['a'],
            },
          ),
          (
            'add an unknown key',
            <String, Object?>{...original, 'x_added': <Object?>[]},
          ),
          for (final key in original.keys) ...<(String, Map<String, Object?>)>[
            ('set $key', <String, Object?>{...original, key: 'changed'}),
            ('remove $key', Map.of(original)..remove(key)),
            if (original[key] case final List<Object?> items)
              (
                'append to $key',
                <String, Object?>{
                  ...original,
                  key: <Object?>[...items, 'appended'],
                },
              ),
            if (original[key] case final Map<Object?, Object?> entries)
              (
                'add inside $key',
                <String, Object?>{
                  ...original,
                  key: <Object?, Object?>{...entries, 'x_added': 1},
                },
              ),
          ],
        ]) {
          edits++;
          final rewritten = document.rewriteSource(frontmatter: frontmatter);
          expect(
            OkfDocument.parse(rewritten).frontmatter,
            frontmatter,
            reason: '$name: $label reads back',
          );
          expect(
            OkfDocument.parse(rewritten).serialize(),
            rewritten,
            reason: '$name: $label stays canonical',
          );
        }
      }
      expect(edits, greaterThan(100));
    });

    test('keeps the frontmatter byte-identical when only the body changes', () {
      final document = OkfDocument.parse(_styled);
      final reordered = <String, Object?>{
        for (final key in document.frontmatter.keys.toList().reversed)
          key: document.frontmatter[key],
      };
      reordered['generated'] = <String, Object?>{
        'at': '2026-08-01T00:00:00Z',
        'by': 'agent:okf',
      };

      final rewritten = document.rewriteSource(
        frontmatter: reordered,
        body: '# Revenue\n\nRewritten.',
      );

      expect(
        rewritten,
        '${_styled.substring(0, _styled.indexOf('# Revenue'))}'
        '# Revenue\n\nRewritten.\n',
      );
      expect(
        document.rewriteSource(frontmatter: reordered),
        _styled,
        reason: 'an equal mapping in another order is not a change',
      );
    });

    test('re-emits a changed top-level value whose nested edit does not '
        'read back', () {
      // Removing `owner` leaves the keeping block scalar's blank line as the
      // YAML's last line, which adds nothing to it, so the nested edit reads
      // back as `kept\n`. Replacing the whole `review` value reads back.
      const source = '''
---
# Reviewed quarterly.
type: Metric
tags: [finance]  # kept
review:
  note: |+
    kept

  owner: finance
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['review'] = <String, Object?>{'note': 'kept\n\n'};
        }),
        '''
---
# Reviewed quarterly.
type: Metric
tags: [finance]  # kept
review:
  note: "kept\\n\\n"
---
''',
      );
    });

    test('re-emits a changed top-level value it cannot edit inside', () {
      const source = '''
---
type: Metric
sources:
  - resource: a.md
    relationship: depends-on
tags: [finance]  # kept
---
''';

      expect(
        _rewrite(source, (frontmatter) {
          frontmatter['sources'] = <Object?>[
            <String, Object?>{'relationship': 'depends-on'},
          ];
        }),
        '''
---
type: Metric
sources:
  -
    relationship: depends-on
tags: [finance]  # kept
---
''',
        reason: 'removing the first key of a `- key:` item would drop its -',
      );
    });

    test('re-emits the whole mapping where it cannot edit in place', () {
      void retitle(Map<String, Object?> frontmatter) =>
          frontmatter['title'] = 'Net';
      for (final (source, change)
          in <(String, void Function(Map<String, Object?>))>[
            // A flow mapping.
            ('---\n{type: Metric, title: Revenue}\n---\n\nBody\n', retitle),
            // An alias.
            (
              '---\ntype: Metric\nowner: &team finance\n'
                  'reviewer: *team\n---\n\nBody\n',
              retitle,
            ),
            // An explicit key.
            ('---\ntype: Metric\n? title\n: Revenue\n---\n\nBody\n', retitle),
            // Removing the last key, after a keeping block scalar: the scalar's
            // trailing blank line would become the YAML's last line, which adds
            // nothing to it, so the edit does not read back.
            (
              '---\ntype: Metric\nnote: |+\n  kept\n\nowner: finance\n---\n\n'
                  'Body\n',
              (frontmatter) => frontmatter.remove('owner'),
            ),
          ]) {
        final document = OkfDocument.parse(source);
        final frontmatter = Map<String, Object?>.of(document.frontmatter);
        change(frontmatter);

        expect(
          document.rewriteSource(frontmatter: frontmatter),
          '---\n${const OkfYamlEmitter().emit(frontmatter)}\n---\n\nBody\n',
          reason: source,
        );
      }
    });

    test('keeps a byte order mark in front of an added frontmatter block', () {
      final document = OkfDocument.parse('\uFEFF# Revenue\n');

      expect(
        document.rewriteSource(
          frontmatter: const <String, Object?>{'type': 'Metric'},
        ),
        '\uFEFF---\ntype: Metric\n---\n\n# Revenue\n',
      );
      expect(
        document.rewriteSource(
          frontmatter: const <String, Object?>{'type': 'Metric'},
          body: '# Revenue',
        ),
        '---\ntype: Metric\n---\n\n# Revenue\n',
        reason: 'a body-only document holds the mark in its body',
      );
    });

    test('refuses a body that would read back as a frontmatter block', () {
      for (final body in const <String>[
        '---\ntype: Injected\n---\nhi\n',
        '---\nno close\n',
        '  ---  \nhi\n',
      ]) {
        expect(
          () => OkfDocument.parse('# Plain body\n').rewriteSource(body: body),
          throwsA(isA<OkfYamlEncodeException>()),
          reason: body,
        );
        expect(
          () => OkfDocument(
            body: 'Plain.',
            hasFrontmatter: false,
          ).rewriteSource(body: body),
          throwsA(isA<OkfYamlEncodeException>()),
          reason: body,
        );
        expect(
          OkfDocument.parse(
            '---\ntype: Metric\n---\n',
          ).rewriteSource(body: body),
          '---\ntype: Metric\n---\n\n$body',
          reason: 'after a frontmatter block it is an ordinary body',
        );
      }
    });

    test('writes a frontmatter block in front of a body-only document', () {
      final document = OkfDocument.parse('# Revenue\r\n\r\nText.');

      expect(
        document.rewriteSource(
          frontmatter: const <String, Object?>{'type': 'Metric'},
        ),
        '---\r\ntype: Metric\r\n---\r\n\r\n# Revenue\r\n\r\nText.',
      );
      expect(
        document.rewriteSource(body: 'Other.'),
        'Other.\r\n',
        reason: 'without frontmatter, only the body is written',
      );
    });

    test('writes a document without source text in canonical form', () {
      final document = OkfDocument(
        frontmatter: const <String, Object?>{'title': 'Revenue'},
        body: '# Revenue',
      );
      final frontmatter = <String, Object?>{
        ...document.frontmatter,
        'type': 'Metric',
      };

      expect(document.sourceText, isNull);
      expect(
        document.rewriteSource(frontmatter: frontmatter),
        document.copyWith(frontmatter: frontmatter).serialize(),
      );
    });

    test('throws when a value cannot be written so that it reads back', () {
      final document = OkfDocument.parse('---\ntype: Metric\n---\n');

      expect(
        () => document.rewriteSource(
          frontmatter: const <String, Object?>{
            'type': 'Metric',
            'title': '\uD800',
          },
        ),
        throwsA(isA<OkfYamlEncodeException>()),
      );
      expect(
        () => document.rewriteSource(
          frontmatter: <String, Object?>{'type': Object()},
        ),
        throwsA(isA<OkfYamlEncodeException>()),
      );
    });

    test('keeps every untouched entry of every fixture', () {
      var edits = 0;
      for (final MapEntry(key: name, value: source) in _fixtures.entries) {
        final document = OkfDocument.parse(source);
        final original = document.frontmatter;
        final cases = <(String, Map<String, Object?>, Set<String>)>[
          (
            'add',
            <String, Object?>{
              ...original,
              'x_added': <Object?>['a', 'b'],
            },
            const <String>{},
          ),
          for (final key in original.keys) ...<
            (String, Map<String, Object?>, Set<String>)
          >[
            (
              'set $key',
              <String, Object?>{...original, key: 'changed'},
              <String>{key},
            ),
            ('remove $key', Map.of(original)..remove(key), <String>{key}),
            if (original[key] case final List<Object?> items
                when items.isNotEmpty)
              (
                'append to $key',
                <String, Object?>{
                  ...original,
                  key: <Object?>[...items, items.first],
                },
                <String>{key},
              ),
            if (original[key] case final Map<Object?, Object?> entries
                when entries.isNotEmpty)
              (
                'edit inside $key',
                <String, Object?>{
                  ...original,
                  key: <Object?, Object?>{
                    ...entries,
                    entries.keys.first: 'changed',
                    'x_added': 1,
                  },
                },
                <String>{key},
              ),
          ],
        ];
        for (final (label, frontmatter, touched) in cases) {
          edits++;
          final rewritten = document.rewriteSource(frontmatter: frontmatter);
          final parsed = OkfDocument.parse(rewritten);

          expect(
            parsed.frontmatter,
            frontmatter,
            reason: '$name: $label reads back',
          );
          expect(parsed.body, document.body, reason: '$name: $label body');
          if (source.contains('\r\n')) {
            expect(
              rewritten.replaceAll('\r\n', ''),
              isNot(contains('\n')),
              reason: '$name: $label keeps CRLF line breaks',
            );
          }
          expect(
            _isSubsequence(_untouchedLines(source, touched), _lines(rewritten)),
            isTrue,
            reason: '$name: $label keeps untouched lines\n$rewritten',
          );
        }
      }
      expect(edits, greaterThan(100));
    });
  });
}

/// Applies [change] to the frontmatter parsed from [source] and rewrites it,
/// checking that the result reads back as the changed mapping.
String _rewrite(
  String source,
  void Function(Map<String, Object?> frontmatter) change, {
  String? body,
}) {
  final document = OkfDocument.parse(source);
  final frontmatter = Map<String, Object?>.of(document.frontmatter);
  change(frontmatter);
  final rewritten = document.rewriteSource(
    frontmatter: frontmatter,
    body: body,
  );
  final parsed = OkfDocument.parse(rewritten);
  expect(parsed.frontmatter, _yamlData(frontmatter));
  return rewritten;
}

/// [frontmatter] as it reads back: dates as their ISO 8601 strings.
Object? _yamlData(Object? value) => switch (value) {
  DateTime() => value.toIso8601String(),
  Map() => <Object?, Object?>{
    for (final entry in value.entries)
      _yamlData(entry.key): _yamlData(entry.value),
  },
  List() => <Object?>[for (final item in value) _yamlData(item)],
  _ => value,
};

List<String> _lines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

/// The lines of [source] outside the regions of the [touched] top-level
/// keys, where a key's region runs from its line to the next key's.
List<String> _untouchedLines(String source, Set<String> touched) {
  final lines = _lines(source);
  final closing = lines.indexWhere((line) => line.trim() == '---', 1);
  final yaml = lines.sublist(1, closing).join('\n');
  final root = yaml.trim().isEmpty ? null : loadYamlNode(yaml);
  final keys = root is YamlMap
      ? root.nodes.keys.cast<YamlNode>().toList()
      : const <YamlNode>[];
  final skipped = <int>{};
  for (var index = 0; index < keys.length; index++) {
    if (!touched.contains(keys[index].value)) {
      continue;
    }
    final start = keys[index].span.start.line + 1;
    final end = index + 1 < keys.length
        ? keys[index + 1].span.start.line + 1
        : closing;
    skipped.addAll(<int>[for (var line = start; line < end; line++) line]);
  }
  return <String>[
    for (var line = 0; line < lines.length; line++)
      if (!skipped.contains(line)) lines[line],
  ];
}

bool _isSubsequence(List<String> needle, List<String> haystack) {
  var matched = 0;
  for (final line in haystack) {
    if (matched < needle.length && needle[matched] == line) {
      matched++;
    }
  }
  return matched == needle.length;
}

const String _styled = '''
---
type: Metric
title: 'Revenue'
tags: [finance, monthly]
generated: { by: agent:okf, at: 2026-08-01T00:00:00Z }
verified: { by: "human:reviewer", at: "2026-08-02T00:00:00Z" }
sources:
  - resource: /references/ledger.md
    relationship: derived-from
---

# Revenue
''';

/// Concept documents in the styles okf's own tests, its README and the
/// documents it writes use, and in the styles people write by hand.
const Map<String, String> _fixtures = <String, String>{
  'README example': '''
---
type: Metric
title: Revenue
verified: {by: "human:reviewer", at: "2026-07-27T12:00:00Z"}
---

# Revenue
''',
  'change-set seed': '''
---
type: Metric
title: Revenue
description: Monthly revenue.
---

# Revenue
''',
  'test support concept': '''
---
type: Reference
title: Alpha
status: retired
---

# Alpha
''',
  'canonical emitter output': '''
---
type: Metric
title: Revenue
description: "Revenue: monthly"
tags:
  - finance
status: stable
generated:
  by: agent:okf
  at: "2026-08-01T00:00:00Z"
verified:
  -
    by: human:ana
    at: "2026-08-02T00:00:00Z"
sources:
  -
    resource: ../ledger.md
    relationship: derived-from
owner: finance-team
---

# Revenue
''',
  'hand-written flow style': _styled,
  'comments and blank lines': '''
---
# Owned by finance.
type: Metric  # the concept type

title: "Revenue"
# Tags drive the index.
tags: [finance, 'q3 close']
review:
  cadence: quarterly  # set by the controller
  # owners are optional
  owners:
  - ana
  - bo

# end
---

# Revenue
''',
  'multi-line strings': '''
---
type: Metric
description: |
  Recognized revenue.
  # Not a comment.
summary: >-
  Folded
  text.
note: plain
  continued
quote: "double
  quoted"
---
''',
  'nested and omitted values': '''
---
type: Metric
owner:
relationships:
  - relationship: depends-on
    resource: ledger.md
    detail:
      confidence: 0.9
      reviewed: true
  -
    relationship: mentions
    resource: churn.md
empty_list: []
empty_map: {}
---
''',
  'CRLF with a byte order mark':
      '﻿---\r\n'
      'type: Metric\r\n'
      'tags: [finance]\r\n'
      'review:\r\n'
      '  cadence: quarterly\r\n'
      '---\r\n'
      '\r\n'
      '# Revenue\r\n',
  'indented mapping': '''
---
  type: Metric
  title: Revenue
  review:
      cadence: quarterly
---
''',
};
