/// The version of this package, as `okf --version` and the MCP server report
/// it.
///
/// This is not the OKF Spec version a root index declares in `okf_version`.
const String okfVersion = '0.5.1';

/// The revision of the bytes `OkfIndexGenerator` emits.
///
/// It names the release that last changed the generator's output for any
/// bundle, so consumers that compare indexes with generated output pin this
/// value rather than [okfVersion]. It changes only in a minor release.
const String okfIndexGeneratorRevision = '0.5.0';
