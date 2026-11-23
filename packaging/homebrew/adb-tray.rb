# Homebrew formula for Appninjas ADB. The published copy is Formula/adb-tray.rb in
# https://github.com/Dvisious-AB/homebrew-tap; update url and sha256 there after each release.
#
# It builds the menu bar app from source on the user's Mac, so the app is ad-hoc signed locally and
# needs no Developer ID or notarization.
class AdbTray < Formula
  desc "Menu bar app for adb devices and scrcpy screen mirroring"
  homepage "https://appninjas.se/en/appar/adb"
  url "https://github.com/Dvisious-AB/adb-tray/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  # The code is MIT. The Appninjas name and logo in the app icon are not; see NOTICE.
  license "MIT"
  head "https://github.com/Dvisious-AB/adb-tray.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura
  depends_on "scrcpy"

  def install
    # Homebrew builds inside a sandbox, and macOS does not let SwiftPM nest its own.
    system "macos/build-app.sh", "--version", version.to_s, "--output", prefix, "--disable-sandbox"
    bin.write_exec_script prefix/"Appninjas ADB.app/Contents/MacOS/adb-tray"
  end

  def caveats
    <<~EOS
      Appninjas ADB needs adb. Homebrew ships it as a cask, which a formula cannot depend on:
        brew install --cask android-platform-tools

      To start Appninjas ADB now and at every login:
        brew services start adb-tray
    EOS
  end

  service do
    run opt_prefix/"Appninjas ADB.app/Contents/MacOS/adb-tray"
    # launchd's PATH does not include Homebrew; the app also searches the usual places itself.
    environment_variables PATH: std_service_path_env
    process_type :interactive
    # Restart after a crash, but not after Quit in the menu.
    keep_alive crashed: true
  end

  test do
    assert_match "adb-tray #{version}", shell_output("#{bin}/adb-tray --version")
  end
end
