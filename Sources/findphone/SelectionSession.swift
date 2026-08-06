import Foundation

enum ManualSelectionRenderEvent: Equatable {
    case waitingMessage
    case offerDisplayed([String], Date)
    case invalidSelection
}

typealias SelectionInputReader = () -> String?
typealias ManualSelectionRenderEventHandler = (ManualSelectionRenderEvent) -> Void

final class ManualSelectionSession {
    private let readInput: SelectionInputReader
    private let snapshotProvider: () -> ([Advertiser], Date)
    private let redact: Bool
    private let onCompletion: (String?) -> Void
    private let onRenderEvent: ManualSelectionRenderEventHandler
    private let inputQueue: DispatchQueue
    private let renderInterval: TimeInterval

    private var isActive = true
    private var offeredCandidates: [Advertiser]?
    private var refreshTimer: Timer?
    private var isInputPending = false
    private var hasPrintedWaitingMessage = false

    init(
        tracker: Tracker,
        redact: Bool,
        onCompletion: @escaping (String?) -> Void,
        onRenderEvent: @escaping ManualSelectionRenderEventHandler = { _ in },
        readInput: @escaping SelectionInputReader = { readLine(strippingNewline: true) },
        inputQueue: DispatchQueue = DispatchQueue(label: "findphone.selection.input"),
        renderInterval: TimeInterval = 1.0
    ) {
        self.snapshotProvider = {
            let snapshot = tracker.snapshot()
            return (snapshot.candidates, snapshot.at)
        }
        self.redact = redact
        self.onCompletion = onCompletion
        self.onRenderEvent = onRenderEvent
        self.readInput = readInput
        self.inputQueue = inputQueue
        self.renderInterval = renderInterval
    }

    /// Test-only initializer.
    init(
        snapshotProvider: @escaping () -> ([Advertiser], Date),
        redact: Bool,
        onCompletion: @escaping (String?) -> Void,
        onRenderEvent: @escaping ManualSelectionRenderEventHandler = { _ in },
        readInput: @escaping SelectionInputReader = { readLine(strippingNewline: true) },
        inputQueue: DispatchQueue = DispatchQueue(label: "findphone.selection.input"),
        renderInterval: TimeInterval = 1.0
    ) {
        self.snapshotProvider = snapshotProvider
        self.redact = redact
        self.onCompletion = onCompletion
        self.onRenderEvent = onRenderEvent
        self.readInput = readInput
        self.inputQueue = inputQueue
        self.renderInterval = renderInterval
    }

    func start(automaticRefreshEnabled: Bool = true) {
        guard isActive else { return }
        requestInput()
        refreshAndRender()
        guard automaticRefreshEnabled else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: renderInterval, repeats: true) { [weak self] _ in
            self?.refreshAndRender()
        }
    }

    func requestInput() {
        guard isActive, !isInputPending else { return }
        isInputPending = true

        inputQueue.async { [weak self] in
            guard let self else { return }
            let rawInput = self.readInput()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isInputPending = false
                self.handle(input: rawInput)
            }
        }
    }

    func refreshAndRender() {
        guard isActive else { return }

        let (candidates, snapshotAt) = snapshotProvider()

        if offeredCandidates != nil && isInputPending {
            // Keep the displayed offer stable until a matching input resolves or is rejected.
            return
        }

        // If we are not waiting on a selected offer, refresh and render the current state.
        if candidates.isEmpty {
            offeredCandidates = nil
            if !hasPrintedWaitingMessage {
                print("Nearby Apple handhelds — no candidates yet")
                print("Waiting for nearby devices... (or press q to quit)")
                onRenderEvent(.waitingMessage)
                hasPrintedWaitingMessage = true
            }
            return
        }

        offeredCandidates = candidates
        hasPrintedWaitingMessage = false

        print("Nearby Apple handhelds — select one to track:\n")
        for (index, candidate) in candidates.enumerated() {
            let live = Int(candidate.smoothed.rounded())
            let stale = snapshotAt.timeIntervalSince(candidate.last) > 3 ? " (stale)" : ""
            let name = redact ? candidate.kind : candidate.label
            let line = String(format: "%2d. %@ %4d dBm  peak %4d", index + 1, bar(live), live, candidate.peak)
            print("\(line)  \(name)\(stale)")
        }

        print("Select a device number, or q to quit: ", terminator: "")
        onRenderEvent(.offerDisplayed(candidates.map(\.identity), snapshotAt))
    }

    private func handle(input: String?) {
        guard isActive else { return }

        guard let rawInput = input else {
            complete(with: nil)
            return
        }

        guard let offer = offeredCandidates else {
            // Waiting state without an active offer.
            complete(with: nil)
            return
        }

        let outcome = CandidateSelectionResolver.resolve(rawInput: rawInput, candidates: offer)
        switch outcome {
        case .quit:
            complete(with: nil)
        case .invalid:
            print("Invalid selection. Enter 1 through \(offer.count), or q to quit.")
            onRenderEvent(.invalidSelection)
            offeredCandidates = nil
            refreshAndRender()
            requestInput()
        case let .selectedIdentity(identity):
            complete(with: identity)
        }
    }

    private func complete(with identity: String?) {
        guard isActive else { return }
        isActive = false
        isInputPending = false
        offeredCandidates = nil
        refreshTimer?.invalidate()
        onCompletion(identity)
    }

    #if DEBUG
    var currentOffer: [Advertiser]? { offeredCandidates }
    #endif
}
