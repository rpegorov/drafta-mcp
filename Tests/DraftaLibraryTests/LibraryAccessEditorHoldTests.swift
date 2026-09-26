import XCTest
import Foundation
@testable import DraftaLibrary

/// The refusal that makes an external write honest.
///
/// `LibraryAccess` is what `drafta-mcp` writes through. When the app's editor is
/// holding text for a note, the app keeps that text over anything written here — so
/// a call that returns a note is a lie the caller cannot detect. It has to come back
/// as an error the agent can act on instead.
final class LibraryAccessEditorHoldTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertNotEqual(root.standardizedFileURL, LibraryAccess.defaultRoot.standardizedFileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func bodyOnDisk(_ id: UUID) throws -> String {
        let raw = try String(
            contentsOf: root.appendingPathComponent("notes/\(id.uuidString).md"),
            encoding: .utf8)
        guard let closing = raw.range(of: "\n---\n") else { return raw }
        return String(raw[closing.upperBound...])
    }

    // MARK: - Refusal

    func testUpdateIsRefusedWhileTheAppHoldsTheNote() throws {
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Held", content: "# Held\noriginal")
        try EditorHold(pid: getpid(), noteIds: [note.id]).write(inLibrary: root)

        XCTAssertThrowsError(try access.update(id: note.id, content: "# Held\nreplaced")) { error in
            guard case LibraryAccess.AccessError.noteOpenInApp(let id) = error else {
                return XCTFail("expected noteOpenInApp, got \(error)")
            }
            XCTAssertEqual(id, note.id.uuidString)
        }

        XCTAssertTrue(try bodyOnDisk(note.id).contains("original"),
                      "a refused write must not touch the file")
    }

    func testTheRefusalSaysWhatToDoAboutIt() throws {
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Held", content: "# Held\noriginal")
        try EditorHold(pid: getpid(), noteIds: [note.id]).write(inLibrary: root)

        let message = LibraryAccess.AccessError.noteOpenInApp(note.id.uuidString).errorDescription ?? ""

        XCTAssertTrue(message.contains("open in the Drafta app"), message)
        XCTAssertTrue(message.contains("Nothing was written"), message)
        XCTAssertTrue(message.contains("retry"), message)
    }

    func testAppendIsRefusedTooBecauseItReplacesTheBody() throws {
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Held", content: "# Held\noriginal")
        try EditorHold(pid: getpid(), noteIds: [note.id]).write(inLibrary: root)

        XCTAssertThrowsError(try access.append(id: note.id, text: "one more line")) { error in
            guard case LibraryAccess.AccessError.noteOpenInApp = error else {
                return XCTFail("expected noteOpenInApp, got \(error)")
            }
        }
        XCTAssertFalse(try bodyOnDisk(note.id).contains("one more line"))
    }

    func testUpdateLandsOnceTheHoldIsReleased() throws {
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Held", content: "# Held\noriginal")
        try EditorHold(pid: getpid(), noteIds: [note.id]).write(inLibrary: root)
        EditorHold.remove(fromLibrary: root)

        let updated = try access.update(id: note.id, content: "# Held\nreplaced")

        XCTAssertTrue(updated.content.contains("replaced"))
        XCTAssertTrue(try bodyOnDisk(note.id).contains("replaced"))
    }

    /// A record left behind by an app that crashed while holding a note names a pid
    /// nobody owns. The write has to go through: a stale file must not block the
    /// library forever.
    func testAHoldFromADeadProcessDoesNotBlockTheWrite() throws {
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Held", content: "# Held\noriginal")
        try EditorHold(pid: 99_999_999, noteIds: [note.id]).write(inLibrary: root)

        XCTAssertNoThrow(try access.update(id: note.id, content: "# Held\nreplaced"))
        XCTAssertTrue(try bodyOnDisk(note.id).contains("replaced"))
    }

    /// The refusal is about the *body*. A note the editor holds can still be tagged,
    /// filed or marked: those read the file's own text and write it back unchanged.
    func testMetadataWritesAreStillAllowedWhileTheNoteIsHeld() throws {
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Held", content: "# Held\noriginal")
        try EditorHold(pid: getpid(), noteIds: [note.id]).write(inLibrary: root)

        XCTAssertNoThrow(try access.addTags(id: note.id, tags: ["drafta"]))
        XCTAssertNoThrow(try access.setStatus(id: note.id, status: .active))
        XCTAssertTrue(try bodyOnDisk(note.id).contains("original"),
                      "metadata writes must keep the body byte-for-byte")
    }

    func testAHoldOnAnotherNoteIsIrrelevant() throws {
        let access = LibraryAccess(root: root)
        let held = try access.create(title: "Held", content: "# Held\noriginal")
        let free = try access.create(title: "Free", content: "# Free\noriginal")
        try EditorHold(pid: getpid(), noteIds: [held.id]).write(inLibrary: root)

        XCTAssertNoThrow(try access.update(id: free.id, content: "# Free\nreplaced"))
        XCTAssertTrue(try bodyOnDisk(free.id).contains("replaced"))
    }

    // MARK: - Tags on create

    /// The model-facing half of the tag bug: the shapes a client actually sends must
    /// all reach the file as tags. See `TagNames` and `DraftaTools`.
    func testCreateStoresTheTagsItWasGivenInTheStoredSpelling() throws {
        let access = LibraryAccess(root: root)

        let note = try access.create(
            title: "Tagged",
            content: "body",
            tags: ["#audit", " drafta ", "AUDIT", ""])

        XCTAssertEqual(note.extraTags, ["audit", "drafta"])
        let raw = try String(
            contentsOf: root.appendingPathComponent("notes/\(note.id.uuidString).md"),
            encoding: .utf8)
        XCTAssertTrue(raw.contains("extraTags: [audit, drafta]"), raw)
    }
}
