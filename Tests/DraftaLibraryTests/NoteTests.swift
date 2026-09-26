import XCTest
@testable import DraftaLibrary

final class NoteTests: XCTestCase {
    func testDisplayTitlePrefersCustomThenTitleThenUntitled() {
        var n = Note(title: "Auto")
        XCTAssertEqual(n.displayTitle, "Auto")
        n.customTitle = "Custom"
        XCTAssertEqual(n.displayTitle, "Custom")
        n.customTitle = ""
        XCTAssertEqual(n.displayTitle, "Auto")
        XCTAssertEqual(Note(title: "").displayTitle, "Untitled")
    }

    func testCodableRoundTrip() throws {
        var note = Note(title: "T", content: "body", tags: ["a"], status: .active)
        note.bookmarks = [Bookmark(anchor: BookmarkAnchor(lineText: "L", lineNumber: 1), name: "B")]
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded, note)
    }

    func testBackwardCompatibleDecodeFillsMissingFields() throws {
        // Minimal legacy payload lacking the fields added over time.
        let json = """
        {"id":"\(UUID().uuidString)","title":"Old","content":"c","tags":[],
         "createdAt":0,"updatedAt":0}
        """
        let decoder = JSONDecoder()
        let note = try decoder.decode(Note.self, from: Data(json.utf8))
        XCTAssertEqual(note.title, "Old")
        XCTAssertEqual(note.status, .none)
        XCTAssertFalse(note.isPinned)
        XCTAssertTrue(note.extraTags.isEmpty)
        XCTAssertTrue(note.bookmarks.isEmpty)
    }

    func testNoteStatusLabels() {
        XCTAssertEqual(NoteStatus.onHold.label, "On Hold")
        XCTAssertEqual(NoteStatus.allCases.count, 5)
    }

    func testNoteRevisionExplicitInit() {
        let id = UUID()
        let rev = NoteRevision(id: id, content: "x", savedAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(rev.id, id)
        XCTAssertEqual(rev.savedAt, Date(timeIntervalSince1970: 10))
    }
}
