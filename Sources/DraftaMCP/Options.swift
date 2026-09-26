import Foundation
import DraftaLibrary

/// The command line `drafta-mcp` accepts.
///
/// Parsing is strict: an unknown flag or a flag missing its value is an error, not
/// something to skip. A client config with `--readonly` (a typo for `--read-only`)
/// would otherwise start a server that writes, and nothing in the client would say
/// the flag was ignored.
struct Options: Equatable {
    var root: URL = LibraryAccess.defaultRoot
    var readOnly = false
    var showsHelp = false

    enum ParseError: LocalizedError, Equatable {
        case unknownArgument(String)
        case missingValue(flag: String)

        var errorDescription: String? {
            switch self {
            case .unknownArgument(let argument):
                return "unknown argument \"\(argument)\""
            case .missingValue(let flag):
                return "\(flag) needs a value"
            }
        }
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var remaining = arguments[...]

        while let argument = remaining.popFirst() {
            switch argument {
            case "--library", "-l":
                guard let value = remaining.popFirst(), !value.isEmpty, !value.hasPrefix("-") else {
                    throw ParseError.missingValue(flag: argument)
                }
                options.root = libraryURL(from: value)
            case "--read-only", "-r":
                options.readOnly = true
            case "--help", "-h":
                options.showsHelp = true
            default:
                throw ParseError.unknownArgument(argument)
            }
        }
        return options
    }

    /// A client config is JSON, not a shell: nobody expands `~` before the server
    /// sees it, so the server does.
    static func libraryURL(from path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    static let usage = """
        usage: drafta-mcp [--library <path>] [--read-only]

        Serves a Drafta note library over the Model Context Protocol (stdio).

          -l, --library <path>  library root (default: \(LibraryAccess.defaultRoot.path))
          -r, --read-only       publish read tools only
          -h, --help            print this help and exit

        """
}
