import Foundation
import MCP

/// The tool declarations, separated from their execution so that neither file
/// grows past reading size.
///
/// Descriptions are written for an assistant that has never seen Drafta: they
/// say what the concept is for, not just what the parameter is called. The
/// library is meant to be used as a source of truth — bugs, ideas, features —
/// so bookkeeping tools (status, tags, notebooks) are first-class here, not
/// afterthoughts.
enum ToolCatalog {

    static func string(_ description: String) -> Value {
        .object(["type": .string("string"), "description": .string(description)])
    }

    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    // MARK: - Reading

    static let readTools: [Tool] = [
        Tool(
            name: "search_notes",
            description: """
            Search the user's Drafta notes. Combine free text with filters: this \
            is how you find "open bugs" or "everything tagged #idea".
            """,
            inputSchema: object([
                "query": string("Words to look for in titles, bodies and tags. Empty returns the most recent notes."),
                "tag": string("Only notes carrying this tag, e.g. bug or drafta/export."),
                "status": string("Only notes with this status: active, onHold, completed, dropped, none."),
                "notebook": string("Only notes in this notebook (name or id)."),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum number of notes to return (default 20).")
                ])
            ])
        ),
        Tool(
            name: "read_note",
            description: "Read one note in full, by id or by exact title.",
            inputSchema: object(
                ["note": string("Note id (UUID) or its exact title.")],
                required: ["note"]
            )
        ),
        Tool(
            name: "list_notebooks",
            description: "List the notebooks, with their hierarchy. Notebooks are how notes are filed.",
            inputSchema: object([:])
        ),
        Tool(
            name: "list_tags",
            description: "List every tag in use across the library.",
            inputSchema: object([:])
        ),
        Tool(
            name: "formatting_guide",
            description: """
            The Markdown Drafta understands: callouts, mermaid diagrams, task \
            lists, tags, wiki links between notes, maths, and how title, \
            notebook and status work. Read this before writing a note, or it \
            will come out as plain unstyled text.
            """,
            inputSchema: object([:])
        )
    ]

    // MARK: - Writing

    static let writeTools: [Tool] = [
        Tool(
            name: "create_note",
            description: """
            Create a note. Without a notebook it goes to the Inbox. Use \
            formatting_guide for what the body can contain.
            """,
            inputSchema: object([
                "title": string("Title. Written into the body as the first heading when it has none."),
                "content": string("Markdown body."),
                "notebook": string("Notebook name or id. Defaults to the Inbox."),
                "tags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Tags to attach, without the leading #.")
                ]),
                "status": string("Initial status: active, onHold, completed, dropped, none.")
            ], required: ["title", "content"])
        ),
        Tool(
            name: "append_to_note",
            description: """
            Append to the end of a note, keeping the previous text as a \
            revision. The usual way to add a finding to an existing note.
            """,
            inputSchema: object([
                "note": string("Note id (UUID) or its exact title."),
                "text": string("Markdown to add at the end.")
            ], required: ["note", "text"])
        ),
        Tool(
            name: "update_note",
            description: "Replace a note's entire body. The previous text is kept as a revision.",
            inputSchema: object([
                "note": string("Note id (UUID) or its exact title."),
                "content": string("The new Markdown body, in full.")
            ], required: ["note", "content"])
        ),
        Tool(
            name: "set_note_status",
            description: """
            Set a note's status — how a bug is marked fixed or an idea dropped. \
            The status is a field the app filters on; do not write "DONE" into \
            the text instead.
            """,
            inputSchema: object([
                "note": string("Note id (UUID) or its exact title."),
                "status": string("One of: active, onHold, completed, dropped, none.")
            ], required: ["note", "status"])
        ),
        Tool(
            name: "tag_note",
            description: """
            Add tags to a note. Tags already present are ignored, including ones \
            written in the body text.
            """,
            inputSchema: object([
                "note": string("Note id (UUID) or its exact title."),
                "tags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Tags to add, without the leading #.")
                ])
            ], required: ["note", "tags"])
        ),
        Tool(
            name: "create_notebook",
            description: """
            Create a notebook, or return the existing one with that name. Use it \
            to file notes by area — Bugs, Ideas, and so on.
            """,
            inputSchema: object([
                "name": string("Notebook name."),
                "parent": string("Parent notebook (name or id) to nest under.")
            ], required: ["name"])
        ),
        Tool(
            name: "trash_note",
            description: "Move a note to the trash. The file is kept, as it is in the app.",
            inputSchema: object(
                ["note": string("Note id (UUID) or its exact title.")],
                required: ["note"]
            )
        )
    ]
}
