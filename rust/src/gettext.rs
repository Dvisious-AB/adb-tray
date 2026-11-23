//! A gettext catalogue read straight from a `.po` file, so every platform uses the same translations.
//!
//! Only what `po/*.po` in this repository uses is supported: `msgid`, `msgid_plural`, `msgstr`,
//! `msgstr[n]`, continuation lines, the common escapes and `#, fuzzy`. The `.po` files are compiled into
//! the program (see build.rs), so a single executable carries every language.

use std::collections::HashMap;

include!(concat!(env!("OUT_DIR"), "/catalogs.rs"));

#[derive(Default)]
pub struct Catalog {
    singular: HashMap<String, String>,
    plural: HashMap<String, Vec<String>>,
    /// gettext's two common two-form rules: `n != 1` (false) and `n > 1` (true); `0` means one form.
    rule: PluralRule,
}

#[derive(Default, Clone, Copy)]
enum PluralRule {
    #[default]
    NotOne,
    GreaterThanOne,
    Single,
}

#[derive(Default)]
struct Pending {
    msgid: Option<String>,
    msgid_plural: Option<String>,
    msgstr: HashMap<usize, String>,
    fuzzy: bool,
}

#[derive(Clone, Copy)]
enum Field {
    Id,
    IdPlural,
    Str(usize),
}

impl Catalog {
    pub fn from_po(text: &str) -> Self {
        let mut catalog = Catalog::default();
        let mut pending = Pending::default();
        let mut current: Option<Field> = None;

        for raw in text.lines() {
            let line = raw.trim();
            if line.is_empty() {
                catalog.flush(&mut pending);
                current = None;
                continue;
            }
            if line.starts_with('#') {
                if pending.msgid.is_some() {
                    catalog.flush(&mut pending);
                    current = None;
                }
                if line.starts_with("#,") && line.contains("fuzzy") {
                    pending.fuzzy = true;
                }
                continue;
            }
            if line.starts_with('"') {
                if let Some(field) = current {
                    pending.append(field, &unquote(line));
                }
                continue;
            }
            let Some((keyword, value)) = line.split_once(' ') else {
                continue;
            };
            let value = unquote(value);
            let field = match keyword {
                "msgid" => {
                    if pending.msgid.is_some() {
                        catalog.flush(&mut pending);
                    }
                    Field::Id
                }
                "msgid_plural" => Field::IdPlural,
                "msgstr" => Field::Str(0),
                _ => match keyword
                    .strip_prefix("msgstr[")
                    .and_then(|k| k.strip_suffix(']'))
                {
                    Some(index) => match index.parse() {
                        Ok(index) => Field::Str(index),
                        Err(_) => continue,
                    },
                    None => continue,
                },
            };
            pending.set(field, value);
            current = Some(field);
        }
        catalog.flush(&mut pending);
        catalog
    }

    fn flush(&mut self, pending: &mut Pending) {
        let entry = std::mem::take(pending);
        let Some(id) = entry.msgid else { return };
        if id.is_empty() {
            // The header entry carries Plural-Forms.
            if let Some(header) = entry.msgstr.get(&0) {
                self.rule = plural_rule(header);
            }
            return;
        }
        if entry.fuzzy {
            return;
        }
        if entry.msgid_plural.is_some() {
            let forms: Vec<String> = (0..entry.msgstr.len().max(1))
                .map(|i| entry.msgstr.get(&i).cloned().unwrap_or_default())
                .collect();
            if forms.iter().all(|f| !f.is_empty()) {
                self.plural.insert(id, forms);
            }
        } else if let Some(text) = entry.msgstr.get(&0).filter(|t| !t.is_empty()) {
            self.singular.insert(id, text.clone());
        }
    }

    pub fn gettext<'a>(&'a self, msgid: &'a str) -> &'a str {
        self.singular
            .get(msgid)
            .map(String::as_str)
            .unwrap_or(msgid)
    }

    pub fn ngettext<'a>(&'a self, msgid: &'a str, msgid_plural: &'a str, n: u64) -> &'a str {
        let Some(forms) = self.plural.get(msgid) else {
            return if n == 1 { msgid } else { msgid_plural };
        };
        let index = match self.rule {
            PluralRule::NotOne => usize::from(n != 1),
            PluralRule::GreaterThanOne => usize::from(n > 1),
            PluralRule::Single => 0,
        };
        forms
            .get(index)
            .or(forms.last())
            .map(String::as_str)
            .unwrap_or(msgid)
    }

    /// The catalogue compiled into the program for the first of `preferred` that has one.
    /// Returns the language code too, or None (English, the source language).
    pub fn for_languages(preferred: &[String]) -> (Catalog, Option<String>) {
        for language in candidate_languages(preferred) {
            if let Some((_, text)) = CATALOGS.iter().find(|(code, _)| *code == language) {
                return (Catalog::from_po(text), Some(language));
            }
        }
        (Catalog::default(), None)
    }
}

impl Pending {
    fn set(&mut self, field: Field, value: String) {
        match field {
            Field::Id => self.msgid = Some(value),
            Field::IdPlural => self.msgid_plural = Some(value),
            Field::Str(i) => {
                self.msgstr.insert(i, value);
            }
        }
    }

    fn append(&mut self, field: Field, text: &str) {
        match field {
            Field::Id => self.msgid.get_or_insert_with(String::new).push_str(text),
            Field::IdPlural => self
                .msgid_plural
                .get_or_insert_with(String::new)
                .push_str(text),
            Field::Str(i) => self.msgstr.entry(i).or_default().push_str(text),
        }
    }
}

