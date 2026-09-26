import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The notes the running Drafta app is holding text for that has not reached disk
/// yet — published by the app so another writer can refuse to overwrite them.
///
/// **Why this exists.** The app keeps an editor buffer that can be ahead of the
/// file, and when it is, the app deliberately keeps what the user typed. A body
/// written here while the note is open would be replaced by the app's own copy,
/// and `update_note` would have reported success for a write that did not stick.
///
/// **Why a file and not a lock.** The app and the server are separate processes
/// with no shared channel, and the library directory is the one thing both already
/// agree on. A single small JSON record is enough:
///
///     { "pid": 4711, "noteIds": ["6F95F2D8-…"] }
///
/// **Why the pid makes it safe.** An app that crashes while holding unsaved text
/// leaves the record behind. A reader that finds a pid nobody owns treats the
/// record as gone, so nothing has to time out and a stale file cannot block writes
/// forever.
///
/// This package only reads the record; the app is the only writer.
public struct EditorHold: Codable, Equatable, Sendable {

    /// The process that published the record.
    public var pid: Int32
    /// Notes whose in-memory text is newer than the file.
    public var noteIds: [UUID]

    public static let fileName = "editor-hold.json"

    public init(pid: Int32, noteIds: [UUID]) {
        self.pid = pid
        self.noteIds = noteIds
    }

    public static func url(inLibrary root: URL) -> URL {
        root.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The record on disk, or `nil` when there is none or it cannot be decoded.
    public static func load(fromLibrary root: URL) -> EditorHold? {
        guard let data = try? Data(contentsOf: url(inLibrary: root)) else { return nil }
        return try? JSONDecoder().decode(EditorHold.self, from: data)
    }

    /// Whether the process that wrote the record still exists.
    public var processIsAlive: Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        // `EPERM` means the process exists but is not ours to signal — still alive.
        return errno == EPERM
    }

    /// The notes an external writer must not replace the body of, right now.
    ///
    /// Empty when the record names a process that no longer exists: the app was quit
    /// or killed with unsaved text, and a record nobody can clear must not block
    /// writes forever.
    public func heldNoteIDs() -> Set<UUID> {
        processIsAlive ? Set(noteIds) : []
    }
}
