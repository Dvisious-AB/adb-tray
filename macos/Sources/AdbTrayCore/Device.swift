import Foundation

/// One line of `adb devices -l`.
public struct Device: Equatable, Hashable, Sendable {
    public let serial: String
    public let state: String
    public let model: String
    public let wifi: Bool

    public init(serial: String, state: String, model: String, wifi: Bool) {
        self.serial = serial
        self.state = state
        self.model = model
        self.wifi = wifi
    }

    public var isReady: Bool { state == "device" }
    public var displayName: String { model.isEmpty ? serial : model }

    /// Parses the output of `adb devices -l`, the same way the Linux version does.
    public static func parse(_ output: String) -> [Device] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of") || line.hasPrefix("*") {
                return nil
            }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { return nil }
            var info: [String: String] = [:]
            for part in parts.dropFirst(2) {
                if let colon = part.firstIndex(of: ":") {
                    info[String(part[..<colon])] = String(part[part.index(after: colon)...])
                }
            }
            let serial = parts[0]
            return Device(
                serial: serial,
                state: parts[1],
                model: (info["model"] ?? "").replacingOccurrences(of: "_", with: "-"),
                wifi: serial.contains(":") || serial.hasPrefix("adb-"))
        }
    }
}

/// Finds the device's Wi-Fi IPv4 address in `ip -f inet addr show wlan0`.
public func wifiAddress(fromIpOutput output: String) -> String? {
    guard let range = output.range(of: #"inet (\d+\.\d+\.\d+\.\d+)"#, options: .regularExpression) else {
        return nil
    }
    return String(output[range].dropFirst("inet ".count))
}

/// `192.168.1.5` becomes `192.168.1.5:5555`; an address with a port is left as it is.
public func normalizedHost(_ input: String, defaultPort: Int = 5555) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.contains(":") ? trimmed : "\(trimmed):\(defaultPort)"
}

/// True when `adb connect` reports success. adb exits 0 even when the connection fails.
public func connectSucceeded(_ output: String) -> Bool {
    output.contains("connected to") && !output.contains("failed")
}
