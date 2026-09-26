import Foundation

/// Errors surfaced by `RevisionDirectoryStore`.
public enum RevisionDirectoryStoreError: LocalizedError {
    case directoryCreationFailed(UUID, Error)
    case writeFailed(UUID, Error)
    case deleteFailed(UUID, Error)
    case listingFailed(UUID, Error)
    case readFailed(UUID, String, Error)
    /// A retention limit below one would delete the whole history.
    case invalidRetention(Int)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let id, let err):
            return "Failed to create revisions directory for note \(id.uuidString): \(err.localizedDescription)"
        case .writeFailed(let id, let err):
            return "Failed to write revision for note \(id.uuidString): \(err.localizedDescription)"
        case .deleteFailed(let id, let err):
            return "Failed to delete revision for note \(id.uuidString): \(err.localizedDescription)"
        case .listingFailed(let id, let err):
            return "Failed to list revisions of note \(id.uuidString): \(err.localizedDescription)"
        case .readFailed(let id, let revisionID, let err):
            return "Failed to read revision \(revisionID) of note \(id.uuidString): \(err.localizedDescription)"
        case .invalidRetention(let keep):
            return "A note must keep at least one revision, not \(keep)"
        }
    }
}

/// Stores revision history for notes, one directory per note:
/// `<revisionsDirectory>/<noteUUID>/<unix-millis>.md`. Each file holds only the
/// Markdown body; the millisecond filename gives chronological order and is the
/// revision's stable id (`RevisionSummary.id`). The Drafta app reads the same
/// directory to show a note's history.
///
/// This package only appends and prunes: the history is listed from file names
/// and sizes (`summaries(for:)`) and no body is ever read back.
///
/// It knows only a root directory and a `NoteFileIO` (used for atomic writes).
public struct RevisionDirectoryStore {
    /// Root directory holding the per-note revision subdirectories.
    public let revisionsDirectory: URL
    /// Revisions kept per note by default; `append` takes the number to keep
    /// from its caller.
    public let retentionLimit: Int
    private let io: NoteFileIO

    private static let fileExtension = "md"
    private static let millisPerSecond = 1000.0
    /// Rapid saves in the same millisecond nudge the stamp forward this many times at most.
    private static let maxStampCollisionNudges = 5

    public init(
        revisionsDirectory: URL,
        retentionLimit: Int = 30,
        io: NoteFileIO = DefaultNoteFileIO()
    ) {
        self.revisionsDirectory = revisionsDirectory
        self.retentionLimit = max(1, retentionLimit)
        self.io = io
    }

    private func directory(for noteId: UUID) -> URL {
        revisionsDirectory.appendingPathComponent(noteId.uuidString, isDirectory: true)
    }

    private func fileURL(stamp: String, for noteId: UUID) -> URL {
        directory(for: noteId).appendingPathComponent(
            "\(stamp).\(Self.fileExtension)", isDirectory: false)
    }

    // MARK: - Append

    /// Append a new revision and keep at most `keep` readable revisions of the
    /// note, pruning the oldest. `keep` below one throws `invalidRetention` and
    /// writes nothing.
    ///
    /// The stamp is never older than the newest revision on disk: a clock that
    /// went backwards would otherwise file the new text as history.
    @discardableResult
    public func append(content: String, for noteId: UUID, keep: Int) throws -> NoteRevision {
        guard keep >= 1 else { throw RevisionDirectoryStoreError.invalidRetention(keep) }
        let nowMillis = Self.millis(of: Date())
        let newestMillis = try stamps(for: noteId).max() ?? Int64.min
        let millis = newestMillis == Int64.min ? nowMillis : max(nowMillis, newestMillis + 1)
        return try write(millis: millis, content: content, for: noteId, keep: keep)
    }

    private func write(millis requested: Int64, content: String, for noteId: UUID, keep: Int) throws -> NoteRevision {
        guard let data = content.data(using: .utf8) else {
            throw RevisionDirectoryStoreError.writeFailed(
                noteId, CocoaError(.fileWriteInapplicableStringEncoding))
        }

        let dir = directory(for: noteId)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw RevisionDirectoryStoreError.directoryCreationFailed(noteId, error)
        }

        let url = try reserveFile(nearMillis: requested, for: noteId)
        do {
            try io.writeAtomically(data, to: url)
        } catch {
            // The reserved name is an empty file until the body lands; left
            // behind, it would read as a revision that wipes the note. Readers
            // skip an empty file too, for the case where even this fails.
            removePlaceholder(at: url)
            throw RevisionDirectoryStoreError.writeFailed(noteId, error)
        }

