import Foundation

// The mutating half of `LibraryAccess`. The state itself lives in
// `LibraryAccess.swift`, because Swift allows stored properties only in the
// main declaration; the directory stores this half writes through are therefore
// `internal` rather than `private`.
//
// Every entry point here calls `requireWritable()` and writes through
// `notes`/`index`; the reading half never calls into it.

extension LibraryAccess {

    // MARK: - Writing

    /// Creates a notebook, or returns the existing one with that name under the
    /// same parent — so an agent organising its notes cannot end up with three
    /// notebooks called "Bugs".
    @discardableResult
    public func createNotebook(name: String, parentID: UUID? = nil) throws -> Notebook {
        try requireWritable()

        // The app writes the same file from another process: the lookup and the
        // append happen under one coordinated write, or a notebook it added in
        // between would be dropped with the old array.
        var result: Notebook?
        try LibraryIndexEditor(url: index.url).modify { library in
            if let existing = library.notebooks.first(where: {
                $0.name.compare(name, options: .caseInsensitive) == .orderedSame && $0.parentId == parentID
            }) {
                result = existing
                return
            }
            var notebook = Notebook(name: name)
            notebook.parentId = parentID
            library.notebooks.append(notebook)
            result = notebook
        }
        guard let result else { throw AccessError.libraryMissing(root) }
        return result
    }

    /// Creates a note. With no notebook given it goes to the Inbox — never
    /// nowhere, or it would be reachable only from All Notes.
    ///
    /// The title is written into the body as a leading `# heading` when the
    /// body has none: a note's title is derived from its first line on every
    /// read (`NoteFileCodec`), so a title passed only as a parameter would
    /// silently disappear the moment the note is loaded again.
    @discardableResult
    public func create(
        title: String,
        content: String,
        notebookID: UUID? = nil,
        tags: [String] = []
    ) throws -> Note {
        try requireWritable()

        let body = Self.body(title: title, content: content)
        var note = Note(title: title, content: body)
        note.title = Note.extractTitle(from: body)
        note.notebookId = try notebookID ?? inboxNotebookID()
        note.extraTags = TagNames.normalise(tags)
        note.createdAt = Date()
        note.updatedAt = note.createdAt

        try notes.write(note)
        return Self.withTags(note)
    }

    /// Replaces a note's body, keeping the previous text as a revision.
    ///
    /// Refuses while the app holds unsaved text for this note: the app keeps what
    /// the user typed, so a body written here would be discarded a moment later
    /// while this call reported success. The refusal is the whole point — see
    /// `requireEditorNotHolding`.
    @discardableResult
    public func update(id: UUID, content: String) throws -> Note {
        try requireWritable()
        try requireEditorNotHolding(id)

        var note = try note(id: id)
        // A revision that cannot be written is the caller's error: reporting
        // success while the replaced text is gone would be worse than refusing.
        if note.content != content {
            _ = try revisions.append(content: note.content, for: note.id, keep: revisions.retentionLimit)
        }
        note.content = content
        note.title = Note.extractTitle(from: content)
        note.updatedAt = Date()

        try notes.write(note)
        return Self.withTags(note)
    }

    /// Appends to the end of a note — the usual shape of "save this into my
    /// notes" from a chat.
    @discardableResult
    public func append(id: UUID, text: String) throws -> Note {
        let existing = try note(id: id)
        let separator = existing.content.hasSuffix("\n") ? "\n" : "\n\n"
        return try update(id: id, content: existing.content + separator + text)
    }

    /// Sets a note's status — how an agent records that a bug is fixed or an
    /// idea was dropped. Deliberately does not touch the body: the status is a
    /// field the app's sidebar filters on, not a line of Markdown.
    @discardableResult
    public func setStatus(id: UUID, status: NoteStatus) throws -> Note {
        try requireWritable()

        var note = try note(id: id)
        guard note.status != status else { return note }
        note.status = status
        note.updatedAt = Date()

        try notes.write(note)
        return Self.withTags(note)
    }

    /// Adds tags, ignoring ones the note already carries — including tags that
    /// come from the body text, which cannot be removed by editing the list.
    @discardableResult
    public func addTags(id: UUID, tags: [String]) throws -> Note {
        try requireWritable()

        var note = try note(id: id)
        let existing = Set(note.tags.map { $0.lowercased() })
        let fresh = TagNames.normalise(tags)
            .filter { !existing.contains($0.lowercased()) }
        guard !fresh.isEmpty else { return note }

        note.extraTags.append(contentsOf: fresh)
        note.updatedAt = Date()

        try notes.write(note)
        return Self.withTags(note)
    }

    /// Moves a note to the trash. The file stays on disk, as it does in the app.
    @discardableResult
    public func trash(id: UUID) throws -> Note {
        try requireWritable()

        var note = try note(id: id)
        note.isTrashed = true
        note.trashedAt = Date()
        note.updatedAt = note.trashedAt ?? Date()

        try notes.write(note)
        return Self.withTags(note)
    }

    // MARK: - Private

    /// Prefixes the body with the title unless it already opens with a heading.
    private static func body(title: String, content: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return content }

        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if firstLine.hasPrefix("#") { return content }

        return "# \(trimmedTitle)\n\n\(content)"
    }

    /// Refuses to replace a body the app's editor is holding text for.
    ///
    /// The app wins that race by design: when its editor holds text the file does
    /// not have, an external change is recorded and the user's text is kept. So a
    /// write here that "succeeded" could be undone by the app's own autosave while
    /// the caller was told it landed. An error the agent can act on is the only
    /// honest answer; a retry a second later, once the app's debounce has saved
    /// and cleared the hold, succeeds.
    private func requireEditorNotHolding(_ id: UUID) throws {
        guard notesHeldByEditor().contains(id) else { return }
        throw AccessError.noteOpenInApp(id.uuidString)
    }

    private func requireWritable() throws {
        if isReadOnly { throw AccessError.readOnly }

        // A missing directory means a mistyped path — refuse. A directory that
        // exists but holds no library.json is a library the app has not opened
        // yet, and writing the index is exactly how one begins.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AccessError.libraryMissing(root)
        }
    }

    /// The Inbox notebook, created if the library has none — the same rule the
    /// app applies to notes it creates itself.
    private func inboxNotebookID() throws -> UUID {
        var inboxID: UUID?
        try LibraryIndexEditor(url: index.url).modify { library in
            if let inbox = library.notebooks.first(where: {
                $0.name.lowercased() == "inbox" && $0.parentId == nil
            }) {
                inboxID = inbox.id
                return
            }
            let inbox = Notebook(name: "Inbox")
            library.notebooks.append(inbox)
            inboxID = inbox.id
        }
        guard let inboxID else { throw AccessError.libraryMissing(root) }
        return inboxID
    }
}
