# okf

`okf` is a format-first Dart toolkit for
[Open Knowledge Format (OKF) v0.2][spec]. It reads, writes, validates,
indexes, and graphs bundles made from Markdown documents with YAML
frontmatter.

This package implements the format described by the specification at
revision `62432a095456147ee71e70ac6e4dc0d2dea3ac30`. It is an independent
implementation and is not affiliated with or endorsed by Google.

## Features

- Parse OKF documents without discarding producer-defined frontmatter.
- Read v0.2 provenance, trust, lifecycle, and Attested Computation metadata.
- Consume v0.1 `timestamp` and `# Citations` fallbacks.
- Validate the deliberately small OKF conformance surface.
- Load bundles safely without following symbolic links.
- Resolve relative and bundle-relative links while retaining broken links.
- Generate deterministic directory indexes.
- Apply validated change sets that write concept, index, and log atomically.
- Parse and emit `index.md` and `log.md` entries through one shared model.
- Export bundle graphs as JSON, DOT, or Mermaid.
- Serve a Model Context Protocol read/write surface for coding agents.
- Use the APIs without `dart:io`, or import `okf_io.dart` for filesystem
  operations.

## Install

Install the command-line tool with Homebrew:

```console
brew install btwld/tap/okf
```

With Dart 3.11 or later, add the library:

```console
dart pub add okf
```

Or activate the command-line tool:

```console
dart pub global activate okf
```

## Command line

```console
okf validate path/to/bundle
okf validate path/to/bundle --strict
okf format path/to/bundle --check
okf format path/to/bundle --migrate-timestamps
okf index path/to/bundle --check
okf graph path/to/bundle --output mermaid
okf mcp path/to/bundle
```

Graph filters are repeatable, compose across fields, and apply to JSON, DOT,
and Mermaid output:

```console
okf graph path/to/bundle \
  --type Metric \
  --path-prefix analytics/ \
  --resolution unresolved
```

Values for the same flag are alternatives; different flags are combined. Type
and path filters select an induced concept subgraph, and resolution filters
then select its edges. Path prefixes match bundle-relative document paths such
as `analytics/revenue.md`. Without filters, the complete graph is emitted.

JSON graph output follows the versioned
[`graph-v1.schema.json`](schemas/graph-v1.schema.json) contract. Its root
`schema_version` is `"1"`; consumers should reject versions they do not
support. The library exports `OkfGraphQuery`, its machine-readable
`OkfGraphQuery.jsonSchema`, and `okfGraphJsonSchemaVersion` so other adapters
can use the same query and output contracts.

Commands use exit code `0` for success, `1` for a conformance or check
failure, and `2` for invalid invocation or I/O failure. Advisory findings
fail validation only under `--strict`. Validation can be emitted as JSON for
automation:

```console
okf validate path/to/bundle --output json
```

## Continuous integration

Gate a repository on OKF Spec conformance with one step and no configuration:

```yaml
steps:
  - uses: btwld/okf@v0.6.0
```

The action downloads the released `okf` archive for the ref in `uses`, unpacks
it, and runs `okf validate` once. The job fails on the exit code of that single
invocation, so CI reaches the same verdict as the command line. Inputs:

- `bundle`: the bundle to validate. Defaults to the repository root.
- `strict`: set to `true` to fail on advisories as well as errors.
- `engine-version`: override the release tag inferred from the action ref.

Releases attach an `okf-<version>-<os>-<arch>.tar.gz` archive per platform, so
the action runs on Linux and macOS runners.

The Dart library and CLI are tested on Linux and Windows with Dart 3.11 and
the current stable SDK. Windows support does not include this composite
action or a prebuilt release binary; install the CLI through Dart on Windows.

## MCP server

`okf mcp <bundle>` serves a Model Context Protocol surface over stdio, so a
coding agent can navigate, check, and edit a bundle without raw file reads.
While the server runs, standard output carries JSON-RPC alone and every
diagnostic goes to standard error. Each call re-reads the bundle, so an agent
that edits files between calls never sees a stale answer.

