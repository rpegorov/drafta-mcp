import XCTest
@testable import DraftaLibrary

final class RevisionDirectoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RevStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var revisionsDirectory: URL {
        tempDir.appendingPathComponent("Revisions", isDirectory: true)
    }

    private func makeStore(retention: Int = 30) -> RevisionDirectoryStore {
        RevisionDirectoryStore(revisionsDirectory: revisionsDirectory, retentionLimit: retention)
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    /// A revision file as the app would have left it, stamped at `savedAt`.
    private func seed(savedAt: Date, content: String, for note: UUID) throws {
        let dir = revisionsDirectory.appendingPathComponent(note.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let millis = Int64(savedAt.timeIntervalSince1970 * 1000)
        try Data(content.utf8).write(to: dir.appendingPathComponent("\(millis).md"))
    }

    /// A write that fails after the name was reserved leaves no empty revision
    /// behind: retention must not evict a real revision to make room for a
    /// placeholder, and the app must never restore an empty body.
    func testAFailedWriteLeavesNoEmptyRevisionBehind() throws {
        let note = UUID()
        try seed(savedAt: at(10), content: "kept", for: note)
        let failing = RevisionDirectoryStore(revisionsDirectory: revisionsDirectory, retentionLimit: 2, io: RefusingIO())

        XCTAssertThrowsError(try failing.append(content: "lost", for: note, keep: 2))

        XCTAssertEqual(try makeStore().summaries(for: note).map(\.id), ["10000"])
        XCTAssertEqual(try makeStore().allRevisions(for: note).map(\.content), ["kept"])
        let files = try FileManager.default.contentsOfDirectory(atPath: revisionsDirectory.appendingPathComponent(note.uuidString).path)
        XCTAssertEqual(files, ["10000.md"], "the placeholder is gone")
    }

    /// An empty revision file that is nonetheless on disk is not history:
    /// listing and retention both look past it.
    func testAnEmptyRevisionFileIsSkippedByEveryReader() throws {
        let store = makeStore(retention: 1)
        let note = UUID()
        try seed(savedAt: at(10), content: "real", for: note)
        let placeholder = store.revisionsDirectory
            .appendingPathComponent(note.uuidString, isDirectory: true)
            .appendingPathComponent("20000.md")
        try Data().write(to: placeholder)

        XCTAssertEqual(try store.summaries(for: note).map(\.id), ["10000"])
        try store.enforceRetention(for: note)
        XCTAssertEqual(try store.allRevisions(for: note).map(\.content), ["real"],
                       "the placeholder did not count against the limit")
    }

    func testRetentionPrunesOldest() throws {
        let store = makeStore()
        let note = UUID()
        for second in 1...5 {
            try seed(savedAt: at(TimeInterval(second)), content: "r\(second)", for: note)
        }
        try store.append(content: "r6", for: note, keep: 3)

        let revisions = try store.allRevisions(for: note)
        XCTAssertEqual(revisions.map(\.content), ["r4", "r5", "r6"])
    }

    func testListForUnknownNoteIsEmpty() throws {
        XCTAssertTrue(try makeStore().allRevisions(for: UUID()).isEmpty)
    }

    /// A clock that went backwards must not file the newest text as history:
    /// the stamp stays ahead of the newest revision on disk.
    func testAppendStampsAfterTheNewestRevisionWhenTheClockWentBack() throws {
        let store = makeStore()
        let note = UUID()
        let future = Date().addingTimeInterval(3600)
        try seed(savedAt: future, content: "old", for: note)

        let appended = try store.append(content: "new", for: note, keep: 30)

        XCTAssertGreaterThan(appended.savedAt, future)
        XCTAssertEqual(try store.allRevisions(for: note).map(\.content), ["old", "new"])
    }

    func testRetentionLimitIsClampedToAtLeastOne() throws {
        let store = makeStore(retention: 0)
        XCTAssertEqual(store.retentionLimit, 1)
        let note = UUID()
        try store.append(content: "a", for: note, keep: store.retentionLimit)
        try store.append(content: "b", for: note, keep: store.retentionLimit)
        try XCTAssertEqual(store.allRevisions(for: note).map(\.content), ["b"])
    }
}

/// The whole readable history with bodies, for assertions only: production code
/// lists `summaries(for:)` and never reads a body back.
extension RevisionDirectoryStore {
    func allRevisions(for noteId: UUID) throws -> [NoteRevision] {
        let dir = revisionsDirectory.appendingPathComponent(noteId.uuidString, isDirectory: true)
        return try summaries(for: noteId)
            .filter { !$0.isSealed }
            .map { summary in
                let url = dir.appendingPathComponent("\(summary.id).md")
                return NoteRevision(id: UUID(), content: try String(contentsOf: url, encoding: .utf8), savedAt: summary.savedAt)
            }
    }
}

/// A disk that refuses every write, as a full volume or a revoked sandbox does.
private struct RefusingIO: NoteFileIO {
    func writeAtomically(_ data: Data, to url: URL) throws {
        throw CocoaError(.fileWriteVolumeReadOnly)
    }

    func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
