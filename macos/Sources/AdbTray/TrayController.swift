import AdbTrayCore
import AppKit

enum Paths {
    static let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/adb-tray")
    static let hostsFile = supportDirectory.appendingPathComponent("hosts.json")
}

/// The menu bar icon. Mirrors adb-tray.py: the same menu, the same polling, the same actions.
final class TrayController: NSObject, NSMenuDelegate {
    static let pollSeconds: TimeInterval = 4
    static let tcpPort = 5555
    static let scrcpyOptions = ["-m", "1600", "--stay-awake"]
    static let adbInstallCommand = "brew install --cask android-platform-tools"
    static let scrcpyInstallCommand = "brew install scrcpy"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let tools = Tools()
    private let hosts = HostStore(file: Paths.hostsFile)
    private let worker = DispatchQueue(label: "adb-tray.worker", attributes: .concurrent)

    private var devices: [Device] = []
    private var mirrors: [String: Process] = [:]
    private var signature: String?
    private var polling = false
    private var menuOpen = false
    private var adbPath: String?

    override init() {
        super.init()
        Notifier.requestAuthorization()
        adbPath = tools.adb
        updateIcon()
        rebuild()
        if let adbPath {
            worker.async { _ = self.tools.run(adbPath, ["start-server"], timeout: 30) }
        }
        poll()
        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - adb

    private func adb(_ arguments: [String], serial: String? = nil, timeout: TimeInterval = 15) -> (Int32, String) {
        // Resolved on every call rather than read from `adbPath`, which belongs to the main thread.
        guard let adbPath = tools.adb else { return (1, tr("adb is not installed")) }
        let result = tools.run(adbPath, (serial.map { ["-s", $0] } ?? []) + arguments, timeout: timeout)
        return (result.status, result.output)
    }

    private func connect(_ host: String) {
        let (_, output) = adb(["connect", host], timeout: 10)
        if connectSucceeded(output) {
            hosts.save(host)
            Notifier.notify(format(tr("Connected to {host}"), ["host": host]))
        } else {
            Notifier.notify(format(tr("Could not connect to {host}. Check that the device is on the same network and that wireless debugging is on."), ["host": host]) + "\n\(output)")
        }
    }

    // MARK: - Polling

    @objc private func poll() {
        guard !polling else { return }
        polling = true
        worker.async {
            let adbPath = self.tools.adb
            let devices = adbPath.map { Device.parse(self.tools.run($0, ["devices", "-l"], timeout: 10).output) } ?? []
            DispatchQueue.main.async {
                self.adbPath = adbPath
                self.polling = false
                self.onDevices(devices)
            }
        }
    }

    private func onDevices(_ devices: [Device]) {
        self.devices = devices
        mirrors = mirrors.filter { $0.value.isRunning }
        let ready = devices.filter(\.isReady).count
        var tooltip = "\(Product.name): "
            + format(trn("{n} device connected", "{n} devices connected", ready), ["n": ready])
        if !mirrors.isEmpty {
            tooltip += ", " + format(trn("{n} mirroring", "{n} mirroring", mirrors.count), ["n": mirrors.count])
        }
        statusItem.button?.toolTip = tooltip
        updateIcon()

        let newSignature = [
            devices.map { "\($0.serial)|\($0.state)|\($0.model)" }.joined(separator: ","),
            mirrors.keys.sorted().joined(separator: ","),
            hosts.load().joined(separator: ","),
            adbPath ?? "-", tools.scrcpy ?? "-",
        ].joined(separator: "\n")
        // Rebuilding an open menu would close it under the user's pointer.
        if newSignature != signature && !menuOpen {
            signature = newSignature
            rebuild()
        }
    }

    private func runInBackground(_ work: @escaping () -> Void) {
        worker.async {
            work()
            DispatchQueue.main.async { self.poll() }
        }
    }

    // MARK: - Menu

    private func updateIcon() {
        let name = mirrors.isEmpty ? Icons.menuBar : Icons.menuBarMirroring
        // The SF Symbol is only a fallback for a bundle that lacks its icons.
        let fallback = NSImage(systemSymbolName: mirrors.isEmpty ? "iphone" : "iphone.radiowaves.left.and.right",
                               accessibilityDescription: Product.name)
        fallback?.isTemplate = true
        statusItem.button?.image = Icons.image(name, size: 18, description: Product.name) ?? fallback
    }

    private func item(_ title: String, icon: String? = nil, action: (() -> Void)? = nil,
                      enabled: Bool = true) -> NSMenuItem {
        let menuItem = ClosureMenuItem(title: title, handler: action)
        menuItem.isEnabled = action != nil && enabled
        menuItem.image = icon.flatMap { Icons.image($0) }
        return menuItem
    }

    private func rebuild() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        if adbPath == nil {
            menu.addItem(item(tr("adb is not installed")))
            menu.addItem(item(tr("Copy the install command"), icon: "copy", action: { Self.copy(Self.adbInstallCommand) }))
            menu.addItem(.separator())
        } else if tools.scrcpy == nil {
            menu.addItem(item(tr("scrcpy is not installed")))
            menu.addItem(item(tr("Copy the install command"), icon: "copy", action: { Self.copy(Self.scrcpyInstallCommand) }))
            menu.addItem(.separator())
        }

        if devices.isEmpty {
            menu.addItem(item(tr("No devices connected")))
        }
        for device in devices {
            menu.addItem(deviceItem(device))
        }

        menu.addItem(.separator())
        let wifi = NSMenuItem(title: tr("Connect via Wi-Fi"), action: nil, keyEquivalent: "")
        wifi.image = Icons.image("wifi-high")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let connected = Set(devices.map(\.serial))
        let saved = hosts.load()
        for host in saved {
            submenu.addItem(item(host, action: { [unowned self] in runInBackground { self.connect(host) } },
                                 enabled: !connected.contains(host)))
        }
        if !saved.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(item(tr("New address..."), action: { [unowned self] in dialogConnect() }))
        submenu.addItem(item(tr("Pair (wireless debugging)..."), action: { [unowned self] in dialogPair() }))
        wifi.submenu = submenu
        wifi.isEnabled = adbPath != nil
        menu.addItem(wifi)

        menu.addItem(item(tr("Refresh"), icon: "arrows-clockwise", action: { [unowned self] in poll() }))
        menu.addItem(item(tr("Restart adb server"), icon: "power", action: { [unowned self] in runInBackground { self.restartServer() } },
                          enabled: adbPath != nil))
        menu.addItem(.separator())
        menu.addItem(item(tr("Help"), icon: "question", action: { [unowned self] in
            NSWorkspace.shared.open(helpURL)
        }))
        menu.addItem(item(format(tr("About {name}"), ["name": Product.name]), icon: "info", action: { [unowned self] in
            showAbout()
        }))
        menu.addItem(item(tr("Quit"), action: { NSApp.terminate(nil) }))
        statusItem.menu = menu
    }