| Tool | Arguments | Returns |
| --- | --- | --- |
| `list-concepts` | `prefix`, `type`, `query` (all optional) | Concepts matching the filters, with type, title, status, and trust tier; an empty match reports the types and areas the bundle holds. |
| `lookup-concept` | `id` | One concept, including its canonical Markdown. |
| `query-graph` | `OkfGraphQuery.jsonSchema` | The versioned graph JSON that `okf graph --output json` emits. |
| `validate` | `strict` | The Report `okf validate --output json` emits, plus the Verdict's `exit_code`. |
| `create-concept` | `id`, `type`, `title`, `description`, `tags`, `body` | The bundle-relative paths the write committed. |
| `update-concept` | `id`, `type`, `title`, `description`, `tags`, `body` | The bundle-relative paths the write committed. |
| `link-concepts` | `source`, `target`, `relationship` | The bundle-relative paths the write committed. |
| `deprecate-concept` | `id`, `note` | The bundle-relative paths the write committed. |

`validate` returns the same Report as the command line for the same bundle
and inputs — the same finding IDs, locations, and severities — and `strict`
is the `--warnings-as-errors` flag, so an agent can
reproduce the CI gate's judgment before pushing. Arguments are validated
against each tool's schema; rejected arguments come back as a tool error.
Invalid concept IDs identify the offending argument and the path rule it
violates, so an agent can correct the call.

### Writes

Every write verb goes through `OkfBundleChangeApplier`, so one call prepares
the changed concept documents and log or index entries, commits them under the
shared bundle lock, and rolls them back together if an ordinary filesystem
write fails. `id`, `source`, and `target` are bundle-relative concept IDs
without the `.md` suffix; `type` is required when creating.

