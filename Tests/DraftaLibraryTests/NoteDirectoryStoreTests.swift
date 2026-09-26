import XCTest
@testable import DraftaLibrary

final class NoteDirectoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: NoteDirectoryStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteDirStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = NoteDirectoryStore(notesDirectory: tempDir.appendingPathComponent("Notes", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWriteThenReadRoundTrip() throws {
        var note = Note(title: "Hello", content: "# Hello\nbody text", status: .active)
        note.createdAt = Date(timeIntervalSince1970: 100)
        note.updatedAt = Date(timeIntervalSince1970: 200)

        try store.write(note)
        let read = try store.read(id: note.id)

        XCTAssertEqual(read.id, note.id)
        XCTAssertEqual(read.title, "Hello")        // derived from body
        XCTAssertEqual(read.content, note.content)
        XCTAssertEqual(read.status, .active)
        XCTAssertEqual(read.createdAt, note.createdAt)
        XCTAssertEqual(read.updatedAt, note.updatedAt)
    }

    func testWriteCreatesMissingDirectory() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.notesDirectory.path))
        try store.write(Note(content: "# A"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.notesDirectory.path))
    }

    func testReadMissingNoteThrows() {
        XCTAssertThrowsError(try store.read(id: UUID()))
    }

    func testLoadAllListsAllNotes() throws {
        let a = Note(content: "# A")
        let b = Note(content: "# B")
        try store.write(a)
        try store.write(b)
        XCTAssertEqual(Set(try store.loadAll().notes.map(\.id)), Set([a.id, b.id]))
    }

    func testLoadAllSortsByUpdatedAtDescending() throws {
        func note(_ body: String, _ updated: TimeInterval) -> Note {
            var n = Note(content: body)
            n.updatedAt = Date(timeIntervalSince1970: updated)
            return n
        }
        let old = note("# Old", 10)
        let mid = note("# Mid", 20)
        let new = note("# New", 30)
        try store.write(old)
        try store.write(mid)
        try store.write(new)

        let all = try store.loadAll().notes
        XCTAssertEqual(all.map(\.id), [new.id, mid.id, old.id])
    }

    func testLoadAllOnEmptyDirectoryReturnsEmpty() throws {
        XCTAssertTrue(try store.loadAll().notes.isEmpty)
    }

    func testInjectedIOIsUsed() throws {
        final class RecordingIO: NoteFileIO {
            var writes = 0
            var reads = 0
            let backing = DefaultNoteFileIO()
            func writeAtomically(_ data: Data, to url: URL) throws {
                writes += 1
                try backing.writeAtomically(data, to: url)
            }
            func read(at url: URL) throws -> Data {
                reads += 1
                return try backing.read(at: url)
            }
        }
        let io = RecordingIO()
        let custom = NoteDirectoryStore(
            notesDirectory: tempDir.appendingPathComponent("Custom", isDirectory: true), io: io)
        let note = Note(content: "# Through custom IO")
        try custom.write(note)
        _ = try custom.read(id: note.id)
        XCTAssertEqual(io.writes, 1)
        XCTAssertEqual(io.reads, 1)
    }
}
