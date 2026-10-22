# ADR-0009: Reserved-file projection joins the single write path

- Status: accepted
- Date: 2026-10-22
- Amends: [ADR-0003](0003-bundle-changeset-single-write-path.md)

## Context

A downstream producer layers its own index and log conventions over a bundle:
a Wayfinder Profile that generates `index.md` for directories okf's overlay
does not touch, or a caller that records its own log entry for a change. The
change set fixes those bytes at preparation, so the producer could either
write the files after commit, outside the lock, the validation and the
rollback, or fork the overlay. Either way the bytes on disk would no longer be
the bytes the Spec validator judged. Producers that compare indexes with
generated output also had to pin an exact okf patch release, because the
package exported no statement of when the generator's bytes change.

## Decision

`OkfBundleChangeApplier.prepare` takes an optional `OkfReservedFileProjection`.
After the change set is overlaid, the projection receives the inspected
source, the candidate, the change set's files and its date, and returns texts
for reserved `index.md` and `log.md` paths; `null` keeps the source text. Any
other path is a tool error (`OkfBundleChangeException`). The projected texts
replace the change set's in the candidate, the closed validator judges the
result exactly as it judges the change set alone, so Spec-invalid output is a
refusal, and the commit plan binds those bytes to the same source snapshot, so
a stale source is still refused at commit. An empty change set with a
projection is a reserved-file repair. A refusal carries its candidate, so a
caller can show what it refused. Every text the change set or the projection
produces must survive UTF-8 encoding; one with an unpaired surrogate is the
same tool error, because the writer would commit other bytes than the ones
judged.

Concepts stay out of reach: the overlay remains their only writer, so the
lossless round trip and the log entries that describe concept changes keep
one owner.

`okfIndexGeneratorRevision` names the release that last changed
`OkfIndexGenerator`'s output bytes. Generator output changes only in a minor
release, which bumps the revision; patch releases never change it.

## Consequences

- Downstream index and log conventions commit atomically with the change that
  needs them, under the bundle lock, and never bypass validation.
- A projection is caller code running inside preparation. It must not write
  the bundle, and preparation is unlocked unless the caller holds
  `OkfBundleLock.write`, which `okf_io.dart` now exports.
- Consumers pin `okfIndexGeneratorRevision` instead of a patch range, so a
  patch release of okf cannot change their expected indexes.
- `okfVersion` reports the package version to such consumers; it is not the
  OKF Spec version a root index declares.
