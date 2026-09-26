import XCTest
@testable import DraftaLibrary

/// Golden tests for the on-disk library format.
///
/// The format has more than one reader and writer: the Drafta app and this
/// server. A format with two writers drifts silently; these fixtures are the
/// contract, not a snapshot of whatever the encoder happens to emit.
///
/// The strings here are the encoder's exact output, byte for byte — including
/// the field order, because a reader written against this must not depend on
/// YAML key order but a writer changing it should be a deliberate, visible
/// change.
final class LibraryFormatGoldenTests: XCTestCase {

    private let noteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let notebookID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!

    // MARK: - Note file

    private static let fullNoteFixture = """
    ---
    id: 11111111-2222-3333-4444-555555555555
    title: Своё имя
    schemaVersion: 1
    createdAt: "2023-11-14T22:13:20.123Z"
    updatedAt: "2023-11-14T22:13:21.500Z"
    customTitle: Своё имя
    notebookId: 66666666-7777-8888-9999-AAAAAAAAAAAA
    status: active
    pinned: true
    extraTags: [design]
    isTemplate: true
    ---
    # SPEC — пример

    Тело с #тегом и `кодом`.

    """

    private func fullNote() -> Note {
        var note = Note(
            id: noteID,
            title: "SPEC — пример",
            content: "# SPEC — пример\n\nТело с #тегом и `кодом`.\n",
            extraTags: ["design"],
            status: .active,
            isTemplate: true
        )
        note.isPinned = true
        note.customTitle = "Своё имя"
        note.notebookId = notebookID
        note.createdAt = Date(timeIntervalSince1970: 1_700_000_000.123)
        note.updatedAt = Date(timeIntervalSince1970: 1_700_000_001.5)
        return note
    }

    func testFullNoteMatchesTheSpecifiedBytes() {
        XCTAssertEqual(NoteFileCodec.encode(fullNote()), Self.fullNoteFixture)
    }

    func testDecodingTheFixtureRestoresEveryField() throws {
        let note = try XCTUnwrap(try NoteFileCodec.decode(Self.fullNoteFixture))

        XCTAssertEqual(note.id, noteID)
        XCTAssertEqual(note.customTitle, "Своё имя")
        XCTAssertEqual(note.notebookId, notebookID)
        XCTAssertEqual(note.status, .active)
        XCTAssertTrue(note.isPinned)
        XCTAssertTrue(note.isTemplate)
        XCTAssertEqual(note.extraTags, ["design"])
        XCTAssertEqual(note.createdAt, Date(timeIntervalSince1970: 1_700_000_000.123))
        XCTAssertEqual(note.updatedAt, Date(timeIntervalSince1970: 1_700_000_001.5))
        XCTAssertEqual(note.content, "# SPEC — пример\n\nТело с #тегом и `кодом`.\n")
    }

    /// The format's most surprising rule: `tags` is never written to YAML. Tags
    /// are derived from the body on load, and a second reader that expects a
    /// `tags` field sees every note as untagged.
    func testTagsComeFromTheBodyAndAreNeverStored() throws {
        let note = try XCTUnwrap(try NoteFileCodec.decode(Self.fullNoteFixture))

        XCTAssertFalse(
            Self.fullNoteFixture.contains("\ntags:"),
            "the encoder must not write a tags field"
        )
        XCTAssertEqual(note.tags, [], "the file carries no tags")
        XCTAssertEqual(
            TagExtraction.tags(in: note.content),
            ["тегом"],
            "the body is where tags come from"
        )
        XCTAssertEqual(
            TagExtraction.allTags(content: note.content, extraTags: note.extraTags),
            ["design", "тегом"],
            "extraTags is the one field that does store tags"
        )
    }

