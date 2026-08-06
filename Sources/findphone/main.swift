import Foundation

private func printUsageAndExit() -> Never {
    print(usageText)
    exit(0)
}

let args = CommandLine.arguments.dropFirst()
let parsed: ParsedArguments

do {
    parsed = try parseArguments(args)
} catch let error as ParseError {
    switch error {
    case .unknownFlag(let flag):
        usageError("unknown option '\(flag)'")
    case .tooManyNames(let count):
        usageError("expected one device name, got \(count)")
    case .selectWithName:
        usageError("--select does not take a device name")
    case .missingNameForSound:
        usageError("--sound needs a device name to track")
    case .selectWithList:
        usageError("--select and --list are mutually exclusive")
    }
} catch {
    usageError("failed to parse arguments")
}

if parsed.wantsHelp {
    printUsageAndExit()
}

if parsed.wantsList {
    Display.list(Classic.devicesByStrength(), redact: parsed.redact)
    exit(0)
}

func runTrackingLoop(redrawInterval: TimeInterval, tracker: Tracker, redact: Bool, clicker: Clicker?) {
    Timer.scheduledTimer(withTimeInterval: redrawInterval, repeats: true) { _ in
        let snapshot = tracker.snapshot()
        Display.render(snapshot, redact: redact)
        let value = snapshot.effectiveFresh ? snapshot.effectiveLive : nil
        clicker?.update(rssi: value)
    }
}

let tracker = Tracker(targetName: parsed.targetName)
tracker.start()

var selectionSession: ManualSelectionSession?

if parsed.wantsSelect {
    selectionSession = ManualSelectionSession(
        tracker: tracker,
        redact: parsed.redact,
        onCompletion: { selectedIdentity in
            selectionSession = nil

            guard let selectedIdentity else {
                print("No selection made.")
                exit(0)
            }

            tracker.setManualSelection(identity: selectedIdentity)

            var clicker: Clicker?
            if parsed.wantsSound {
                clicker = Clicker()
                clicker?.start()
            }

            runTrackingLoop(redrawInterval: 0.25, tracker: tracker, redact: parsed.redact, clicker: clicker)
        }
    )
    selectionSession?.start()
} else {
    var clicker: Clicker?
    if parsed.wantsSound {
        clicker = Clicker()
        if let clicker {
            clicker.start()
        } else {
            FileHandle.standardError.write(Data("findphone: could not open the click sound\n".utf8))
        }
    }

    let renderInterval = parsed.targetName == nil ? 1.0 : 0.25
    runTrackingLoop(redrawInterval: renderInterval, tracker: tracker, redact: parsed.redact, clicker: clicker)
}

RunLoop.main.run()
