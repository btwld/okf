# OKF 0.2 conformance matrix

This matrix pins consumer behavior to Google OKF revision
`62432a095456147ee71e70ac6e4dc0d2dea3ac30`. “Error” means an OKF Spec
conformance failure. “Advisory” is surfaced guidance that never changes
`OkfSpecValidation.isConformant`.

| Spec clause | Required consumer behavior | Finding / outcome | Evidence |
| --- | --- | --- | --- |
| §3.1 | Reserve `index.md` and `log.md` for their defined formats. | Reserved files are parsed separately from concepts. | `test/io/bundle_loader_test.dart`, `test/validator_test.dart` |
| §4, §11.1 | Every concept is UTF-8 Markdown with parseable YAML frontmatter. | `okf/invalid-utf8`, `okf/invalid-document`, or `okf/missing-frontmatter` error. | `test/io/bundle_loader_test.dart`, `test/validator_test.dart` |
| §4.1, §11.2 | Every concept has a non-empty `type`. | `okf/missing-type` error. | `test/validator_test.dart`, `test/cli_test.dart` |
| §4.1, §11 | Unknown type values are tolerated. | Conformant. | `test/conformance_test.dart` |
| §4.1, §11 | Unknown frontmatter keys are preserved and tolerated. | Conformant and round-tripped. | `test/conformance_test.dart`, `test/document_test.dart` |
| §5 | Every timestamp is an ISO 8601 datetime with a UTC offset. A date-only `stale_after`, `usage_window` boundary or `last_modified` from an earlier revision is read as midnight UTC; `generated.at` and `verified[].at` have always required a time, so a date-only value there carries no instant. | `okf/timestamp-without-offset` advisory; still conformant. `okf validate --strict` fails on it. `okf format --migrate-timestamps` rewrites date-only values, which can make a date-only `verified[].at` count as a verification again and change `trust_tier`. | `test/timestamps_test.dart`, `test/cli_test.dart` |
| §5.5 | A concept is stale when `now >= stale_after`, compared as instants. | `OkfMetadata.isStale`. | `test/metadata_test.dart` |
| §5.2, §11 | Treat a bare `verified` mapping as one event. | Conformant; one normalized verification. | `test/conformance_test.dart`, `test/metadata_test.dart` |
| §5.3, §11 | Missing optional provenance, trust, lifecycle, and computation families are accepted. | Conformant. | `test/conformance_test.dart` |
| §6.1, §11 | Broken cross-links are accepted. | Conformant; graph retains an unresolved edge. | `test/conformance_test.dart`, `test/graph_test.dart` |
| §8, §11.3 | A present `index.md` follows the index structure, as okf reads it ([below](#reserved-file-readings)). | `okf/invalid-reserved-document` or an `okf/*index*` error. | `test/validator_test.dart` |
| §8, §11 | Missing indexes are accepted. | Conformant. | `test/conformance_test.dart` |
| §8, §11 | Index link destinations are percent-encoded or angle-bracketed; raw whitespace, parentheses, and angle brackets are surfaced guidance. | `okf/non-portable-index-link` advisory; still conformant. | `test/validator_test.dart`, `test/index_log_test.dart` |
| §9, §11.3 | A present `log.md` follows the log structure, as okf reads it ([below](#reserved-file-readings)), and uses ISO dates. | `okf/invalid-reserved-document` or an `okf/*log*` error. | `test/validator_test.dart`, `test/conformance_test.dart` |
| §10, §11 | Optional Attested Computation shape deviations are soft guidance. | Advisory findings only. | `test/validator_test.dart` |
| §12 | Unknown declared versions are consumed best-effort. | `okf/unsupported-okf-version` advisory; still conformant. | `test/conformance_test.dart`, `test/validator_test.dart` |

The public `OkfSpecValidator` has a const, zero-argument constructor and no
configuration seam. `OkfBundleLoadResult.validate` merges load and fixed Spec
findings into the same `OkfReport`. CLI, MCP, CI, and prepared-write parity are
covered in their adapter slices against this shared result.

## Reserved-file readings

§8 and §9 define `index.md` and `log.md` largely by example. The closed
validator reads those examples as the required structure, so it refuses some
reserved files the Spec's text allows. These readings are fixed, like every
other rule (ADR-0002):

| Rule | okf requires | Spec text |
| --- | --- | --- |
| `okf/invalid-index-structure` | An index body holds only level-one headings and list entries of the form `* [Title](link)`, optionally followed by ` - description`; a `-` bullet works as well as `*`. Prose lines, other heading levels, other list markers such as `+` or `1.`, and unlinked entries are errors. | §8 shows the heading level and the entry form only in its example. |
| `okf/index-entry-before-section` | Every entry follows a level-one section heading. | §8 groups entries "under a heading", of no stated level. |
| `okf/empty-index-section` | Every section holds at least one entry. | §8 sets no minimum per section. |
| `okf/invalid-log-frontmatter` | A log has no frontmatter. | §8 and §12 forbid frontmatter in indexes, apart from the root `okf_version`; §9 does not mention it. |
| `okf/missing-log-title` | A log begins with one level-one title. | The title appears only in §9's example. |
| `okf/invalid-log-structure` | A log body holds only that title, `## YYYY-MM-DD` date headings and `*` or `-` list entries. Prose lines, other heading levels and other list markers are errors. | §9 calls log entries "prose" and shows the heading level and list form only in its example. |
| `okf/missing-log-date` | A log has at least one date heading. | §9 requires no entry. |
| `okf/empty-log-date` | Every date heading has at least one entry. | §9 sets no minimum per date. |

The other reserved-file rules restate the Spec's text:
`okf/missing-index-section` (one or more sections),
`okf/invalid-index-frontmatter` (no frontmatter but a root `okf_version`),
`okf/invalid-log-date` (ISO 8601 `YYYY-MM-DD` dates),
`okf/log-entry-before-date` (date-grouped entries) and
`okf/log-not-newest-first` (newest first).

Validation does not check that an index is complete either. okf accepts an
index that omits concepts or subdirectories, links to missing files or leaves
out descriptions. §8 says an index enumerates its directory's contents but not
which concepts and subdirectories it must list, §11 makes missing `index.md`
files and broken cross-links non-rejectable, and §8 only recommends
descriptions, so okf leaves completeness to the producer. A producer that
writes its own `index.md` or `log.md`, directly or through a reserved-file
projection, must therefore meet okf's structure rather than only the Spec's
text, and alone decides what its index lists.

## Package contracts

The package also defines behavior for its APIs and adapters. These contracts
support consumption and writing; they do not add OKF Spec requirements.

| Contract | Authoritative implementation | Evidence |
| --- | --- | --- |
| Logical bundle paths are relative POSIX paths without traversal or C0/DEL/C1 control characters. Graph targets use the same control-character predicate after decoding; invalid targets remain graph information, not conformance errors. | `bundle_path.dart`, `control_characters.dart`, `graph.dart` | `test/concept_id_test.dart`, `test/graph_test.dart` |
| Optional MCP inputs may be omitted but reject explicit null. Empty updates and absent fields have distinct meanings. | Ack schemas in `mcp/inputs.dart` | `test/mcp/inputs_test.dart`, `test/mcp/server_test.dart` |
| Spec conformance fails only on errors; adapter strictness may additionally fail on advisories. | `OkfSpecValidation` and `OkfVerdict` in `finding.dart` | `test/finding_test.dart`, `test/conformance_test.dart` |
| Change requests snapshot supported YAML values; unknown fields survive updates. Parser, snapshot, and emitter traversals share structural limits. | `yaml_data.dart`, `bundle_change_set.dart`, `document.dart`, `yaml_emitter.dart` | `test/bundle_change_set_test.dart`, `test/document_test.dart` |
| Preparation freezes complete candidate bytes; commit rejects stale or reused preparation and rolls back failed writes. Shared and exclusive claims coordinate readers and writers. | `io/bundle_change_applier.dart`, `io/bundle_writer.dart`, `io/bundle_lock.dart` | `test/io/bundle_change_applier_test.dart`, `test/io/bundle_writer_test.dart`, `test/io/bundle_lock_test.dart` |

Legacy timestamp and citation handling remains the optional compatibility
behavior permitted by §13.1, covered by `test/metadata_test.dart` and
`test/document_test.dart`.
