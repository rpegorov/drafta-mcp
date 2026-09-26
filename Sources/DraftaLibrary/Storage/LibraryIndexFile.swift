import Foundation

/// Metadata for the library: notebooks, last opened note, schema version.
///
/// Part of the on-disk contract: anything that opens a Drafta library — the app
/// or this server — has to agree on what `library.json` means.
public struct LibraryIndex: Codable, Sendable {
    public var schemaVersion: Int
    public var notebooks: [Notebook]
    public var lastOpenedNoteId: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = currentSchemaVersion,
        notebooks: [Notebook] = [],
        lastOpenedNoteId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.notebooks = notebooks
        self.lastOpenedNoteId = lastOpenedNoteId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func empty() -> LibraryIndex { LibraryIndex() }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, notebooks, lastOpenedNoteId, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        notebooks = try c.decode([Notebook].self, forKey: .notebooks)
        lastOpenedNoteId = try c.decodeIfPresent(UUID.self, forKey: .lastOpenedNoteId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(notebooks, forKey: .notebooks)
        try c.encodeIfPresent(lastOpenedNoteId, forKey: .lastOpenedNoteId)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Reads and writes `library.json`.
///
/// Like `NoteDirectoryStore`, it knows a file URL and a `NoteFileIO`, nothing
/// about where libraries live. Read-modify-write goes through
/// `LibraryIndexEditor`, which coordinates it with other processes.
public struct LibraryIndexFile {
    public let url: URL
    private let io: NoteFileIO

    public init(url: URL, io: NoteFileIO = DefaultNoteFileIO()) {
        self.url = url
        self.io = io
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func load() throws -> LibraryIndex {
        let data = try io.read(at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryIndex.self, from: data)
    }

    /// Writes the index, stamping `updatedAt`.
    public func write(_ index: LibraryIndex) throws {
        var stamped = index
        stamped.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try io.writeAtomically(try encoder.encode(stamped), to: url)
    }
}
