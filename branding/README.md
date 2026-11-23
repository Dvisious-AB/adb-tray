# Branding

Appninjas ADB follows the Appninjas brand. The brand is defined in the appninjas.se repository
(`varumarke/` and `docs/varumarke/`), and the files here are copies of it, not new drawings.

| File | What it is | Licence |
| --- | --- | --- |
| `symbol.svg` | The Appninjas symbol, byte for byte as approved in `varumarke/godkanda.sha256` | Proprietary, see [NOTICE](../NOTICE) |
| `colours.json` | The token values the icon uses, and where in `varumarke/tokens.json` they come from | Proprietary |
| `appninjas-adb.svg` | The app icon: the unchanged symbol paths on a tile, generated | Proprietary |
| `phosphor/*.svg` | Phosphor icons in the weight fill, unchanged | MIT, `phosphor/LICENSE` |

## Updating

```bash
branding/brand.py import ~/source/appninjas/appninjas.se   # copy the master files and colours again
branding/brand.py generate --check                          # CI: is appninjas-adb.svg up to date?
```

`import` refuses a `symbol.svg` whose checksum is not in `godkanda.sha256`. To add an icon, add its
Phosphor name to `PHOSPHOR_ICONS` in `brand.py` and run `import` again.

## Where the files are used

| Use | macOS | Linux |
| --- | --- | --- |
| App icon | `AppIcon.icns`, rendered from `appninjas-adb.svg` by `build-app.sh` | `hicolor/scalable/apps/appninjas-adb.svg` |
| Menu bar or tray | `device-mobile-fill`, `screencast-fill` while mirroring (template images) | `appninjas-adb-symbolic`, `appninjas-adb-mirroring-symbolic` |
| Menu items | One Phosphor icon per action | None; GTK menus in Cinnamon show no icons |

The tile colour is `farg.ljus.bakgrund`, the main form is `farg.ljus.text` (what `currentColor` is on
the site in light mode) and the band is `logotyp.bandLjus`, as for `apple-touch-icon.png` on the site.
