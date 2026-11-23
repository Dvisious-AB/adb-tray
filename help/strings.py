#!/usr/bin/env python3
"""Write the manual's string catalogues, help/strings/<locale>.json, from the app's gettext catalogue.

    help/strings.py [--check]

The manual names menu items with :button[menu.mirror] (docs/hjalp/content-and-writing.md in
appninjas.se). The labels must be the app's own, so they are taken from po/*.po here rather than
typed again. KEYS maps a stable key to the English source string (msgid).
"""
import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "help" / "strings"
# Manual locale -> po file; None means the English source strings.
LOCALES = {"sv": "sv", "en-GB": None}

KEYS = {
    "menu": {
        "noDevices": "No devices connected",
        "connectWifi": "Connect via Wi-Fi",
        "newAddress": "New address...",
        "pair": "Pair (wireless debugging)...",
        "refresh": "Refresh",
        "restartServer": "Restart adb server",
        "help": "Help",
        "about": "About {name}",
        "quit": "Quit",
        "copyInstall": "Copy the install command",
    },
    "device": {
        "mirror": "Mirror screen",
        "stopMirroring": "Stop mirroring",
        "lockPortrait": "Lock portrait",
        "lockLandscape": "Lock landscape",
        "autoRotate": "Auto-rotate",
        "screenshot": "Take screenshot",
        "shell": "Open adb shell",
        "switchToWifi": "Switch to Wi-Fi",
        "disconnect": "Disconnect",
        "unauthorized": "authorize on device",
        "offline": "offline",
    },
    "dialog": {
        "address": "Address (IP:port)",
        "pairingAddress": "Pairing address (IP:port)",
        "pairingCode": "Pairing code",
        "connectionAddress": "Connection address (optional)",
        "ok": "OK",
    },
}


def read_po(path):
    """msgid -> msgstr for the singular entries of a .po file."""
    entries, msgid, msgstr, field = {}, None, None, None
    for line in [*path.read_text(encoding="utf-8").splitlines(), ""]:
        match = re.match(r'(msgid|msgstr) (".*")$', line)
        if match:
            field = match.group(1)
            if field == "msgid":
                if msgid and msgstr:
                    entries[msgid] = msgstr
                msgid, msgstr = ast.literal_eval(match.group(2)), None
            else:
                msgstr = ast.literal_eval(match.group(2))
        elif line.startswith('"') and field:
            if field == "msgid":
                msgid += ast.literal_eval(line)
            else:
                msgstr = (msgstr or "") + ast.literal_eval(line)
        elif not line.strip() or line.startswith(("msgid_plural", "msgstr[")):
            field = None if not line.strip() else field
    if msgid and msgstr:
        entries[msgid] = msgstr
    return entries


def catalogue(po):
    translations = read_po(ROOT / "po" / f"{po}.po") if po else {}
    missing = [msgid for group in KEYS.values() for msgid in group.values() if po and msgid not in translations]
    if missing:
        sys.exit(f"po/{po}.po lacks {missing}")
    return {group: {key: translations.get(msgid, msgid) for key, msgid in strings.items()}
            for group, strings in KEYS.items()}


def main(check):
    stale = []
    OUT.mkdir(exist_ok=True)
    for locale, po in LOCALES.items():
        path = OUT / f"{locale}.json"
        text = json.dumps(catalogue(po), ensure_ascii=False, indent="\t") + "\n"
        if check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(path.name)
        else:
            path.write_text(text, encoding="utf-8")
    if stale:
        sys.exit(f"help/strings is out of date ({', '.join(stale)}): run help/strings.py")
    print("help/strings is up to date" if check else f"Wrote {len(LOCALES)} catalogues to {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:] == ["--check"])
