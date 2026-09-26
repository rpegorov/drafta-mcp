import XCTest
@testable import DraftaLibrary

/// The app compares `updatedAt` to tell which copy of a note is newer, so every
/// writer of a note file has to preserve it exactly. These tests pin that down.
final class ISO8601DateCodingTests: XCTestCase {

    /// A timestamp with a sub-second component that whole-second ISO-8601
    /// would silently truncate.
    private let precise = Date(timeIntervalSince1970: 1_754_600_000.123)

    func testStringRoundTripKeepsMilliseconds() throws {
        let text = ISO8601DateCoding.string(from: precise)
        XCTAssertTrue(text.contains(".123"), "expected milliseconds in \(text)")

        let parsed = try XCTUnwrap(ISO8601DateCoding.date(from: text))
        XCTAssertEqual(parsed.timeIntervalSince1970,
                       precise.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testParsesTimestampsWithoutFractionalSeconds() throws {
        // Produced by other tools and older builds; must not fail to parse.
        let parsed = try XCTUnwrap(ISO8601DateCoding.date(from: "2026-08-08T01:00:00Z"))
        XCTAssertEqual(ISO8601DateCoding.string(from: parsed), "2026-08-08T01:00:00.000Z")
    }

    func testRejectsGarbage() {
        XCTAssertNil(ISO8601DateCoding.date(from: "not a date"))
    }
}
