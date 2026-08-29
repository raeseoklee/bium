# Homebrew formula for bium.
#
# This file belongs in a separate tap repository named `homebrew-bium`, at
# `Formula/bium.rb`, so users can install with:
#
#   brew tap raeseoklee/bium
#   brew install bium
#
# Before the first release, fill in the sha256 of the release tarball:
#
#   curl -sL https://github.com/raeseoklee/bium/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
class Bium < Formula
  desc "Reclaim disk space on a Mac, honestly"
  homepage "https://github.com/raeseoklee/bium"
  url "https://github.com/raeseoklee/bium/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/raeseoklee/bium.git", branch: "main"

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/bium"
  end

  test do
    assert_match "bium", shell_output("#{bin}/bium --help")
    # scan must never modify anything, so it is safe to run in a sandbox.
    system bin/"bium", "scan", "--no-actions"
  end
end
