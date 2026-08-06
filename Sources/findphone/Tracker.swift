import Foundation
import CoreBluetooth

enum LinkState: String {
    case down = "LINK DOWN"
    case classic = "link up"
    case live = "LIVE LINK"
}

let continuityNames: [UInt8: String] = [
    0x0C: "Handoff", 0x0D: "Hotspot-tgt", 0x0E: "Hotspot-src",
    0x0F: "NearbyAction", 0x10: "NearbyInfo",
]

/// Continuity message types that phones, tablets and watches emit.
let handheldTypes = Set(continuityNames.keys)

struct Advertiser: Equatable {
    let identity: String
    var name: String?
    var peak: Int
    var smoothed: Double
    var types: Set<UInt8>
    var last: Date

    /// What the device is, from its Continuity advertisement. Carries no
    /// identity, so it is what redacted output falls back to.
    var kind: String {
        let kinds = types.compactMap { continuityNames[$0] }.sorted()
        return kinds.isEmpty ? "unknown" : kinds.joined(separator: ",")
    }

    var label: String { name ?? kind }
}

struct Snapshot {
    let candidates: [Advertiser]
    let selectedIdentity: String?
    let isManualTracking: Bool
    let focusedAdvertiser: Advertiser?
    let targetName: String?
    let address: String?
    let at: Date
    let elapsed: Int
    let readings: [Reading]
    let link: LinkState
    let radioIssue: String?
    let deviceCount: Int

    /// The reading everything reports: a short median, so one reflected spike
    /// cannot move the number, the arrow and the clicks apart from each other.
    var live: Int? {
        readings.since(liveWindow, now: at).medianRSSI ?? readings.last?.rssi
    }

    /// Whether the last reading is recent enough to steer by.
    var isFresh: Bool {
        readings.last.map { at.timeIntervalSince($0.at) < 10 } ?? false
    }

    var focusedLive: Int? {
        guard let focused = focusedAdvertiser else { return nil }
        return Int(focused.smoothed.rounded())
    }

    var focusedFresh: Bool {
        guard let focused = focusedAdvertiser else { return isFresh }
        return at.timeIntervalSince(focused.last) < 10
    }

    var focusedLabel: String? {
        focusedAdvertiser?.label
    }

    /// Use focused data when manually selected; fall back to all-source live data.
    var effectiveLive: Int? {
        focusedLive ?? live
    }

    /// Use focused staleness when manually selected; fall back to global freshness.
    var effectiveFresh: Bool {
        if selectedIdentity == nil {
            return isFresh
        }

        return selectedIdentity != nil && focusedAdvertiser != nil
            ? focusedFresh
            : false
    }
}

private let appleCompanyID: UInt16 = 0x004C
private let historyWindow: TimeInterval = 600
private let advertiserTTL: TimeInterval = 20

