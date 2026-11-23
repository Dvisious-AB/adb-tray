import Foundation

/// Recently used Wi-Fi addresses, newest first, at most ten. Same JSON format as the Linux version.
public struct HostStore {
    public let file: URL
    public static let limit = 10

    public init(file: URL) {
        self.file = file
    }

    public func load() -> [String] {
        guard let data = try? Data(contentsOf: file),
              let hosts = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return hosts
    }

    public func save(_ host: String) {
        var hosts = load().filter { $0 != host }
        hosts.insert(host, at: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(Array(hosts.prefix(Self.limit))) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
