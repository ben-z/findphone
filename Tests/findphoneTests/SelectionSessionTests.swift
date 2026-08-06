import XCTest
@testable import findphone

final class ManualSelectionSessionTests: XCTestCase {
    private final class SequencedInputReader {
        private let values: [String?]
        private var index = 0
        private let lock = NSLock()
        private var readCalls = 0

        init(_ values: [String?]) {
            self.values = values
        }

        func readLine() -> String? {
            lock.lock()
            defer { lock.unlock() }
            defer { readCalls += 1 }

            guard index < values.count else { return nil }
            let next = values[index]
            index += 1
            return next
        }

        func readCallCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return readCalls
        }
    }

    private final class MutableSnapshotSource {
        private let lock = NSLock()
        private var storedCandidates: [Advertiser]

        init(_ candidates: [Advertiser]) {
            self.storedCandidates = candidates
        }

        func replace(with candidates: [Advertiser]) {
            lock.lock()
            defer { lock.unlock() }
            storedCandidates = candidates
        }

        func snapshot() -> ([Advertiser], Date) {
            lock.lock()
            defer { lock.unlock() }
            return (storedCandidates, Date())
        }
    }

    private final class RenderEventRecorder {
        private let lock = NSLock()
        private(set) var events: [ManualSelectionRenderEvent] = []

        func record(_ event: ManualSelectionRenderEvent) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }

        var capturedEvents: [ManualSelectionRenderEvent] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }
    }

    private func candidate(
        _ identity: String,
        name: String? = "Device",
        peak: Int = -80,
        smoothed: Double = -80,
        types: Set<UInt8> = [],
        last: Date = Date()
    ) -> Advertiser {
        Advertiser(identity: identity, name: name, peak: peak, smoothed: smoothed, types: types, last: last)
    }

    func testSnapshotProviderObservesMutableReplacement() {
        let source = MutableSnapshotSource([])
        XCTAssertTrue(source.snapshot().0.isEmpty)

        source.replace(with: [candidate("id-1")])
        XCTAssertEqual(source.snapshot().0.map(\.identity), ["id-1"])
    }

    func testStartRequestsSingleInputRead() {
        let source = MutableSnapshotSource([candidate("id-1")])
        let reader = SequencedInputReader(["q"])
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { _ in
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.1")
        )

        session.start(automaticRefreshEnabled: false)
        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testStartingTwiceDoesNotQueueSecondInputReader() {
        let source = MutableSnapshotSource([candidate("id-1"), candidate("id-2")])
        let reader = SequencedInputReader(["q", "2"])
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { _ in
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.2")
        )

        session.start(automaticRefreshEnabled: false)
        session.start(automaticRefreshEnabled: false)
        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testInvalidInputSchedulesExactlyOneAdditionalRead() {
        let source = MutableSnapshotSource([candidate("id-1"), candidate("id-2")])
        let reader = SequencedInputReader(["abc", "2"])
        let completion = expectation(description: "session complete")
        var selectedIdentity: String?

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                selectedIdentity = selected
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.3")
        )

        session.start(automaticRefreshEnabled: false)
        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(selectedIdentity, "id-2")
        XCTAssertEqual(reader.readCallCount(), 2)
    }

    func testValidSelectionCompletesExactlyOnce() {
        let source = MutableSnapshotSource([candidate("id-1"), candidate("id-2")])
        let reader = SequencedInputReader(["2", "1"])
        let completion = expectation(description: "session complete")

        var completionCount = 0
        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                completionCount += 1
                XCTAssertEqual(selected, "id-2")
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.4")
        )

        session.start(automaticRefreshEnabled: false)
        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testQuitCompletesOnceAndStopsReading() {
        let source = MutableSnapshotSource([candidate("id-1"), candidate("id-2")])
        let reader = SequencedInputReader(["q", "1"])
        let completion = expectation(description: "session complete")

        var completionCount = 0
        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                completionCount += 1
                XCTAssertNil(selected)
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.5")
        )

        session.start(automaticRefreshEnabled: false)

        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testEOFCompletesOnceAndStopsReading() {
        let source = MutableSnapshotSource([candidate("id-1")])
        let reader = SequencedInputReader([nil, "q"])
        let completion = expectation(description: "session complete")

        var completionCount = 0
        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                completionCount += 1
                XCTAssertNil(selected)
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.6")
        )

        session.start(automaticRefreshEnabled: false)

        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testEmptyCandidateStateCanTransitionToCandidates() {
        let source = MutableSnapshotSource([])
        let reader = SequencedInputReader(["q"])
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { _ in
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.7")
        )

        session.start(automaticRefreshEnabled: false)
        session.refreshAndRender()

        source.replace(with: [candidate("id-1")])
        session.refreshAndRender()

        wait(for: [completion], timeout: 1.0)
        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testDuplicateDisplayNamesResolveByStableIndexOrder() {
        let source = MutableSnapshotSource([
            candidate("id-a", name: "Watch"),
            candidate("id-b", name: "Watch"),
            candidate("id-c", name: "Watch")
        ])
        let reader = SequencedInputReader(["3"])
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                XCTAssertEqual(selected, "id-c")
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.8")
        )

        session.start(automaticRefreshEnabled: false)
        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testSnapshotUsedForResolutionEvenAfterLiveCandidatesChange() {
        let source = MutableSnapshotSource([candidate("id-a"), candidate("id-b")])
        let reader = SequencedInputReader(["2"])
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                XCTAssertEqual(selected, "id-b")
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.9")
        )

        session.start(automaticRefreshEnabled: false)

        source.replace(with: [candidate("id-b"), candidate("id-a")])

        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testCompletionPreventsQueuedInputFromCompletingAgain() {
        let source = MutableSnapshotSource([candidate("id-1"), candidate("id-2")])
        let reader = SequencedInputReader(["2", "1", nil])
        let completion = expectation(description: "session complete")

        var completionCount = 0
        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                XCTAssertEqual(selected, "id-2")
                completionCount += 1
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.10")
        )

        session.start(automaticRefreshEnabled: false)

        wait(for: [completion], timeout: 1.0)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(reader.readCallCount(), 1)
    }

    func testRefreshDoesNotRefreezeOfferWhileInputIsPending() {
        let source = MutableSnapshotSource([candidate("id-a"), candidate("id-b")])
        let reader = SequencedInputReader(["2"])
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                XCTAssertEqual(selected, "id-b")
                completion.fulfill()
            },
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.11")
        )

        session.start(automaticRefreshEnabled: false)

        XCTAssertEqual(session.currentOffer?.map(\.identity), ["id-a", "id-b"])
        source.replace(with: [candidate("id-b"), candidate("id-a")])
        session.refreshAndRender()
        XCTAssertEqual(session.currentOffer?.map(\.identity), ["id-a", "id-b"])

        wait(for: [completion], timeout: 1.0)
    }

    func testWaitingOutputDoesNotRepeatAcrossRefreshes() {
        let source = MutableSnapshotSource([])
        let reader = SequencedInputReader(["q"])
        let events = RenderEventRecorder()

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { _ in },
            onRenderEvent: events.record,
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.12")
        )

        session.start(automaticRefreshEnabled: false)
        session.refreshAndRender()
        session.refreshAndRender()
        session.refreshAndRender()

        XCTAssertEqual(events.capturedEvents.filter { if case .waitingMessage = $0 { return true }; return false }.count, 1)
        XCTAssertGreaterThanOrEqual(reader.readCallCount(), 0)
    }

    func testOfferRenderingDoesNotRepeatWhileInputIsPending() {
        let source = MutableSnapshotSource([candidate("id-a"), candidate("id-b")])
        let reader = SequencedInputReader(["q"])
        let events = RenderEventRecorder()
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { _ in
                completion.fulfill()
            },
            onRenderEvent: events.record,
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.13")
        )

        session.start(automaticRefreshEnabled: false)
        session.refreshAndRender()
        session.refreshAndRender()

        wait(for: [completion], timeout: 1.0)

        let offerCount = events.capturedEvents.filter { if case .offerDisplayed = $0 { return true }; return false }.count
        XCTAssertEqual(offerCount, 1)
    }

    func testInvalidInputPromptsNewOfferFromLatestSnapshot() {
        let source = MutableSnapshotSource([candidate("id-a", peak: -84), candidate("id-b", peak: -70)])
        let reader = SequencedInputReader(["abc", "2"])
        let events = RenderEventRecorder()
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { selected in
                XCTAssertEqual(selected, "id-a")
                completion.fulfill()
            },
            onRenderEvent: events.record,
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.14")
        )

        session.start(automaticRefreshEnabled: false)
        source.replace(with: [candidate("id-b", peak: -70), candidate("id-a", peak: -84)])
        session.refreshAndRender()

        wait(for: [completion], timeout: 1.0)

        let offers = events.capturedEvents.compactMap { event -> [String]? in
            if case .offerDisplayed(let identities, _) = event {
                return identities
            }
            return nil
        }
        XCTAssertGreaterThanOrEqual(offers.count, 2)
        XCTAssertEqual(offers.first, ["id-a", "id-b"])
        XCTAssertEqual(offers[1], ["id-b", "id-a"])
    }

    func testCompletionPreventsFurtherRenderAndInputAfterCompletion() {
        let source = MutableSnapshotSource([candidate("id-a")])
        let reader = SequencedInputReader(["q"])
        let events = RenderEventRecorder()
        let completion = expectation(description: "session complete")

        let session = ManualSelectionSession(
            snapshotProvider: source.snapshot,
            redact: false,
            onCompletion: { _ in
                completion.fulfill()
            },
            onRenderEvent: events.record,
            readInput: { reader.readLine() },
            inputQueue: DispatchQueue(label: "findphone.selection.session.tests.15")
        )

        session.start()
        wait(for: [completion], timeout: 1.0)

        source.replace(with: [candidate("id-b"), candidate("id-c")])
        session.refreshAndRender()
        session.requestInput()

        let waitingEvents = events.capturedEvents.filter { if case .waitingMessage = $0 { return true }; return false }
        let offerEvents = events.capturedEvents.filter { if case .offerDisplayed = $0 { return true }; return false }

        XCTAssertEqual(waitingEvents.count, 0)
        XCTAssertEqual(offerEvents.count, 1)
        XCTAssertEqual(reader.readCallCount(), 1)
    }
}
