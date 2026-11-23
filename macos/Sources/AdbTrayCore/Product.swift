import Foundation

/// The product's name and addresses. The name follows the Appninjas product architecture,
/// "Appninjas {Product}"; the command, the package and the bundle identifier stay `adb-tray`.
public enum Product {
    public static let name = "Appninjas ADB"
    public static let command = "adb-tray"
    public static let repository = URL(string: "https://github.com/Dvisious-AB/adb-tray")!
    /// The English help page. Each translation points to the page in its own language (see po/*.po).
    public static let helpPageEnglish = "https://appninjas.se/en/hjalp/adb"
}
