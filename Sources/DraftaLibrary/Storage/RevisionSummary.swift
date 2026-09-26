import Foundation

/// One revision of a note without its text: enough to list the history and
/// decide what retention prunes.
public struct RevisionSummary: Identifiable, Equatable, Hashable, Sendable {
    /// The revision file's millisecond stamp; stable across reads.
    public let id: String
    public let savedAt: Date
    public let byteCount: Int
    /// Sealed by an earlier app build: listed, never counted or pruned.
    public let isSealed: Bool

    public init(id: String, savedAt: Date, byteCount: Int, isSealed: Bool = false) {
        self.id = id
        self.savedAt = savedAt
        self.byteCount = byteCount
        self.isSealed = isSealed
    }
}
