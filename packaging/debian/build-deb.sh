#!/usr/bin/env bash
# Build the Debian package adb-tray_<version>_all.deb.
#
#   packaging/debian/build-deb.sh [--version X.Y.Z] [--output DIR]
#
# The version defaults to the VERSION file. Needs dpkg-deb and msgfmt (gettext).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUTPUT="$ROOT/dist"
MAINTAINER="${DEB_MAINTAINER:-Anders Elmén <anders@need2code.se>}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/adb-tray"

install -d "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/etc/xdg/autostart" \
    "$PKG/usr/share/icons/hicolor/scalable/apps" "$PKG/usr/share/icons/hicolor/symbolic/apps" \
    "$PKG/usr/share/doc/adb-tray"

sed "s|@VERSION@|$VERSION|" "$ROOT/adb-tray.py" > "$PKG/usr/bin/adb-tray"
chmod 755 "$PKG/usr/bin/adb-tray"

while read -r lang; do
    [[ -z "$lang" ]] && continue
    install -d "$PKG/usr/share/locale/$lang/LC_MESSAGES"
    msgfmt --check -o "$PKG/usr/share/locale/$lang/LC_MESSAGES/adb-tray.mo" "$ROOT/po/$lang.po"
done < "$ROOT/po/LINGUAS"

sed "s|@EXEC@|/usr/bin/adb-tray|" "$ROOT/adb-tray.desktop.in" \
    | msgfmt --desktop --template=/dev/stdin -d "$ROOT/po" -o "$PKG/usr/share/applications/adb-tray.desktop"
install -m 644 "$PKG/usr/share/applications/adb-tray.desktop" "$PKG/etc/xdg/autostart/adb-tray.desktop"

install -m 644 "$ROOT/branding/appninjas-adb.svg" "$PKG/usr/share/icons/hicolor/scalable/apps/appninjas-adb.svg"
install -m 644 "$ROOT/branding/phosphor/device-mobile-fill.svg" \
    "$PKG/usr/share/icons/hicolor/symbolic/apps/appninjas-adb-symbolic.svg"
install -m 644 "$ROOT/branding/phosphor/screencast-fill.svg" \
    "$PKG/usr/share/icons/hicolor/symbolic/apps/appninjas-adb-mirroring-symbolic.svg"

cat > "$PKG/usr/share/doc/adb-tray/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: adb-tray (Appninjas ADB)
Source: https://github.com/Dvisious-AB/adb-tray

Files: *
Copyright: 2026 Anders Elmén and Dvisious AB
License: MIT
$(sed -e '/not covered by this licence/d' -e 's/^$/./' -e 's/^/ /' "$ROOT/LICENSE")

Files: usr/share/icons/hicolor/scalable/apps/appninjas-adb.svg
Copyright: 2026 Dvisious AB
License: proprietary
 The Appninjas name and logo are trademarks of Dvisious AB. All rights reserved.
 They may be distributed unchanged as part of this package and not used for anything else.

Files: usr/share/icons/hicolor/symbolic/apps/*
Copyright: 2023 Phosphor Icons
License: MIT
COPYRIGHT

INSTALLED_SIZE="$(du -sk "$PKG" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: adb-tray
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER
Installed-Size: $INSTALLED_SIZE
Depends: python3, python3-gi, gir1.2-gtk-3.0, gir1.2-xapp-1.0, libnotify-bin, adb, scrcpy
Section: utils
Priority: optional
Homepage: https://appninjas.se/appar/adb
Description: Appninjas ADB: Android devices in the system tray
 A tray icon that lists the devices adb sees. From its menu you mirror a
 screen with scrcpy, rotate it, take a screenshot, open adb shell and
 connect over Wi-Fi, without opening a terminal. Built for Cinnamon (XApp).
CONTROL

mkdir -p "$OUTPUT"
DEB="$OUTPUT/adb-tray_${VERSION}_all.deb"
dpkg-deb --root-owner-group -Zxz --build "$PKG" "$DEB" >/dev/null
echo "$DEB"
