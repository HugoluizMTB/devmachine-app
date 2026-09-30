import CryptoKit
import Foundation

public enum ReleaseDigest {
    public static func parse(_ text: String) -> String? {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() }
            .first { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }
    }

    public static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(fileAt url: URL, expected: String) throws {
        let actual = try sha256(ofFileAt: url)
        guard actual == expected.lowercased() else {
            throw UpdateInstallError.digestMismatch(expected: expected, actual: actual)
        }
    }
}
