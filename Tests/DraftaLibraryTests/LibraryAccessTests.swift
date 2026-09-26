import XCTest
import Foundation
@testable import DraftaLibrary

/// `LibraryAccess` is the door the MCP server writes through. The contract it
/// has to keep is not "the file appeared" but "the app cannot tell who wrote
/// it": the note belongs to a notebook and the previous text survives as a
/// revision.
///
/// Every test builds its own library under `temporaryDirectory/<uuid>` and
/// passes that root in explicitly. `LibraryAccess.defaultRoot` must never be
/// used here — the real library has the user's notes in it.
final class LibraryAccessTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Guard rail: a bug in path math must not point the suite at the real library.
        XCTAssertNotEqual(root.standardizedFileURL, LibraryAccess.defaultRoot.standardizedFileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    /// Writes `library.json` with no notebooks — a library the app has opened
    /// but that has no Inbox yet.
    private func makeEmptyIndex() throws {
        try LibraryIndexFile(url: root.appendingPathComponent("library.json"))
            .write(LibraryIndex.empty())
    }

    /// Stores built the way the app builds them, pointed at the same root.
    /// Constructed fresh on every call so assertions read disk, not a cache.
    private var appNotes: NoteDirectoryStore {
        NoteDirectoryStore(notesDirectory: root.appendingPathComponent("notes"))
    }
    /// The revision bodies of a note, oldest first, read straight from
    /// `revisions/<uuid>/<ms>.md` the way the app lists them.
    private func revisionTexts(of id: UUID) throws -> [String] {
        let dir = root.appendingPathComponent("revisions").appendingPathComponent(id.uuidString)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .compactMap { url in Int64(url.deletingPathExtension().lastPathComponent).map { ($0, url) } }
            .sorted { $0.0 < $1.0 }
            .map { try String(contentsOf: $0.1, encoding: .utf8) }
    }
    private var appIndex: LibraryIndexFile {
        LibraryIndexFile(url: root.appendingPathComponent("library.json"))
    }

    /// Relative path -> bytes for every regular file under `root`.
    ///
    /// Paths are symlink-resolved on both sides: the enumerator hands back
    /// `/private/var/…` for a `/var/…` root, and an unresolved prefix would be
    /// stripped from nothing, leaving keys nothing could match.
    private func diskSnapshot() throws -> [String: Data] {
        var result: [String: Data] = [:]
        let base = root.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return result }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let path = url.resolvingSymlinksInPath().path
            result[String(path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return result
    }

    private func assertIsAccessError(
        _ error: Error,
        _ expected: LibraryAccess.AccessError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = error as? LibraryAccess.AccessError else {
            return XCTFail("Expected AccessError, got \(error)", file: file, line: line)
        }
        switch (actual, expected) {
        case (.readOnly, .readOnly),
             (.noteNotFound, .noteNotFound),
             (.libraryMissing, .libraryMissing):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }

    // MARK: - Positive

    /// Wiring: a write from the chat has to land in the very files the app
    /// reads. Everything here is asserted through separately constructed
    /// stores — never through the `LibraryAccess` instance that did the
    /// writing — so a write that only lives in memory fails the test.
    func testWritesLandInTheAppsOwnFiles() throws {
        try makeEmptyIndex()
        let access = LibraryAccess(root: root)

        // create
        let created = try access.create(title: "From chat", content: "# From chat\nbody")
        XCTAssertEqual(try appNotes.read(id: created.id).content, "# From chat\nbody",
                       "the note file the app reads must hold the created text")

        // update
        try access.update(id: created.id, content: "# From chat\nbody, edited")
        XCTAssertEqual(try appNotes.read(id: created.id).content, "# From chat\nbody, edited")

        // trash — the note is gone from the app's lists, the file is not
        let trashed = try access.trash(id: created.id)
        XCTAssertTrue(trashed.isTrashed)
        XCTAssertNotNil(trashed.trashedAt)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("notes")
                .appendingPathComponent("\(created.id.uuidString).md").path),
            "trash must not delete the file — the app only flags it")
        XCTAssertTrue(try appNotes.read(id: created.id).isTrashed,
                      "the flag has to be on disk, not only on the returned copy")
        XCTAssertFalse(try access.allNotes().contains { $0.id == created.id })
    }

    /// A note with no notebook is an orphan, reachable only from All Notes.
    /// Creating without one must land in the Inbox, creating that Inbox when
    /// the library has none, and reusing it afterwards.
    func testCreateWithoutNotebookLandsInInboxAndCreatesItOnce() throws {
        // A mistyped path must be refused; a directory with no library.json is
        // just a library nobody has opened yet, and writing the index is how
        // one starts.
        let missing = root.appendingPathComponent("nope", isDirectory: true)
        XCTAssertThrowsError(try LibraryAccess(root: missing).create(title: "x", content: "x")) {
            assertIsAccessError($0, .libraryMissing(missing))
        }
        let bare = try LibraryAccess(root: root).create(title: "Bare", content: "# Bare")
        XCTAssertEqual(try appIndex.load().notebooks.map(\.name), ["Inbox"])
        XCTAssertNotNil(bare.notebookId)

        try makeEmptyIndex()
        XCTAssertTrue(try appIndex.load().notebooks.isEmpty)

        let access = LibraryAccess(root: root)
        let first = try access.create(title: "First", content: "# First")
        let second = try access.create(title: "Second", content: "# Second")

        let inboxes = try appIndex.load().notebooks.filter {
            $0.name.lowercased() == "inbox" && $0.parentId == nil
        }
        XCTAssertEqual(inboxes.count, 1, "the Inbox must be created once and then reused")
        XCTAssertEqual(first.notebookId, inboxes.first?.id)
        XCTAssertEqual(second.notebookId, inboxes.first?.id)
        // And it is on disk in library.json, not only in the returned notes.
        XCTAssertEqual(try appNotes.read(id: first.id).notebookId, inboxes.first?.id)
        XCTAssertEqual(try access.notebooks().count, 1)
    }

    /// An edit without a revision loses the previous text for good.
    func testUpdateKeepsThePreviousTextAsARevisionAndRetitles() throws {
        try makeEmptyIndex()
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Draft", content: "# Draft\noriginal text")

        let updated = try access.update(id: note.id, content: "# Renamed\nnew text")

        let history = try revisionTexts(of: note.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first, "# Draft\noriginal text",
                       "the text that was replaced must be recoverable")
        XCTAssertEqual(updated.title, "Renamed", "the title follows the first line")
        XCTAssertEqual(try appNotes.read(id: note.id).displayTitle, "Renamed")
        XCTAssertEqual(try appNotes.read(id: note.id).content, "# Renamed\nnew text")
    }

    /// "Save this into my notes" is usually an append: the existing text has to
    /// survive both in the note and in history.
    func testAppendKeepsTheOriginalText() throws {
        try makeEmptyIndex()
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Log", content: "# Log\nfirst entry")

        let appended = try access.append(id: note.id, text: "second entry")

        XCTAssertEqual(appended.content, "# Log\nfirst entry\n\nsecond entry")
        XCTAssertEqual(try appNotes.read(id: note.id).content, "# Log\nfirst entry\n\nsecond entry")
        try XCTAssertEqual(revisionTexts(of: note.id).first, "# Log\nfirst entry")
    }

    // MARK: - Negative

    /// A miss has to be an error the caller can report, not an empty result the
    /// caller silently treats as "nothing to do".
    func testNoteMatchingUnknownIdentifierThrows() throws {
        try makeEmptyIndex()
        let access = LibraryAccess(root: root)
        try access.create(title: "Present", content: "# Present")

        XCTAssertThrowsError(try access.note(matching: UUID().uuidString)) {
            assertIsAccessError($0, .noteNotFound(""))
        }
        XCTAssertThrowsError(try access.note(matching: "No such title")) {
            assertIsAccessError($0, .noteNotFound(""))
        }
        XCTAssertThrowsError(try access.note(matching: "")) {
            assertIsAccessError($0, .noteNotFound(""))
        }
        XCTAssertThrowsError(try access.note(id: UUID())) {
            assertIsAccessError($0, .noteNotFound(""))
        }
    }

    /// Read-only is a promise about the disk, not about the return value: after
    /// four refused writes the library must be byte-for-byte what it was.
    func testReadOnlyRefusesEveryWriteAndLeavesNoTrace() throws {
        try makeEmptyIndex()
        let seeded = try LibraryAccess(root: root).create(title: "Seed", content: "# Seed\ntext")

        let before = try diskSnapshot()
        // The comparison below is only worth anything if the snapshot sees files.
        XCTAssertEqual(Set(before.keys), [
            "/library.json",
            "/notes/\(seeded.id.uuidString).md",
        ])

        let access = LibraryAccess(root: root, readOnly: true)

        XCTAssertThrowsError(try access.create(title: "New", content: "# New")) {
            assertIsAccessError($0, .readOnly)
        }
        XCTAssertThrowsError(try access.update(id: seeded.id, content: "# Overwritten")) {
            assertIsAccessError($0, .readOnly)
        }
        XCTAssertThrowsError(try access.append(id: seeded.id, text: "more")) {
            assertIsAccessError($0, .readOnly)
        }
        XCTAssertThrowsError(try access.trash(id: seeded.id)) {
            assertIsAccessError($0, .readOnly)
        }

        // Reading still works, and nothing on disk moved.
        XCTAssertEqual(try access.note(id: seeded.id).content, "# Seed\ntext")
        XCTAssertEqual(try diskSnapshot(), before,
                       "a read-only server must leave no note or revision behind")
    }

    /// Re-saving identical text is what an editor does constantly; every such
    /// save must not push a duplicate out of the retention window.
    func testUpdateWithIdenticalContentAddsNoRevision() throws {
        try makeEmptyIndex()
        let access = LibraryAccess(root: root)
        let note = try access.create(title: "Stable", content: "# Stable\nv1")

        try access.update(id: note.id, content: "# Stable\nv2")   // one real edit
        try access.update(id: note.id, content: "# Stable\nv2")   // no-op saves
        try access.update(id: note.id, content: "# Stable\nv2")

        try XCTAssertEqual(revisionTexts(of: note.id).count, 1)
        try XCTAssertEqual(revisionTexts(of: note.id).first, "# Stable\nv1")
    }

    /// An empty query is what an agent sends when it wants "the recent notes";
    /// it must not throw and must not dump the whole library past `limit`.
    func testEmptySearchDoesNotThrowAndRespectsLimit() throws {
        try makeEmptyIndex()
        let access = LibraryAccess(root: root)
        for i in 1...3 { try access.create(title: "N\(i)", content: "# N\(i)\nbody") }

        XCTAssertEqual(try access.search(query: "", limit: 10).count, 3)
        XCTAssertEqual(try access.search(query: "   \n ", limit: 10).count, 3,
                       "whitespace is an empty query, not a needle")
        XCTAssertEqual(try access.search(query: "", limit: 2).count, 2)
        XCTAssertTrue(try access.search(query: "", limit: 0).isEmpty)
        // A needle honours the limit too, and misses return nothing rather than everything.
        XCTAssertEqual(try access.search(query: "body", limit: 1).count, 1)
        XCTAssertTrue(try access.search(query: "nothing matches this", limit: 10).isEmpty)
    }
}
