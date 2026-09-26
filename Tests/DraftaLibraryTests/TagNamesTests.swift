import XCTest
import Foundation
@testable import DraftaLibrary

/// Tag spellings as they arrive from a tool call or a chat message: the app stores
/// a tag name, not the `#tag` spelling and not a pair of entries differing only by
/// case.
final class TagNamesTests: XCTestCase {

    func testSplitAcceptsACommaSeparatedList() {
        XCTAssertEqual(TagNames.split("audit, drafta"), ["audit", "drafta"])
    }

    func testSplitAcceptsWhitespaceAndRepeatedSeparators() {
        XCTAssertEqual(TagNames.split("audit,drafta  bug"), ["audit", "drafta", "bug"])
        XCTAssertEqual(TagNames.split("  "), [])
        XCTAssertEqual(TagNames.split(""), [])
    }

    func testNormaliseStripsTheHashTheSpacesAndEmptyEntries() {
        XCTAssertEqual(
            TagNames.normalise(["#gamma", " delta ", "", "   "]),
            ["gamma", "delta"])
    }

    func testNormaliseKeepsOneSpellingOfADuplicate() {
        XCTAssertEqual(TagNames.normalise(["Drafta", "drafta", "DRAFTA"]), ["Drafta"])
    }
}
