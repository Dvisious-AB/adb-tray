# Unpacks the release zip; Chocolatey puts a shim for adb-tray.exe on the PATH.
$ErrorActionPreference = 'Stop'
$version = '1.1.0'
Install-ChocolateyZipPackage -PackageName $env:ChocolateyPackageName `
    -Url64bit "https://github.com/Dvisious-AB/adb-tray/releases/download/v$version/adb-tray-$version-windows-x64.zip" `
    -Checksum64 '0000000000000000000000000000000000000000000000000000000000000000' -ChecksumType64 'sha256' `
    -UnzipLocation (Split-Path -Parent $MyInvocation.MyCommand.Definition)
