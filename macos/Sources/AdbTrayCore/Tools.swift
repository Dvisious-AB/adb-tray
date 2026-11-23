import Foundation

/// Finds `adb` and `scrcpy` and runs them.
///
/// Started by `brew services` (launchd), the app gets launchd's minimal PATH, which does not include
/// Homebrew. The usual install locations are therefore searched as well, and the PATH handed to child
/// processes is widened the same way so that scrcpy, which starts adb itself, finds it too.
public struct Tools {
    public static let fallbackDirectories = [
        "/opt/homebrew/bin",  // Homebrew on Apple silicon
        "/usr/local/bin",  // Homebrew on Intel
        "~/Library/Android/sdk/platform-tools",  // Android Studio
    ]

    public let searchPath: [String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let fromEnvironment = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let extra = Self.fallbackDirectories.map { NSString(string: $0).expandingTildeInPath }
        var seen = Set<String>()
        searchPath = (fromEnvironment + extra).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func find(_ name: String, fileManager: FileManager = .default) -> String? {
        searchPath
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    public var adb: String? { find("adb") }
    public var scrcpy: String? { find("scrcpy") }

    /// Environment for child processes: the widened PATH, and `ADB` so scrcpy uses the same adb.
    public var childEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        if let adb { environment["ADB"] = adb }
        return environment
    }

    public struct Result {
        public let status: Int32
        public let output: String
        public let data: Data
    }

    /// Runs a program and waits for it, killing it after `timeout` seconds.
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = childEnvironment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription, data: Data())
        }
        // Read both pipes while the process runs, so a full pipe buffer cannot block it.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let deadline = DispatchTime.now() + timeout
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return Result(status: 1, output: "timeout", data: Data())
        }
        // A daemon the program started (adb start-server) may inherit the pipes and keep them open.
        _ = group.wait(timeout: .now() + 2)
        let text = (String(decoding: outData, as: UTF8.self) + String(decoding: errData, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(status: process.terminationStatus, output: text, data: outData)
    }
}