    private func deviceItem(_ device: Device) -> NSMenuItem {
        let serial = device.serial
        var label = "\(device.displayName)  (\(device.wifi ? "Wi-Fi" : "USB"))"
        if mirrors[serial] != nil { label = "▶ " + label }
        let stateText = ["unauthorized": tr("authorize on device"), "offline": tr("offline")]
        if !device.isReady { label += " – " + (stateText[device.state] ?? device.state) }

        let top = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        top.image = Icons.image(mirrors[serial] != nil ? Icons.menuBarMirroring : Icons.menuBar)
        let sub = NSMenu()
        sub.autoenablesItems = false
        if device.isReady {
            if mirrors[serial] != nil {
                sub.addItem(item(tr("Stop mirroring"), icon: "screencast", action: { [unowned self] in stopMirror(serial) }))
            } else {
                sub.addItem(item(tr("Mirror screen"), icon: "screencast", action: { [unowned self] in startMirror(device) },
                                 enabled: tools.scrcpy != nil))
            }
            sub.addItem(.separator())
            sub.addItem(item(tr("Lock portrait"), icon: "device-rotate", action: { [unowned self] in rotate(serial, 0) }))
            sub.addItem(item(tr("Lock landscape"), icon: "device-rotate", action: { [unowned self] in rotate(serial, 1) }))
            sub.addItem(item(tr("Auto-rotate"), icon: "device-rotate", action: { [unowned self] in rotate(serial, nil) }))
            sub.addItem(.separator())
            sub.addItem(item(tr("Take screenshot"), icon: "camera", action: { [unowned self] in runInBackground { self.screenshot(device) } }))
            sub.addItem(item(tr("Open adb shell"), icon: "terminal-window", action: { [unowned self] in openShell(serial) }))
            if device.wifi {
                sub.addItem(item(tr("Disconnect"), icon: "plugs", action: { [unowned self] in runInBackground { self.disconnect(serial) } }))
            } else {
                sub.addItem(item(tr("Switch to Wi-Fi"), icon: "wifi-high", action: { [unowned self] in
                    runInBackground { self.switchToWifi(serial) }
                }))
            }
        } else if device.state == "unauthorized" {
            sub.addItem(item(tr("Tap Allow in the dialog on the device")))
        }
        if device.wifi && !device.isReady {
            sub.addItem(item(tr("Disconnect"), icon: "plugs", action: { [unowned self] in runInBackground { self.disconnect(serial) } }))
        }
        sub.addItem(.separator())
        sub.addItem(item(format(tr("Serial number: {serial}"), ["serial": serial])))
        top.submenu = sub
        return top
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        poll()  // Picks up any change that was held back while the menu was open.
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Notifier.notify(format(tr("Copied {command}. Paste it into Terminal to install."), ["command": text]))
    }

