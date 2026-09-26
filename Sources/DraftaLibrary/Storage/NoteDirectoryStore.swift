import Foundation

/// Abstraction over the atomic file read/write primitives a note store needs,
/// so a test can substitute its own.
public protocol NoteFileIO {
    /// Write `data` to `url`, replacing any existing file atomically.
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Read the contents of `url`.
    func read(at url: URL) throws -> Data
}

/// Plain `FileManager`-based IO. Atomic writes via `Data.write(options: .atomic)`.
public struct DefaultNoteFileIO: NoteFileIO {
    public init() {}

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}

/// Errors surfaced by `NoteDirectoryStore`.
public enum NoteDirectoryStoreError: LocalizedError {
    case fileNotFound(UUID)
    case decodeFailed(UUID, Error)
    case writeError(UUID, Error)
    case directoryError(Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let id):
            return "Note file not found: \(id.uuidString)"
        case .decodeFailed(let id, let err):
            return "Failed to decode note \(id.uuidString): \(err.localizedDescription)"
        case .writeError(let id, let err):
            return "Failed to write note \(id.uuidString): \(err.localizedDescription)"
        case .directoryError(let err):
            return "Directory operation failed: \(err.localizedDescription)"
        }
    }
}

/// Persists individual notes to disk as `<uuid>.md` files (YAML front-matter +
/// Markdown body) inside a single directory.
///
/// It knows only a target directory and a `NoteFileIO`; where the library
/// lives is `LibraryLayout`'s business.
public struct NoteDirectoryStore {
    /// Directory that holds the `<uuid>.md` files.
    public let notesDirectory: URL
    private let io: NoteFileIO

    public init(
        notesDirectory: URL,
        io: NoteFileIO = DefaultNoteFileIO()
    ) {
        self.notesDirectory = notesDirectory
        self.io = io
    }

    private func fileURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).md", isDirectory: false)
    }

    // MARK: - Single note

    /// Encode and write a note atomically, creating the directory if needed.
    public func write(_ note: Note) throws {
        let encoded = NoteFileCodec.encode(note)
        guard let data = encoded.data(using: .utf8) else {
            throw NoteDirectoryStoreError.writeError(
                note.id,
                CocoaError(.fileWriteInapplicableStringEncoding))
        }
        do {
            try FileManager.default.createDirectory(
                at: notesDirectory, withIntermediateDirectories: true)
            try io.writeAtomically(data, to: fileURL(for: note.id))
        } catch {
            throw NoteDirectoryStoreError.writeError(note.id, error)
        }
    }

    /// Read and decode a single note by id.
    ///
    /// Throws `NoteFileError.encryptedButLocked` when an earlier app build sealed
    /// the file: a silent nil here would look like a missing note.
    public func read(id: UUID) throws -> Note {
        let data: Data
        do {
            data = try io.read(at: fileURL(for: id))
        } catch {
            throw NoteDirectoryStoreError.fileNotFound(id)
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw NoteDirectoryStoreError.decodeFailed(
                id, CocoaError(.fileReadInapplicableStringEncoding))
        }
        guard let note = try NoteFileCodec.decode(contents) else {
            throw NoteDirectoryStoreError.decodeFailed(
                id, CocoaError(.fileReadCorruptFile))
        }
        return note
    }

    // MARK: - Bulk

    /// Load every readable note in the directory, newest `updatedAt` first.
    ///
    /// Nothing aborts the load — one unreadable file must not hide the other four
    /// hundred. A file sealed by an earlier app build is counted in `skippedSealed` and
    /// left untouched; a file that exists but does not decode is listed in `failed`.
    public func loadAll() throws -> LoadReport {
        var report = LoadReport()
        for id in try noteFileIDs() {
            do {
                report.notes.append(try read(id: id))
            } catch NoteFileError.encryptedButLocked {
                report.skippedSealed += 1
            } catch {
                report.failed.append(id)
            }
        }
        report.notes.sort { $0.updatedAt > $1.updatedAt }
        return report
    }

    /// Ids of the `<uuid>.md` files in the directory, creating it if missing.
    private func noteFileIDs() throws -> [UUID] {
        do {
            try FileManager.default.createDirectory(
                at: notesDirectory, withIntermediateDirectories: true)
        } catch {
            throw NoteDirectoryStoreError.directoryError(error)
        }

        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: notesDirectory, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "md" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw NoteDirectoryStoreError.directoryError(error)
        }

        return fileURLs.compactMap {
            UUID(uuidString: $0.deletingPathExtension().lastPathComponent)
        }
    }
}
