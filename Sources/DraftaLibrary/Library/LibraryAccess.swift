import Foundation

/// Read and write access to a Drafta library from outside the app.
///
/// The MCP server is the caller: it opens the very same files the app does, so
/// a note written from a chat has to be indistinguishable from one the user
/// typed. Two things make it so, and both are easy to forget when writing
/// `<uuid>.md` by hand:
///
/// 1. a note with no notebook is an orphan — visible only under All Notes — so
///    new notes land in the Inbox, exactly as the app does for its own UI;
/// 2. an edit without a revision loses the previous text for good.
///
/// Not thread-safe by itself: one instance per process, used from one task.
public final class LibraryAccess {

    public enum AccessError: LocalizedError, Equatable {
        case noteNotFound(String)
        case libraryMissing(URL)
        case readOnly
        /// The note is open in the app, which holds text for it that is not on disk
        /// yet, so a body written here would be replaced by the app's own copy.
        case noteOpenInApp(String)

        public var errorDescription: String? {
            switch self {
            case .noteNotFound(let what):
                return "No note matching \(what)"
            case .libraryMissing(let url):
                return "No Drafta library at \(url.path)"
            case .readOnly:
                return "This server is running read-only"
            case .noteOpenInApp(let id):
                return """
                    Note \(id) is open in the Drafta app, which is holding text for it that \
                    is not saved yet. Nothing was written: the app would have replaced it with \
                    what the user has on screen, and that is how a write reported as successful \
                    disappears. Ask the user to save or close the note, then retry — the app \
                    saves by itself within a second of the last keystroke, so a retry usually \
                    succeeds on its own.
                    """
            }
        }
    }

    public let root: URL
    /// When true, every mutating call throws `AccessError.readOnly`.
    public let isReadOnly: Bool

    private let layout: LibraryLayout
    let notes: NoteDirectoryStore
    let revisions: RevisionDirectoryStore
    let index: LibraryIndexFile

    /// - Parameter root: the library directory — the one holding `notes/` and
    ///   `library.json`. Defaults to where the macOS app keeps it.
    public init(root: URL = LibraryAccess.defaultRoot, readOnly: Bool = false) {
        self.root = root
        self.isReadOnly = readOnly
        self.layout = LibraryLayout(root: root)

        self.notes = NoteDirectoryStore(notesDirectory: layout.notesDirectory)
        self.revisions = RevisionDirectoryStore(revisionsDirectory: layout.revisionsDirectory)
        self.index = LibraryIndexFile(url: layout.libraryIndexURL)
    }

    /// The folder under `Application Support` where the Drafta app keeps its library.
    public static let supportFolderName = "Drafta"

    /// `~/Library/Application Support/Drafta/Library` — where the macOS app keeps
    /// the library.
    public static var defaultRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent(supportFolderName, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    public var exists: Bool { index.exists }

    /// The notes the running app is holding unsaved text for, asked of the library
    /// itself on every call.
    ///
    /// Read fresh rather than cached: the app clears a note the moment its autosave
    /// lands, so a cached answer would keep refusing a write the app would now
    /// accept. The record is one small file in the library root, written by the app
    /// only when the set of held notes changes (see `EditorHold`).
    public func notesHeldByEditor() -> Set<UUID> {
        EditorHold.load(fromLibrary: root)?.heldNoteIDs() ?? []
    }

    // MARK: - Reading

    /// Every readable note. A file sealed by an earlier app build is not one of
    /// them (see `NoteDirectoryStore.loadAll`) and is left untouched.
    public func allNotes() throws -> [Note] {
        try notes.loadAll().notes.filter { !$0.isTrashed }.map(Self.withTags)
    }

    public func note(id: UUID) throws -> Note {
        do {
            return Self.withTags(try notes.read(id: id))
        } catch {
            throw AccessError.noteNotFound(id.uuidString)
        }
    }

    /// Fills in the tags a note carries.
    ///
    /// Tags are not stored: `NoteFileCodec` writes none and the app derives
    /// them after loading. A reader that skips this sees every note as
    /// untagged, and tag search returns nothing.
    static func withTags(_ note: Note) -> Note {
        var note = note
        note.tags = TagExtraction.allTags(content: note.content, extraTags: note.extraTags)
        return note
    }

    /// Finds a note by id string or by exact title, in that order. Titles are
    /// not unique, so the newest match wins — that is what "the note I just
    /// worked on" means in practice.
    public func note(matching identifier: String) throws -> Note {
        if let id = UUID(uuidString: identifier), let note = try? note(id: id) {
            return note
        }
        let matches = try allNotes()
            .filter { $0.displayTitle.compare(identifier, options: .caseInsensitive) == .orderedSame }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let note = matches.first else { throw AccessError.noteNotFound(identifier) }
        return note
    }

    public func notebooks() throws -> [Notebook] {
        guard index.exists else { return [] }
        return try index.load().notebooks
    }

    public func tags() throws -> [String] {
        var seen = Set<String>()
        for note in try allNotes() { seen.formUnion(note.tags) }
        return seen.sorted()
    }

    /// Full-text search over titles and bodies, newest first.
    ///
    /// The filters exist for bookkeeping: a library used as a bug and idea
    /// tracker is queried as "open bugs" far more often than by free text.
    ///
    /// A negative `limit` is clamped rather than trusted: it arrives from an
    /// MCP client, and `Array.prefix(-1)` traps — a remote caller must not be
    /// able to kill the process with a number.
    public func search(
        query: String,
        tag: String? = nil,
        status: NoteStatus? = nil,
        notebookID: UUID? = nil,
        limit: Int = 20
    ) throws -> [Note] {
        let limit = max(0, limit)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return try allNotes()
            .filter { note in
                if let tag, !note.tags.contains(where: {
                    $0.compare(tag, options: .caseInsensitive) == .orderedSame
                }) { return false }
                if let status, note.status != status { return false }
                if let notebookID, note.notebookId != notebookID { return false }
                guard !needle.isEmpty else { return true }
                return note.displayTitle.lowercased().contains(needle)
                    || note.content.lowercased().contains(needle)
                    || note.tags.contains { $0.lowercased().contains(needle) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
}
