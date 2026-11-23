import Foundation

/// The product's name and addresses. The name follows the Appninjas product architecture,
/// "Appninjas {Product}"; the command, the package and the bundle identifier stay `adb-tray`.
public enum Product {
    public static let name = "Appninjas ADB"
    public static let command = "adb-tray"
    public static let repository = URL(string: "https://github.com/Dvisious-AB/adb-tray")!
    /// The help pages: `helpBase/<language>`, with the two-letter language code (ISO 639-1).
    /// appninjas.se shows the manual in that language, or in English when there is none.
    public static let helpBase = "https://appninjas.se/adb/help"

    /// The language code of the first preferred language (`sv-SE` gives `sv`), or `en`.
    public static func helpLanguage(_ preferred: [String]) -> String {
        for tag in preferred {
            let code = tag.split(whereSeparator: { "-_.@".contains($0) }).first.map { $0.lowercased() } ?? ""
            if (2...3).contains(code.count), code.allSatisfy(\.isLetter) { return code }
        }
        return "en"
    }

    public static func helpURL(preferred: [String]) -> URL {
        URL(string: "\(helpBase)/\(helpLanguage(preferred))")!
    }
}
