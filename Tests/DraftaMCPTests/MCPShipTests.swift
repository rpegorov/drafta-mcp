import XCTest
import Foundation
import MCP
@testable import DraftaMCP
@testable import DraftaLibrary

/// `drafta-mcp` as a user launches it — a process with arguments, stdin and an
/// exit code — plus the one write gate it has: `--read-only`.
///
/// Most of these run the built executable (`swift test` builds it next to the test
/// bundle), so they check the command line and the protocol, not internal types.
final class MCPShipTests: XCTestCase {

    private var root: URL!

    private static let writeTools: Set<String> = [
        "create_note", "append_to_note", "update_note", "set_note_status",
        "tag_note", "create_notebook", "trash_note",
    ]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPShipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Positive

    /// `--library ~/…` is what a user types into a client config; the shell is not
    /// there to expand it.
    func testATildeInTheLibraryPathIsExpandedToTheHomeDirectory() throws {
        let name = "drafta-mcp-tilde-\(UUID().uuidString)"

        let run = try MCPProcess.run(arguments: ["--library", "~/\(name)"], stdin: .none)

        let expanded = NSHomeDirectory() + "/" + name
        XCTAssertTrue(run.stderr.contains(expanded), "the server reports the expanded path: \(run.stderr)")
        XCTAssertFalse(run.stderr.contains("/~/"), "a literal ~ directory is never served: \(run.stderr)")
    }

    /// A writable library publishes every tool, read and write.
    func testAWritableLibraryListsTheWriteTools() throws {
        let session = try MCPSession(arguments: ["--library", root.path])
        defer { session.close() }

        let names = try session.toolNames()

        XCTAssertTrue(names.contains("search_notes"), "reading is always published: \(names)")
        XCTAssertTrue(Self.writeTools.isSubset(of: names),
                      "every write tool is published: \(Self.writeTools.subtracting(names))")
    }

    /// `--read-only` publishes the read tools and nothing else.
    func testReadOnlyListsOnlyReadTools() throws {
        let session = try MCPSession(arguments: ["--library", root.path, "--read-only"])
        defer { session.close() }

        let names = try session.toolNames()

        XCTAssertTrue(names.contains("search_notes"), "reading is never gated: \(names)")
        XCTAssertTrue(names.isDisjoint(with: Self.writeTools),
                      "no write tool when read-only: \(names.intersection(Self.writeTools))")
    }

    // MARK: - Negative

    /// A misspelt flag used to be ignored, so `--readonly` served a writable
    /// library to a user who asked for the opposite.
    func testAMisspeltFlagFailsWithAMessage() throws {
        let run = try MCPProcess.run(arguments: ["--library", root.path, "--readonly"], stdin: .none)

        XCTAssertNotEqual(run.status, 0, "an unknown argument is an error")
        XCTAssertTrue(run.stderr.contains("--readonly"), "and the message names it: \(run.stderr)")
    }

    func testLibraryWithoutAValueFails() throws {
        let run = try MCPProcess.run(arguments: ["--library"], stdin: .none)

        XCTAssertNotEqual(run.status, 0, "`--library` with nothing after it is an error, not the default library")
        XCTAssertFalse(run.stderr.isEmpty, "and it says so")
    }

    /// The status is checked before anything is written: a refused call must not
    /// leave a note behind.
    func testCreateNoteWithAnUnknownStatusCreatesNothing() async throws {
        let tools = DraftaTools(library: LibraryAccess(root: root))
        let result = await tools.call(name: "create_note", arguments: [
            "title": .string("Bad status"),
            "content": .string("body"),
            "status": .string("open"),
        ])

        XCTAssertEqual(result.isError, true, "an unknown status is an error")
        XCTAssertTrue(noteFiles().isEmpty, "and no note was created: \(noteFiles())")
    }

    /// A read-only server hides the write tools, and a call to one anyway is
    /// refused without writing.
    func testAReadOnlyServerRefusesCreateNote() throws {
        let session = try MCPSession(arguments: ["--library", root.path, "--read-only"])
        defer { session.close() }

        XCTAssertFalse(try session.toolNames().contains("create_note"))
        let call = try session.request("tools/call", params: [
            "name": "create_note",
            "arguments": ["title": "Should not exist", "content": "body"],
        ])

        let refused = call["error"] != nil || ((call["result"] as? [String: Any])?["isError"] as? Bool) == true
        XCTAssertTrue(refused, "create_note must be refused: \(call)")
        XCTAssertTrue(noteFiles().isEmpty, "and nothing is written: \(noteFiles())")
    }

    // MARK: - Helpers

    private func noteFiles() -> [String] {
        let dir = root.appendingPathComponent("notes")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".md") }
    }
}

// MARK: - Running the executable

/// The `drafta-mcp` binary SwiftPM built beside this test bundle.
enum MCPProcess {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    enum Input { case none }

    /// Upper bound for a process that should exit by itself; exceeding it is a
    /// failure (a hang), not a timing assumption.
    static let exitDeadline: TimeInterval = 20

    static var executable: URL {
        Bundle(for: MCPShipTests.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("drafta-mcp")
    }

    static func run(arguments: [String], stdin: Input) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let stdout = PipeReader(out)
        let stderr = PipeReader(err)
        if exited.wait(timeout: .now() + exitDeadline) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            XCTFail("drafta-mcp \(arguments) did not exit by itself")
        }
        return Result(status: process.terminationStatus, stdout: stdout.text(), stderr: stderr.text())
    }
}

/// Drains a pipe on a background queue so a chatty or hung child never blocks
/// the test on a full pipe buffer.
final class PipeReader: @unchecked Sendable {
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        DispatchQueue.global().async {
            self.data = handle.readDataToEndOfFile()
            self.done.signal()
        }
    }

    func text() -> String {
        _ = done.wait(timeout: .now() + MCPProcess.exitDeadline)
        return String(decoding: data, as: UTF8.self)
    }
}

/// A newline-delimited JSON-RPC conversation with a running `drafta-mcp`.
final class MCPSession: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private let arrived = DispatchSemaphore(value: 0)
    private var nextID = 1

    static let responseDeadline: TimeInterval = 20

    init(arguments: [String]) throws {
        process.executableURL = MCPProcess.executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        try process.run()

        _ = try request("initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "DraftaMCPTests", "version": "1"],
        ])
        send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    func toolNames() throws -> Set<String> {
        let response = try request("tools/list", params: [:])
        let tools = (response["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        return Set(tools.compactMap { $0["name"] as? String })
    }

    /// Sends a request and waits for the response with the same id.
    func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(Self.responseDeadline)
        while true {
            if let response = lock.withLockCompat({ responses.removeValue(forKey: id) }) { return response }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, arrived.wait(timeout: .now() + remaining) == .success else {
                throw NSError(domain: "MCPSession", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "no response to \(method)"])
            }
        }
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        input.fileHandleForWriting.write(data + Data("\n".utf8))
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLockCompat {
            buffer.append(data)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = object["id"] as? Int {
                    responses[id] = object
                }
            }
        }
        arrived.signal()
    }
}

private extension NSLock {
    func withLockCompat<R>(_ body: () throws -> R) rethrows -> R {
        lock()
        defer { unlock() }
        return try body()
    }
}
