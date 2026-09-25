# OKF GitHub Workflows

## Workflows

### `test.yml`

**Trigger**: push to `main`, pull requests, `workflow_call`, manual dispatch
**Purpose**: format, analyze, and test the package, the release tool, and the
`>=3.4.0` SDK floor
**Used by**: `release.yml`, which calls it before deploying anything

### `release.yml`

**Trigger**: git tag push matching `v*` + manual dispatch
**Process**:

1. **Test** — the whole of `test.yml`
2. **Release** (ubuntu) — `pkg-github-release`, `pkg-github-linux`, then
   `dart pub publish --force`
3. **Deploy macOS** — `pkg-github-macos`, then the Homebrew formula, versioned
   and unversioned

Release notes come from the first `## <version>` section of `CHANGELOG.md`.

## Release process

1. Bump `version:` in `pubspec.yaml`
2. Update `lib/src/version.dart` and the `btwld/okf@vX.Y.Z` reference in
   `README.md` to the same value (`dart test test/ci_gate_test.dart` checks all
   three agree)
3. Add the matching `## X.Y.Z` section at the top of `CHANGELOG.md`
4. Commit
5. `git tag vX.Y.Z && git push origin vX.Y.Z`

cli_pkg reads the version from `pubspec.yaml`, not from the tag. A tag that
disagrees with the pubspec publishes under the pubspec's version, so step 5
must match step 1.

## Version management

- **Version source**: `pubspec.yaml`, edited by hand
- **Tag format**: `vX.Y.Z` is what you push and what triggers the release.
  cli_pkg hardcodes the GitHub release's `tag_name` to the **bare** version, so
  the release job also publishes a `X.Y.Z` tag at the same commit and the
  release assets hang off that one. Both tags therefore exist for every
  release, and `btwld/okf@vX.Y.Z` keeps working as an action ref.
- **CHANGELOG**: cli_pkg reads `CHANGELOG.md` for the GitHub release body
- **Assets**: `okf-<version>-<os>-<arch>.tar.gz` per platform, attached to the
  bare-version release. Only the
  platform that runs the build gets a self-contained executable; every
  cross-compiled archive is a launcher plus a snapshot under `src/`.

## Required secrets

| Secret | Used by | Purpose |
| --- | --- | --- |
| `GITHUB_TOKEN` | automatic | create the release, upload assets |
| `HOMEBREW_TAP_GH_TOKEN` | `pkg-homebrew-update` | push to `btwld/homebrew-tap` |

pub.dev needs no secret: the `release` job requests `id-token: write` and
setup-dart exchanges that OIDC token for temporary credentials. This requires
automated publishing to be configured on pub.dev for `btwld/okf` with
this workflow filename (`release.yml`) and a `v{{version}}` tag pattern.
cli_pkg's `pkg-pub-deploy` is deliberately unused: it can only publish from a
long-lived `PUB_CREDENTIALS` file.

## Homebrew

`pkg-homebrew-update` rewrites exactly one `url` and one `sha256` in the tap's
`Formula/okf.rb`, pointing them at the GitHub **source** archive for the tag.
The canonical formula lives at `tool/release/homebrew/okf.rb`; the tap must
carry that source build, not per-platform bottle blocks, or only the first
block would ever be updated. Homebrew therefore compiles okf from source and
does not use the release binaries.

The formula vendors the Dart SDK as a `resource` (Homebrew core has no dart
formula) and stages it into `buildpath`, so the SDK is discarded after the
build and the keg holds only the 10MB executable. Bump `dart_sdk_version` and
its four digests there when the SDK needs refreshing.

`--versioned-formula` additionally copies the result to `Formula/okf@X.Y.Z.rb`,
so the tap accumulates one file per release.

## Troubleshooting

### Workflow doesn't trigger

Ensure the tag is pushed to the remote and matches `v*`.

### `307 Moved Permanently` when creating the release

`_owner` in `tool/release/tool/grind.dart` no longer names the account that
canonically owns the repository. cli_pkg does not follow redirects on POST.

### Homebrew step fails to push

`HOMEBREW_TAP_GH_TOKEN` needs write access to `btwld/homebrew-tap`, and
the tap must already contain `Formula/okf.rb`.
