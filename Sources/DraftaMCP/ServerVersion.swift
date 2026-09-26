import Foundation

/// The version this server reports to clients.
///
/// A binary linked with an embedded Info.plist (`__TEXT,__info_plist`) reports its
/// `CFBundleShortVersionString`. A plain `swift build` has no such section and
/// reports `unbundledVersion`, which says so honestly instead of passing for a
/// release.
enum ServerVersion {
    static let unbundledVersion = "0.0.0-dev"

    static func current(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            return unbundledVersion
        }
        return version
    }
}
