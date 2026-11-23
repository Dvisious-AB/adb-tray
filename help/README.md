# The manual

The source of the Appninjas ADB manual, published at <https://appninjas.se/hjalp/adb> (Swedish) and
<https://appninjas.se/en/hjalp/adb> (British English). **Help** in the app's menu opens it.

The format is the Appninjas help module's (`docs/hjalp/content-and-writing.md` in appninjas.se):

| Path | What it is |
| --- | --- |
| `manual.json` | Chapters, the five *Kom igång* articles, searches, the string catalogues |
| `content/<locale>/<id>.md` | One article per locale. Swedish is the source; `en-GB` is complete too |
| `content/<locale>/_glossary.md` | The terms that `:term[...]` explains |
| `strings/<locale>.json` | Menu labels for `:button[...]`, generated from `po/*.po` by `strings.py` |
| `screens.json` | Screenshot definitions; none yet |

Article ids are URLs. They freeze at the first public release and are never renamed.

## Checking and building

`strings.py` must be run after a menu label changes; CI runs `help/strings.py --check`.

The build tool `appninjas-help` lives in the appninjas.se repository (`packages/help`), which is private:

```bash
H=~/source/appninjas/appninjas.se/packages/help    # npm install and npm run build there once
node $H/bin/appninjas-help.mjs check --root help --strict
node $H/bin/appninjas-help.mjs build --root help --out <appninjas.se>/hjalp-bundles/adb --strict
```

The site renders every bundle in `hjalp-bundles/` (see `docs/hjalp/manual-site.md` there).

## Writing

Follow the help module's writing rules and the Appninjas tone: *du*, the verb first (*klicka*, since this is
a desktop app), one action per step, no exclamation marks, and a last section on what to do when it does not
work. Name a menu item only through `:button[...]`, never by typing its label.
