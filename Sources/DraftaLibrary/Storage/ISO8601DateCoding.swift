import Foundation

/// The one place that decides how a `Date` becomes text in Drafta.
///
/// Every writer of a note file must agree on this, because the app compares
/// `updatedAt` to tell which copy of a note is newer. `Foundation`'s built-in
/// `.iso8601` strategy drops sub-second precision, so a note that made a round
/// trip through a layer using it came back with a different timestamp than the
/// one on disk, which reads as a spurious edit.
///
/// Writing always emits fractional seconds. Reading accepts both, so
/// timestamps produced elsewhere (another tool, an older build) still parse.
public enum ISO8601DateCoding {

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `ISO8601DateFormatter` is strict: one configured for fractional seconds
    /// rejects a string without them, so whole-second input needs its own.
    private static let wholeSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? wholeSeconds.date(from: string)
    }
}
