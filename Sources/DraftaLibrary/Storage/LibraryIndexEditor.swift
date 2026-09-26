import Foundation

/// The one owner of read-modify-write on `library.json`.
///
/// The Drafta app and this server change the notebooks of a library from two
/// processes. A write that dumps a whole in-memory array loses whatever another
/// writer put in the file since that array was read. So every change goes through
/// `modify`: read the file, change it, write it back, all under one
/// coordinated write of the URL — `NSFileCoordinator` serialises that against
/// every other coordinated access in this process and any other. Callers
/// change one notebook at a time, never replace the array.
///
/// The IO inside is deliberately plain: a second coordinator on the same URL
/// from within the accessor would wait on the first one forever.
public struct LibraryIndexEditor: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Applies `change` to the index as it is on disk right now and writes
    /// the result — unless the change left the index as it was loaded, in
    /// which case the file is not touched: a write of the same bytes still
    /// wakes every watcher of the library. A library that has no index yet
    /// starts from an empty one, and is written even when left empty.
    public func modify(_ change: (inout LibraryIndex) throws -> Void) throws {
        let file = LibraryIndexFile(url: url, io: DefaultNoteFileIO())
        try coordinatedWrite {
            let loaded: LibraryIndex? = file.exists ? try file.load() : nil
            var index = loaded ?? .empty()
            try change(&index)
            index.notebooks.sort { $0.name < $1.name }
            if let loaded, Self.sameContent(index, loaded) { return }
            try file.write(index)
        }
    }

    /// The fields a `modify` can change; the stamps are the file's own.
    private static func sameContent(_ a: LibraryIndex, _ b: LibraryIndex) -> Bool {
        a.schemaVersion == b.schemaVersion
            && a.notebooks == b.notebooks
            && a.lastOpenedNoteId == b.lastOpenedNoteId
    }

    private func coordinatedWrite(_ body: () throws -> Void) throws {
        var coordinationError: NSError?
        var outcome: Result<Void, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { _ in
            outcome = Result { try body() }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "file coordination did not run"])
        }
        try outcome.get()
    }
}
