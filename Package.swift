// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "drafta-mcp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "drafta-mcp", targets: ["DraftaMCP"])
    ],
    dependencies: [
        // Official MCP implementation — stdio transport is what both Claude Code
        // and Zed speak.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        // The Drafta library format: notes, notebooks, revisions, tags. Plain
        // files under the library root; no network, no keychain.
        // Swift 5 language mode: the code is a snapshot of the app's core, which
        // is built that way.
        .target(
            name: "DraftaLibrary",
            path: "Sources/DraftaLibrary",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DraftaMCP",
            dependencies: [
                .target(name: "DraftaLibrary"),
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/DraftaMCP"
        ),
        .testTarget(
            name: "DraftaLibraryTests",
            dependencies: [.target(name: "DraftaLibrary")],
            path: "Tests/DraftaLibraryTests"
        ),
        // The tool layer is where a dropped argument becomes a silent lie — a call
        // that answers "Created …" and writes no tags. It has to be reachable from a
        // test, which is why this target exists.
        .testTarget(
            name: "DraftaMCPTests",
            dependencies: [.target(name: "DraftaMCP")],
            path: "Tests/DraftaMCPTests"
        )
    ]
)
