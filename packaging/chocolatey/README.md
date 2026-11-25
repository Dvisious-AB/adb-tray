# Chocolatey

The `adb-tray` package for the [Chocolatey community repository](https://community.chocolatey.org).
It unpacks the release zip, and Chocolatey puts a shim for `adb-tray.exe` on the PATH.
`tools/chocolateyuninstall.ps1` removes the Start at login entry from the registry on uninstall. It depends on
the community `scrcpy` package, which contains adb.

After a release:

1. Set the version in `adb-tray.nuspec` and in `tools/chocolateyinstall.ps1`, and the zip's SHA-256
   from the release job summary in `tools/chocolateyinstall.ps1`.
2. `choco pack packaging/chocolatey/adb-tray.nuspec`, then test with
   `choco install adb-tray --source .` on a Windows machine.
3. `choco push adb-tray.<version>.nupkg --source https://push.chocolatey.org/` with the API key from
   the maintainer's Chocolatey account. The package then waits in moderation, usually a few days.
