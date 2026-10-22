import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support.dart';

void main() {
  late Directory root;
  late OkfBundleChangeApplier changes;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('okf-change-set-test-');
    changes = OkfBundleChangeApplier(clock: () => DateTime.utc(2026, 8, 18));
    await _seedBundle(root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'prepare is non-mutating and commit writes the prepared candidate',
    () async {
      final before = await _snapshot(root);
      final preparation = await changes.prepare(root.path, _createChurn());

      expect(preparation, isA<OkfPreparationReady>());
      expect(await _snapshot(root), before);
      final prepared = (preparation as OkfPreparationReady).prepared;
      expect(prepared.validation.isConformant, isTrue);
      expect(
        prepared.validation.report.toJson(),
        const OkfSpecValidator()
            .validate(prepared.candidate.toBundle())
            .report
            .toJson(),
      );

      final result = await changes.commit(prepared);
      expect(
        result.changedPaths,
        containsAll(<String>['metrics/churn.md', 'metrics/index.md', 'log.md']),
      );
      expect(
        await _read(root, 'metrics/churn.md'),
        prepared.candidate.concepts['metrics/churn.md'],
      );

      final loaded = await const OkfBundleLoader().inspect(root.path);
      expect(
        loaded.validate().report.toJson(),
        prepared.validation.report.toJson(),
        reason: 'ordinary validation and preparation share the Spec report',
      );
    },
  );

  test('a Spec-invalid candidate is refused without changing a file', () async {
    final before = await _snapshot(root);
    final result = await changes.prepare(
      root.path,
      OkfBundleChangeSet(<OkfBundleChange>[
        OkfCreateConceptChange(
          id: OkfConceptId('metrics/untyped'),
          document: OkfDocument(),
        ),
      ]),
    );

    expect(result, isA<OkfPreparationRefused>());
    final refusal = result as OkfPreparationRefused;
    expect(refusal.validation.isConformant, isFalse);
    expect(
      refusal.validation.report.findings.map((finding) => finding.id.value),
      contains('okf/missing-type'),
    );
    expect(refusal.candidate?.concepts, contains('metrics/untyped.md'));
    expect(await _snapshot(root), before);
  });

  test('replacing a malformed file removes its stale load finding', () async {
    await File(p.join(root.path, 'fixed.md')).writeAsBytes(<int>[0xff]);
    final result = await changes.prepare(
      root.path,
      OkfBundleChangeSet(<OkfBundleChange>[
        OkfCreateConceptChange(
          id: OkfConceptId('fixed'),
          document: OkfDocument(
            frontmatter: <String, Object?>{'type': 'Reference'},
          ),
        ),
      ]),
    );

    final prepared = (result as OkfPreparationReady).prepared;
    expect(prepared.validation.isConformant, isTrue);
    await changes.commit(prepared);

    final loaded = await const OkfBundleLoader().inspect(root.path);
    expect(
      loaded.validate().report.toJson(),
      prepared.validation.report.toJson(),
    );
  });

  test('prepare rejects file and directory path collisions', () async {
    final result = changes.prepare(
      root.path,
      OkfBundleChangeSet(<OkfBundleChange>[
        for (final id in <String>['node', 'node.md/child'])
          OkfCreateConceptChange(
            id: OkfConceptId(id),
            document: OkfDocument(
              frontmatter: <String, Object?>{'type': 'Reference'},
            ),
          ),
      ]),
    );

    await expectLater(result, throwsA(isA<OkfBundleChangeException>()));
  });

  test('prepare rejects case-folded path collisions', () async {
    await _write(root, 'A.md', '''
---
type: Reference
---
''');

    await expectLater(
      changes.prepare(
        root.path,
        OkfBundleChangeSet(<OkfBundleChange>[
          OkfCreateConceptChange(
            id: OkfConceptId('a'),
            document: OkfDocument(
              frontmatter: <String, Object?>{'type': 'Reference'},
            ),
          ),
        ]),
      ),
      throwsA(isA<OkfBundleChangeException>()),
    );
  });

  for (final aliases in <({String existing, String added, String name})>[
    (existing: '\u00e9', added: 'e\u0301', name: 'canonical normalization'),
    (existing: '\u03a3', added: '\u03c2', name: 'Greek case folding'),
    (existing: '\u00df', added: 'SS', name: 'expanding case folding'),
    (existing: '\u017f', added: 'S', name: 'historic case folding'),
  ]) {
    test('prepare rejects ${aliases.name} path collisions', () async {
      await _write(root, '${aliases.existing}.md', '''
---
type: Reference
---
''');

      await expectLater(
        changes.prepare(
          root.path,
          OkfBundleChangeSet(<OkfBundleChange>[
            OkfCreateConceptChange(
              id: OkfConceptId(aliases.added),
              document: OkfDocument(
                frontmatter: <String, Object?>{'type': 'Reference'},
              ),
            ),
          ]),
        ),
        throwsA(isA<OkfBundleChangeException>()),
      );
    });
  }

  test('an advisory-only Unicode candidate can commit', () async {
    final result = await changes.prepare(
      root.path,
      OkfBundleChangeSet(<OkfBundleChange>[
        OkfCreateConceptChange(
          id: OkfConceptId('metrics/évolution'),
          document: OkfDocument(
            frontmatter: <String, Object?>{'type': 'Metric'},
          ),
        ),
      ]),
    );

    final prepared = (result as OkfPreparationReady).prepared;
    expect(
      prepared.validation.report.findings.map((finding) => finding.id.value),
      contains('okf/non-portable-concept-id'),
    );
    expect(prepared.validation.isConformant, isTrue);
    await changes.commit(prepared);
    expect(
      await File(p.join(root.path, 'metrics', 'évolution.md')).exists(),
      isTrue,
    );
  });

  test('an unresolved link is a conformant prepared change', () async {
    final result = await changes.prepare(
      root.path,
      OkfBundleChangeSet(<OkfBundleChange>[
        OkfLinkConceptsChange(
          source: OkfConceptId('metrics/revenue'),
          target: OkfConceptId('planned/future'),
          relationship: 'depends-on',
        ),
      ]),
    );

    final prepared = (result as OkfPreparationReady).prepared;
    expect(prepared.validation.isConformant, isTrue);
    expect(
      OkfGraph.fromBundle(prepared.candidate.toBundle()).edges
          .singleWhere((edge) => edge.rawTarget.contains('future'))
          .resolution,
      OkfGraphResolution.unresolved,
    );
    await changes.commit(prepared);
    expect(await _read(root, 'log.md'), contains('planned/future'));
  });

  test('a link target cannot name a reserved document', () async {
    final before = await _snapshot(root);

    for (final target in <String>['metrics/index', 'log']) {
      await expectLater(
        changes.prepare(
          root.path,
          OkfBundleChangeSet(<OkfBundleChange>[
            OkfLinkConceptsChange(
              source: OkfConceptId('metrics/revenue'),
              target: OkfConceptId(target),
              relationship: 'depends-on',
            ),
          ]),
        ),
        throwsA(isA<OkfBundleChangeException>()),
      );
    }

    expect(await _snapshot(root), before);
  });

  test('inspection cannot mutate the candidate or committed bytes', () async {
    final preparation = await changes.prepare(root.path, _createChurn());
    final prepared = (preparation as OkfPreparationReady).prepared;
    final expected = prepared.candidate.concepts['metrics/churn.md']!;

    expect(
      () => prepared.candidate.concepts['metrics/churn.md'] = 'forged',
      throwsUnsupportedError,
    );
    final detached = prepared.candidate.toBundle();
    detached.concept(OkfConceptId('metrics/churn'))!.frontmatter['title'] =
        'Forged';

    await changes.commit(prepared);
    expect(await _read(root, 'metrics/churn.md'), expected);
    expect(await _read(root, 'metrics/churn.md'), isNot(contains('Forged')));
  });

  test('commit rejects stale source state and reuse', () async {
    final first =
        (await changes.prepare(root.path, _createChurn())
                as OkfPreparationReady)
            .prepared;
    await _write(
      root,
      'metrics/revenue.md',
      '${await _read(root, 'metrics/revenue.md')}\n',
    );

    await expectLater(
      changes.commit(first),
      throwsA(isA<OkfStalePreparedChangeException>()),
    );
    expect(
      await File(p.join(root.path, 'metrics', 'churn.md')).exists(),
      isFalse,
    );

    final second =
        (await changes.prepare(root.path, _createChurn())
                as OkfPreparationReady)
            .prepared;
    await changes.commit(second);
    expect(() => changes.commit(second), throwsStateError);
  });

  test('commit ignores nested lock metadata created after prepare', () async {
    final prepared =
        (await changes.prepare(root.path, _createChurn())
                as OkfPreparationReady)
            .prepared;
    final nestedRoot = p.join(root.path, 'metrics');

    await const OkfBundleWriter().writeAll(
      nestedRoot,
      const <String, String>{},
    );

    expect(
      await File(p.join(nestedRoot, okfBundleLockFileName)).exists(),
      isTrue,
    );
    final result = await changes.commit(prepared);
    expect(result.changedPaths, contains('metrics/churn.md'));
  });

  test('prepare rejects an uncommittable source topology', () async {
    await File(p.join(root.path, 'log.md')).delete();
    await _write(root, 'log.md/occupied.txt', 'not a log\n');
    final before = await _snapshot(root);

    await expectLater(
      changes.prepare(root.path, _createChurn(id: 'a/churn')),
      throwsA(isA<OkfBundleChangeException>()),
    );
    expect(await _snapshot(root), before);
    expect(await Directory(p.join(root.path, 'a')).exists(), isFalse);
  });

  test('update preserves unmanaged field order and body content', () async {
    await _write(root, 'metrics/revenue.md', '''
---
type: Metric
title: Revenue
description: Monthly revenue.
owner: finance-team
review:
  cadence: quarterly
---

$_richBody''');
    final prepared =
        (await changes.prepare(
                  root.path,
                  OkfBundleChangeSet(<OkfBundleChange>[
                    OkfUpdateConceptChange(
                      id: OkfConceptId('metrics/revenue'),
                      frontmatterChanges: const <String, Object?>{
                        'description': 'Recognized monthly revenue.',
                        'status': 'stable',
                      },
                    ),
                  ]),
                )
                as OkfPreparationReady)
            .prepared;

    await changes.commit(prepared);
    final document = OkfDocument.parse(await _read(root, 'metrics/revenue.md'));
    expect(document.frontmatter['owner'], 'finance-team');
    expect(document.frontmatter['review'], <String, Object?>{
      'cadence': 'quarterly',
    });
    expect(
      document.frontmatter.keys.where(
        const <String>{'owner', 'review'}.contains,
      ),
      <String>['owner', 'review'],
    );
    expect(document.body, _richBody);
  });

  test('candidate concepts record where their bodies start', () async {
    final candidate =
        (await changes.prepare(
                  root.path,
                  OkfBundleChangeSet(<OkfBundleChange>[
                    ..._createChurn().changes,
                    OkfUpdateConceptChange(
                      id: OkfConceptId('metrics/revenue'),
                      frontmatterChanges: const <String, Object?>{
                        'status': 'stable',
                      },
                    ),
                  ]),
                )
                as OkfPreparationReady)
            .prepared
            .candidate;

    for (final (path, line, heading) in const <(String, int, String)>[
      ('metrics/churn.md', 7, '# Churn'),
      ('metrics/revenue.md', 8, '# Revenue'),
    ]) {
      expect(
        candidate.concepts[path]!.split('\n')[line - 1],
        heading,
        reason: path,
      );
      expect(
        candidate.toBundle().conceptAtPath(path)!.bodyStartLine,
        line,
        reason: path,
      );
      expect(
        candidate.toLoadResult().documents[path]!.bodyStartLine,
        line,
        reason: path,
      );
    }
  });

  test('unrelated authored indexes remain byte-identical', () async {
    const authored = '# Reference\n\n* [Note](note.md) - Hand ordered.\n';
    await _write(root, 'other/note.md', '''
---
type: Reference
title: Note
---
''');
    await _write(root, 'other/index.md', authored);
    final prepared =
        (await changes.prepare(root.path, _createChurn())
                as OkfPreparationReady)
            .prepared;

    await changes.commit(prepared);

    expect(await _read(root, 'other/index.md'), authored);
    expect(prepared.candidate.indexes['other/index.md'], authored);
  });

  test('an idempotent change writes no file', () async {
    final first =
        (await changes.prepare(
                  root.path,
                  OkfBundleChangeSet(<OkfBundleChange>[
                    OkfDeprecateConceptChange(
                      id: OkfConceptId('metrics/revenue'),
                    ),
                  ]),
                )
                as OkfPreparationReady)
            .prepared;
    await changes.commit(first);
    final before = await _snapshot(root);

    final second =
        (await changes.prepare(
                  root.path,
                  OkfBundleChangeSet(<OkfBundleChange>[
                    OkfDeprecateConceptChange(
                      id: OkfConceptId('metrics/revenue'),
                    ),
                  ]),
                )
                as OkfPreparationReady)
            .prepared;
    final result = await changes.commit(second);

    expect(result.changedPaths, isEmpty);
    expect(await _snapshot(root), before);
  });

  test('an empty update is idempotent', () async {
    final before = await _snapshot(root);
    final prepared =
        (await changes.prepare(
                  root.path,
                  OkfBundleChangeSet(<OkfBundleChange>[
                    OkfUpdateConceptChange(id: OkfConceptId('metrics/revenue')),
                  ]),
                )
                as OkfPreparationReady)
            .prepared;

    final result = await changes.commit(prepared);

    expect(result.changedPaths, isEmpty);
    expect(await _snapshot(root), before);
  });

  test(
    'non-index updates preserve an authored index in the same directory',
    () async {
      final authored = '${await _read(root, 'metrics/index.md')}\n';
      await _write(root, 'metrics/index.md', authored);
      final prepared =
          (await changes.prepare(
                    root.path,
                    OkfBundleChangeSet(<OkfBundleChange>[
                      OkfUpdateConceptChange(
                        id: OkfConceptId('metrics/revenue'),
                        body: '# Revenue\n\nExpanded narrative.\n',
                      ),
                    ]),
                  )
                  as OkfPreparationReady)
              .prepared;

      await changes.commit(prepared);

      expect(await _read(root, 'metrics/index.md'), authored);
      expect(prepared.candidate.indexes['metrics/index.md'], authored);
    },
  );

  test('changes that describe no state remain tool errors', () async {
    await expectLater(
      changes.prepare(
        root.path,
        OkfBundleChangeSet(<OkfBundleChange>[
          OkfCreateConceptChange(
            id: OkfConceptId('metrics/revenue'),
            document: OkfDocument(
              frontmatter: <String, Object?>{'type': 'Metric'},
            ),
          ),
        ]),
      ),
      throwsA(isA<OkfBundleChangeException>()),
    );
  });

  test(
    'apply serializes preparation and commit for concurrent callers',
    () async {
      final results = await Future.wait(<Future<OkfBundleApplication>>[
        changes.apply(root.path, _createChurn(id: 'metrics/churn')),
        changes.apply(root.path, _createChurn(id: 'metrics/margin')),
      ]);

      expect(results, everyElement(isA<OkfBundleApplied>()));
      final loaded = await const OkfBundleLoader().inspect(root.path);
      expect(
        loaded.bundle.concepts.keys.map((id) => id.value),
        containsAll(<String>['metrics/churn', 'metrics/margin']),
      );
      expect(
        OkfLogDocument.parse(
          loaded.logs['log.md']!,
        ).entries.map((entry) => entry.description),
        containsAll(<String>[
          '[Churn](metrics/churn.md)',
          '[Churn](metrics/margin.md)',
        ]),
      );
    },
  );

  test('a change set text UTF-8 cannot encode is a tool error', () async {
    final before = await _snapshot(root);

    await expectLater(
      changes.prepare(
        root.path,
        OkfBundleChangeSet(<OkfBundleChange>[
          OkfCreateConceptChange(
            id: OkfConceptId('metrics/churn'),
            document: OkfDocument(
              frontmatter: <String, Object?>{'type': 'Metric'},
              body: '# Churn \uDC00\n',
            ),
          ),
        ]),
      ),
      throwsA(
        isA<OkfBundleChangeException>().having(
          (error) => error.message,
          'message',
          contains('metrics/churn.md'),
        ),
      ),
    );
    expect(await _snapshot(root), before);
  });

  test('frontmatter YAML cannot represent is a tool error', () async {
    final before = await _snapshot(root);
    final revenue = OkfConceptId('metrics/revenue');

    // The emitter cannot write an unpaired surrogate, so each change names
    // the concept it would have written instead of failing to read it back.
    for (final (concept, change) in <(String, OkfBundleChange)>[
      (
        'metrics/churn',
        OkfCreateConceptChange(
          id: OkfConceptId('metrics/churn'),
          document: OkfDocument(
            frontmatter: <String, Object?>{
              'type': 'Metric',
              'title': 'Churn \uD800',
            },
            body: '# Churn\n',
          ),
        ),
      ),
      (
        'metrics/revenue',
        OkfUpdateConceptChange(
          id: revenue,
          frontmatterChanges: <String, Object?>{'title': 'Revenue \uDC00'},
        ),
      ),
      (
        'metrics/revenue',
        OkfLinkConceptsChange(
          source: revenue,
          target: OkfConceptId('metrics/margin'),
          relationship: 'relates \uD800 to',
        ),
      ),
    ]) {
      for (final run in <Future<Object?> Function()>[
        () => changes.prepare(root.path, OkfBundleChangeSet([change])),
        () => changes.apply(root.path, OkfBundleChangeSet([change])),
      ]) {
        await expectLater(
          run(),
          throwsA(
            isA<OkfBundleChangeException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('Concept $concept cannot be written'),
                contains('unpaired surrogate'),
              ),
            ),
          ),
          reason: '${change.runtimeType}',
        );
      }
    }
    expect(await _snapshot(root), before);
  });

  group('concept edits keep the bytes they do not change', () {
    const styled = '''
---
type: Metric
title: 'Revenue'   # shown in indexes
tags: [finance, monthly]
generated: { by: agent:okf, at: 2026-08-01T00:00:00Z }
# Kept by the finance team.
owner: finance-team
status: draft
sources:
  - resource: ledger.md
    relationship: derived-from
---

# Revenue
''';

    Future<OkfBundleCommitResult> commit(OkfBundleChange change) async {
      final preparation = await changes.prepare(
        root.path,
        OkfBundleChangeSet(<OkfBundleChange>[change]),
      );
      return changes.commit((preparation as OkfPreparationReady).prepared);
    }

    setUp(() => _write(root, 'metrics/revenue.md', styled));

    test('an update edits only the keys it changes', () async {
      await commit(
        OkfUpdateConceptChange(
          id: OkfConceptId('metrics/revenue'),
          frontmatterChanges: const <String, Object?>{
            'description': 'Recognized monthly revenue.',
            'owner': null,
            'generated': <String, Object?>{
              'by': 'agent:okf',
              'at': '2026-09-01T00:00:00Z',
            },
          },
        ),
      );

      expect(await _read(root, 'metrics/revenue.md'), '''
---
type: Metric
title: 'Revenue'   # shown in indexes
tags: [finance, monthly]
generated: { by: agent:okf, at: "2026-09-01T00:00:00Z" }
# Kept by the finance team.
status: draft
sources:
  - resource: ledger.md
    relationship: derived-from
description: Recognized monthly revenue.
---

# Revenue
''');
    });

    test('a link appends to the sources list in place', () async {
      await commit(
        OkfLinkConceptsChange(
          source: OkfConceptId('metrics/revenue'),
          target: OkfConceptId('metrics/churn'),
          relationship: 'depends-on',
        ),
      );

      expect(
        await _read(root, 'metrics/revenue.md'),
        styled.replaceFirst(
          '    relationship: derived-from\n',
          '    relationship: derived-from\n'
              '  - resource: churn.md\n'
              '    relationship: depends-on\n',
        ),
      );
    });

    test('a deprecation replaces the status where it stands', () async {
      await commit(
        OkfDeprecateConceptChange(id: OkfConceptId('metrics/revenue')),
      );

      expect(
        await _read(root, 'metrics/revenue.md'),
        styled.replaceFirst('status: draft', 'status: deprecated'),
      );
    });

    test('a deprecation adds a missing status after the last key', () async {
      await _write(
        root,
        'metrics/revenue.md',
        styled.replaceFirst('status: draft\n', ''),
      );

      await commit(
        OkfDeprecateConceptChange(id: OkfConceptId('metrics/revenue')),
      );

      expect(
        await _read(root, 'metrics/revenue.md'),
        styled
            .replaceFirst('status: draft\n', '')
            .replaceFirst(
              '    relationship: derived-from\n',
              '    relationship: derived-from\nstatus: deprecated\n',
            ),
      );
    });

    test('an edit keeps a canonical bundle canonical', () async {
      // `okf format` leaves this bundle alone, so no edit may make
      // `okf format --check` fail on it: new keys go to their place in the
      // preferred order, not after the last entry.
      await _write(root, 'metrics/revenue.md', '''
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
''');
      expect(await _formatCheck(root), 0, reason: 'the seed is canonical');

      final revenue = OkfConceptId('metrics/revenue');
      for (final change in <OkfBundleChange>[
        OkfDeprecateConceptChange(id: revenue),
        OkfUpdateConceptChange(
          id: revenue,
          frontmatterChanges: const <String, Object?>{
            'description': 'Monthly revenue.',
            'tags': <Object?>['finance'],
          },
        ),
        OkfLinkConceptsChange(
          source: revenue,
          target: OkfConceptId('metrics/margin'),
          relationship: 'feeds',
        ),
      ]) {
        await commit(change);
        expect(
          await _formatCheck(root),
          0,
          reason: '${change.runtimeType} keeps the bundle formatted',
        );
      }

      expect(await _read(root, 'metrics/revenue.md'), '''
---
type: Metric
title: Revenue
description: Monthly revenue.
tags:
  - finance
status: deprecated
sources:
  -
    resource: ledger.md
    relationship: derived-from
  -
    resource: margin.md
    relationship: feeds
owner: finance-team
---

# Revenue
''');
    });

    test('an edit that cannot be written so is a tool error', () async {
      await _write(root, 'notes/plain.md', '# Plain\n');
      final before = await _snapshot(root);

      await expectLater(
        changes.prepare(
          root.path,
          OkfBundleChangeSet(<OkfBundleChange>[
            OkfUpdateConceptChange(
              id: OkfConceptId('notes/plain'),
              body: '---\ntype: Injected\n---\n',
            ),
          ]),
        ),
        throwsA(
          isA<OkfBundleChangeException>().having(
            (error) => error.message,
            'message',
            allOf(contains('notes/plain'), contains('--- delimiter')),
          ),
        ),
      );
      expect(await _snapshot(root), before);
    });

    test('a body update keeps the frontmatter bytes', () async {
      await commit(
        OkfUpdateConceptChange(
          id: OkfConceptId('metrics/revenue'),
          frontmatterChanges: const <String, Object?>{'title': 'Revenue'},
          body: '# Revenue\n\nRewritten.\n',
        ),
      );

      expect(
        await _read(root, 'metrics/revenue.md'),
        '${styled.substring(0, styled.indexOf('# Revenue'))}'
        '# Revenue\n\nRewritten.\n',
      );
    });

    test('an update to values the concept holds writes nothing', () async {
      final before = await _snapshot(root);
      final result = await commit(
        OkfUpdateConceptChange(
          id: OkfConceptId('metrics/revenue'),
          frontmatterChanges: <String, Object?>{
            ...OkfDocument.parse(styled).frontmatter,
            'generated': const <String, Object?>{
              'at': '2026-08-01T00:00:00Z',
              'by': 'agent:okf',
            },
          },
          body: '# Revenue',
        ),
      );

      expect(result.changedPaths, isEmpty);
      expect(await _snapshot(root), before);
    });

    test('an update keeps CRLF line endings and a byte order mark', () async {
      final file = File(p.join(root.path, 'metrics', 'revenue.md'));
      await file.writeAsBytes(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(
          '---\r\ntype: Metric\r\ntitle: Revenue\r\ntags: [finance]\r\n'
          '---\r\n\r\n# Revenue\r\n',
        ),
      ]);

      final preparation = await changes.prepare(
        root.path,
        OkfBundleChangeSet(<OkfBundleChange>[
          OkfUpdateConceptChange(
            id: OkfConceptId('metrics/revenue'),
            frontmatterChanges: const <String, Object?>{
              'tags': <Object?>['finance', 'monthly'],
              'status': 'stable',
            },
          ),
        ]),
      );
      final prepared = (preparation as OkfPreparationReady).prepared;
      const edited =
          '---\r\ntype: Metric\r\ntitle: Revenue\r\n'
          'tags: [finance, monthly]\r\nstatus: stable\r\n'
          '---\r\n\r\n# Revenue\r\n';
      expect(prepared.candidate.concepts['metrics/revenue.md'], edited);
      await changes.commit(prepared);

      expect(await file.readAsBytes(), <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(edited),
      ]);
    });
  });

  group('reserved-file projection', () {
    const projectedIndex =
        '# Metric\n'
        '\n'
        '* [Churn](churn.md) - Projected churn.\n'
        '* [Revenue](revenue.md) - Projected revenue.\n';
    const projectedLog =
        '# Log\n'
        '\n'
        '## 2026-08-18\n'
        '\n'
        '* **Recorded**: Churn, by the caller.\n'
        '\n'
        '## 2026-08-01\n'
        '\n'
        '* **Created**: [Revenue](metrics/revenue.md)\n';

    test('commits exactly the projected bytes', () async {
      late OkfProjectionInput seen;
      final preparation = await changes.prepare(
        root.path,
        _createChurn(),
        project: (input) {
          seen = input;
          return <String, String?>{
            'metrics/index.md': projectedIndex,
            'log.md': projectedLog,
          };
        },
      );

      expect(seen.date, DateTime.utc(2026, 8, 18));
      expect(
        seen.changedFiles.keys,
        containsAll(<String>['metrics/churn.md', 'metrics/index.md', 'log.md']),
      );
      expect(seen.base.documents, isNot(contains('metrics/churn.md')));
      expect(
        seen.candidate.concepts['metrics/churn.md'],
        seen.changedFiles['metrics/churn.md'],
      );
      expect(seen.candidate.logs['log.md'], seen.changedFiles['log.md']);

      final prepared = (preparation as OkfPreparationReady).prepared;
      expect(prepared.candidate.indexes['metrics/index.md'], projectedIndex);
      expect(prepared.candidate.logs['log.md'], projectedLog);
      expect(
        prepared.validation.report.toJson(),
        const OkfSpecValidator()
            .validate(prepared.candidate.toBundle())
            .report
            .toJson(),
      );

      final result = await changes.commit(prepared);
      expect(result.changedPaths, unorderedEquals(seen.changedFiles.keys));
      expect(
        await _readBytes(root, 'metrics/index.md'),
        utf8.encode(projectedIndex),
      );
      expect(await _readBytes(root, 'log.md'), utf8.encode(projectedLog));
    });

    test('the projection sees the date the change set logs', () async {
      var day = 17;
      final advancing = OkfBundleChangeApplier(
        clock: () => DateTime.utc(2026, 8, day++),
      );
      late OkfProjectionInput seen;
      await advancing.prepare(
        root.path,
        _createChurn(),
        project: (input) {
          seen = input;
          return const <String, String?>{};
        },
      );

      expect(seen.date, DateTime.utc(2026, 8, 17));
      expect(seen.changedFiles['log.md'], contains('## 2026-08-17'));
    });

    test('reserved files keep a byte order mark', () async {
      const mark = <int>[0xEF, 0xBB, 0xBF];
      // The change set's own index and log, and a projection's, are written
      // back with the mark the file began with, as concepts are.
      for (final projected in <bool>[false, true]) {
        await _seedBundle(root);
        for (final path in <String>['metrics/index.md', 'log.md']) {
          final file = File(p.join(root.path, path));
          await file.writeAsBytes(<int>[...mark, ...await file.readAsBytes()]);
        }
        final churn = File(p.join(root.path, 'metrics', 'churn.md'));
        if (await churn.exists()) {
          await churn.delete();
        }

        final preparation = await changes.prepare(
          root.path,
          _createChurn(),
          project: projected
              ? (_) => <String, String?>{
                  'metrics/index.md': projectedIndex,
                  'log.md': projectedLog,
                }
              : null,
        );
        final prepared = (preparation as OkfPreparationReady).prepared;
        final index = prepared.candidate.indexes['metrics/index.md']!;
        final log = prepared.candidate.logs['log.md']!;
        expect(index.startsWith('\uFEFF'), isFalse);
        expect(log.startsWith('\uFEFF'), isFalse);
        if (projected) {
          expect(index, projectedIndex);
          expect(log, projectedLog);
        }
        final result = await changes.commit(prepared);
        expect(
          result.changedPaths,
          containsAll(<String>['metrics/index.md', 'log.md', 'index.md']),
        );

        expect(
          await _readBytes(root, 'metrics/index.md'),
          <int>[...mark, ...utf8.encode(index)],
          reason: 'projected: $projected',
        );
        expect(await _readBytes(root, 'log.md'), <int>[
          ...mark,
          ...utf8.encode(log),
        ], reason: 'projected: $projected');
        expect(
          (await _readBytes(root, 'index.md')).take(3),
          isNot(mark),
          reason: 'a file without the mark does not gain one',
        );
        final reloaded = await const OkfBundleLoader().inspect(root.path);
        expect(reloaded.indexes['metrics/index.md'], index);
        expect(reloaded.logs['log.md'], log);
      }
    });

    test('null keeps the source text or its absence', () async {
      final sourceLog = await _read(root, 'log.md');
      final sourceIndex = await _read(root, 'index.md');
      final prepared =
          (await changes.prepare(
                    root.path,
                    _createChurn(id: 'reports/churn'),
                    project: (_) => <String, String?>{
                      'log.md': null,
                      'reports/index.md': null,
                      'index.md': sourceIndex,
                    },
                  )
                  as OkfPreparationReady)
              .prepared;

      expect(prepared.candidate.logs['log.md'], sourceLog);
      expect(prepared.candidate.indexes, isNot(contains('reports/index.md')));
      final result = await changes.commit(prepared);

      expect(result.changedPaths, <String>['reports/churn.md']);
      expect(await _read(root, 'log.md'), sourceLog);
      expect(await _read(root, 'index.md'), sourceIndex);
      expect(
        await File(p.join(root.path, 'reports', 'index.md')).exists(),
        isFalse,
      );
    });

    test('a path other than a reserved file is a tool error', () async {
      final before = await _snapshot(root);

      for (final path in <String>[
        'metrics/revenue.md',
        'metrics/churn.md',
        'metrics/data.csv',
        'metrics/INDEX.md',
        'metrics/index.md/',
        '../index.md',
        '/log.md',
      ]) {
        await expectLater(
          changes.prepare(
            root.path,
            _createChurn(),
            project: (_) => <String, String?>{path: projectedIndex},
          ),
          throwsA(isA<OkfBundleChangeException>()),
          reason: path,
        );
      }

      expect(await _snapshot(root), before);
    });

    test('a projected text UTF-8 cannot encode is a tool error', () async {
      final before = await _snapshot(root);

      // The writer would encode the unpaired surrogate as U+FFFD, so the
      // committed bytes would not be the text the validator judged.
      await expectLater(
        changes.prepare(
          root.path,
          _createChurn(),
          project: (_) => <String, String?>{
            'metrics/index.md': projectedIndex.replaceFirst(
              'Projected churn',
              'Projected \uD800 churn',
            ),
          },
        ),
        throwsA(
          isA<OkfBundleChangeException>().having(
            (error) => error.message,
            'message',
            contains('metrics/index.md'),
          ),
        ),
      );
      expect(await _snapshot(root), before);
    });

    test('Spec-invalid projected output is refused', () async {
      final before = await _snapshot(root);
      final result = await changes.prepare(
        root.path,
        _createChurn(),
        project: (_) => const <String, String?>{
          'metrics/index.md': 'Not an index.\n',
          'log.md': '---\nowner: caller\n---\n\n$projectedLog',
        },
      );

      expect(result, isA<OkfPreparationRefused>());
      final refusal = result as OkfPreparationRefused;
      expect(
        refusal.validation.report.findings.map(
          (finding) => (finding.id.value, finding.location?.path),
        ),
        containsAll(<(String, String)>[
          ('okf/invalid-index-structure', 'metrics/index.md'),
          ('okf/invalid-log-frontmatter', 'log.md'),
        ]),
      );

      // The refused candidate is the projected one, so a caller can show it.
      final candidate = refusal.candidate!;
      expect(candidate.indexes['metrics/index.md'], 'Not an index.\n');
      expect(candidate.concepts, contains('metrics/churn.md'));
      expect(
        candidate.toLoadResult().validate().report.toJson(),
        refusal.validation.report.toJson(),
      );
      expect(await _snapshot(root), before);
    });

    test('apply commits or refuses a projected candidate', () async {
      final before = await _snapshot(root);
      final refused = await changes.apply(
        root.path,
        _createChurn(),
        project: (_) => const <String, String?>{
          'metrics/index.md': 'Not an index.\n',
        },
      );
      expect(refused, isA<OkfBundleApplicationRefused>());
      final refusal = refused as OkfBundleApplicationRefused;
      expect(
        refusal.validation.report.findings.map((finding) => finding.id.value),
        contains('okf/invalid-index-structure'),
      );
      // apply returns the refused projected candidate, as prepare does.
      expect(refusal.candidate!.indexes['metrics/index.md'], 'Not an index.\n');
      expect(refusal.candidate!.concepts, contains('metrics/churn.md'));
      expect(await _snapshot(root), before);

      final applied = await changes.apply(
        root.path,
        _createChurn(),
        project: (_) => const <String, String?>{
          'metrics/index.md': projectedIndex,
        },
      );
      expect(applied, isA<OkfBundleApplied>());
      expect(
        await _readBytes(root, 'metrics/index.md'),
        utf8.encode(projectedIndex),
      );
    });

    test('a source change after projection is refused at commit', () async {
      final prepared =
          (await changes.prepare(
                    root.path,
                    _createChurn(),
                    project: (_) => const <String, String?>{
                      'metrics/index.md': projectedIndex,
                    },
                  )
                  as OkfPreparationReady)
              .prepared;
      await _write(
        root,
        'metrics/revenue.md',
        '${await _read(root, 'metrics/revenue.md')}\n',
      );
      final before = await _snapshot(root);

      await expectLater(
        changes.commit(prepared),
        throwsA(isA<OkfStalePreparedChangeException>()),
      );
      expect(await _snapshot(root), before);
    });

    test('a projection that changes the source is refused at commit', () async {
      final prepared =
          (await changes.prepare(
                    root.path,
                    _createChurn(),
                    project: (_) async {
                      await _write(root, 'notes.txt', 'written mid-prepare\n');
                      return const <String, String?>{};
                    },
                  )
                  as OkfPreparationReady)
              .prepared;

      await expectLater(
        changes.commit(prepared),
        throwsA(isA<OkfStalePreparedChangeException>()),
      );
      expect(
        await File(p.join(root.path, 'metrics', 'churn.md')).exists(),
        isFalse,
      );
    });

    test('an empty change set with a projection repairs indexes', () async {
      final generated = await _read(root, 'metrics/index.md');
      await _write(root, 'metrics/index.md', projectedIndex);
      final log = await _read(root, 'log.md');

      final prepared =
          (await changes.prepare(
                    root.path,
                    OkfBundleChangeSet(const <OkfBundleChange>[]),
                    project: (input) => <String, String?>{
                      'metrics/index.md': const OkfIndexGenerator().generate(
                        input.base.bundle,
                      )['metrics/index.md'],
                    },
                  )
                  as OkfPreparationReady)
              .prepared;
      final result = await changes.commit(prepared);

      expect(result.changedPaths, <String>['metrics/index.md']);
      expect(await _read(root, 'metrics/index.md'), generated);
      expect(await _read(root, 'log.md'), log);
    });
  });

  group('toLoadResult', () {
    test('reads the candidate as a later load would', () async {
      await _write(root, 'metrics/data.csv', 'month,revenue\n');
      await _write(root, 'archive/old.md', '---\ntype: Reference\n---\n');
      // The change replaces a file that fails to load.
      await _write(root, 'a/churn.md', '');
      await File(p.join(root.path, 'a', 'churn.md')).writeAsBytes(<int>[0xff]);
      final prepared =
          (await changes.prepare(root.path, _createChurn(id: 'a/churn'))
                  as OkfPreparationReady)
              .prepared;
      final candidate = prepared.candidate.toLoadResult();
      expect(candidate.report.findings, isEmpty);
      expect(
        candidate.validate().report.toJson(),
        prepared.validation.report.toJson(),
      );

      await changes.commit(prepared);
      final loaded = await const OkfBundleLoader().inspect(root.path);

      expect(candidate.rootPath, loaded.rootPath);
      expect(candidate.paths, loaded.paths);
      expect(
        candidate.documents
            .map((path, document) {
              return MapEntry(path, document.serialize());
            })
            .entries
            .map((entry) => (entry.key, entry.value)),
        orderedEquals(
          loaded.documents
              .map((path, document) {
                return MapEntry(path, document.serialize());
              })
              .entries
              .map((entry) => (entry.key, entry.value)),
        ),
      );
      expect(
        candidate.indexes.entries.map((entry) => (entry.key, entry.value)),
        orderedEquals(
          loaded.indexes.entries.map((entry) => (entry.key, entry.value)),
        ),
      );
      expect(candidate.logs, loaded.logs);
      expect(candidate.assets, loaded.assets);
      expect(candidate.report.toJson(), loaded.report.toJson());
    });

    test('keeps load findings for files the candidate keeps', () async {
      await File(p.join(root.path, 'broken.md')).writeAsBytes(<int>[0xff]);
      late OkfBundleLoadResult candidate;

      final result = await changes.prepare(
        root.path,
        _createChurn(),
        project: (input) {
          candidate = input.candidate.toLoadResult();
          return const <String, String?>{};
        },
      );

      expect(result, isA<OkfPreparationRefused>());
      expect(
        candidate.report.findings.map((finding) => finding.location?.path),
        <String>['broken.md'],
      );
      expect(candidate.paths, contains('broken.md'));
      expect(candidate.documents, contains('metrics/churn.md'));
    });
  });
}

