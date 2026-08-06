import Foundation

struct ClassicDevice {
    let name: String
    let address: String
    let rssi: Int?
    let connected: Bool
}

/// The paired-device table from system_profiler. Unlike BLE advertising
/// addresses, which Apple rotates every few minutes, these public addresses
/// are stable, so a device stays identifiable across runs.
enum Classic {
    static func devices() -> [ClassicDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return [] }

        return bt.flatMap { section, value -> [ClassicDevice] in
            guard let items = value as? [[String: Any]] else { return [] }
            return items.flatMap { item in
                item.compactMap { name, raw -> ClassicDevice? in
                    guard let info = raw as? [String: Any],
                          let address = info["device_address"] as? String else { return nil }
                    let rssi = (info["device_rssi"] as? String).flatMap(Int.init)
                        ?? info["device_rssi"] as? Int
                    return ClassicDevice(name: name, address: address, rssi: rssi,
                                         connected: section == "device_connected")
                }
            }
        }
    }

    static func devicesByStrength() -> [ClassicDevice] {
        devices().sorted { ($0.rssi ?? .min) > ($1.rssi ?? .min) }
    }

    static func find(name: String) -> ClassicDevice? {
        devices().first { $0.name.localizedCaseInsensitiveContains(name) }
    }

    /// All paired devices matching a name, so a caller can tell an ambiguous
    /// match from a resolvable one before committing to either. Sorted, since
    /// devices() draws from JSON dictionaries whose enumeration order is not
    /// stable across runs, and this list can end up in an error message.
    static func matches(name: String) -> [ClassicDevice] {
        devices()
            .filter { $0.name.localizedCaseInsensitiveContains(name) }
            .sorted { ($0.name.lowercased(), $0.address) < ($1.name.lowercased(), $1.address) }
    }
}

/// Remembers which CoreBluetooth peripheral matched a search, so a later run
/// can connect straight away instead of waiting for one of the rare
/// advertisements that carries the device name.
enum DeviceCache {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/findphone/devices.json")

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func peripheralID(for name: String) -> UUID? {
        load()[name.lowercased()].flatMap(UUID.init(uuidString:))
    }

    static func store(_ id: UUID, for name: String) {
        var map = load()
        map[name.lowercased()] = id.uuidString
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(map).write(to: url)
    }
}
