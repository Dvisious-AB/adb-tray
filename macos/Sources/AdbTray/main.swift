import AppKit
import AdbTrayCore
import Darwin

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

if CommandLine.arguments.contains("--version") {
    print("adb-tray \(appVersion)")
    exit(0)
}

// Used by build-app.sh: render an SVG into the PNG sizes of a macOS .iconset for iconutil.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--render-iconset" {
    let source = URL(fileURLWithPath: CommandLine.arguments[2])
    let iconset = URL(fileURLWithPath: CommandLine.arguments[3])
    do {
        let image = try VectorImage(contentsOf: source)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                guard let data = image.pngData(pixels: points * scale) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: iconset.appendingPathComponent(name))
            }
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Could not render \(source.path): \(error)\n".utf8))
        exit(1)
    }
}

// Kept open for the process lifetime; the flock is the single-instance guard, as on Linux.
try? FileManager.default.createDirectory(at: Paths.supportDirectory, withIntermediateDirectories: true)
let lockDescriptor = open(Paths.supportDirectory.appendingPathComponent("tray.lock").path, O_CREAT | O_WRONLY, 0o644)
if lockDescriptor < 0 || flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
    FileHandle.standardError.write(Data((format(tr("{name} is already running"), ["name": Product.name]) + "\n").utf8))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Menu bar only: no Dock icon, no app menu.
let tray = TrayController()
app.run()
