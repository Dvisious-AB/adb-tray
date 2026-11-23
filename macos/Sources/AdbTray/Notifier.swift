import AdbTrayCore
import AppKit
import UserNotifications

/// Desktop notifications. Inside the app bundle (how Homebrew installs it) they come from the app itself;
/// a bare executable, such as `swift run` during development, has no bundle identifier and falls back to
/// AppleScript's `display notification`.
enum Notifier {
    private static let hasBundle = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")

    static func requestAuthorization() {
        guard hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ message: String) {
        if hasBundle {
            let content = UNMutableNotificationContent()
            content.title = Product.name
            content.body = message
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            return
        }
        let script = "display notification \(appleScriptString(message)) with title \(appleScriptString(Product.name))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