`type`, `title`, `description`, `tags`, and `body` are the fields
`create-concept` and `update-concept` manage. An update overlays only the
arguments it is given and retains every other field — `resource`,
`verification`, `sources`, and anything else the document carries keep their
values, their order and their exact text, comments included. Only the lines
of the fields the update changes are rewritten, as described under
[Library](#library).

`link-concepts` records `relationship` on the `source` concept as a reference
to `target`, which `okf graph` exposes as a concept edge. The target may be
planned rather than present: that write succeeds and the graph retains an
unresolved edge. `deprecate-concept` sets the concept's lifecycle status to
`deprecated` and records `note` with the log entry. Both are idempotent: a
link the source already declares, or a concept that is already deprecated,
changes no file.

A write is judged before it reaches disk, against the same rules
`okf validate` runs. Two outcomes are distinguished:

- A Spec-invalid candidate is **refused**: the call fails with structured
  content carrying the Report — the same finding IDs the command line prints
  for that state — and not one file is changed. Only Spec errors refuse a
  write; an advisory-only candidate remains conformant and can commit.
- Input that describes no bundle state is a plain **tool error**, with a
  message and no Report: a malformed argument, an ID that is not
  bundle-relative or that would occupy a reserved `index.md` or `log.md` path,
  creating a concept that already exists, or naming a missing source concept
  to update, link, or deprecate.

Register the server with an MCP client by pointing it at the executable:

```json
{
  "mcpServers": {
    "okf": {"command": "okf", "args": ["mcp", "path/to/bundle"]}
  }
}
```

## Concurrency

OKF coordinates concurrent operations through a reserved `.okf.lock` file at
the bundle root. Reads share the lock and writes hold it exclusively, preventing
one command from overwriting a newer change with an older snapshot.

The lock file is empty and excluded from bundle inventories. Writers create it;
`validate`, `graph`, and both `--check` modes use it when present but never
create it, so read-only commands still work on bundles they cannot modify. Add
the file to `.gitignore` if you do not want to commit it. Its name is exported
as `okfBundleLockFileName` for tools that walk bundle directories directly.

If a read starts before the first writer creates the file, it checks again and
repeats under a shared lock when necessary. Formatting a nested file cannot
identify the enclosing bundle root, so it instead refuses to write or report
against content that changed after it was read.

Locking is advisory. Within one isolate, operations on a bundle queue behind
each other; across processes, the lock file excludes them. On POSIX the lock
is an `fcntl` record lock, which belongs to the process, not to an isolate:
two isolates in one process do not exclude each other, and closing any handle
on the lock file releases every claim the process holds, so a read finishing
in one isolate can silently drop another isolate's write lock. **Run every
okf operation on a bundle — loads, validation, graphs, formatting and writes —
in one isolate per process.** `okf_io.dart` exports `OkfBundleLock` so
applications can run their own reads and writes under the same claims;
`OkfBundleLock.write` held around `prepare` and `commit` keeps the source from
changing between them. Await every bundle operation inside the action you pass
it: work that outlives the action, such as an unawaited future, still counts as
holding the claim while no lock is held.

## Library

Use `okf.dart` when working with in-memory documents:

```dart
import 'package:okf/okf.dart';

final document = OkfDocument.parse('''
---
type: Metric
title: Revenue
verified: {by: "human:reviewer", at: "2026-07-27T12:00:00Z"}
---

# Revenue
''');

print(document.metadata.trustTier.wireValue); // human-reviewed
print(document.bodyStartLine); // 7
```

`bodyStartLine` is the 1-based line of the parsed text on which `body`
begins, so a host can cite body text by file line: line `n` of `body` is line
`bodyStartLine + n - 1` of the source. A final line break ends the body's last
line rather than starting another, so a body of `k` lines ends on line
`bodyStartLine + k - 1`, the source's last line. It counts LF, CRLF and a lone
CR as one line break each, as parsing does, and a byte order mark as none.
Without frontmatter it is 1, and it is `null` for a document built with the
constructor or `copyWith`.

`sourceText` is the exact text a document was parsed from, and `null` for a
document built with the constructor or `copyWith`.

Filesystem operations live in the separate `okf_io.dart` library:

```dart
import 'package:okf/okf_io.dart';

final result = await const OkfBundleLoader().inspect('path/to/bundle');
final validation = result.validate();
final report = validation.report;
final verdict = OkfVerdict.of(report);
final graph = OkfGraph.fromBundle(result.bundle);

print(
  '${report.findings.length} findings, '
  '${graph.edges.length} relationships, exit ${verdict.exitCode}',
);
```

Bundle mutations go through one prepared write path. Preparation builds the
complete candidate and runs the closed OKF Spec validator without touching
disk. Callers may inspect the immutable candidate before committing the exact
prepared bytes across concept, index, and log files together:

```dart
import 'package:okf/okf_io.dart';

const writer = OkfBundleChangeApplier();
final result = await writer.prepare(
  'path/to/bundle',
  OkfBundleChangeSet(<OkfBundleChange>[
    OkfCreateConceptChange(
      id: OkfConceptId('metrics/churn'),
      document: OkfDocument(
        frontmatter: const <String, Object?>{
          'type': 'Metric',
          'title': 'Churn',
        },
        body: '# Churn\n',
      ),
    ),
  ]),
);

switch (result) {
  case OkfPreparationReady(:final prepared):
    // Downstream policy may inspect prepared.candidate.toBundle() here.
    final committed = await writer.commit(prepared);
    print('Wrote ${committed.changedPaths.length} file(s).');
  case OkfPreparationRefused(:final validation):
    print(validation.report.toText());
}
```

Update, link and deprecate changes edit an existing concept's text in place
rather than writing the concept anew, so a diff shows only the lines a change
touches. Deprecating this concept adds only the `status` line, after its last
entry:

```markdown
---
type: Metric
title: 'Revenue'   # shown in indexes
tags: [finance, monthly]
status: deprecated
---

# Revenue
```

A key whose value is unchanged keeps its exact bytes: its position, flow or
block style, quoting, comments and the blank lines around it. A changed
one-line value is replaced where it stands, keeping a comment after it on its
line. A changed flow collection is edited by span: changed values are replaced
and new entries go after the last one, so its unchanged entries and spacing
stay; when an entry is removed, the collection is rewritten whole on one line.
A changed `|` or `>` block scalar stays a literal block when its new value has
a line break and a literal block holds it as written. A changed block mapping
is edited entry by entry, and items added to the end of a block sequence go
after its last item, in that item's style, which is how a link appends its
`sources` item. A removed key removes only its own lines, and a new key goes
directly after the last entry of its mapping. New lines take the file's line
break, so CRLF files stay CRLF, and a concept file that begins with a UTF-8
byte order mark keeps it. An update that leaves a concept as it is writes
nothing. New concepts are written in canonical form.

Frontmatter already in canonical form, as `okf format` writes it, stays in
canonical form: a new key goes to its place in the preferred key order, such
as `status` before `sources`, and a filled `[]` is written as a block list.
So an edit never makes `okf format --check` fail on a bundle that passed it.

Every edit is parsed again and must read back as the requested mapping and
body. When an in-place edit does not, or cannot be made, okf replaces the
whole value of each changed top-level key, and failing that re-emits the whole
mapping in canonical order, which moves keys such as `tags` and drops
comments. An in-place edit cannot be made when it would remove the first key
of a `- key: value` item, edit inside a block sequence that has a tag or
anchor before its first `-`, or make two edits that overlap. The whole mapping
is re-emitted straight away for a one-line `{...}` mapping, or one that uses
YAML aliases, explicit `?` keys or collections as keys. A change that cannot
be written so that it reads back, such as a body-only concept's new body whose
first line is `---`, throws `OkfBundleChangeException` from `prepare`. Values
a change writes take the spelling okf's emitter gives them; read the
candidate's text to see what a change writes.

A projection lets a caller rewrite the reserved `index.md` and `log.md` files
of the same candidate, for example to apply its own index conventions or to
record its own log entry. Projected texts are validated and committed with the
rest of the change; a `null` text keeps the source file, and any path other
than an `index.md` or `log.md` throws `OkfBundleChangeException`. `apply`
takes the same `project` argument, and the refusals of both `prepare` and
`apply` carry the projected candidate. Dropping the `index.md` of a directory
the change adds leaves its regenerated ancestors linking to it, so project
those too. With no changes, a projection repairs reserved files on its own:

```dart
final repair = await writer.prepare(
  'path/to/bundle',
  OkfBundleChangeSet(const <OkfBundleChange>[]),
  project: (input) {
    final base = input.base.bundle;
    return <String, String?>{
      for (final entry in const OkfIndexGenerator().generate(base).entries)
        if (base.indexFiles.containsKey(entry.key)) entry.key: entry.value,
    };
  },
);
```

`OkfPreparedCandidate.toLoadResult()` reads a candidate as a later load of the
committed bundle would, so checks written against `OkfBundleLoadResult` can
judge it before commit. `okfVersion` is this package's version, and
`okfIndexGeneratorRevision` identifies the generator's output bytes: every
release with the same revision generates the same indexes for the same
bundle. It is `0.5.0`, the baseline the promise starts from, and a change to
the output ships only in a minor release that sets the revision to its own
version, so compare generated indexes against it rather than against a patch
range.

See [`example/okf.dart`][example] for a complete command-line example.

### Findings and rules

Every finding carries a stable `okf/<code>` ID (for example
`okf/missing-type`). The package exposes read-only rule descriptors with
prose, severity, and pinned-Spec references; executable rules remain fixed
inside `OkfSpecValidator`. Text output renders one line per finding
(`path[:line[:column]]: severity okf/code: message`); JSON output is the
Report projection — a `findings` array whose entries carry `id`,
`severity`, `message`, and `location`.

For the same bundle, OKF Spec validation always produces the same result; it
accepts no rule catalog, suppression, strictness, or downstream parameters.
Downstream packages run their own checks separately and combine acceptance at
their own boundary.

```dart
final validation = const OkfSpecValidator().validate(bundle);
if (validation.isConformant) {
  // Run downstream checks against the same candidate separately.
}
```

The reserved-file rules read §8 and §9 more strictly than the Spec's text. An
index may hold only level-one section headings and linked list entries, with
no prose lines or empty sections (`okf/invalid-index-structure`,
`okf/index-entry-before-section`, `okf/empty-index-section`). A log needs a
level-one title, no frontmatter, at least one `## YYYY-MM-DD` date heading and
list entries under every date, with no prose lines (`okf/missing-log-title`,
`okf/invalid-log-frontmatter`, `okf/missing-log-date`, `okf/empty-log-date`,
`okf/invalid-log-structure`). Validation does not check that an index lists
every concept. So okf can refuse an index or log the Spec allows, and accepts
an incomplete index; the [conformance matrix][matrix] sets out each reading.

## Compatibility principles

OKF intentionally requires very little. This package therefore separates
hard conformance errors from advisory findings:

- Unknown concept types and extension keys are preserved.
- Missing optional trust or provenance fields never invalidate a concept.
- A bare `verified` mapping is treated as a one-element list.
- Broken links remain visible as unresolved graph edges.
- Unknown bundle versions are consumed on a best-effort basis.
- Unicode concept IDs are accepted when safe; an advisory finding marks
  IDs that may be less portable across producers.

Formatting is semantic rather than byte-preserving. It retains unknown data
and Markdown content, but YAML comments, anchors, scalar quoting, and
whitespace style are not retained.

Filesystem link checks assume a quiescent bundle rather than a directory tree
being concurrently replaced by an adversarial process. Prepared multi-file
writes are rollback-backed, not crash-atomic: destination files are replaced
independently, so a process or power failure can interrupt the transaction.
Writes do not preserve platform-specific ACLs or extended attributes.

## Scope

The package models Attested Computation contracts but does not execute
computations or attesters. Google Cloud enrichment, Gemini orchestration,
web crawling, and the reference HTML viewer are outside this package.

## Development

Source files group related types with their behavior: document parsing and
document values live together, as do graph queries, nodes, edges, and rendering.
Finding values and rule metadata live in `finding.dart`; the internal rule
engine lives in `spec_rules/`. Shared YAML limits and immutable snapshots live
in `yaml_data.dart`. Filesystem operations and MCP transport have their own
directories. Wire input models belong to MCP; domain types do not need a second
set of models or DTOs solely for moving values between internal calls.

Tests mirror those boundaries: domain tests live at `test/`, with `io/`,
`mcp/`, and `spec_rules/` subdirectories matching the source. Repository
automation checks live in `test/ci/`; process helpers live in `test/support/`.
Run `dart test` from the package root to include every suite.

MCP inputs use Ack's `@AckInfer()` schemas in `lib/src/mcp/inputs.dart`.
The schema defines both runtime parsing and the JSON Schema advertised to
clients. Schema-first generation preserves the distinction between omitted
arguments and explicit nulls, including partial updates. Graph queries use
a runtime Ack codec around the existing `OkfGraphQuery` API. Spec validation
and tolerant YAML metadata keep their own contracts.

Concept-ID codecs keep strings on the wire and decode through `OkfConceptId`.
The advertised JSON Schema describes their string shape; runtime parsing
enforces the domain's path rules. MCP and graph-query errors share a formatter
that preserves nested field paths and reasons without producing an OKF Report.

Inferring these optional inputs from nullable Dart fields with `@AckModel()`
would also permit explicit nulls. Their wire contract therefore remains the
source of truth through `@AckInfer()`.

Index/log entries and legacy citation values use `@AckModel()` to generate
equality, hashing, `copyWith`, and diagnostic strings. Their Markdown parsers
and emitters still own the OKF document format. Entry constructors remain
permissive so parsing can retain malformed content for validation.

Ack 1.2 supports validation in generative constructors, but requires that
constructor shape and rejects custom methods that override generated members.
IDs, diagnostics, and documents retain their domain validation and custom
formatting; switching their constructor syntax alone does not make them
compatible with generated members.

Legacy citation extraction is an optional v0.1 compatibility feature permitted
by OKF v0.2 §13.1. Current provenance comes from `sources` frontmatter.

After changing an annotated model or input schema, regenerate and commit its
Ack parts:

```console
dart pub get
dart run build_runner build
dart analyze --fatal-infos
dart test
```

CI runs the same check the following command runs:

```console
dart run tool/ci/check_generated.dart
```

The command regenerates the models and compares them with the parts committed
at `HEAD`. It checks committed artifacts, so it fails while a regenerated part
is only staged or still untracked. Commit all parts, then run it. Use
`dart run build_runner build` alone while developing the change.

Generated MCP input classes stay internal. The annotated entry classes and
their generated schema companions are available through the public OKF library.

## License

Apache License 2.0.

[spec]: https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/62432a095456147ee71e70ac6e4dc0d2dea3ac30/okf/SPEC.md
[example]: https://github.com/btwld/okf/blob/main/example/okf.dart
[matrix]: https://github.com/btwld/okf/blob/main/docs/conformance-matrix.md#reserved-file-readings
