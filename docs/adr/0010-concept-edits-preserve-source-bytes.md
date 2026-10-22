# ADR-0010: Concept edits preserve source bytes

- Status: accepted
- Date: 2026-10-22
- Amends: [ADR-0003](0003-bundle-changeset-single-write-path.md)

## Context

ADR-0003 gave the change set a lossless concept round trip, which the overlay
met by parsing a concept and re-emitting it in canonical form. The values
survived, but the text did not: a one-key update turned flow collections into
block ones, moved keys such as `tags` into the preferred order, dropped
comments and rewrote CRLF files with LF. A host that shows the diff of a
change before committing it, such as a write pipeline's preview, saw every
line move.

## Decision

Update, link and deprecate changes edit an existing concept's text,
`OkfDocument.sourceText`, through a package-internal rewriter. It locates each
entry by `package:yaml` source spans and rewrites only what the change alters.
New concepts, `serialize` and `okf format` keep the canonical form.

- Unchanged keys keep their bytes. A changed value is replaced where it
  stands, a block mapping is edited entry by entry, and a flow collection by
  span while it keeps its entries. A block scalar stays a literal block when
  its new value has a line break. Other values take the emitter's spelling.
- A new key goes directly after the last entry of its mapping, not at its
  place in the preferred key order: reordering would move lines the change
  did not touch.
- Canonical in, canonical out. Frontmatter that already holds exactly what
  the emitter writes for it, as `okf format` leaves it, stays that way: the
  edited block is written from its values in the emitter's form, which puts a
  new key at its place in the preferred order and a filled `[]` or `{}` in
  block style while keeping every unchanged line. Before this ADR every
  change set wrote canonical concepts, so an okf write must not make a bundle
  that passed `okf format --check` fail it.
- A change is a no-op when the resulting mapping and body equal the current
  ones as YAML data: mappings compare without regard to key order, and an
  integer never equals a double. A no-op returns the text byte for byte and
  writes nothing.
- Every result is parsed again and must read back as the requested mapping
  and body. The edit falls back in a fixed ladder: in place, then each changed
  top-level value replaced whole, then the whole mapping re-emitted between
  the existing delimiters. Frontmatter whose spans cannot locate an entry (a
  flow root, aliases, explicit `?` keys, collection keys) goes straight to the
  last step. A result that no step can make read back is a tool error.
- The rewriter and the emitter's scalar spelling stay package-internal:
  `okf.dart` exports neither. Publishing them would freeze okf's layout rules
  and quoting as a contract no consumer needs. A host that previews or scans a
  change reads the candidate's text instead. `OkfDocument.sourceText` is
  public, since it is only the text a document was parsed from.

## Consequences

- Diffs of concept changes show only the lines the change touches, and a
  file's style, comments, line breaks and byte order mark survive edits.
- The read-back check keeps the ADR-0003 guarantee: the bytes validated and
  committed always parse to the requested values, whatever path wrote them.
- The rewriter is the one place that knows YAML layout. Its fallbacks are
  coarser but always correct, so a layout it does not handle costs diff noise,
  never data.
- Parsed documents keep their source text, so a loaded bundle holds each
  concept's text about twice.
