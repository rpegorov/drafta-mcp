import Foundation

/// Pulls `#tags` out of note text.
///
/// A note's tags are not stored — they are derived from the body on every load
/// (`NoteFileCodec` writes no `tags` field). Anything that reads a library and
/// skips this step sees every note as untagged. The rules match the app's.
public enum TagExtraction {

    public struct Result: Sendable {
        /// `#singleword` → `"singleword"`.
        public var simpleTags: [String]
        /// `#A/B/C` → path `["a", "b"]`, leaf `"c"`. The app turns paths into
        /// nested notebooks.
        public var pathTags: [(path: [String], leaf: String)]

        public init(simpleTags: [String] = [], pathTags: [(path: [String], leaf: String)] = []) {
            self.simpleTags = simpleTags
            self.pathTags = pathTags
        }
    }

    /// Negative lookbehind excludes word characters (already part of another
    /// token), `&` (HTML entities), and `/` or `(` (URL fragments like
    /// `.../#group/181` and anchor links `[label](#anchor)`).
    private static let pattern = "(?<![\\w&/(])#([a-zA-Zа-яА-ЯёЁ][a-zA-Z0-9а-яА-ЯёЁ_/]{1,})"

    /// Content with code removed, so a colour literal in a snippet is not read
    /// as a tag. Users hit exactly that: `#f7f7f7` and friends from CSS blocks
    /// turned into tags, and the tag list filled with hex values.
    ///
    /// Fenced blocks (``` and ~~~) and inline spans (`code`) are masked.
    /// Indented (four-space) code blocks are deliberately left alone: the same
    /// indentation inside a list item is ordinary text, and telling the two
    /// apart needs a real Markdown parser.
    private static func masked(_ content: String) -> String {
        var out = ""
        out.reserveCapacity(content.count)
        // The opening fence we are inside, if any.
        var fence: (char: Character, count: Int)?

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }

            if let open = fence {
                if isClosingFence(trimmed, open) { fence = nil }
                out.append("\n")
                continue
            }
            if let open = openingFence(trimmed) {
                fence = open
                out.append("\n")
                continue
            }
            out.append(maskInlineCode(line))
            out.append("\n")
        }
        return out
    }

    /// A fence opener: three or more backticks or tildes at the start of the
    /// line (after indentation).
    private static func openingFence(_ line: Substring) -> (char: Character, count: Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix { $0 == first }.count
        return count >= 3 ? (first, count) : nil
    }

    /// A fence closer: the same character, at least as many of them, and
    /// nothing else on the line but whitespace.
    private static func isClosingFence(_ line: Substring, _ open: (char: Character, count: Int)) -> Bool {
        let run = line.prefix { $0 == open.char }.count
        guard run >= open.count else { return false }
        return line.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// Removes `` `code` `` spans (any run length, matched by an equal run).
    private static func maskInlineCode(_ line: Substring) -> String {
        var out = ""
        var rest = line

        while let start = rest.firstIndex(of: "`") {
            out += rest[rest.startIndex..<start]

            let run = rest[start...].prefix { $0 == "`" }.count
            let after = rest.index(start, offsetBy: run)
            let closer = String(repeating: "`", count: run)

            if let end = rest.range(of: closer, range: after..<rest.endIndex) {
                rest = rest[end.upperBound...]
            } else {
                // Unmatched run: keep the rest verbatim.
                out += rest[start...]
                rest = rest[rest.endIndex...]
            }
        }
        out += rest
        return out
    }

    public static func parse(_ content: String) -> Result {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return Result() }

        let scanned = masked(content)
        let range = NSRange(scanned.startIndex..., in: scanned)
        var simpleTags: [String] = []
        var pathTags: [(path: [String], leaf: String)] = []
        var seen = Set<String>()

        for match in regex.matches(in: scanned, range: range) {
            guard let r = Range(match.range(at: 1), in: scanned) else { continue }
            let raw = String(scanned[r]).lowercased()
            guard seen.insert(raw).inserted else { continue }

            let parts = raw.components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if parts.count >= 2, let leaf = parts.last {
                pathTags.append((path: Array(parts.dropLast()), leaf: leaf))
            } else {
                simpleTags.append(raw)
            }
        }
        return Result(simpleTags: simpleTags, pathTags: pathTags)
    }

    /// The tags a note carries: simple ones plus the last segment of each path.
    public static func tags(in content: String) -> [String] {
        let result = parse(content)
        var seen = Set<String>()
        return (result.simpleTags + result.pathTags.map(\.leaf))
            .filter { seen.insert($0).inserted }
    }

    /// Everything a loaded note should report as its tags: those written in the
    /// body plus those attached separately.
    public static func allTags(content: String, extraTags: [String]) -> [String] {
        Array(Set(tags(in: content) + extraTags)).sorted()
    }
}
