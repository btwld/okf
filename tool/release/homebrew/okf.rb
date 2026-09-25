# Canonical source: btwld/okf, tool/release/homebrew/okf.rb. Edit it
# there and copy the result into the tap; a hand edit made only in the tap is
# lost at the next release.
#
# cli_pkg's pkg-homebrew-update rewrites exactly one "url" and one "sha256"
# field, pointing them at the GitHub source archive for the released tag. A
# formula with per-platform bottle blocks would have only its first block
# rewritten and the rest left stale, so this must be a source build.
#
# The Dart SDK is vendored as a resource rather than declared as a build
# dependency: Homebrew core has no dart formula, and depending on a
# third-party tap would make every install pull that tap in.
class Okf < Formula
  desc "Format-first toolkit for Open Knowledge Format bundles"
  homepage "https://github.com/btwld/okf"
  url "https://github.com/btwld/okf/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "d7edf53e48533cea185cb237a563470af0515843b08862bc8267b3f4d6972df0"
  license "Apache-2.0"

  # Refresh the digests from the checksum published beside each SDK archive:
  #   curl "<archive url>.sha256sum"
  dart_sdk_version = "3.13.3"
  dart_sdk_url, dart_sdk_sha = if OS.mac? && Hardware::CPU.intel?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-macos-x64-release.zip",
     "df957f34954c03c6551ff1ca7ce0c31038039689345f8b4d658aa5e69e28495c"]
  elsif OS.mac? && Hardware::CPU.arm?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-macos-arm64-release.zip",
     "c703bcbb25ca0cc5df9109fb8272d52786ac14782437bd9e365a01985273c1cc"]
  elsif OS.linux? && Hardware::CPU.intel?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-linux-x64-release.zip",
     "549c182cffbdc6864df7509c16fec646c73fe6cb8a18c2cb572db1292f300cd7"]
  elsif OS.linux? && Hardware::CPU.arm?
    ["https://storage.googleapis.com/dart-archive/channels/stable/release/#{dart_sdk_version}/sdk/dartsdk-linux-arm64-release.zip",
     "c59c535623f3ab9717e8755237df695f153fb3af3bfb0f6c281b2eb4fefe669e"]
  end

  resource "dart-sdk" do
    url dart_sdk_url
    sha256 dart_sdk_sha
  end

  def install
    # Into buildpath, not libexec: the SDK is only needed to compile, and
    # keeping it would leave a ~620MB keg behind for a 10MB executable.
    (buildpath/"dart-sdk").install resource("dart-sdk")

    ENV["PUB_ENVIRONMENT"] = "homebrew:okf"

    dart = buildpath/"dart-sdk/bin/dart"
    system dart, "pub", "get"
    system dart, "compile", "exe", "bin/okf.dart", "-o", "okf"
    bin.install "okf"
  end

  test do
    assert_match "okf #{version}", shell_output("#{bin}/okf --version")
  end
end
