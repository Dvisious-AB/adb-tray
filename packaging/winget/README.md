# winget

The manifests for `Dvisious.AppninjasADB` in [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs).
The package is the portable `adb-tray.exe` in a zip, which winget unpacks and puts on the PATH as
`adb-tray`. It depends on `Genymobile.scrcpy`, whose Windows release also contains adb.

After a release:

1. Put the version and the zip's SHA-256 (from the release job summary) into the three files in
   `manifests/`, and move them to `manifests/d/Dvisious/AppninjasADB/<version>/` in a fork of
   winget-pkgs.
2. Check them with `winget validate --manifest <folder>` and install them locally with
   `winget install --manifest <folder>`.
3. Open a pull request against microsoft/winget-pkgs. Microsoft's pipeline scans and installs the
   package, and a moderator merges it.

The program is not code-signed, so SmartScreen may say "unknown publisher" the first time it runs.
