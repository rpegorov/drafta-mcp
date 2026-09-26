import Foundation

/// Codec for encoding/decoding Note to/from file format.
///
/// Format: YAML front-matter + Markdown body, both plaintext. The library on disk
/// is legible to the rest of the system — Quick Look, Spotlight, a person opening
/// the folder in Finder — and to any tool that reads Markdown.
///
/// A file whose front matter declares an `encryption` scheme was sealed by an
/// earlier build of the app. `decode` refuses it with
/// `NoteFileError.encryptedButLocked` so the loader can skip it and leave the
/// bytes untouched.
public struct NoteFileCodec {

    // MARK: - Encode

    /// Encode a Note to file format.
    public static func encode(_ note: Note) -> String {
        encodeFrontmatter(note) + "\n" + note.content
    }

    private static func encodeFrontmatter(_ note: Note) -> String {
        // Determine display title for YAML (use customTitle if set)
        let displayTitle = note.customTitle ?? note.title

        // Build ordered field list
        var fields: [(String, YAMLValue)] = [
            ("id", .string(note.id.uuidString)),
            ("title", .string(displayTitle)),
            ("schemaVersion", .int(1)),
            ("createdAt", .string(iso8601String(note.createdAt))),
            ("updatedAt", .string(iso8601String(note.updatedAt))),
        ]

        // Optional fields (only include if non-default)
        if let customTitle = note.customTitle {
            fields.append(("customTitle", .string(customTitle)))
        }

        if let notebookId = note.notebookId {
            fields.append(("notebookId", .string(notebookId.uuidString)))
        }

        if note.status != .none {
            fields.append(("status", .string(statusString(note.status))))
        }

        if note.isPinned {
            fields.append(("pinned", .bool(true)))
        }

        if note.isTrashed {
            fields.append(("trashed", .bool(true)))
            if let trashedAt = note.trashedAt {
                fields.append(("trashedAt", .string(iso8601String(trashedAt))))
            }
        }

        if !note.extraTags.isEmpty {
            fields.append(("extraTags", .array(note.extraTags)))
        }

        if note.isTemplate {
            fields.append(("isTemplate", .bool(true)))
        }

        if !note.bookmarks.isEmpty,
           let bookmarksData = try? JSONEncoder().encode(note.bookmarks),
           let bookmarksJSON = String(data: bookmarksData, encoding: .utf8) {
            fields.append(("bookmarks", .string(bookmarksJSON)))
        }

        return YAMLFrontmatter.encode(fields)
    }

    /// Refuses a body that an earlier build sealed.
    ///
    /// Thrown rather than returned empty: the ciphertext must never be shown as the
    /// note's text, and a nil here would look like a missing note.
    private static func requirePlaintext(fields: [String: YAMLValue]) throws {
        guard let scheme = NoteEncryptionScheme.declared(in: fields) else { return }
        guard scheme == NoteEncryptionScheme.aesGCMv1 else {
            throw NoteFileError.unsupportedScheme(scheme)
        }
        throw NoteFileError.encryptedButLocked
    }

    /// Decode a Note from file format (YAML front-matter + body).
    ///
    /// Returns nil if the front matter is unusable. Throws when the file *is*
    /// readable but its body is sealed — by a scheme this build knows or by one it
    /// does not — because those are different problems from "corrupt file", and
    /// conflating them is how a sealed note gets overwritten.
    public static func decode(_ contents: String) throws -> Note? {
        // Parse front-matter
        guard let yamlDict = YAMLFrontmatter.parse(contents) else {
            return nil
        }

        // Extract required fields
        guard let idValue = yamlDict["id"],
              let idString = idValue.stringValue,
              let id = UUID(uuidString: idString) else {
            return nil
        }

        // Validate that a title field exists (required for format compliance)
        guard yamlDict["title"]?.stringValue != nil else {
            return nil
        }

        guard let createdAtValue = yamlDict["createdAt"],
              let createdAtString = createdAtValue.stringValue,
              let createdAt = parseISO8601(createdAtString) else {
            return nil
        }

        guard let updatedAtValue = yamlDict["updatedAt"],
              let updatedAtString = updatedAtValue.stringValue,
              let updatedAt = parseISO8601(updatedAtString) else {
            return nil
        }

        // Extract optional fields
        let customTitle = yamlDict["customTitle"]?.stringValue

        let notebookId: UUID?
        if let nbIdValue = yamlDict["notebookId"],
           let nbIdString = nbIdValue.stringValue {
            notebookId = UUID(uuidString: nbIdString)
        } else {
            notebookId = nil
        }

        let status: NoteStatus
        if let statusValue = yamlDict["status"],
           let statusString = statusValue.stringValue {
            status = parseStatus(statusString)
        } else {
            status = .none
        }

        let isPinned = yamlDict["pinned"]?.boolValue ?? false

        let isTrashed = yamlDict["trashed"]?.boolValue ?? false

        let trashedAt: Date?
        if let trashedAtValue = yamlDict["trashedAt"],
           let trashedAtString = trashedAtValue.stringValue {
            trashedAt = parseISO8601(trashedAtString)
        } else {
            trashedAt = nil
        }

        let extraTags = yamlDict["extraTags"]?.arrayValue ?? []

        let isTemplate = yamlDict["isTemplate"]?.boolValue ?? false

        // Decode bookmarks from JSON-encoded string if present
        let bookmarks: [Bookmark]
        if let bookmarksJSONValue = yamlDict["bookmarks"],
           let bookmarksJSON = bookmarksJSONValue.stringValue,
           let bookmarksData = bookmarksJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: bookmarksData) {
            bookmarks = decoded
        } else {
            bookmarks = []
        }

        try requirePlaintext(fields: yamlDict)
        let body = YAMLFrontmatter.stripFrontmatter(contents)

        // Restore title from body content (title is a computed property of body, not stored state).
        // YAML title field is for human readability only; customTitle overrides display separately.
        let derivedTitle = Note.extractTitle(from: body)

        // Create Note
        var note = Note(
            id: id,
            title: derivedTitle,
            customTitle: customTitle,
            content: body,
            tags: [], // Derived from the body by the reader (`LibraryAccess.withTags`)
            extraTags: extraTags,
            notebookId: notebookId,
            status: status,
            isTemplate: isTemplate
        )
        note.bookmarks = bookmarks

        note.createdAt = createdAt
        note.updatedAt = updatedAt
        note.isPinned = isPinned
        note.isTrashed = isTrashed
        note.trashedAt = trashedAt

        return note
    }

    // MARK: - Helpers

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateCoding.string(from: date)
    }

    private static func parseISO8601(_ str: String) -> Date? {
        ISO8601DateCoding.date(from: str)
    }

    private static func statusString(_ status: NoteStatus) -> String {
        switch status {
        case .none: return ""
        case .active: return "active"
        case .onHold: return "onHold"
        case .completed: return "completed"
        case .dropped: return "dropped"
        }
    }

    private static func parseStatus(_ str: String) -> NoteStatus {
        switch str {
        case "active": return .active
        case "onHold": return .onHold
        case "completed": return .completed
        case "dropped": return .dropped
        default: return .none
        }
    }
}
