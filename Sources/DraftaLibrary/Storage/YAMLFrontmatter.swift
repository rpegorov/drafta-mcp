import Foundation

// MARK: - YAMLValue

/// A scalar or flow-array value parsed from / written to YAML front-matter.
public enum YAMLValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([String])

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [String]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

// MARK: - YAMLFrontmatter

/// Minimal, dependency-free YAML front-matter engine (the subset Drafta writes:
/// scalars + flow arrays). Matches the app's own writer, so a note round-trips
/// byte-for-byte whichever side wrote it.
public struct YAMLFrontmatter {
    /// Parse YAML front-matter from source.
    /// Returns nil if no valid front-matter found.
    /// Front-matter must start with `---\n` and contain a closing `---\n`.
    public static func parse(_ source: String) -> [String: YAMLValue]? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Must start with `---`
        guard !lines.isEmpty, lines[0] == "---" else {
            return nil
        }

        // Find closing `---`
        var endIdx: Int?
        for i in 1..<lines.count {
            if lines[i] == "---" {
                endIdx = i
                break
            }
        }

        guard let endIdx = endIdx else {
            return nil
        }

        // Parse lines between delimiters
        var result: [String: YAMLValue] = [:]
        for i in 1..<endIdx {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }

            // Find first unquoted `:`
            if let (key, valueStr) = parseKeyValue(line) {
                if let value = parseValue(valueStr) {
                    result[key] = value
                }
            }
        }

        return result
    }

    /// Encode fields into YAML front-matter string.
    /// Preserves order of fields.
    public static func encode(_ fields: [(String, YAMLValue)]) -> String {
        var lines = ["---"]

        for (key, value) in fields {
            let line = encodeField(key: key, value: value)
            lines.append(line)
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }

    /// Strip front-matter from source, return body.
    /// Returns original source if no front-matter found.
    public static func stripFrontmatter(_ source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard !lines.isEmpty, lines[0] == "---" else {
            return source
        }

        var endIdx: Int?
        for i in 1..<lines.count {
            if lines[i] == "---" {
                endIdx = i
                break
            }
        }

        guard let endIdx = endIdx, endIdx + 1 < lines.count else {
            return source
        }

        return lines[(endIdx + 1)...].joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        var inQuotes = false
        var escapeNext = false
        var colonIdx: Int?

        for (i, char) in line.enumerated() {
            if escapeNext {
                escapeNext = false
                continue
            }

            if char == "\\" {
                escapeNext = true
                continue
            }

            if char == "\"" {
                inQuotes.toggle()
                continue
            }

            if !inQuotes && char == ":" {
                colonIdx = i
                break
            }
        }

        guard let colonIdx = colonIdx else {
            return nil
        }

        let key = line[..<line.index(line.startIndex, offsetBy: colonIdx)].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(line.startIndex, offsetBy: colonIdx + 1)...].trimmingCharacters(in: .whitespaces)

        return (key, String(value))
    }

    private static func parseValue(_ str: String) -> YAMLValue? {
        // Boolean
        if str == "true" {
            return .bool(true)
        }
        if str == "false" {
            return .bool(false)
        }

        // Integer
        if let i = Int(str) {
            return .int(i)
        }

        // Flow-style array: [a, b, c]
        if str.hasPrefix("[") && str.hasSuffix("]") {
            let inner = String(str.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty {
                return .array([])
            }
            let items = inner.split(separator: ",").map { item in
                unquoteString(String(item).trimmingCharacters(in: .whitespaces)) ?? String(item).trimmingCharacters(in: .whitespaces)
            }
            return .array(items)
        }

        // String (quoted or unquoted)
        if let unquoted = unquoteString(str) {
            return .string(unquoted)
        }

        return .string(str)
    }

    private static func unquoteString(_ str: String) -> String? {
        if str.hasPrefix("\"") && str.hasSuffix("\"") && str.count >= 2 {
            let content = String(str.dropFirst().dropLast())
            // Unescape
            var result = ""
            var escapeNext = false
            for char in content {
                if escapeNext {
                    switch char {
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default: result.append(char)
                    }
                    escapeNext = false
                } else if char == "\\" {
                    escapeNext = true
                } else {
                    result.append(char)
                }
            }
            return result
        }
        return nil
    }

    private static func encodeField(key: String, value: YAMLValue) -> String {
        let valueStr: String
        switch value {
        case .string(let s):
            valueStr = escapeYAMLString(s)
        case .int(let i):
            valueStr = String(i)
        case .bool(let b):
            valueStr = b ? "true" : "false"
        case .array(let arr):
            let items = arr.map { escapeYAMLString($0) }
            valueStr = "[\(items.joined(separator: ", "))]"
        }
        return "\(key): \(valueStr)"
    }

    /// Quote and escape a string for YAML if needed.
    private static func escapeYAMLString(_ s: String) -> String {
        let specialChars: [Character] = [":", "#", "{", "}", "[", "]", ",", "&", "*", "|", ">", "!", "?", "\"", "'", "\\"]
        let specialLeadChars: [Character] = ["-", "?", ":", ",", " "]
        let reservedWords = ["null", "true", "false", "yes", "no", "on", "off"]

        let needsQuotes = s.isEmpty ||
            specialChars.contains(where: { s.contains($0) }) ||
            s.contains("\n") ||
            s.contains("\r") ||
            s.contains("\t") ||
            specialLeadChars.contains(where: { s.starts(with: String($0)) }) ||
            reservedWords.contains(s.lowercased())

        if !needsQuotes {
            return s
        }

        // Double-quoted with escapes
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        return "\"\(escaped)\""
    }
}
