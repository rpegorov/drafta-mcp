import Foundation

/// A note's status. Raw values are what the note file's `status` field holds.
public enum NoteStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case active
    case onHold
    case completed
    case dropped

    /// Human-readable label.
    public var label: String {
        switch self {
        case .none:      return "No Status"
        case .active:    return "Active"
        case .onHold:    return "On Hold"
        case .completed: return "Completed"
        case .dropped:   return "Dropped"
        }
    }
}