const String _richBody = '''
# Revenue

Recognized revenue, see [churn](churn.md).
''';

OkfBundleChangeSet _createChurn({String id = 'metrics/churn'}) =>
    OkfBundleChangeSet(<OkfBundleChange>[
      OkfCreateConceptChange(
        id: OkfConceptId(id),
        document: OkfDocument(
          frontmatter: <String, Object?>{
            'type': 'Metric',
            'title': 'Churn',
            'description': 'Monthly churn.',
          },
          body: '# Churn\n',
        ),
      ),
    ]);

Future<void> _seedBundle(Directory root) async {
  await _write(root, 'metrics/revenue.md', '''
---
type: Metric
title: Revenue
description: Monthly revenue.
---

# Revenue
''');
  await _write(root, 'index.md', '''
---
okf_version: "0.2"
---

# Subdirectories

* [metrics](metrics/index.md) - Monthly revenue.
''');
  await _write(root, 'metrics/index.md', '''
# Metric

* [Revenue](revenue.md) - Monthly revenue.
''');
  await _write(root, 'log.md', '''
# Log

## 2026-08-01

* **Created**: [Revenue](metrics/revenue.md)
''');
}

/// The exit code of `okf format --check` on the bundle at [root].
Future<int> _formatCheck(Directory root) async => (await runCli(<String>[
  'format',
  '--check',
  root.path,
], root.path)).exitCode;

Future<String> _read(Directory root, String relativePath) => File(
  p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
).readAsString();

Future<List<int>> _readBytes(Directory root, String relativePath) => File(
  p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
).readAsBytes();

Future<Map<String, String>> _snapshot(Directory root) async {
  final files = <String, String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relativePath = p.relative(entity.path, from: root.path);
    if (entity is File && p.basename(relativePath) != okfBundleLockFileName) {
      files[relativePath] = base64Encode(await entity.readAsBytes());
    }
  }
  return files;
}

Future<void> _write(Directory root, String relativePath, String content) async {
  final file = File(
    p.joinAll(<String>[root.path, ...p.posix.split(relativePath)]),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
