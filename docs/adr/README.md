# Architecture decision records

One file per decision. Decisions here bind the base-toolchain work specced in
[#2](https://github.com/conceptadev/okf/issues/2) and its sub-issues. A future
architecture review must not re-litigate an accepted ADR unless real friction
warrants reopening it; supersede with a new record instead of editing history.

Vocabulary: these records use *module*, *interface*, *seam*, *adapter*, *depth*,
*leverage*, and *locality* in the deep-module sense — a module is anything with
an interface and an implementation; a seam is where an interface lives; depth is
behaviour per unit of interface a caller must learn.

| # | Decision |
|---|----------|
| [0001](0001-one-finding-contract.md) | One Finding contract owns finding identity, the Report, and the Verdict |
| [0002](0002-rule-catalog-registration-seam.md) | OKF Spec rule execution is closed |
| [0003](0003-bundle-changeset-single-write-path.md) | BundleChangeSet is the single write path; MCP verbs are thin adapters |
| [0004](0004-index-log-model-single-owner.md) | One module owns the index/log entry format |
| [0005](0005-single-graph-query-interface.md) | One graph filter vocabulary; CLI and MCP are two adapters |
| [0006](0006-verdict-judges-loaded-content.md) | The Verdict judges loaded content; usage exits are adapter decisions |
| [0007](0007-check-mode-exits-are-adapter-decisions.md) | Check-mode "would change" exits are adapter decisions |
| [0008](0008-index-link-destination-grammar.md) | Index link destinations are percent-encoded |
| [0009](0009-reserved-file-projection.md) | Reserved-file projection joins the single write path |
