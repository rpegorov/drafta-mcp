import Foundation
import DraftaLibrary

/// Turns notes into the text an assistant reads.
///
/// Search results carry an excerpt rather than the whole body: a client pulling
/// twenty full notes into context spends the budget it was given for finding the
/// right one.
enum NoteRendering {

    static func summaries(_ notes: [Note]) -> String {
        guard !notes.isEmpty else { return "No matching notes." }

        return notes.map { note in
            var line = "• \(note.displayTitle) — \(note.id.uuidString)"
            if !note.tags.isEmpty {
                line += "\n  tags: \(note.tags.joined(separator: ", "))"
            }
            line += "\n  edited: \(date(note.updatedAt))"
            let excerpt = excerpt(of: note.content)
            if !excerpt.isEmpty {
                line += "\n  \(excerpt)"
            }
            return line
        }
        .joined(separator: "\n\n")
    }

    static func full(_ note: Note) -> String {
        var header = "# \(note.displayTitle)\n\nid: \(note.id.uuidString)\n"
        if !note.tags.isEmpty {
            header += "tags: \(note.tags.joined(separator: ", "))\n"
        }
        header += "edited: \(date(note.updatedAt))\n\n---\n\n"
        return header + note.content
    }

    static func notebooks(_ notebooks: [Notebook]) -> String {
        guard !notebooks.isEmpty else { return "No notebooks yet." }

        // Children under their parent, so the shape of the sidebar survives the
        // trip into a flat list.
        let roots = notebooks.filter { $0.parentId == nil }
        var lines: [String] = []
        for root in roots.sorted(by: { $0.name < $1.name }) {
            lines.append("• \(root.name) — \(root.id.uuidString)")
            let children = notebooks
                .filter { $0.parentId == root.id }
                .sorted { $0.name < $1.name }
            for child in children {
                lines.append("    ◦ \(child.name) — \(child.id.uuidString)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Timestamps are rendered in the machine's own time zone with an explicit
    /// offset. Notes store UTC; a reader comparing a bare UTC stamp against
    /// "now" silently reads every note as hours older than it is.
    static func date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withColonSeparatorInTime,
            .withSpaceBetweenDateAndTime,
            .withTimeZone,
            .withColonSeparatorInTimeZone,
        ]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// First meaningful line of the body, trimmed to one screen's worth.
    private static func excerpt(of content: String, limit: Int = 160) -> String {
        let body = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""

        guard body.count > limit else { return body }
        return String(body.prefix(limit)) + "…"
    }
}
