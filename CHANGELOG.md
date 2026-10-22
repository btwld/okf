## 0.6.0

- Edit existing concepts in place. `OkfUpdateConceptChange`,
  `OkfLinkConceptsChange` and `OkfDeprecateConceptChange` used to re-emit the
  whole concept in canonical form, which turned flow style into block style,
  moved keys such as `tags` and dropped comments. They now keep the exact
  bytes of every frontmatter key they do not change, and of the body unless an
  update replaces it: a changed value is replaced where it stands, a changed
  flow collection has its changed values replaced and new entries added after
  its last one (one that loses an entry is rewritten whole on one line), a
  changed `|` or `>` block scalar stays a literal block when its new value has
  a line break, a changed block mapping is edited entry by entry, a removed
  key removes only its own lines, a new key goes directly after the last entry
  of its mapping, and a link appends its `sources` item after the last one.
  Frontmatter already in the canonical form `okf format` writes stays
  canonical, with a new key at its place in the preferred key order, so an
  edit never makes `okf format --check` fail on a bundle that passed it. New
  lines take the file's line break, so CRLF files stay CRLF, and a concept
  file that begins with a UTF-8 byte order mark keeps it. Every edit is parsed
  again and must read back as the requested mapping; otherwise the changed
  top-level values, and failing that the whole mapping, are re-emitted, as the
  whole mapping is for frontmatter written as one `{...}` mapping or with YAML
  aliases, explicit `?` keys or collection keys. An update whose result equals
  the concept writes nothing, now also when it only reorders a nested
  mapping's keys. An edit that cannot be written so that it reads back, such
  as a body-only concept's new body whose first line is `---`, throws
  `OkfBundleChangeException` from `prepare`, and so does an edit whose input
  holds an unpaired surrogate, naming the field, body or deprecation note
  that holds it before any rewrite is tried. New concepts, `serialize` and
  `okf format` keep the canonical form. See ADR-0010.
- Keep the UTF-8 byte order mark of every file a commit rewrites. A concept,
  `index.md` or `log.md` file that began with one keeps it, whether the
  change set or a reserved-file projection wrote its new text. Loading drops
  one leading mark, so a candidate's texts never include the file's own and a
  projection returns texts without it. A text that does begin with U+FEFF
  holds it as content: the commit writes a mark before it, so the file loads
  as the text that was validated. In 0.5.1 every rewritten file lost its
  mark, and such a text lost its leading U+FEFF on the next load.
- Add `OkfDocument.sourceText`, the exact text given to `OkfDocument.parse`,
  or `null` for a document built with the constructor or `copyWith`. It is
  the text update, link and deprecate changes edit. The rewriter that makes
  those edits, and the emitter's spelling of the scalars they write, stay
  package-internal; a host reads what a change writes from its candidate.

## 0.5.1

- Add a reserved-file projection to `OkfBundleChangeApplier.prepare`. The
  optional `project` callback receives the inspected source, the candidate,
  the change set's files and its date, and returns texts for `index.md` and
  `log.md` paths, or `null` to keep the source text. The projected texts are
  validated with the rest of the candidate, so Spec-invalid output is refused,
  and the commit writes exactly those bytes or refuses a stale source. Naming
  any other path throws `OkfBundleChangeException`. An empty change set with a
  projection repairs reserved files on their own. `apply` takes the same
  `project` argument. See ADR-0009.
- Add `candidate` to `OkfPreparationRefused` and
  `OkfBundleApplicationRefused`: the refused candidate after any projection,
  so a caller can show what a refused change would have written. `prepare`
  and `apply` always set it; it is nullable only because both constructors
  were already public.
- Throw `OkfBundleChangeException` from `prepare` for a text that holds an
  unpaired surrogate, whether a change set or a projection produced it.
  Previously the writer replaced the surrogate with U+FFFD, so the committed
  bytes differed from the text the validator judged. `OkfBundleWriter.writeAll`
  and `writeDocument`, which `okf format` and `okf index` write through, now
  throw `ArgumentError` for such a text in check mode too, before touching the
  filesystem.
