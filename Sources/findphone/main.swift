import Foundation

let usage = """
findphone — locate a nearby Bluetooth device by signal strength

  findphone            survey every nearby Apple handheld
  findphone <name>     track one device by name (case-insensitive)
  findphone --list     show paired devices and their addresses

  --sound              click faster as you get closer (hunt mode)
  --redact             mask Bluetooth addresses, for screen recording
"""

let knownFlags: Set<String> = ["-h", "--help", "--list", "--redact", "--sound"]

func usageError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("findphone: \(message)\n\n\(usage)\n".utf8))
    exit(2)
}

let args = CommandLine.arguments.dropFirst()

if args.contains("-h") || args.contains("--help") {
    print(usage)
    exit(0)
}

if let unknown = args.first(where: { $0.hasPrefix("-") && !knownFlags.contains($0) }) {
    usageError("unknown option '\(unknown)'")
}

let names = args.filter { !$0.hasPrefix("-") }
if names.count > 1 {
    usageError("expected one device name, got \(names.count): \(names.joined(separator: ", "))")
}

let redact = args.contains("--redact")

if args.contains("--list") {
    Display.list(Classic.devicesByStrength(), redact: redact)
    exit(0)
}

/// Clicks only make sense with a single target; survey mode tracks many.
var clicker: Clicker?
if args.contains("--sound") {
    if names.isEmpty {
        usageError("--sound needs a device name to track")
    }
    clicker = Clicker()
    if let clicker {
        clicker.start()
    } else {
        FileHandle.standardError.write(Data("findphone: could not open the click sound\n".utf8))
    }
}

/// Resolved once against the paired list, not the live scan: BLE-only devices
/// aren't known until scanning starts, so only this half of the ambiguity is
/// catchable up front. Zero matches means classic polling would just spawn
/// system_profiler forever for a device it will never find.
var pollClassic = true
if let name = names.first {
    let matches = Classic.matches(name: name)
    if matches.count > 1 {
        usageError("'\(name)' matches \(matches.count) paired devices — be more specific: "
                   + matches.map(\.name).joined(separator: ", "))
    }
    pollClassic = !matches.isEmpty
}

let tracker = Tracker(targetName: names.first, pollClassic: pollClassic)
tracker.start()

Timer.scheduledTimer(withTimeInterval: names.isEmpty ? 1.0 : 0.25, repeats: true) { _ in
    let snapshot = tracker.snapshot()
    Display.render(snapshot, redact: redact)
    clicker?.update(rssi: snapshot.isFresh ? snapshot.live : nil)
}

RunLoop.main.run()
