import Foundation

/// A notebook (folder) that groups notes. Notebooks may nest via `parentId`.
///
/// Stored in the `notebooks` array of `library.json`.
public struct Notebook: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var parentId: UUID?
    public var createdAt: Date
    /// Last rename or move. Equals `createdAt` for a notebook never changed.
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, parentId: UUID? = nil) {
        let now = Date()
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = now
        self.updatedAt = now
    }

    /// Initialize with an explicit `createdAt` (used when loading from disk).
    public init(id: UUID, name: String, parentId: UUID?, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

extension Notebook {
    private enum CodingKeys: String, CodingKey {
        case id, name, parentId, createdAt, updatedAt
    }

    /// A library written before `updatedAt` existed reads it as `createdAt`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            parentId: try container.decodeIfPresent(UUID.self, forKey: .parentId),
            createdAt: createdAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt))
    }
}
