import AppKit
import AdbTrayCore
import Darwin

let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

if CommandLine.arguments.contains("--version") {
    print("adb-tray \(version)")
    exit(0)
}

// Kept open for the process lifetime; the flock is the single-instance guard, as on Linux.
try? FileManager.default.createDirectory(at: Paths.supportDirectory, withIntermediateDirectories: true)
let lockDescriptor = open(Paths.supportDirectory.appendingPathComponent("tray.lock").path, O_CREAT | O_WRONLY, 0o644)
if lockDescriptor < 0 || flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
    FileHandle.standardError.write(Data((tr("adb-tray is already running") + "\n").utf8))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Menu bar only: no Dock icon, no app menu.
let tray = TrayController()
app.run()
