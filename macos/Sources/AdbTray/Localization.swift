import AdbTrayCore
import Foundation

/// Loads `<lang>.po` for the user's preferred language from the first of:
/// `$ADB_TRAY_LOCALE_DIR`, the app bundle's `Resources/locale`, and `../share/adb-tray/locale` next to
/// the executable. Falls back to English (the source strings).
enum L10n {
    static let catalog: Catalog = {
        let fileManager = FileManager.default
        for directory in localeDirectories() {
            for language in Catalog.candidateLanguages(Locale.preferredLanguages) {
                let file = directory.appendingPathComponent("\(language).po")
                if let text = try? String(contentsOf: file, encoding: .utf8), fileManager.fileExists(atPath: file.path) {
                    return Catalog(poText: text)
                }
            }
        }
        return Catalog()
    }()

    static func localeDirectories() -> [URL] {
        var directories: [URL] = []
        if let override = ProcessInfo.processInfo.environment["ADB_TRAY_LOCALE_DIR"] {
            directories.append(URL(fileURLWithPath: override))
        }
        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent("locale"))
        }
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            directories.append(executable.deletingLastPathComponent()
                .appendingPathComponent("../share/adb-tray/locale").standardizedFileURL)
        }
        return directories
    }
}

func tr(_ msgid: String) -> String {
    L10n.catalog.gettext(msgid)
}

func trn(_ msgid: String, _ msgidPlural: String, _ n: Int) -> String {
    L10n.catalog.ngettext(msgid, msgidPlural, n)
}
