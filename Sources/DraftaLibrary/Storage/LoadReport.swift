import Foundation

/// The outcome of loading a library directory.
///
/// A file that could not be opened is counted rather than thrown, so one bad
/// file never hides the rest of the library.
public struct LoadReport {
    /// Notes that loaded, newest `updatedAt` first.
    public var notes: [Note]
    /// Files sealed by an earlier app build (`encryption: aes-gcm-v1`); left untouched.
    public var skippedSealed: Int
    /// Ids of files that exist but could not be decoded.
    public var failed: [UUID]

    public init(notes: [Note] = [], skippedSealed: Int = 0, failed: [UUID] = []) {
        self.notes = notes
        self.skippedSealed = skippedSealed
        self.failed = failed
    }
}
