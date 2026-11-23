#!/usr/bin/env bash
set -euo pipefail

pkill -f "adb-tray(\.py)?$" 2>/dev/null || true
rm -f "$HOME/.local/bin/adb-tray" \
      "$HOME/.local/share/applications/adb-tray.desktop" \
      "$HOME/.config/autostart/adb-tray.desktop" \
      "$HOME"/.local/share/locale/*/LC_MESSAGES/adb-tray.mo \
      "$HOME/.local/share/icons/hicolor/scalable/apps/appninjas-adb.svg" \
      "$HOME"/.local/share/icons/hicolor/symbolic/apps/appninjas-adb*-symbolic.svg
echo "Appninjas ADB uninstalled. Settings are kept in ~/.config/adb-tray."