/// The languages in the user's order of preference, most specific first: `pt-BR` gives `pt_BR`, `pt`.
/// English is the source language, so the search stops there.
pub fn candidate_languages(preferred: &[String]) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    for language in preferred {
        // POSIX locales: "sv_SE.UTF-8@euro" -> "sv_SE"; LANGUAGE may hold "sv:en".
        for item in language.split(':') {
            let item = item.split(['.', '@']).next().unwrap_or("");
            let parts: Vec<&str> = item.split(['-', '_']).filter(|p| !p.is_empty()).collect();
            let Some(base) = parts.first().map(|b| b.to_ascii_lowercase()) else {
                continue;
            };
            if base == "en" || base == "c" || base == "posix" {
                return dedup(result);
            }
            // Script subtags (zh-Hans) are not region codes, so keep only a two-letter region.
            if let Some(region) = parts[1..].iter().rev().find(|p| p.len() == 2) {
                result.push(format!("{base}_{}", region.to_ascii_uppercase()));
            }
            result.push(base);
        }
    }
    dedup(result)
}

fn dedup(items: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    items
        .into_iter()
        .filter(|i| seen.insert(i.clone()))
        .collect()
}

fn unquote(quoted: &str) -> String {
    let text = quoted.trim();
    let Some(inner) = text.strip_prefix('"').and_then(|t| t.strip_suffix('"')) else {
        return text.to_string();
    };
    let mut result = String::with_capacity(inner.len());
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            result.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => result.push('\n'),
            Some('t') => result.push('\t'),
            Some(other) => result.push(other),
            None => {}
        }
    }
    result
}

fn plural_rule(header: &str) -> PluralRule {
    let Some(start) = header.find("plural=") else {
        return PluralRule::NotOne;
    };
    let expression: String = header[start + 7..]
        .chars()
        .take_while(|c| *c != ';' && *c != '\n')
        .filter(|c| !c.is_whitespace())
        .collect();
    match expression.as_str() {
        "0" => PluralRule::Single,
        "(n>1)" | "n>1" => PluralRule::GreaterThanOne,
        _ => PluralRule::NotOne,
    }
}

/// `"Connected to {host}"` with `[("host", "x")]` becomes `"Connected to x"`, like Python's `str.format`.
pub fn format(template: &str, values: &[(&str, &dyn std::fmt::Display)]) -> String {
    values
        .iter()
        .fold(template.to_string(), |text, (name, value)| {
            text.replace(&format!("{{{name}}}"), &value.to_string())
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    const PO: &str = r#"msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\n"

msgid "Refresh"
msgstr "Uppdatera"

#, python-brace-format
msgid "{n} device connected"
msgid_plural "{n} devices connected"
msgstr[0] "{n} enhet ansluten"
msgstr[1] "{n} enheter anslutna"

msgid ""
"Could not connect. "
"Check the network."
msgstr ""
"Kunde inte ansluta. "
"Kontrollera nätverket."

#, fuzzy
msgid "Quit"
msgstr "Avsluta"

msgid "Help"
msgstr ""
"#;

    #[test]
    fn translates_singular_plural_and_continuation_lines() {
        let catalog = Catalog::from_po(PO);
        assert_eq!(catalog.gettext("Refresh"), "Uppdatera");
        assert_eq!(
            catalog.ngettext("{n} device connected", "{n} devices connected", 1),
            "{n} enhet ansluten"
        );
        assert_eq!(
            catalog.ngettext("{n} device connected", "{n} devices connected", 3),
            "{n} enheter anslutna"
        );
        assert_eq!(
            catalog.gettext("Could not connect. Check the network."),
            "Kunde inte ansluta. Kontrollera nätverket."
        );
    }

    #[test]
    fn fuzzy_untranslated_and_unknown_strings_fall_back_to_english() {
        let catalog = Catalog::from_po(PO);
        assert_eq!(catalog.gettext("Quit"), "Quit");
        assert_eq!(catalog.gettext("Help"), "Help");
        assert_eq!(catalog.gettext("Unknown"), "Unknown");
        assert_eq!(catalog.ngettext("{n} file", "{n} files", 2), "{n} files");
    }

    #[test]
    fn picks_candidate_languages() {
        let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        assert_eq!(
            candidate_languages(&s(&["sv-SE", "en-US"])),
            ["sv_SE", "sv"]
        );
        assert_eq!(
            candidate_languages(&s(&["en-GB", "sv-SE"])),
            Vec::<String>::new()
        );
        assert_eq!(candidate_languages(&s(&["pt-BR"])), ["pt_BR", "pt"]);
        assert_eq!(candidate_languages(&s(&["zh-Hans-CN"])), ["zh_CN", "zh"]);
        assert_eq!(candidate_languages(&s(&["sv_SE.UTF-8"])), ["sv_SE", "sv"]);
        assert_eq!(candidate_languages(&s(&["sv:en"])), ["sv"]);
    }

    #[test]
    fn every_compiled_catalogue_translates_the_menu() {
        assert!(!CATALOGS.is_empty());
        for (code, text) in CATALOGS {
            let catalog = Catalog::from_po(text);
            assert_ne!(catalog.gettext("Help"), "Help", "{code}");
            assert_ne!(catalog.gettext("Mirror screen"), "Mirror screen", "{code}");
        }
        let (_, language) = Catalog::for_languages(&["sv-SE".to_string()]);
        assert_eq!(language.as_deref(), Some("sv"));
    }

    #[test]
    fn formats_named_placeholders() {
        assert_eq!(
            format("Connected to {host}", &[("host", &"10.0.0.2:5555")]),
            "Connected to 10.0.0.2:5555"
        );
        assert_eq!(format("{n} of {n}", &[("n", &3)]), "3 of 3");
    }
}
