# Removes the Start at login entry that the menu's "Start at login" writes for the current user.
# Chocolatey removes the unpacked files itself.
$ErrorActionPreference = 'Stop'
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
    -Name 'Appninjas ADB' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' `
    -Name 'Appninjas ADB' -ErrorAction SilentlyContinue
