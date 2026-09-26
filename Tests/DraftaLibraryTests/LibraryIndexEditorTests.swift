import XCTest
@testable import DraftaLibrary

/// `library.json` is rewritten only when a change actually changed it: a
/// write of the same notebooks still stamps the file and wakes every watcher.
final class LibraryIndexEditorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryIndexEditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testAChangeThatLeavesTheIndexAsItWasDoesNotRewriteTheFile() throws {
        let url = tempDir.appendingPathComponent("library.json")
        let editor = LibraryIndexEditor(url: url)
        let notebook = Notebook(name: "Projects")
        try editor.modify { $0.notebooks.append(notebook) }
        let written = try Data(contentsOf: url)

        try editor.modify { index in
            if let existing = index.notebooks.firstIndex(where: { $0.id == notebook.id }) {
                index.notebooks[existing] = notebook
            }
        }
        try editor.modify { index in
            let absent = UUID()
            index.notebooks.removeAll { $0.id == absent }
        }

        XCTAssertEqual(try Data(contentsOf: url), written, "the same content, byte for byte — no fresh stamp")
        XCTAssertEqual(try LibraryIndexFile(url: url).load().notebooks.map(\.id), [notebook.id])
    }

    func testAMissingIndexIsWrittenEvenWhenTheChangeAddsNothing() throws {
        let url = tempDir.appendingPathComponent("library.json")

        try LibraryIndexEditor(url: url).modify { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
