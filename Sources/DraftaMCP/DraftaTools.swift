import Foundation
import DraftaLibrary
import MCP

/// The tools this server exposes, and their execution.
///
/// An actor because the MCP server calls handlers concurrently while
/// `LibraryAccess` touches files: serialising here is cheaper than making the
/// library thread-safe for a process that only ever has one client.
actor DraftaTools {
    private let library: LibraryAccess

    init(library: LibraryAccess) {
        self.library = library
    }

    // MARK: - Definitions

    /// Write tools are published only when the library is writable; a call to
    /// one anyway is refused by `LibraryAccess` itself.
    var definitions: [Tool] {
        ToolCatalog.readTools + (library.isReadOnly ? [] : ToolCatalog.writeTools)
    }

    // MARK: - Execution

    func call(name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            switch name {
            case "search_notes":
                let hits = try library.search(
                    query: arguments["query"]?.stringValue ?? "",
                    tag: arguments["tag"]?.stringValue,
                    status: try status(arguments["status"]?.stringValue),
                    notebookID: try resolveNotebook(arguments["notebook"]?.stringValue),
                    limit: max(1, min(arguments["limit"]?.intValue ?? 20, 100))
                )
                return .init(content: [.text(NoteRendering.summaries(hits))])

            case "formatting_guide":
                return .init(content: [.text(FormattingGuide.text)])

            case "read_note":
                let note = try library.note(matching: try requiredString(arguments, "note"))
                return .init(content: [.text(NoteRendering.full(note))])

            case "list_notebooks":
                return .init(content: [.text(NoteRendering.notebooks(try library.notebooks()))])

            case "list_tags":
                let tags = try library.tags()
                return .init(content: [.text(tags.isEmpty ? "No tags." : tags.joined(separator: ", "))])

            case "create_note":
                // Parsed before `create`: a rejected status must leave no note behind.
                let initialStatus = try status(arguments["status"]?.stringValue)
                var note = try library.create(
                    title: try requiredString(arguments, "title"),
                    content: try requiredString(arguments, "content"),
                    notebookID: try resolveNotebook(arguments["notebook"]?.stringValue),
                    tags: try tags(arguments)
                )
                if let initialStatus {
                    note = try library.setStatus(id: note.id, status: initialStatus)
                }
                return .init(content: [.text("Created \"\(note.displayTitle)\" (\(note.id.uuidString)).")])

            case "set_note_status":
                let target = try library.note(matching: try requiredString(arguments, "note"))
                let wanted = try status(try requiredString(arguments, "status")) ?? .none
                let note = try library.setStatus(id: target.id, status: wanted)
                return .init(content: [.text("\"\(note.displayTitle)\" is now \(note.status.label).")])

            case "tag_note":
                let target = try library.note(matching: try requiredString(arguments, "note"))
                let tags = try tags(arguments)
                let note = try library.addTags(id: target.id, tags: tags)
                return .init(content: [.text("\"\(note.displayTitle)\" tags: \(note.tags.joined(separator: ", "))")])

            case "create_notebook":
                let notebook = try library.createNotebook(
                    name: try requiredString(arguments, "name"),
                    parentID: try resolveNotebook(arguments["parent"]?.stringValue)
                )
                return .init(content: [.text("Notebook \"\(notebook.name)\" (\(notebook.id.uuidString)).")])

            case "append_to_note":
                let target = try library.note(matching: try requiredString(arguments, "note"))
                let note = try library.append(id: target.id, text: try requiredString(arguments, "text"))
                return .init(content: [.text("Appended to \"\(note.displayTitle)\" (\(note.id.uuidString)).")])

            case "update_note":
                let target = try library.note(matching: try requiredString(arguments, "note"))
                let note = try library.update(id: target.id, content: try requiredString(arguments, "content"))
                return .init(content: [.text("Updated \"\(note.displayTitle)\" (\(note.id.uuidString)).")])

            case "trash_note":
                let target = try library.note(matching: try requiredString(arguments, "note"))
                let note = try library.trash(id: target.id)
                return .init(content: [.text("Moved \"\(note.displayTitle)\" to the trash.")])

            default:
                return .init(content: [.text("Unknown tool: \(name)")], isError: true)
            }
        } catch {
            return .init(content: [.text(error.localizedDescription)], isError: true)
        }
    }

    // MARK: - Resources

    /// Notes as resources, so a client can pull one in as context without
    /// calling a tool. Capped: a library runs to thousands of notes and the
    /// list is sent whole.
    func noteResources(limit: Int = 200) -> [Resource] {
        let notes = (try? library.search(query: "", limit: limit)) ?? []
        return notes.map { note in
            Resource(
                name: note.displayTitle,
                uri: "drafta://note/\(note.id.uuidString)",
                description: "Drafta note, edited \(NoteRendering.date(note.updatedAt))",
                mimeType: "text/markdown"
            )
        }
    }

    func readResource(uri: String) -> [Resource.Content] {
        let prefix = "drafta://note/"
        guard uri.hasPrefix(prefix),
              let id = UUID(uuidString: String(uri.dropFirst(prefix.count))),
              let note = try? library.note(id: id)
        else {
            return [.text("No note at \(uri)", uri: uri, mimeType: "text/plain")]
        }
        return [.text(NoteRendering.full(note), uri: uri, mimeType: "text/markdown")]
    }

    // MARK: - Argument helpers

    private func requiredString(_ arguments: [String: Value], _ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw ToolError.missingArgument(key)
        }
        return value
    }

    /// The `tags` argument, in either shape a client sends it.
    ///
    /// The schema declares an array of strings, and a model regularly writes a
    /// comma-separated string instead. Reading only `arrayValue` dropped that
    /// without a word: `create_note(tags: "audit, drafta")` would answer
    /// "Created …" with no `extraTags` in the file. A value that is neither shape
    /// is an error rather than an empty list, for the same reason: a dropped
    /// argument that reports success is the bug, not the tag.
    private func tags(_ arguments: [String: Value]) throws -> [String] {
        guard let value = arguments["tags"] else { return [] }

        if let array = value.arrayValue {
            guard array.allSatisfy({ $0.stringValue != nil }) else {
                throw ToolError.invalidArgument("tags")
            }
            return TagNames.normalise(array.compactMap(\.stringValue))
        }
        if let text = value.stringValue {
            return TagNames.normalise(TagNames.split(text))
        }
        throw ToolError.invalidArgument("tags")
    }

    /// Accepts a notebook id or a name; nil means "the Inbox", which
    /// `LibraryAccess` resolves.
    private func resolveNotebook(_ identifier: String?) throws -> UUID? {
        guard let identifier, !identifier.isEmpty else { return nil }
        if let id = UUID(uuidString: identifier) { return id }

        let match = try library.notebooks().first {
            $0.name.compare(identifier, options: .caseInsensitive) == .orderedSame
        }
        guard let match else { throw ToolError.unknownNotebook(identifier) }
        return match.id
    }

    /// Parses a status name. Rejects an unknown one rather than silently
    /// filing the note under "no status" — a bug quietly marked wrong is worse
    /// than an error the caller can read.
    private func status(_ raw: String?) throws -> NoteStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalised = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = NoteStatus.allCases.first(where: {
            $0.rawValue.lowercased() == normalised || $0.label.lowercased() == normalised
        }) else {
            throw ToolError.unknownStatus(raw)
        }
        return match
    }

    enum ToolError: LocalizedError {
        case missingArgument(String)
        case unknownNotebook(String)
        case unknownStatus(String)
        case invalidArgument(String)

        var errorDescription: String? {
            switch self {
            case .missingArgument(let key): return "Missing required argument: \(key)"
            case .unknownNotebook(let name): return "No notebook named \(name)"
            case .unknownStatus(let name):
                let known = NoteStatus.allCases.map(\.rawValue).joined(separator: ", ")
                return "Unknown status \"\(name)\". One of: \(known)"
            case .invalidArgument(let key):
                return """
                    Invalid \(key): expected an array of strings (or a comma-separated \
                    string). Nothing was written.
                    """
            }
        }
    }
}
