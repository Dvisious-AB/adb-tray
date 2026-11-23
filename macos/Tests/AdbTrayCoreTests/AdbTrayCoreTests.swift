@testable import AdbTrayCore
import XCTest

final class DeviceTests: XCTestCase {
    func testParsesUsbWifiAndUnauthorizedDevices() {
        let output = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        R52W70ABCDE            device usb:1-1 product:gta9pwifixx model:SM_X210 device:gta9pwifi transport_id:1
        192.168.1.42:5555      device product:gta9pwifixx model:SM_X210 device:gta9pwifi transport_id:2
        adb-R52W70-abc._adb-tls-connect._tcp offline transport_id:3
        0123456789             unauthorized usb:1-2 transport_id:4

        """
        let devices = Device.parse(output)
        XCTAssertEqual(devices, [
            Device(serial: "R52W70ABCDE", state: "device", model: "SM-X210", wifi: false),
            Device(serial: "192.168.1.42:5555", state: "device", model: "SM-X210", wifi: true),
            Device(serial: "adb-R52W70-abc._adb-tls-connect._tcp", state: "offline", model: "", wifi: true),
            Device(serial: "0123456789", state: "unauthorized", model: "", wifi: false),
        ])
        XCTAssertEqual(devices[3].displayName, "0123456789")
        XCTAssertTrue(devices[0].isReady)
        XCTAssertFalse(devices[2].isReady)
    }

    func testEmptyListGivesNoDevices() {
        XCTAssertEqual(Device.parse("List of devices attached\n\n"), [])
    }

    func testWifiAddress() {
        let output = """
        30: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 3000
            inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0
        """
        XCTAssertEqual(wifiAddress(fromIpOutput: output), "192.168.1.42")
        XCTAssertNil(wifiAddress(fromIpOutput: "Device \"wlan0\" does not exist."))
    }

    func testNormalizedHostAddsDefaultPort() {
        XCTAssertEqual(normalizedHost(" 10.0.0.5 "), "10.0.0.5:5555")
        XCTAssertEqual(normalizedHost("10.0.0.5:37123"), "10.0.0.5:37123")
    }

    func testConnectSucceeded() {
        XCTAssertTrue(connectSucceeded("connected to 10.0.0.5:5555"))
        XCTAssertTrue(connectSucceeded("already connected to 10.0.0.5:5555"))
        XCTAssertFalse(connectSucceeded("failed to connect to '10.0.0.5:5555': Connection refused"))
        XCTAssertFalse(connectSucceeded("cannot connect to 10.0.0.5:5555: No route to host"))
    }
}

final class HostStoreTests: XCTestCase {
    func testNewestFirstWithoutDuplicatesAndAtMostTen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HostStore(file: directory.appendingPathComponent("hosts.json"))
        XCTAssertEqual(store.load(), [])
        for index in 1...12 { store.save("10.0.0.\(index):5555") }
        store.save("10.0.0.5:5555")
        let hosts = store.load()
        XCTAssertEqual(hosts.count, HostStore.limit)
        XCTAssertEqual(hosts.first, "10.0.0.5:5555")
        XCTAssertEqual(hosts.filter { $0 == "10.0.0.5:5555" }.count, 1)
    }
}

final class ToolsTests: XCTestCase {
    func testSearchesHomebrewEvenWithLaunchdsMinimalPath() {
        let tools = Tools(environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        XCTAssertEqual(Array(tools.searchPath.prefix(4)), ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        XCTAssertTrue(tools.searchPath.contains("/opt/homebrew/bin"))
        XCTAssertTrue(tools.searchPath.contains("/usr/local/bin"))
        XCTAssertFalse(tools.searchPath.contains { $0.hasPrefix("~") })
        XCTAssertTrue(tools.childEnvironment["PATH"]!.contains("/opt/homebrew/bin"))
    }

    func testRunCapturesOutputAndStatus() {
        let tools = Tools()
        let result = tools.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.output, "out\nerr")
    }

    func testRunTimesOut() {
        let result = Tools().run("/bin/sleep", ["5"], timeout: 0.5)
        XCTAssertEqual(result.output, "timeout")
    }
}

final class CatalogTests: XCTestCase {
    static let po = #"""
    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\n"
    "Plural-Forms: nplurals=2; plural=(n != 1);\n"

    msgid "ADB Devices"
    msgstr "ADB-enheter"

    #, python-brace-format
    msgid "Connected to {host}"
    msgstr "Ansluten till {host}"

    msgid "{n} device connected"
    msgid_plural "{n} devices connected"
    msgstr[0] "{n} enhet ansluten"
    msgstr[1] "{n} enheter anslutna"

    msgid "Tap 'Allow' in the dialog on the device"
    msgstr ""
    "Tryck på \"Tillåt\" "
    "på enheten"

    #, fuzzy
    msgid "Refresh"
    msgstr "Uppdatera kanske"

    msgid "Quit"
    msgstr ""
    """#

    func testTranslatesSingularPluralAndContinuationLines() {
        let catalog = Catalog(poText: Self.po)
        XCTAssertEqual(catalog.gettext("ADB Devices"), "ADB-enheter")
        XCTAssertEqual(format(catalog.gettext("Connected to {host}"), ["host": "10.0.0.5:5555"]),
                       "Ansluten till 10.0.0.5:5555")
        XCTAssertEqual(catalog.ngettext("{n} device connected", "{n} devices connected", 1), "{n} enhet ansluten")
        XCTAssertEqual(catalog.ngettext("{n} device connected", "{n} devices connected", 0), "{n} enheter anslutna")
        XCTAssertEqual(catalog.gettext("Tap 'Allow' in the dialog on the device"), "Tryck på \"Tillåt\" på enheten")
    }

    func testFuzzyUntranslatedAndUnknownStringsFallBackToEnglish() {
        let catalog = Catalog(poText: Self.po)
        XCTAssertEqual(catalog.gettext("Refresh"), "Refresh")
        XCTAssertEqual(catalog.gettext("Quit"), "Quit")
        XCTAssertEqual(catalog.gettext("Not in the file"), "Not in the file")
        XCTAssertEqual(Catalog().ngettext("{n} mirroring", "{n} mirroring", 2), "{n} mirroring")
    }

    func testCandidateLanguages() {
        XCTAssertEqual(Catalog.candidateLanguages(["sv-SE", "en-US"]), ["sv_SE", "sv"])
        XCTAssertEqual(Catalog.candidateLanguages(["en-SE", "sv-SE"]), [])
        XCTAssertEqual(Catalog.candidateLanguages(["pt-BR"]), ["pt_BR", "pt"])
        XCTAssertEqual(Catalog.candidateLanguages(["zh-Hans-CN"]), ["zh_CN", "zh"])
    }

    /// Every .po in the repository must load and translate every string the template has.
    func testRepositoryTranslationsLoad() throws {
        let poDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../po").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: poDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "po" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let catalog = Catalog(poText: try String(contentsOf: file, encoding: .utf8))
            XCTAssertNotEqual(catalog.gettext("ADB Devices"), "ADB Devices", file.lastPathComponent)
            XCTAssertNotEqual(catalog.gettext("Copy the install command"), "Copy the install command",
                              file.lastPathComponent)
        }
    }
}
