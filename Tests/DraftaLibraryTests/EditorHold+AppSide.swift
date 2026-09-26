import Foundation
@testable import DraftaLibrary

/// The app's half of the editor-hold record, which this package never writes:
/// tests use it to stand in for a running Drafta app.
extension EditorHold {
    func write(inLibrary root: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.url(inLibrary: root), options: .atomic)
    }

    static func remove(fromLibrary root: URL) {
        try? FileManager.default.removeItem(at: url(inLibrary: root))
    }
}
