import Foundation

// MARK: - NoteRevision

/// A point-in-time snapshot of note content. Revisions are stored separately
/// on disk (`RevisionDirectoryStore`); this is the value a write returns.
public struct NoteRevision: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let content: String
    public let savedAt: Date

    public init(content: String) {
        self.id = UUID()
        self.content = content
        self.savedAt = Date()
    }

    /// Initialize with explicit id and savedAt.
    public init(id: UUID, content: String, savedAt: Date) {
        self.id = id
        self.content = content
        self.savedAt = savedAt
    }
}

// MARK: - Bookmark

/// A named, content-anchored bookmark within a note.
public struct Bookmark: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var anchor: BookmarkAnchor
    public var name: String
    public var createdAt: Date

    public init(id: UUID = UUID(), anchor: BookmarkAnchor, name: String, createdAt: Date = Date()) {
        self.id = id
        self.anchor = anchor
        self.name = name
        self.createdAt = createdAt
    }

    public enum CodingKeys: String, CodingKey {
        case id, anchor, name, createdAt
    }
}

/// Surrounding-line context used to re-locate a bookmark after edits.
public struct BookmarkAnchor: Codable, Hashable, Sendable {
    public var lineText: String
    public var lineNumber: Int
    public var prevLineText: String?
    public var nextLineText: String?

    public init(lineText: String, lineNumber: Int, prevLineText: String? = nil, nextLineText: String? = nil) {
        self.lineText = lineText
        self.lineNumber = lineNumber
        self.prevLineText = prevLineText
        self.nextLineText = nextLineText
    }
}

// MARK: - Note

/// A note as it lives in `notes/<uuid>.md`: every field `NoteFileCodec` reads
/// and writes, plus the derived `tags`. Pure value type with no UI concerns.
public struct Note: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var customTitle: String?   // user-defined title, overrides auto-extracted title
    public var content: String
    public var tags: [String]
    public var extraTags: [String]   // tags added via UI (not extracted from content)
    public var notebookId: UUID?
    public var status: NoteStatus
    public var isPinned: Bool
    public var isTrashed: Bool
    public var trashedAt: Date?
    /// Legacy field: revisions are stored separately on disk. Kept only so the
    /// `Codable` shape matches older JSON; never set.
    public private(set) var revisions: [NoteRevision]
    public var bookmarks: [Bookmark]
    public var isTemplate: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        customTitle: String? = nil,
        content: String = "",
        tags: [String] = [],
        extraTags: [String] = [],
        notebookId: UUID? = nil,
        status: NoteStatus = .none,
        isTemplate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.customTitle = customTitle
        self.content = content
        self.tags = tags
        self.extraTags = extraTags
        self.notebookId = notebookId
        self.status = status
        self.isPinned = false
        self.isTrashed = false
        self.trashedAt = nil
        self.revisions = []
        self.bookmarks = []
        self.isTemplate = isTemplate
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, customTitle, content, tags, extraTags, notebookId
        case status, isPinned, isTrashed, trashedAt, revisions, bookmarks
        case isTemplate, createdAt, updatedAt
    }

    // Backward-compatible decode: old notes lack new fields
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,   forKey: .id)
        title       = try c.decode(String.self, forKey: .title)
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        content     = try c.decode(String.self, forKey: .content)
        tags        = try c.decode([String].self, forKey: .tags)
        extraTags   = try c.decodeIfPresent([String].self, forKey: .extraTags) ?? []
        createdAt   = try c.decode(Date.self,   forKey: .createdAt)
        updatedAt   = try c.decode(Date.self,   forKey: .updatedAt)
        notebookId  = try c.decodeIfPresent(UUID.self,       forKey: .notebookId)
        status      = try c.decodeIfPresent(NoteStatus.self, forKey: .status)     ?? .none
        isPinned    = try c.decodeIfPresent(Bool.self,       forKey: .isPinned)   ?? false
        isTrashed   = try c.decodeIfPresent(Bool.self,       forKey: .isTrashed)  ?? false
        trashedAt   = try c.decodeIfPresent(Date.self,       forKey: .trashedAt)
        revisions   = try c.decodeIfPresent([NoteRevision].self, forKey: .revisions) ?? []
        bookmarks   = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        isTemplate  = try c.decodeIfPresent(Bool.self,       forKey: .isTemplate) ?? false
    }

    /// The name shown in lists and editor titles: a non-empty `customTitle`
    /// wins, then the stored `title`, then a title derived live from the body
    /// (so freshly created in-memory notes — whose `title` the store has not yet
    /// recomputed — still show a sensible name), otherwise "Untitled".
    public var displayTitle: String {
        if let c = customTitle, !c.isEmpty { return c }
        if !title.isEmpty { return title }
        let derived = Note.extractTitle(from: content)
        return derived.isEmpty ? "Untitled" : derived
    }

    /// Derive a title from note body: the first line, trimmed, with a leading
    /// markdown heading marker (`#`, `##`, …) removed. The title is a function
    /// of the body, not stored state — the codec recomputes it on every read.
    public static func extractTitle(from text: String) -> String {
        (text.components(separatedBy: .newlines).first ?? "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
    }
}
