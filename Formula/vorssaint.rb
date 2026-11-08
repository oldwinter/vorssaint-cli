# SPDX-License-Identifier: GPL-3.0-or-later
#
# Homebrew formula for vorssaint — source of truth for
# oldwinter/tap/vorssaint.rb.
#
# Before the first tagged release this installs from source:
#
#   brew install --HEAD oldwinter/tap/vorssaint
#
# Once a release exists, run `scripts/release-formula.sh <tag>`; it replaces
# this file with a binary formula pinned to the release asset url + sha256.
class Vorssaint < Formula
  desc "macOS power tools as a single terminal binary"
  homepage "https://github.com/oldwinter/vorssaint-cli"
  license "GPL-3.0-or-later"
  head "https://github.com/oldwinter/vorssaint-cli.git", branch: "master"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/vorssaint"
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/vorssaint --version"))
    assert_match "all checks passed", shell_output("#{bin}/vorssaint --selftest")
  end
end
