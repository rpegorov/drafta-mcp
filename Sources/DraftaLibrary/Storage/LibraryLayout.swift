import Foundation

/// Pure path math for the on-disk Drafta library layout.
///
/// A library `root` directory contains `library.json`, `notes/<uuid>.md`,
/// `revisions/<note-uuid>/<ms>.md`, and folders the app keeps for itself
/// (`attachments/`, `themes/`, sidecar JSON files) that this package never
/// touches. This type performs **no file IO** — it only computes URLs relative
/// to `root`.
///
/// The UUID in a file name is upper-case, as `UUID.uuidString` writes it and as
/// `NoteDirectoryStore` and `RevisionDirectoryStore` put it on disk.
public struct LibraryLayout: Sendable {
    /// The library root directory. All other URLs are derived from this.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Top-level locations

    /// The library index: `root/library.json`.
    public var libraryIndexURL: URL {
        root.appendingPathComponent("library.json")
    }

    /// The notes directory: `root/notes`.
    public var notesDirectory: URL {
        root.appendingPathComponent("notes")
    }

    /// The revisions directory: `root/revisions`.
    public var revisionsDirectory: URL {
        root.appendingPathComponent("revisions")
    }
}
