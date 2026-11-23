import AdbTrayCore
import AppKit

/// Phosphor icons (weight fill) as template images, so the menu bar and menus colour them for the
/// current appearance. The SVG files are copied into the app's `Resources/icons` by build-app.sh; during
/// development (`swift run`) they are read from `branding/phosphor` in the checkout.
enum Icons {
    static let menuBar = "device-mobile"
    static let menuBarMirroring = "screencast"

    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String, size: CGFloat = 16, description: String? = nil) -> NSImage? {
        let key = "\(name)@\(size)"
        if let cached = cache[key] { return cached }
        guard let file = directories().map({ $0.appendingPathComponent("\(name)-fill.svg") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let vector = try? VectorImage(contentsOf: file) else { return nil }
        // Drawn on demand at the screen's scale, so the icon stays sharp on every display.
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            vector.draw(in: context, rect: rect, currentColor: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        cache[key] = image
        return image
    }

    private static func directories() -> [URL] {
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent("icons"))
        }
        directories.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../branding/phosphor").standardizedFileURL)
        return directories
    }
}
