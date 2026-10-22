/// The version of this package, as `okf --version` and the MCP server report
/// it.
///
/// This is not the OKF Spec version a root index declares in `okf_version`.
const String okfVersion = '0.6.0';

/// The revision of the bytes `OkfIndexGenerator` emits.
///
/// Every release with the same revision generates the same indexes for the
/// same bundle, so consumers that compare indexes with generated output pin
/// this value rather than [okfVersion]. `0.5.0` is the baseline the promise
/// starts from, not the release that last changed the output. A later change
/// to the output ships only in a minor release, which sets the revision to
/// its own version.
const String okfIndexGeneratorRevision = '0.5.0';