- Throw `OkfYamlEncodeException` from `OkfYamlEmitter.emit`, and so from
  `OkfDocument.serialize`, for a frontmatter string that holds an unpaired
  surrogate. The emitter used to write it as a `\ud800` escape that YAML
  parsers reject, so `OkfBundleWriter.writeDocument` wrote a concept that
  failed to load. `writeDocument` now fails before touching the filesystem,
  reporting this like every other failure through its future, and `prepare`
  throws `OkfBundleChangeException` for a change whose frontmatter the
  emitter cannot write, such as one that holds such a string.
- Add `OkfPreparedCandidate.toLoadResult()`, a new public method that reads
  a candidate as a later load of the committed bundle would, retaining load
  findings for source files the candidate does not replace, so downstream
  checks written against `OkfBundleLoadResult` can judge a candidate before
  commit. See ADR-0009.
- Export `OkfBundleLock` from `okf_io.dart`, so applications can run their own
  reads and writes under the bundle's claims. Its documentation and the README
  now state the rule the `fcntl` lock implies: run every operation on a bundle
  in one isolate per process.
- Export `okfVersion`, the package version, and `okfIndexGeneratorRevision`,
  which identifies `OkfIndexGenerator`'s output bytes, from `okf.dart`. Every
  release with the same revision generates the same indexes for the same
  bundle. The revision is `0.5.0`, the baseline the promise starts from; a
  later change to the output ships only in a minor release, which sets the
  revision to its own version.
- Add `OkfDocument.bodyStartLine`, the 1-based line of the parsed text on
  which the body begins, so a host can cite body text by file line instead of
  assuming the body is a suffix of the file: line `n` of `body` is line
  `bodyStartLine + n - 1` of the source, whatever its line endings, byte order
  mark or blank lines around the frontmatter. Concepts loaded by
  `OkfBundleLoader` or read from an `OkfPreparedCandidate` carry it; documents
  built with the constructor or `copyWith` have none.
