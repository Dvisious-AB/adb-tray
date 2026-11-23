import Foundation

/// A gettext catalogue read straight from a `.po` file, so macOS uses the same translations as Linux.
///
/// Only what `po/*.po` in this repository uses is supported: `msgid`, `msgid_plural`, `msgstr`,
/// `msgstr[n]`, continuation lines, the common escapes and `#, fuzzy`.
public struct Catalog {
    struct Entry {
        var singular: [String] = []
        var plural: [String] = []
    }

    private var singular: [String: String] = [:]
    private var plural: [String: [String]] = [:]
    private var pluralRule: (Int) -> Int = { $0 == 1 ? 0 : 1 }

    public init() {}

    public init(poText: String) {
        var fuzzy = false
        var msgid: String?
        var msgidPlural: String?
        var msgstr: [Int: String] = [:]
        var current: (field: String, index: Int)?

        func flush() {
            defer {
                msgid = nil
                msgidPlural = nil
                msgstr = [:]
                current = nil
                fuzzy = false
            }
            guard let id = msgid else { return }
            if id.isEmpty {
                // The header entry carries Plural-Forms.
                if let header = msgstr[0] { pluralRule = Catalog.pluralRule(fromHeader: header) }
                return
            }
            if fuzzy { return }
            if msgidPlural != nil {
                let forms = (0..<max(msgstr.count, 1)).map { msgstr[$0] ?? "" }
                if !forms.contains(where: \.isEmpty) { plural[id] = forms }
            } else if let text = msgstr[0], !text.isEmpty {
                singular[id] = text
            }
        }

        func append(_ text: String, to target: (field: String, index: Int)) {
            switch target.field {
            case "msgid": msgid = (msgid ?? "") + text
            case "msgid_plural": msgidPlural = (msgidPlural ?? "") + text
            default: msgstr[target.index] = (msgstr[target.index] ?? "") + text
            }
        }

        for rawLine in poText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("#") {
                if msgid != nil { flush() }
                if line.hasPrefix("#,") && line.contains("fuzzy") { fuzzy = true }
                continue
            }
            if line.hasPrefix("\"") {
                guard let target = current else { continue }
                append(Catalog.unquote(line), to: target)
                continue
            }
            guard let space = line.firstIndex(of: " ") else { continue }
            let keyword = String(line[..<space])
            let value = Catalog.unquote(String(line[line.index(after: space)...]))
            switch keyword {
            case "msgid":
                if msgid != nil { flush() }
                msgid = value
                current = ("msgid", 0)
            case "msgid_plural":
                msgidPlural = value
                current = ("msgid_plural", 0)
            case "msgstr":
                msgstr[0] = value
                current = ("msgstr", 0)
            default:
                if keyword.hasPrefix("msgstr["), let index = Int(keyword.dropFirst(7).dropLast()) {
                    msgstr[index] = value
                    current = ("msgstr", index)
                }
            }
        }
        flush()
    }

    public func gettext(_ msgid: String) -> String {
        singular[msgid] ?? msgid
    }

    public func ngettext(_ msgid: String, _ msgidPlural: String, _ n: Int) -> String {
        guard let forms = plural[msgid] else { return n == 1 ? msgid : msgidPlural }
        let index = pluralRule(n)
        return forms.indices.contains(index) ? forms[index] : forms[forms.count - 1]
    }

    /// The languages in the user's order of preference, most specific first: `pt-BR` gives `pt_BR`, `pt`.
    public static func candidateLanguages(_ preferred: [String]) -> [String] {
        var result: [String] = []
        for language in preferred {
            let parts = language.replacingOccurrences(of: "-", with: "_").split(separator: "_").map(String.init)
            guard let base = parts.first, !base.isEmpty else { continue }
            if base == "en" { break }  // English is the source language: nothing to load.
            // Script subtags (zh_Hans) are not region codes, so keep only a two-letter region.
            if let region = parts.dropFirst().last(where: { $0.count == 2 }) {
                result.append("\(base)_\(region.uppercased())")
            }
            result.append(base)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    static func unquote(_ quoted: String) -> String {
        var text = quoted.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        text = String(text.dropFirst().dropLast())
        var result = ""
        var escaping = false
        for char in text {
            if escaping {
                switch char {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(char)
                }
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Supports the plural expressions of the languages gettext's documentation lists as two-form
    /// (`n != 1`, `n > 1`) and one-form (`0`); anything else falls back to `n != 1`.
    static func pluralRule(fromHeader header: String) -> (Int) -> Int {
        guard let range = header.range(of: #"plural=[^;\n]+"#, options: .regularExpression) else {
            return { $0 == 1 ? 0 : 1 }
        }
        let expression = header[range].dropFirst("plural=".count).filter { !$0.isWhitespace }
        switch expression {
        case "0": return { _ in 0 }
        case "(n>1)", "n>1": return { $0 > 1 ? 1 : 0 }
        default: return { $0 == 1 ? 0 : 1 }
        }
    }
}

/// `"Connected to {host}"` with `["host": "x"]` becomes `"Connected to x"`, like Python's `str.format`.
public func format(_ template: String, _ values: [String: CustomStringConvertible]) -> String {
    values.reduce(template) { text, pair in
        text.replacingOccurrences(of: "{\(pair.key)}", with: pair.value.description)
    }
}
