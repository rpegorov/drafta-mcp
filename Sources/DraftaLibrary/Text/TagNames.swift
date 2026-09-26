import Foundation

/// Tag spellings as they arrive from outside: a tool call, a chat message, a list
/// a person typed.
///
/// A tag is a name, not a string of Markdown: the leading `#` is how it is written
/// in a body, never how it is stored, and `#gamma` in the front matter is a tag
/// nothing will match — the app lowercases and folds every tag it shows. The same
/// goes for a trailing space or a repeated entry: harmless-looking, and a tag the
/// sidebar counts under a different name than the one asked for.
public enum TagNames {

    /// Tags from a comma- or whitespace-separated list.
    ///
    /// This shape exists because clients send it: a parameter the schema declares as
    /// an array of strings is regularly filled with `"audit, drafta"` instead, and
    /// silently dropping it would make `create_note(tags:)` report success with no
    /// tags on the note.
    public static func split(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
    }

    /// The stored spelling of each tag: trimmed, without a leading `#`, empty ones
    /// gone, and no two entries differing only by case.
    ///
    /// The first spelling of a duplicate wins, so a caller that wrote `Drafta` and
    /// `drafta` gets `Drafta` once.
    public static func normalise(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in raw {
            let cleaned = String(tag.trimmingCharacters(in: .whitespacesAndNewlines)
                .drop(while: { $0 == "#" }))
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }
            guard seen.insert(cleaned.lowercased()).inserted else { continue }
            out.append(cleaned)
        }
        return out
    }
}
