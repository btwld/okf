# ADR-0003: BundleChangeSet is the single write path; MCP verbs are thin adapters

- Status: accepted, amended by [ADR-0009](0009-reserved-file-projection.md)
- Date: 2026-08-14
- Issues: [#16](https://github.com/conceptadev/okf/issues/16), #12, #13

## Context

The four MCP write verbs each restated the same obligations: validate before
write, refuse with the CLI's finding IDs, round-trip concept files losslessly,
maintain `index.md` and `log.md`, all-or-nothing across files. The #3 contract
froze only bundle-in → report-out, so a prospective write had no validation
seam — each verb would re-implement checks or reach past the validator's
interface. `OkfBundleWriter` is atomic per file but documented non-transactional
across files, so multi-file atomicity had no owner either.

## Decision

One deep module, the BundleChangeSet (#16): describe a change (create, update,
link, deprecate) → prepare and validate the complete candidate in memory →
inspect an immutable candidate → atomically commit the exact prepared bytes.
Preparation always runs the closed OKF Spec validator on `bundle ⊕ change`, so
refusals carry the same Report the CLI produces, by construction. The
implementation hides the bundle overlay, lossless concept round-trip,
index/log maintenance (through the ADR-0004 model), and multi-file staging
with rollback.

MCP write verbs are thin adapters: translate tool parameters into a change
description, return the change-set's result, own no validation or file logic.
The error tiers are decided at this seam: malformed tool input is a tool error;
a schema-valid but non-conformant change is a refusal carrying the Report.

## Consequences

- Atomicity and round-trip fidelity are implemented and tested once.
- No configurable Spec checker: preparation cannot drift from `okf validate`.
- The opaque prepared value binds commit to the exact candidate that passed.
- Two adapters justify the seam: the MCP verbs now, batch/enrichment harnesses
  later.
- Shipping order: #3 ships the change *descriptions* only. The preparation
  results — the immutable candidate, the opaque prepared value, and the
  refused/ready pair — land with the #16 implementation that produces them.
  Shipping them earlier meant public types no caller could construct and no
  test could exercise, which pins a shape without proving it. This Decision
  is unchanged; only its delivery is deferred.
