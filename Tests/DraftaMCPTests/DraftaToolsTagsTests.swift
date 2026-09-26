import XCTest
import Foundation
import MCP
@testable import DraftaMCP
@testable import DraftaLibrary

/// The `tags` argument has to reach the file, in every shape a client sends it.
///
/// `tags: ["alpha","beta"]` is what the schema declares, and `tags: "alpha, beta"`
/// is the shape a model writes when it does not honour the schema. Both must
/// land in `extraTags`, for `create_note` and `tag_note` alike. A tool that
/// reports success and discards an argument is worse than one that refuses it.
final class DraftaToolsTagsTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func tools() -> DraftaTools {
        DraftaTools(library: LibraryAccess(root: root))
    }

    /// The single note file in the fixture library, as text.
    private func noteFile() throws -> String {
        let dir = root.appendingPathComponent("notes")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") }
        let name = try XCTUnwrap(names.first, "no note file was written")
        return try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    private func extraTagsLine(_ file: String) -> String? {
        file.split(separator: "\n").first { $0.hasPrefix("extraTags:") }.map(String.init)
    }

    private func text(of result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let value, _, _) = content { return value }
            return nil
        }.joined(separator: "\n")
    }

    // MARK: - create_note

    func testCreateNoteWritesTheTagsFromAnArray() async throws {
        let result = await tools().call(name: "create_note", arguments: [
            "title": .string("Array tags"),
            "content": .string("body"),
            "tags": .array([.string("audit"), .string("drafta")])
        ])

        XCTAssertNotEqual(result.isError, true, text(of: result))
        XCTAssertEqual(extraTagsLine(try noteFile()), "extraTags: [audit, drafta]")
    }

    func testCreateNoteWritesTheTagsFromACommaSeparatedString() async throws {
        let result = await tools().call(name: "create_note", arguments: [
            "title": .string("String tags"),
            "content": .string("body"),
            "tags": .string("audit, drafta")
        ])

        XCTAssertNotEqual(result.isError, true, text(of: result))
        XCTAssertEqual(extraTagsLine(try noteFile()), "extraTags: [audit, drafta]")
    }

    func testCreateNoteStoresATagWithoutItsHash() async throws {
        _ = await tools().call(name: "create_note", arguments: [
            "title": .string("Hashed"),
            "content": .string("body"),
            "tags": .array([.string("#audit"), .string(" audit ")])
        ])

        XCTAssertEqual(extraTagsLine(try noteFile()), "extraTags: [audit]")
    }

    func testCreateNoteWithoutTagsWritesNoExtraTags() async throws {
        _ = await tools().call(name: "create_note", arguments: [
            "title": .string("Untagged"),
            "content": .string("body")
        ])

        XCTAssertNil(extraTagsLine(try noteFile()))
    }

    /// A shape that is neither an array of strings nor a string used to be read as
    /// "no tags". It is an error now: the caller has to be able to tell that its
    /// argument did not land.
    func testCreateNoteRefusesATagsValueItCannotRead() async throws {
        let result = await tools().call(name: "create_note", arguments: [
            "title": .string("Bad tags"),
            "content": .string("body"),
            "tags": .array([.string("ok"), .int(3)])
        ])

        XCTAssertEqual(result.isError, true, "an unreadable tags value must not be a silent success")
        XCTAssertTrue(text(of: result).contains("tags"), text(of: result))
        let notesDir = root.appendingPathComponent("notes")
        let written = ((try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? [])
            .filter { $0.hasSuffix(".md") }
        XCTAssertTrue(written.isEmpty, "a refused call must not create a note: \(written)")
    }

    // MARK: - tag_note

    func testTagNoteTakesACommaSeparatedString() async throws {
        _ = await tools().call(name: "create_note", arguments: [
            "title": .string("Tagged later"),
            "content": .string("body")
        ])

        let result = await tools().call(name: "tag_note", arguments: [
            "note": .string("Tagged later"),
            "tags": .string("epsilon")
        ])

        XCTAssertNotEqual(result.isError, true, text(of: result))
        XCTAssertEqual(extraTagsLine(try noteFile()), "extraTags: [epsilon]")
    }

    func testTagNoteTakesAnArray() async throws {
        _ = await tools().call(name: "create_note", arguments: [
            "title": .string("Tagged later"),
            "content": .string("body")
        ])

        _ = await tools().call(name: "tag_note", arguments: [
            "note": .string("Tagged later"),
            "tags": .array([.string("epsilon"), .string("zeta")])
        ])

        XCTAssertEqual(extraTagsLine(try noteFile()), "extraTags: [epsilon, zeta]")
    }
}
