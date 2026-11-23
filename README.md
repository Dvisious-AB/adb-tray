# Appninjas ADB

[![CI](https://github.com/Dvisious-AB/adb-tray/actions/workflows/ci.yml/badge.svg)](https://github.com/Dvisious-AB/adb-tray/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Your Android devices in the menu bar or system tray.** Open the menu to see the connected devices, mirror a
screen, rotate it, take a screenshot or connect over Wi-Fi without opening a terminal.

Appninjas ADB runs on **macOS** (a menu bar app) and on **Linux Mint / Cinnamon** (a tray icon), on top of
[`adb`](https://developer.android.com/tools/adb) and [`scrcpy`](https://github.com/Genymobile/scrcpy). The
command and the package are called `adb-tray`. Product page:
[appninjas.se/appar/adb](https://appninjas.se/appar/adb). The manual, which **Help** in the menu opens:
[appninjas.se/adb/help/sv](https://appninjas.se/adb/help/sv), in English
[appninjas.se/adb/help/en](https://appninjas.se/adb/help/en).

```text
[icon] ─┬─ SM-X210  (USB)        ─┬─ Mirror screen
        ├─ ▶ SM-X210  (Wi-Fi)     ├─ Lock portrait / Lock landscape / Rotate automatically
        ├─ Connect via Wi-Fi  ►   ├─ Take screenshot
        ├─ Refresh                ├─ Open adb shell
        ├─ Restart adb server     └─ Switch to Wi-Fi / Disconnect
        ├─ Help
        ├─ About Appninjas ADB
        └─ Quit
```

> The menu follows your system language. English is the default; see [Languages](#languages).

## Contents

- [Features](#features)
- [Installation](#installation)
- [Getting started](#getting-started)
- [Languages](#languages)
- [Configuration and files](#configuration-and-files)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Contributing](#contributing)
- [License](#license)

## Features

| Area | What you can do |
| --- | --- |
| Devices | Lists USB and Wi-Fi devices with model names, refreshed every 4 seconds. Shows when a device is waiting for authorization or does not respond. |
| Mirroring | Start and stop `scrcpy` per device. Active mirrors are marked with ▶. Several devices can be mirrored at once. |
| Rotation | Lock portrait, lock landscape or rotate automatically, also while mirroring. |
| Tools | Screenshot to your Pictures folder, `adb shell` in a terminal, restart the adb server. |
| Wi-Fi | *Switch to Wi-Fi* from a USB-connected device, reconnect to previous addresses or a new one, or pair using Android's **Wireless debugging**. |

## Installation

### macOS (Homebrew)

Needs macOS 13 Ventura or later and Xcode, because Homebrew builds the app on your Mac.

```bash
brew install --cask android-platform-tools   # adb
brew install dvisious-ab/tap/adb-tray         # the app, and scrcpy
brew services start adb-tray                  # start now and at every login
```

`adb` is a cask, which a formula cannot depend on, so it is installed separately. The app is
`$(brew --prefix)/opt/adb-tray/Appninjas ADB.app`, and `adb-tray` in the terminal starts it too.

Update with `brew upgrade adb-tray`, then `brew services restart adb-tray`.

### Linux Mint, Ubuntu and Debian (apt)

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dvisious-ab.github.io/adb-tray/appninjas-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/appninjas-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/appninjas-archive-keyring.gpg] https://dvisious-ab.github.io/adb-tray stable main" \
  | sudo tee /etc/apt/sources.list.d/appninjas.list
sudo apt update
sudo apt install adb-tray
```

The package pulls in `adb`, `scrcpy`, PyGObject, GTK and XApp, adds **Appninjas ADB** to the application
menu and starts it at login. Start it the first time from the menu, or with `adb-tray &`. Updates arrive
with the rest of the system.

The icon uses `XApp.StatusIcon`, which Cinnamon shows through the *Xapp Status Applet*. Other desktops with
StatusNotifier support through `xapp-sn-watcher` should work but are untested.

### From source

```bash
git clone https://github.com/Dvisious-AB/adb-tray.git
cd adb-tray
./install.sh --deps        # Linux: installs for your user only; --deps apt-installs the dependencies
macos/build-app.sh         # macOS: builds macos/build/Appninjas ADB.app
```

## Getting started

### Over USB

1. On the device: **Settings → About device → Software information**, tap *Build number* seven times to
   unlock developer options.
2. **Developer options → USB debugging**: turn it on.
3. Plug in the cable and tap **Allow** in the dialog on the device (ticking *Always allow* is recommended).
4. The device appears in the menu. Choose **Mirror screen**.

### Over Wi-Fi, no cable at all

1. **Developer options → Wireless debugging**: turn it on and choose *Pair device with pairing code*.
2. In the menu: **Connect via Wi-Fi → Pair (wireless debugging)...** and enter the pairing address, the code
   and, optionally, the connection address shown under *Wireless debugging*.

### Over Wi-Fi after USB

Choose **Switch to Wi-Fi** on a USB-connected device. The address is saved and can be
picked under *Connect via Wi-Fi* next time. This mode lasts until the device reboots.

## Languages

The menu, dialogs and notifications use your system language: on Linux through `LANGUAGE`, `LC_ALL`,
`LC_MESSAGES` and `LANG`, on macOS through the preferred languages in System Settings. If no translation
exists for your language, English is used. **Help** opens the help page in the same language when there is
one, otherwise the English page.

| Language | Status |
| --- | --- |
| English | built in |
| Swedish (`sv`) | complete |

To try another language on Linux without changing your desktop settings:

```bash
pkill -f 'adb-tray$'; LANGUAGE=sv adb-tray &
```

New translations are very welcome; see [Translations](CONTRIBUTING.md#translations).

## Configuration and files

| Linux | macOS | Contents |
| --- | --- | --- |
| `~/.config/adb-tray/hosts.json` | `~/Library/Application Support/adb-tray/hosts.json` | Recently used Wi-Fi addresses (max 10) |
| `~/.config/adb-tray/scrcpy-*.log` | `~/Library/Application Support/adb-tray/scrcpy-*.log` | Output of the latest mirroring session per device |
| `/etc/xdg/autostart/adb-tray.desktop` | `brew services` | Start at login |

The default `scrcpy` flags (`-m 1600 --stay-awake`, plus `-b 6M` over Wi-Fi) are in `SCRCPY_OPTS`
at the top of `adb-tray.py` and in `scrcpyOptions` in `macos/Sources/AdbTray/TrayController.swift`.

To keep a Linux installation from starting at login, open *Startup Applications* and turn off Appninjas ADB.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| No icon on Linux | Make sure the *Xapp Status Applet* is in your panel. Run `adb-tray` in a terminal and read the output. |
| No icon on macOS | Run `brew services list`. If adb-tray is not *started*, run `brew services restart adb-tray`. A full menu bar can hide icons behind the camera housing. |
| The menu says *adb is not installed* | macOS: `brew install --cask android-platform-tools`. Linux: `sudo apt install adb`. |
| Device is shown as *authorize on device* | Tap **Allow** in the dialog on the device. If no dialog appears, choose *Revoke USB debugging authorizations* in developer options and reconnect. |
| Mirroring closes immediately | Read the `scrcpy-*.log` file above. Some devices cannot encode full resolution; lower `-m` in the scrcpy flags. |
| Wi-Fi connection fails | The device has probably rebooted. Connect over USB and choose *Switch to Wi-Fi* again, or use pairing. |
| Everything seems stuck | Choose **Restart adb server** in the menu. |
| The menu is in English although my system is not | Your language has no translation yet. |
| `Failed to load module "xapp-gtk3-module"` | Harmless message, can be ignored. |

## Uninstall

```bash
sudo apt remove adb-tray                                     # Linux, apt
brew services stop adb-tray && brew uninstall adb-tray       # macOS
./uninstall.sh                                               # Linux, installed from source
```

Your settings and saved addresses are kept.

## Contributing

Contributions are welcome through pull requests. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.
Report security issues as described in [SECURITY.md](SECURITY.md).

## License

The code is [MIT](LICENSE) © Anders Elmén and Dvisious AB. The Appninjas name and logo in the app icon are
trademarks of Dvisious AB and are not covered by the MIT License. The menu icons are
[Phosphor Icons](https://phosphoricons.com) (MIT). See [NOTICE](NOTICE).
