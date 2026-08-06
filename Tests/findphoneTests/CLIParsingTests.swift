import XCTest
@testable import findphone

final class CLIParsingTests: XCTestCase {
    func testUsageAndHelp() throws {
        let args = ["--help"]
        let parsed = try parseArguments(args[0...])
        XCTAssertTrue(parsed.wantsHelp)
        XCTAssertNil(parsed.targetName)
    }

    func testSurveyMode() throws {
        let parsed = try parseArguments(ArraySlice<String>([]))
        XCTAssertNil(parsed.targetName)
        XCTAssertFalse(parsed.wantsList)
        XCTAssertFalse(parsed.wantsSelect)
        XCTAssertFalse(parsed.wantsSound)
    }

    func testHuntMode() throws {
        let parsed = try parseArguments(["iphone"][0...])
        XCTAssertEqual(parsed.targetName, "iphone")
        XCTAssertFalse(parsed.wantsSelect)
        XCTAssertFalse(parsed.wantsList)
        XCTAssertFalse(parsed.wantsSound)
    }

    func testListModePreservesNames() throws {
        let parsed = try parseArguments(["--list"][0...])
        XCTAssertTrue(parsed.wantsList)
        XCTAssertNil(parsed.targetName)
    }

    func testSelectModeRequiresNoName() {
        XCTAssertThrowsError(try parseArguments(["--select", "iphone"][0...])) { error in
            XCTAssertEqual(error as? ParseError, ParseError.selectWithName)
        }
    }

    func testSoundRequiresTargetOrSelect() {
        XCTAssertThrowsError(try parseArguments(["--sound"][0...])) { error in
            XCTAssertEqual(error as? ParseError, ParseError.missingNameForSound)
        }
        XCTAssertNoThrow(try parseArguments(["--sound", "phone"][0...]))
        XCTAssertNoThrow(try parseArguments(["--sound", "--select"][0...]))
    }

    func testUnknownFlag() {
        XCTAssertThrowsError(try parseArguments(["--unknown"][0...])) { error in
            XCTAssertEqual(error as? ParseError, ParseError.unknownFlag("--unknown"))
        }
    }

    func testTooManyNames() {
        XCTAssertThrowsError(try parseArguments(["phone", "watch"][0...])) { error in
            if case .tooManyNames = error as? ParseError {
                // pass
            } else {
                XCTFail("Expected too many names")
            }
        }
    }

    func testSelectAndListConflict() {
        XCTAssertThrowsError(try parseArguments(["--select", "--list"][0...])) { error in
            XCTAssertEqual(error as? ParseError, ParseError.selectWithList)
        }
    }
}
