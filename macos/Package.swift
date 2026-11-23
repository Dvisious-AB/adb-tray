// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "adb-tray",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "adb-tray", targets: ["AdbTray"]),
    ],
    targets: [
        // Everything that can be tested without a menu bar: adb output parsing, the saved hosts and gettext.
        .target(name: "AdbTrayCore"),
        .executableTarget(name: "AdbTray", dependencies: ["AdbTrayCore"]),
        .testTarget(name: "AdbTrayCoreTests", dependencies: ["AdbTrayCore"]),
    ]
)