final class Tracker: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let targetName: String?
    private let startedAt = Date()

    private var central: CBCentralManager!
    private var target: CBPeripheral?
    private var linkTimer: Timer?

    private var readings: [Reading] = []
    private var advertisers: [String: Advertiser] = [:]
    private var selectedIdentity: String?
    private var address: String?
    private var radioIssue: String?
    private var cachedID: UUID?

    private let lock = NSLock()
    private var liveLink = false
    private var linkUp = false

    private var isLive: Bool { lock.withLock { liveLink } }

    init(targetName: String?) {
        self.targetName = targetName
        super.init()
    }

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
        if let name = targetName {
            cachedID = DeviceCache.peripheralID(for: name)
            pollClassic(name: name)
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.prune()
        }
    }

    func snapshot() -> Snapshot {
        let now = Date()
        let snapshotCandidates = lock.withLock { advertisers.values.sorted { $0.smoothed > $1.smoothed } }
        let selectedIdentity = lock.withLock { self.selectedIdentity }
        let focusedAdvertiser = selectedIdentity.flatMap { selected in snapshotCandidates.first { $0.identity == selected } }
        return Snapshot(
            candidates: targetName == nil ? snapshotCandidates : [],
            selectedIdentity: selectedIdentity,
            isManualTracking: selectedIdentity != nil,
            focusedAdvertiser: focusedAdvertiser,
            targetName: targetName,
            address: address,
            at: now,
            elapsed: Int(now.timeIntervalSince(startedAt)),
            readings: lock.withLock { readings },
            link: isLive ? .live : (linkUp ? .classic : .down),
            radioIssue: radioIssue,
            deviceCount: snapshotCandidates.count)
    }

    func setManualSelection(identity: String?) {
        lock.withLock { selectedIdentity = identity }
    }

    private func prune() {
        let now = Date()
        while let oldest = readings.first,
              now.timeIntervalSince(oldest.at) >= historyWindow {
            readings.removeFirst()
        }
        advertisers = advertisers.filter { now.timeIntervalSince($0.value.last) < advertiserTTL }
    }

    private func record(_ rssi: Int, _ source: String) {
        guard rssi < 0, rssi > -127 else { return }
        readings.append(Reading(rssi: rssi, at: Date(), source: source))
    }

    // MARK: - Classic polling

    /// Skipped while the GATT link is live: the link is both fresher and far
    /// cheaper than spawning system_profiler. macOS serves a cached RSSI
    /// between its own refreshes, so only a changed value is a real
    /// measurement.
    private func pollClassic(name: String) {
        DispatchQueue(label: "classic.poll").async { [weak self] in
            var lastRaw: Int?
            var addressResolved = false
            while true {
                guard let self else { return }
                if self.isLive && addressResolved {
                    lastRaw = nil
                } else {
                    let found = Classic.find(name: name)
                    let value = found?.rssi
                    let changed = value != nil && value != lastRaw
                    lastRaw = value
                    addressResolved = true
                    DispatchQueue.main.async {
                        self.address = found?.address ?? self.address
                        self.linkUp = value != nil
                        if changed, let v = value { self.record(v, "classic") }
                    }
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
    }

    // MARK: - Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            radioIssue = nil
            c.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            restoreCachedTarget()
        case .poweredOff:
            radioIssue = "Bluetooth is off. Waiting for it to come back on."
            dropLink()
        case .unauthorized:
            fail("""
                 Bluetooth permission denied.
                 System Settings > Privacy & Security > Bluetooth > enable your terminal.
                 """)
        case .unsupported:
            fail("This Mac has no Bluetooth LE support.")
        default:
            radioIssue = "Bluetooth unavailable."
        }
    }

    /// A remembered peripheral can be connected before any advertisement
    /// arrives, which is the difference between a 2s and a 30s cold start.
    private func restoreCachedTarget() {
        guard target == nil, let id = cachedID,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first
        else { return }
        adopt(p)
    }

    private func adopt(_ p: CBPeripheral) {
        target = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func dropLink() {
        lock.withLock { liveLink = false }
        linkTimer?.invalidate()
        linkTimer = nil
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData d: [String: Any], rssi RSSI: NSNumber) {
        let r = RSSI.intValue
        guard r < 0, r > -127 else { return }

        let types = continuityTypes(d)
        if targetName == nil && types.isDisjoint(with: handheldTypes) { return }

        let now = Date()
        let identity = p.identifier.uuidString
        var a = advertisers[identity, default:
            Advertiser(
                identity: identity,
                name: nil,
                peak: r,
                smoothed: Double(r),
                types: [],
                last: now)]
        a.name = a.name ?? (d[CBAdvertisementDataLocalNameKey] as? String ?? p.name)
        a.peak = max(a.peak, r)
        a.smoothed = a.smoothed * 0.7 + Double(r) * 0.3
        a.types.formUnion(types)
        a.last = now
        advertisers[identity] = a

        guard let t = targetName, let n = a.name,
              n.localizedCaseInsensitiveContains(t) else { return }
        record(r, "advert")

        if cachedID != p.identifier {
            cachedID = p.identifier
            DeviceCache.store(p.identifier, for: t)
        }
        guard let current = target else { return adopt(p) }
        if current.state != .connected && current.identifier != p.identifier {
            central.cancelPeripheralConnection(current)
            adopt(p)
        }
    }

    private func continuityTypes(_ d: [String: Any]) -> Set<UInt8> {
        guard let mfg = d[CBAdvertisementDataManufacturerDataKey] as? Data else { return [] }
        let bytes = [UInt8](mfg)
        guard bytes.count >= 3,
              UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == appleCompanyID else { return [] }
        var types = Set<UInt8>()
        var i = 2
        while i + 1 < bytes.count {
            types.insert(bytes[i])
            let len = Int(bytes[i + 1])
            if len == 0 { break }
            i += 2 + len
        }
        return types
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        lock.withLock { liveLink = true }
        linkTimer?.invalidate()
        linkTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            p.readRSSI()
        }
    }

    /// CoreBluetooth holds an unfulfilled connect pending indefinitely, so
    /// simply reissuing it is a complete reconnect strategy.
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {
        dropLink()
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        dropLink()
        c.connect(p, options: nil)
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        record(RSSI.intValue, "link")
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("findphone: \(message)\n".utf8))
    exit(1)
}