    /// The smallest file the format allows: required fields only. Every optional
    /// field is absent, and decoding must still produce a usable note.
    func testMinimalNoteOmitsEveryOptionalField() throws {
        var note = Note(id: noteID, title: "Минимум", content: "# Минимум\n\nАбзац.\n", status: .none)
        note.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        note.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let fixture = """
        ---
        id: 11111111-2222-3333-4444-555555555555
        title: Минимум
        schemaVersion: 1
        createdAt: "2023-11-14T22:13:20.000Z"
        updatedAt: "2023-11-14T22:13:20.000Z"
        ---
        # Минимум

        Абзац.

        """

        XCTAssertEqual(NoteFileCodec.encode(note), fixture)

        let decoded = try XCTUnwrap(try NoteFileCodec.decode(fixture))
        XCTAssertNil(decoded.customTitle)
        XCTAssertNil(decoded.notebookId)
        XCTAssertNil(decoded.trashedAt)
        XCTAssertEqual(decoded.status, .none)
        XCTAssertFalse(decoded.isPinned)
        XCTAssertFalse(decoded.isTrashed)
        XCTAssertFalse(decoded.isTemplate)
        XCTAssertEqual(decoded.extraTags, [])
        XCTAssertEqual(decoded.bookmarks, [])
    }

    /// Writing always emits milliseconds; reading accepts a timestamp without
    /// them, because another tool or an older build can produce one.
    func testTimestampsWithoutMillisecondsStillParse() throws {
        let fixture = """
        ---
        id: 11111111-2222-3333-4444-555555555555
        title: Легаси
        schemaVersion: 1
        createdAt: "2023-11-14T22:13:20Z"
        updatedAt: "2023-11-14T22:13:21Z"
        ---
        # Легаси
        """

        let note = try XCTUnwrap(try NoteFileCodec.decode(fixture))
        XCTAssertEqual(note.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(note.updatedAt, Date(timeIntervalSince1970: 1_700_000_001))
    }

    /// A file without `id` or `title` is not a note. Silence here would create a
    /// ghost note with a fresh UUID on every load.
    func testAFileWithoutIdOrTitleIsRejected() throws {
        let noID = """
        ---
        title: Без id
        schemaVersion: 1
        createdAt: "2023-11-14T22:13:20.000Z"
        updatedAt: "2023-11-14T22:13:20.000Z"
        ---
        body
        """
        XCTAssertNil(try NoteFileCodec.decode(noID))

        let noTitle = """
        ---
        id: 11111111-2222-3333-4444-555555555555
        schemaVersion: 1
        createdAt: "2023-11-14T22:13:20.000Z"
        updatedAt: "2023-11-14T22:13:20.000Z"
        ---
        body
        """
        XCTAssertNil(try NoteFileCodec.decode(noTitle))
    }

    // MARK: - Library index

    func testLibraryIndexRoundTripsThroughItsFileFormat() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryIndexFixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let parentID = UUID(uuidString: "0698D88A-06B0-47D6-8665-4BA9259D88A6")!
        let childID = UUID(uuidString: "099DFCD9-9608-48D9-9F43-A837F774E71E")!
        let index = LibraryIndex(
            schemaVersion: LibraryIndex.currentSchemaVersion,
            notebooks: [
                Notebook(id: parentID, name: "Projects", parentId: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
                Notebook(id: childID, name: "Drafta", parentId: parentID, createdAt: Date(timeIntervalSince1970: 1_700_000_001)),
            ],
            lastOpenedNoteId: noteID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let file = LibraryIndexFile(url: LibraryLayout(root: root).libraryIndexURL)
        try file.write(index)
        let loaded = try file.load()

        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.notebooks.count, 2)
        XCTAssertEqual(loaded.notebooks.first { $0.id == childID }?.parentId, parentID)
        XCTAssertEqual(loaded.lastOpenedNoteId, noteID)

        // Written as pretty-printed, sorted JSON so a diff of the file is stable.
        let raw = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertTrue(raw.contains("\n"), "library.json is written pretty-printed")
        let keys = ["createdAt", "lastOpenedNoteId", "notebooks", "schemaVersion", "updatedAt"]
        var cursor = raw.startIndex
        for key in keys {
            guard let range = raw.range(of: "\"\(key)\"", range: cursor..<raw.endIndex) else {
                return XCTFail("\(key) missing from library.json, or out of sorted order")
            }
            cursor = range.upperBound
        }
    }
}