    // MARK: - Actions

    private func startMirror(_ device: Device) {
        guard let scrcpy = tools.scrcpy else { return }
        let serial = device.serial
        let safeName = serial.replacingOccurrences(of: #"[^A-Za-z0-9]"#, with: "_", options: .regularExpression)
        let log = Paths.supportDirectory.appendingPathComponent("scrcpy-\(safeName).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: log) else { return }

        var arguments = ["-s", serial, "--window-title", device.displayName] + Self.scrcpyOptions
        if device.wifi { arguments += ["-b", "6M"] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: scrcpy)
        process.arguments = arguments
        process.environment = tools.childEnvironment
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.standardInput = FileHandle.nullDevice
        let started = Date()
        process.terminationHandler = { [weak self] finished in
            try? logHandle.close()
            let code = finished.terminationStatus
            if code != 0 && Date().timeIntervalSince(started) < 10 {
                Notifier.notify(format(tr("Mirroring stopped because scrcpy exited with error {code}. The details are in {log}."),
                                       ["code": code, "log": log.path]))
            }
            DispatchQueue.main.async { self?.poll() }
        }
        do {
            try process.run()
        } catch {
            Notifier.notify(error.localizedDescription)
            return
        }
        mirrors[serial] = process
        signature = nil  // Force a rebuild so the ▶ marker appears at once.
        onDevices(devices)
    }

    private func stopMirror(_ serial: String) {
        if let process = mirrors[serial], process.isRunning {
            process.terminate()
        }
    }

    private func rotate(_ serial: String, _ rotation: Int?) {
        runInBackground {
            guard let rotation else {
                _ = self.adb(["shell", "settings", "put", "system", "accelerometer_rotation", "1"], serial: serial)
                return
            }
            _ = self.adb(["shell", "settings", "put", "system", "accelerometer_rotation", "0"], serial: serial)
            _ = self.adb(["shell", "settings", "put", "system", "user_rotation", String(rotation)], serial: serial)
        }
    }

    private func screenshot(_ device: Device) {
        guard let adbPath = tools.adb else { return }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = device.model.isEmpty ? "android" : device.model
        let target = pictures.appendingPathComponent("\(name)-\(stamp.string(from: Date())).png")
        let result = tools.run(adbPath, ["-s", device.serial, "exec-out", "screencap", "-p"], timeout: 30)
        guard result.status == 0, !result.data.isEmpty, (try? result.data.write(to: target)) != nil else {
            Notifier.notify(tr("Could not take a screenshot. Check that the device is connected and unlocked, and try again."))
            return
        }
        Notifier.notify(format(tr("Screenshot saved: {path}"), ["path": target.path]))
    }

    /// Opens `adb shell` in Terminal through a temporary `.command` file. Unlike scripting Terminal with
    /// AppleScript, this needs no Automation permission.
    private func openShell(_ serial: String) {
        guard let adbPath = tools.adb else { return }
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("adb-shell-\(UUID().uuidString).command")
        let body = "#!/bin/sh\nrm -f \(shellQuote(script.path))\nexec \(shellQuote(adbPath)) -s \(shellQuote(serial)) shell\n"
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            Notifier.notify(error.localizedDescription)
            return
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    private func switchToWifi(_ serial: String) {
        let (_, output) = adb(["shell", "ip", "-f", "inet", "addr", "show", "wlan0"], serial: serial)
        guard let address = wifiAddress(fromIpOutput: output) else {
            Notifier.notify(tr("Could not switch to Wi-Fi because the device has no Wi-Fi address. Connect it to a Wi-Fi network and try again."))
            return
        }
        _ = adb(["tcpip", String(Self.tcpPort)], serial: serial)
        Thread.sleep(forTimeInterval: 2)
        connect("\(address):\(Self.tcpPort)")
    }

    private func disconnect(_ serial: String) {
        _ = adb(["disconnect", serial])
        Notifier.notify(format(tr("Disconnected from {serial}"), ["serial": serial]))
    }

    private func restartServer() {
        _ = adb(["kill-server"])
        _ = adb(["start-server"], timeout: 30)
        Notifier.notify(tr("The adb server has been restarted"))
    }

    // MARK: - Dialogs

    /// The help page in the menu's language: the address is itself a translated string.
    private var helpURL: URL {
        // Translators: the address of the help page in your language, or leave the English page.
        URL(string: tr("https://appninjas.se/en/appar/adb")) ?? URL(string: Product.helpPageEnglish)!
    }

    /// The standard About panel, with the version, the help page, the source and the licences.
    private func showAbout() {
        let lines: [(String, URL?)] = [
            (tr("Help and common questions"), helpURL),
            (tr("Source code on GitHub"), Product.repository),
            (tr("The program is free software under the MIT License. The Appninjas name and logo are trademarks of Dvisious AB and are not covered by the MIT License."), nil),
            (tr("Icons: Phosphor Icons, MIT License."), nil),
        ]
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        for (index, (text, link)) in lines.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text + (index < lines.count - 1 ? "\n" : ""), attributes: attributes))
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Product.name,
            .applicationVersion: appVersion,
            .version: "",  // hides the build number in parentheses; the version says it all
            .credits: credits,
        ])
    }

    private func dialogConnect() {
        let saved = hosts.load()
        guard let values = Dialogs.ask(title: tr("Connect via Wi-Fi"),
                                       fields: [(tr("Address (IP:port)"), saved.first ?? "")]),
              let address = values.first, !address.isEmpty else { return }
        let host = normalizedHost(address, defaultPort: Self.tcpPort)
        runInBackground { self.connect(host) }
    }

    private func dialogPair() {
        guard let values = Dialogs.ask(title: tr("Pair - wireless debugging"), fields: [
            (tr("Pairing address (IP:port)"), ""),
            (tr("Pairing code"), ""),
            (tr("Connection address (optional)"), ""),
        ]), !values[0].isEmpty, !values[1].isEmpty else { return }
        let (address, code, connectTo) = (values[0], values[1], values[2])
        runInBackground {
            let (_, output) = self.adb(["pair", address, code], timeout: 20)
            guard output.contains("Successfully paired") else {
                Notifier.notify(tr("Pairing failed. Check the pairing address and code under Wireless debugging on the device, and try again.") + "\n\(output)")
                return
            }
            Notifier.notify(tr("Pairing succeeded"))
            if !connectTo.isEmpty { self.connect(normalizedHost(connectTo, defaultPort: Self.tcpPort)) }
        }
    }
}

/// An NSMenuItem that runs a closure, so the menu can be built the way the Linux version builds it.
final class ClosureMenuItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(title: String, handler: (() -> Void)?) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        handler?()
    }
}

private func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}
