#!/usr/bin/env bash
set -euo pipefail

# Installs the released okf engine for a runner and prints the executable path.
#
# cli_pkg publishes standalone executables as archives, and only the platform
# that built the release gets a self-contained binary: every cross-compiled
# target ships a launcher that resolves a snapshot from the "src" directory
# beside it. The whole tree is therefore kept, never just the entrypoint.

version="${1:?engine version is required}"
runner_os="${2:?runner OS is required}"
runner_arch="${3:?runner architecture is required}"
directory="${4:?install directory is required}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "okf: engine version must be a complete v-prefixed release tag" >&2
  exit 2
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
asset="$(bash "$script_dir/platform-asset.sh" "$version" "$runner_os" \
  "$runner_arch")"
# cli_pkg names the release after the bare version, so the assets hang off
# "<version>", not off the "v<version>" tag this action is referenced by.
release="${version#v}"

rm -rf "$directory"
mkdir -p "$directory"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT

curl --fail --silent --show-error --location --retry 3 \
  --output "$archive" \
  "https://github.com/btwld/okf/releases/download/$release/$asset"
tar --extract --gzip --file "$archive" --directory "$directory"

# cli_pkg archives unpack to "<standalone name>/<executable>".
engine="$directory/okf/okf"
[[ -f "$engine" ]] || {
  echo "okf: $asset does not carry an okf executable" >&2
  exit 1
}

chmod +x "$engine"
printf '%s\n' "$engine"