        try enforceRetention(for: noteId, limit: keep)
        return NoteRevision(
            id: UUID(), content: content,
            savedAt: Date(timeIntervalSince1970: Double(requested) / Self.millisPerSecond))
    }

    /// Claims a file name for the revision by creating it exclusively, so two
    /// writers landing on the same millisecond never share a file: the loser
    /// sees the name taken and nudges its stamp forward.
    private func reserveFile(nearMillis: Int64, for noteId: UUID) throws -> URL {
        var millis = nearMillis
        var attempts = 0
        while true {
            let url = fileURL(stamp: String(millis), for: noteId)
            do {
                try Data().write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists where attempts < Self.maxStampCollisionNudges {
                millis += 1
                attempts += 1
            } catch {
                throw RevisionDirectoryStoreError.writeFailed(noteId, error)
            }
        }
    }

    /// Best effort after a failed write: the write's own error is the one the
    /// caller gets, and a placeholder that could not be removed is harmless
    /// because every reader ignores an empty revision file.
    private func removePlaceholder(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Reported through the write error the caller is about to receive.
        }
    }

    private static func millis(of date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * millisPerSecond)
    }

    // MARK: - Read

    /// The history of a note without the texts, oldest first.
    ///
    /// Reads only file names, sizes and the first bytes of each file (to flag a
    /// revision sealed by an earlier app build), never a whole body. A note with no
    /// history yet has an empty list; a file whose name is not a millisecond
    /// stamp is not a revision and is ignored, and so is an empty file — a
    /// name reserved by a write that never landed.
    public func summaries(for noteId: UUID) throws -> [RevisionSummary] {
        var summaries: [RevisionSummary] = []
        for millis in try stamps(for: noteId).sorted() {
            // A revision pruned by another writer between the listing and this
            // read is not part of the history any more; it is left out.
            if let summary = try summary(of: fileURL(stamp: String(millis), for: noteId), millis: millis, for: noteId) {
                summaries.append(summary)
            }
        }
        return summaries
    }

    /// The millisecond stamps of the note's revision files, in directory order.
    /// A file whose name is not a stamp is not a revision and is ignored.
    private func stamps(for noteId: UUID) throws -> [Int64] {
        let dir = directory(for: noteId)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            throw RevisionDirectoryStoreError.listingFailed(noteId, error)
        }
        return files
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { Int64($0.deletingPathExtension().lastPathComponent) }
    }

    /// Nil when the file vanished between the listing and this read, or is
    /// empty — a reserved name whose body never landed.
    private func summary(of url: URL, millis: Int64, for noteId: UUID) throws -> RevisionSummary? {
        let stamp = String(millis)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else { return nil }
            return RevisionSummary(
                id: stamp,
                savedAt: Date(timeIntervalSince1970: Double(millis) / Self.millisPerSecond),
                byteCount: size,
                isSealed: try startsWithSealMarker(url))
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        } catch {
            throw RevisionDirectoryStoreError.readFailed(noteId, stamp, error)
        }
    }

    /// Reads only as many bytes as the seal marker has.
    private func startsWithSealMarker(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        let prefix = Result { try handle.read(upToCount: SealedRevision.markerData.count) }
        try handle.close()
        return try prefix.get() == SealedRevision.markerData
    }

    // MARK: - Retention

    /// Prune the oldest readable revisions beyond `limit` (defaults to
    /// `retentionLimit`). Works from file names only; sealed revisions are not
    /// counted and stay on disk. A `limit` below one throws `invalidRetention`.
    public func enforceRetention(for noteId: UUID, limit: Int? = nil) throws {
        let keep = limit ?? retentionLimit
        guard keep >= 1 else { throw RevisionDirectoryStoreError.invalidRetention(keep) }
        let readable = try summaries(for: noteId).filter { !$0.isSealed }
        for summary in readable.dropLast(keep) {
            try removeFile(stamp: summary.id, for: noteId)
        }
    }

    private func removeFile(stamp: String, for noteId: UUID) throws {
        let url = fileURL(stamp: stamp, for: noteId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw RevisionDirectoryStoreError.deleteFailed(noteId, error)
        }
    }
}

/// Recognises a revision file sealed by an earlier build of the app.
///
/// Revision files are raw text with no front matter, so those builds marked a
/// sealed one with a first line of `<!--drafta-sealed:aes-gcm-v1-->` followed by
/// the base64 box. No current build writes the marker; it is recognised only so
/// such a file is neither counted nor pruned by retention.
public enum SealedRevision {
    static let marker = "<!--drafta-sealed:aes-gcm-v1-->"
    static let markerData = Data(marker.utf8)
}
