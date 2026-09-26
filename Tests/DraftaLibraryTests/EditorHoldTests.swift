import XCTest
import Foundation
@testable import DraftaLibrary

/// The contract behind the editor-hold record: a writer must be able to learn
/// that the app is holding unsaved text for a note, and must not stay blocked by a
/// record left behind by an app that is gone.
final class EditorHoldTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRoundTripsTheNotesItNames() throws {
        let id = UUID()
        try EditorHold(pid: getpid(), noteIds: [id]).write(inLibrary: root)

        let loaded = try XCTUnwrap(EditorHold.load(fromLibrary: root))

        XCTAssertEqual(loaded.pid, getpid())
        XCTAssertEqual(loaded.heldNoteIDs(), [id])
    }

    func testAMissingRecordHoldsNothing() {
        XCTAssertNil(EditorHold.load(fromLibrary: root))
        XCTAssertTrue(EditorHold.load(fromLibrary: root)?.heldNoteIDs().isEmpty ?? true)
    }

    func testARecordFromAProcessThatIsGoneHoldsNothing() throws {
        // Pids on macOS are capped well below this, so no process can own it.
        try EditorHold(pid: 99_999_999, noteIds: [UUID()]).write(inLibrary: root)

        let loaded = try XCTUnwrap(EditorHold.load(fromLibrary: root))

        XCTAssertFalse(loaded.processIsAlive)
        XCTAssertTrue(loaded.heldNoteIDs().isEmpty,
                      "a record nobody can clear must not block writes forever")
    }

    func testAnUndecodableRecordIsTreatedAsAbsent() throws {
        try Data("not json".utf8).write(to: EditorHold.url(inLibrary: root))

        XCTAssertNil(EditorHold.load(fromLibrary: root))
    }
}
