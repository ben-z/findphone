import XCTest
@testable import findphone

final class CandidateSelectionResolverTests: XCTestCase {
    private func candidate(_ identity: String, name: String = "Device") -> Advertiser {
        Advertiser(
            identity: identity,
            name: name,
            peak: -80,
            smoothed: -80,
            types: [],
            last: Date()
        )
    }

    func testQuitSelection() {
        let candidates = [candidate("id-1"), candidate("id-2")]
        let result = CandidateSelectionResolver.resolve(rawInput: "q", candidates: candidates)

        XCTAssertEqual(result, .quit)
    }

    func testValidSelectionReturnsIdentity() {
        let candidates = [candidate("id-1"), candidate("id-2", name: "Phone"), candidate("id-3", name: "Watch")]
        let result = CandidateSelectionResolver.resolve(rawInput: "2", candidates: candidates)

        XCTAssertEqual(result, .selectedIdentity("id-2"))
    }

    func testValidSelectionHonorsDuplicateDisplayNamesByIndex() {
        let candidates = [
            candidate("id-a", name: "Apple Watch"),
            candidate("id-b", name: "Apple Watch"),
            candidate("id-c", name: "Apple Watch")
        ]

        let result = CandidateSelectionResolver.resolve(rawInput: "3", candidates: candidates)
        XCTAssertEqual(result, .selectedIdentity("id-c"))
    }

    func testRejectsOutOfRangeZeroNegativeAndOverCount() {
        let candidates = [candidate("id-1"), candidate("id-2")]

        XCTAssertEqual(CandidateSelectionResolver.resolve(rawInput: "0", candidates: candidates), .invalid)
        XCTAssertEqual(CandidateSelectionResolver.resolve(rawInput: "-1", candidates: candidates), .invalid)
        XCTAssertEqual(CandidateSelectionResolver.resolve(rawInput: "3", candidates: candidates), .invalid)
    }

    func testRejectsNonNumericInput() {
        let candidates = [candidate("id-1"), candidate("id-2")]

        XCTAssertEqual(CandidateSelectionResolver.resolve(rawInput: "abc", candidates: candidates), .invalid)
        XCTAssertEqual(CandidateSelectionResolver.resolve(rawInput: "1.5", candidates: candidates), .invalid)
        XCTAssertEqual(CandidateSelectionResolver.resolve(rawInput: "", candidates: candidates), .invalid)
    }
}
