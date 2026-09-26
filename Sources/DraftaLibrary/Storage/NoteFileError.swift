import Foundation

/// The `encryption` field an earlier build of the app wrote into the front matter
/// of a note it sealed.
///
/// No current build writes it, and this package never decrypts anything. It is
/// recognised only so that such a file is **skipped and left alone** on load
/// instead of being read as an empty note or overwritten with plaintext.
///
/// A plain string rather than an enum, because it is read from a file that another
/// version of the app wrote: an unknown value must be reported, not silently treated
/// as plaintext.
public enum NoteEncryptionScheme {
    public static let aesGCMv1 = "aes-gcm-v1"

    /// The key name in the front matter.
    public static let schemeField = "encryption"

    /// The scheme a file declares, or nil when the file is plaintext.
    public static func declared(in fields: [String: YAMLValue]) -> String? {
        fields[schemeField]?.stringValue
    }
}

/// What went wrong reading a note file.
public enum NoteFileError: Error, Equatable {
    /// The file was sealed by an earlier build of the app and is never opened
    /// here. The loader counts it (`LoadReport.skippedSealed`) and moves on.
    case encryptedButLocked
    /// Sealed with a scheme this package does not know. Refusing beats writing
    /// plaintext over a file we cannot read.
    case unsupportedScheme(String)
}