- Raise the minimum supported Dart SDK from 3.9 to 3.11 (#62).
- Turn `OkfGraphResolution.fromWireValue` from a static method into a factory
  constructor (#65). Calls and tear-offs compile unchanged.
- Move the repository, issue tracker, Homebrew tap and composite action to
  `btwld` (#66): install with `brew install btwld/tap/okf` and reference the
  action as `btwld/okf@v0.5.1`.
- Validate the package again when the release workflow publishes it to
  pub.dev (#63).

## 0.5.0

- Adopt OKF revision `62432a0`: every timestamp is an ISO 8601 datetime with a
  UTC offset. A date-only or offset-less value raises the non-blocking
  `okf/timestamp-without-offset` advisory naming the exact field, and
  `OkfSpecValidation.isConformant` is unchanged, so a bundle that validates today
  still validates. `okf validate --strict` is the exception: it escalates
  advisories to failures, so it starts failing on date-only timestamps it used to
  accept. Run `okf format --migrate-timestamps` on those bundles, or drop
  `--strict` until you have.
- Compare staleness as an instant rather than a local calendar day. `stale_after`
  was read as a calendar date and compared in the caller's local zone; it is now
  an instant, stale when `now >= stale_after`. East of UTC a concept goes stale
  later than before — two hours in Berlin, twelve in Auckland — and west of UTC it
  can now become stale on the previous local day. Callers in UTC see no change.
- Add `okf format --migrate-timestamps`, which rewrites date-only values to
  `T00:00:00Z` and reports every change. It is opt-in, idempotent, writes nothing
  under `--check`, and leaves offset-less datetimes alone rather than guessing a
  zone for them. Migrating a date-only `verified.at` can raise a concept's
  `trust_tier` from `unverified` to `human-reviewed`, because the verification now
  carries a usable time; that change is visible in `okf graph`.
- Reject impossible timestamps through one strict parser. `2026-02-30` previously
  rolled over into March 2 and was accepted; it is now rejected everywhere. Date
  values still read as midnight UTC for `stale_after`, `usage_window` and
  `last_modified`, where a date has always been valid. `generated.at` and
  `verified[].at` have always required a time, so a date-only value there carries
  no instant and does not count as a verification.

## 0.4.2

- No changes to the package. This release completes the deployment pipeline:
  the macOS job now holds the `contents: write` permission its uploads need,
  so 0.4.1's macOS archives and Homebrew formula, which were published by
  hand, are produced by CI again.

## 0.4.1

- Use Ack schemas for graph-query parsing and generated, typed MCP arguments.
  Each input schema owns runtime constraints and the advertised JSON Schema.
  Partial updates retain omitted fields, and OKF Spec findings and tolerant
  metadata behavior remain unchanged. Concept IDs stay encoded as strings, and
  invalid IDs and graph-query fields are reported with their specific paths and
  validation reasons.
- Generate equality, hashing, `copyWith`, diagnostic strings, and JSON adapters
  for index entries, log entries, and legacy citation values with Ack. Use the
  generated copies when normalizing writable index and log entries, and verify
  all generated model parts in CI. Const constructors, tolerant parsing,
  Markdown output, and optional v0.1 citation compatibility are preserved;
  concept IDs, diagnostics, and documents retain their existing validated
  constructors and custom formatting.
- Consolidate internal rule metadata, execution context, and YAML value helpers
  while preserving the public package exports. Remove redundant construction
  wrappers and use normal constructors where direct initialization suffices.
  Align IO, MCP, and rule tests with their source modules and consolidate the
  index/log contract suites without changing their assertions.
- Classify local graph targets containing raw or percent-encoded C1 control
  characters as invalid, matching bundle-path validation, instead of
  unresolved.
- Raise the minimum supported Dart SDK from 3.4 to 3.9 for Ack 1.2.

## 0.3.0

- Narrow MCP `list-concepts` with optional `prefix`, `type`, and `query`
  parameters: `prefix` names a bundle area, `type` keeps one concept type, and
  `query` is a case-insensitive substring over concept IDs and titles. A
  filtered listing that matches nothing reports the type and area vocabulary
  the bundle actually holds, so a caller corrects its filters in one round
  trip.
- Serialize MCP tool results exactly once, as the JSON text block. Results no
  longer carry a duplicate `structuredContent` copy, which doubled every
  result on the wire; a client that read `structuredContent` reads the text
  block instead.
- Drop the `path` field from MCP concept summaries and lookups; it is always
  the concept ID plus the `.md` suffix.
- Match graph `path_prefixes` (CLI `--path-prefix`) per whole path segment
  through the new `OkfConceptId.isWithin`: a value names a concept or a
  directory, so `architecture` matches `architecture` and everything under
  `architecture/`, and no longer the unrelated `architecture-notes`. A value
  that named a full document path, such as `notes/beta.md`, becomes the
  concept ID, `notes/beta`.

## 0.2.0

- Add the engine contract types: findings, the immutable OKF Spec report and
  conformance judgment, adapter verdicts, change descriptions, and index/log
  entries.
- Pin the finding ID grammar to lowercase kebab-case `<namespace>/<code>`
  and hold `OkfReport` findings in one canonical order on every surface:
  path, line, column, ID, severity, message.
- Move `OkfIndexEntry` into the index/log model and add value equality to
  index and log entries.
- Add `OkfIndexDocument` and `OkfLogDocument`, which parse and emit the
  `index.md` and `log.md` entry format. The index generator and the reserved
  file rules consume them instead of carrying their own copy of the format.
- Namespace every Spec finding as `okf/<code>` and expose read-only rule
  descriptors while keeping execution fixed inside `OkfSpecValidator`.
  Validation text and JSON now project the shared Report, bundle load failures
  are findings, and CLI exit status is judged by the Verdict. `okf validate
  --strict` fails on advisories; `--warnings-as-errors` remains as an alias.
- Add prepared bundle changes as the single safe write path for create,
  update, link, and deprecate operations. Preparation validates a complete
  immutable candidate with the closed Spec validator; commit detects stale
  source state and writes the exact prepared files transactionally.
- Add composable graph filters for concept type, path prefix, and edge
  resolution.
- Version and document the graph JSON schema.
- Add `okf mcp`, a Model Context Protocol server over stdio with the
  `list-concepts`, `lookup-concept`, `query-graph`, and `validate` tools. Its
  `validate` tool returns the same Report and Verdict as the command line, and
  `query-graph` takes the graph filter vocabulary as its input schema.
- Add the `create-concept` and `update-concept` MCP write tools, thin adapters
  over `OkfBundleChangeApplier`: one call writes the concept and maintains the
  `index.md` and `log.md` entries atomically. A Spec-invalid candidate is
  refused with the Report the command line prints for the same state and
  leaves no file changed, while input that describes no bundle state is a
  plain tool error. Updates manage `type`, `title`, `description`,
  `tags`, and `body`, and retain every other frontmatter field.
- Add the `link-concepts` and `deprecate-concept` MCP write tools, completing
  the fixed tool surface. A link records the relationship on the source
  concept; an absent target is accepted and remains an unresolved graph edge.
  A deprecation sets `status: deprecated`. Both update the concept and
  `log.md` in the same operation and share the write path's refusal and
  tool-error tiers.
- Breaking: `okf validate --output json` replaces the `valid`, `error_count`,
  `warning_count`, and `diagnostics` fields with the Report projection — a
  `findings` array whose entries carry `id`, `severity`, `message`, and
  `location`.
- Breaking: remove `OkfDiagnostic` and `OkfValidationReport` (with `isValid`,
  `errorCount`, and `warningCount`) in favor of `OkfFinding`, `OkfReport`, and
  the closed `OkfSpecValidator`.
- Enforce one non-normalizing POSIX grammar across bundle inventories, concept
  IDs, and file-system adapters.
- Snapshot bundle change descriptions faithfully, keeping frontmatter value
  types, key order, and the body verbatim, and reject YAML values no change
  kind can represent with `ArgumentError`.
- Validate relationship names, and escape control characters in one-line
  finding text while retaining raw locations and messages in JSON.
- Add the CI gate: releases attach `dart compile exe` binaries for Linux and
  macOS, and a composite GitHub Action pins an engine version, downloads the
  matching attested binary from an immutable release, and runs OKF Spec
  validation as a single invocation whose exit code decides the job.
- Define the index link destination grammar (ADR-0008): destinations are
  percent-encoded — generated links now encode parentheses too — and
  CommonMark angle-bracket destinations (`(<…>)`) parse and normalize to the
  encoded spelling, so reference filenames with spaces and parentheses are
  writable and parseable. Plain destinations carrying raw whitespace,
  parentheses, or angle brackets surface the new advisory
  `okf/non-portable-index-link`, and `OkfIndexDocument` rejects them with
  `ArgumentError` instead of emitting a line CommonMark cannot read.
- Fix graph target resolution crashing the host process on link targets that
  fail percent-decoding: a segment with no `%` (raw non-ASCII such as an em
  dash in a reference filename) now resolves against the bundle as already
  decoded, and a segment with a genuinely malformed escape resolves as an
  `invalid` edge.
- Classify prose `sources[].resource` descriptors that contain slashes
  ("extracted PDF/OOXML text") as `descriptor` graph edges: whitespace or a
  backtick now marks a source resource as prose before the slash test, since
  genuine link paths percent-encode whitespace (ADR-0008).

## 0.1.2

- Move package ownership to the verified `concepta.dev` publisher.
- Update repository and issue links for the `conceptadev` organization.

## 0.1.1

- Remove development-only and copied third-party test artifacts.
- Replace copied fixtures with independently authored compatibility tests.

## 0.1.0

- Initial implementation of the Open Knowledge Format v0.2.
- Parse, write, validate, index, and graph OKF bundles.
- Add the `okf` command-line interface.
