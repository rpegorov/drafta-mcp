import Foundation
import DraftaLibrary
import MCP

/// `drafta-mcp` — exposes a Drafta note library over the Model Context Protocol.
///
/// Speaks stdio, which is what both Claude Code and Zed launch. The library is
/// plain files, so the server works whether or not the app is running; when it
/// is, the app's file watcher picks up what was written here.
///
/// The server opens no network connection: its only channels are stdin/stdout
/// to the client and the files under the library root.
///
/// NOTHING may be printed to stdout except protocol frames — stdout *is* the
/// transport. Diagnostics go to stderr.

func log(_ message: String) {
    FileHandle.standardError.write(Data("drafta-mcp: \(message)\n".utf8))
}

let options: Options
do {
    options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    log(error.localizedDescription)
    FileHandle.standardError.write(Data(Options.usage.utf8))
    exit(EX_USAGE)
}
if options.showsHelp {
    // Help is the one output that is not a protocol frame: no client is attached.
    FileHandle.standardOutput.write(Data(Options.usage.utf8))
    exit(EXIT_SUCCESS)
}

let library = LibraryAccess(root: options.root, readOnly: options.readOnly)

if !library.exists {
    // Not fatal: the user may point at a library that has not been created yet,
    // and a server that refuses to start is harder to diagnose from a client
    // than one that answers with an explicit error.
    log("no library.json under \(library.root.path) — read calls will come back empty")
}
log("serving \(library.root.path)\(library.isReadOnly ? " (read-only)" : "")")

let server = Server(
    name: "drafta",
    version: ServerVersion.current(),
    capabilities: .init(
        resources: .init(subscribe: false, listChanged: false),
        tools: .init(listChanged: false)
    )
)

let tools = DraftaTools(library: library)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: await tools.definitions)
}

await server.withMethodHandler(CallTool.self) { params in
    await tools.call(name: params.name, arguments: params.arguments ?? [:])
}

await server.withMethodHandler(ListResources.self) { _ in
    .init(resources: await tools.noteResources())
}

await server.withMethodHandler(ReadResource.self) { params in
    .init(contents: await tools.readResource(uri: params.uri))
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
