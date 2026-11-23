# Contributing to Appninjas ADB (adb-tray)

Thanks for wanting to contribute! This document describes how changes are accepted.

## Workflow

`main` is protected. All changes go through a **pull request** and are merged by the maintainer
([@aelmen](https://github.com/aelmen)). Pushing directly to `main` is not possible.

1. **Fork** the repository.
2. Create a branch from `main` with a descriptive name, e.g. `feat/wifi-qr-pairing` or
   `fix/offline-device-label`.
3. Make small, focused commits (see [Commit messages](#commit-messages)).
4. Run the checks locally (see [Checks](#checks)).
5. Open a pull request against `main` and fill in the template.
6. CI must be green and the maintainer must approve before the change is merged.
   Pull requests are merged with **squash merge**.

For larger changes or new features, please open an issue first so we can agree on the approach
before you spend time on it.

## Layout

| Path | What it is |
| --- | --- |
| `adb-tray.py` | The Linux tray icon (Python, GTK 3, XApp) |
| `rust/` | The Rust version, today the Windows app: `src/lib.rs` holds what can be tested, `src/main.rs` the tray icon and menu. Meant to replace `adb-tray.py` and `macos/` |
| `macos/` | The macOS menu bar app, a Swift package. `AdbTrayCore` holds what can be tested without a menu bar; `AdbTray` is the app |
| `po/` | Translations, shared by both apps |
| `branding/` | Logo, icons and colours from the Appninjas brand; see [branding/README.md](branding/README.md) |
| `packaging/debian/` | Builds the `.deb` |
| `packaging/apt/` | Maintains the apt repository on `gh-pages`; see [packaging/apt/README.md](packaging/apt/README.md) |
| `packaging/homebrew/` | The Homebrew formula, published in [Dvisious-AB/homebrew-tap](https://github.com/Dvisious-AB/homebrew-tap) |
| `help/` | The manual on appninjas.se/adb/help/<language>; see [help/README.md](help/README.md) |
| `VERSION` | The release version, used by every build |

Both apps have the same menu and the same behaviour. A change to one should be made in the other too.

## Development setup

On Linux:

```bash
sudo apt install adb scrcpy python3-gi gir1.2-gtk-3.0 gir1.2-xapp-1.0 libnotify-bin gettext shellcheck
pipx install ruff        # or: python3 -m venv .venv && .venv/bin/pip install ruff

git clone https://github.com/<your-account>/adb-tray.git
cd adb-tray
```

On macOS, with Xcode 15 or later:

```bash
brew install scrcpy gettext shellcheck ruff
brew install --cask android-platform-tools
swift test --package-path macos
macos/build-app.sh && open "macos/build/Appninjas ADB.app"
```

Run the Linux program straight from source, without installing:

```bash
pkill -f 'adb-tray(\.py)?$'   # stop an installed instance, if any
./adb-tray.py
```

Only one instance can run at a time (lock file `~/.config/adb-tray/tray.lock`, on macOS
`~/Library/Application Support/adb-tray/tray.lock`). Translations are loaded from `~/.local/share/locale`,
so run `./install.sh` once to see them when running from source. The macOS app reads the `.po` files
directly, from the app bundle or from `$ADB_TRAY_LOCALE_DIR`.

## Checks

The same checks run in CI on every pull request:

```bash
ruff check adb-tray.py branding/brand.py
python3 -m py_compile adb-tray.py branding/brand.py
shellcheck install.sh uninstall.sh po/update.sh macos/build-app.sh packaging/debian/build-deb.sh packaging/apt/update-repo.sh
branding/brand.py generate --check
po/update.sh --check
help/strings.py --check
packaging/debian/build-deb.sh            # Linux: builds dist/adb-tray_<version>_all.deb
cargo test --lib --manifest-path rust/Cargo.toml   # every platform
swift test --package-path macos          # macOS
macos/build-app.sh                       # macOS
```

Also test manually in Cinnamon with at least one real device:

- [ ] The icon appears and the menu opens on left and right click
- [ ] A USB device is listed, mirroring starts and stops
- [ ] Wi-Fi: *Switch to Wi-Fi* and reconnecting via a saved address
- [ ] `./install.sh` and `./uninstall.sh` work
- [ ] On macOS: the icon appears in the menu bar, the menu and About open, and `brew install --HEAD`
      from a local tap builds and starts the app

## Code style

- Python 3, standard library + PyGObject. Swift with AppKit and the standard library only. Do not add new
  dependencies without discussing it first.
- GTK calls happen on the main thread only. Blocking work (`adb`, network) runs on a background thread via
  `run_bg`, and results are handed back with `GLib.idle_add`.
- Call external programs with argument lists (`subprocess.run([...])`), never through a shell with
  concatenated strings.
- User-visible strings are written in English and wrapped for translation: `_("Mirror screen")` in
  Python and `tr("Mirror screen")` in Swift, with named placeholders
  (`_("Connected to {host}").format(host=host)`, `format(tr("Connected to {host}"), ["host": host])`)
  and `ngettext`/`trn` for plurals. Keep
  source strings ASCII-only. After changing strings, run `po/update.sh`, update the translations you can,
  and run `help/strings.py` so the manual's button names follow.
- Messages follow the Appninjas tone: calm and exact, no exclamation marks. An error says what happened,
  why, and what to do now, in that order.
- The product name *Appninjas ADB* is never translated. Icons come from `branding/` only.
- Code, comments, commit messages and documentation are in English.
- Comment *why*, not *what*. Lint rules are defined in `ruff.toml`.

## Translations

Translations use GNU gettext and live in `po/`:

| File | Purpose |
| --- | --- |
| `po/adb-tray.pot` | Template with every translatable string (generated) |
| `po/<lang>.po` | One file per language, e.g. `po/sv.po` |
| `po/LINGUAS` | List of languages, one code per line |
| `po/update.sh` | Regenerates the template and merges it into every `.po` file |

To add a language, for example German:

```bash
msginit --no-translator -l de_DE.UTF-8 -i po/adb-tray.pot -o po/de.po
echo de >> po/LINGUAS
# translate po/de.po with a text editor or a tool like Poedit
./install.sh
LANGUAGE=de adb-tray
```

The language code must match what gettext looks up (`de`, `pt_BR`, `nb`, ...). Keep placeholders such as
`{host}` unchanged, and remove any `#, fuzzy` marker once an entry is correct. CI fails if a translation
has untranslated or fuzzy entries, or if `po/adb-tray.pot` is out of date.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add QR code pairing
fix: show offline wifi devices with disconnect option
docs: clarify wireless debugging steps
chore: bump CI actions
```

## Releases

A maintainer sets `VERSION`, merges it, and pushes a matching `v*` tag. The release workflow builds the
Debian package, updates the apt repository and publishes the GitHub release. The Homebrew formula in the tap
is then updated with the new `url` and `sha256`. Details: [packaging/apt/README.md](packaging/apt/README.md).

## Reporting bugs and requesting features

Use the issue templates under **Issues → New issue**. Include:

- distribution and Cinnamon version, or the macOS version
- `adb version` and `scrcpy --version`
- device model and Android version
- the version from **About Appninjas ADB** or `adb-tray --version`
- relevant lines from the `scrcpy-*.log` file (see the README) or the output of `adb-tray`

Do **not** report security issues as public issues – see [SECURITY.md](SECURITY.md).

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By participating you are expected to uphold it.

## License

By submitting a contribution you agree that it is licensed under the project's [MIT License](LICENSE).
