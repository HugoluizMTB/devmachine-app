import CryptoKit
import Foundation

/// Lima without Homebrew: its own release tarball from GitHub, checked
/// against the release's `SHA256SUMS`, unpacked into `~/.local` (`bin`,
/// `share`, `libexec`), where `limactl` finds the rest of itself. Homebrew
/// is only the fallback, when it is there. Nothing here touches the network
/// or the disk; the app does, step by step, with what this says.
public enum LimaInstall {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/lima-vm/lima/releases/latest")!
    public static let homebrewArguments = ["install", "lima"]
    public static let releasePage = "github.com/lima-vm/lima"

    public enum Method: Equatable, Sendable {
        case release
        case homebrew(brew: String)
    }

    public struct Release: Equatable, Sendable {
        public let version: String
        public let asset: String
        public let tarballURL: URL
        public let checksumsURL: URL
    }

    public enum Check: Equatable, Sendable {
        case verified
        case mismatch(expected: String, actual: String)
        case notListed

        public var problem: String? {
            switch self {
            case .verified:
                return nil
            case let .mismatch(expected, actual):
                return "The download does not match Lima's published checksum (expected \(expected), "
                    + "got \(actual)). Nothing was installed."
            case .notListed:
                return "Lima's SHA256SUMS does not list this file, so it cannot be checked. Nothing was installed."
            }
        }
    }

    /// The Mac's tarball for a release tag. `machine` is what `uname -m`
    /// says. A tag that is not a plain version builds no URL.
    public static func release(tag: String, machine: String) -> Release? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let first = version.first, first.isNumber,
              version.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              let arch = darwinArch(machine)
        else { return nil }
        let asset = "lima-\(version)-Darwin-\(arch).tar.gz"
        let base = "https://github.com/lima-vm/lima/releases/download/v\(version)/"
        guard let tarball = URL(string: base + asset), let sums = URL(string: base + "SHA256SUMS") else { return nil }
        return Release(version: version, asset: asset, tarballURL: tarball, checksumsURL: sums)
    }

    private static func darwinArch(_ machine: String) -> String? {
        switch machine {
        case "arm64", "aarch64": return "arm64"
        case "x86_64", "amd64": return "x86_64"
        default: return nil
        }
    }

    public static func tag(fromLatestRelease data: Data) -> String? {
        (try? GitHubRelease.decode(data))?.tagName
    }

    /// `<digest>  <file>` per line, as `shasum` writes it (`*` marks binary mode).
    public static func expectedDigest(sums: String, asset: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2 else { continue }
            let name = fields[1].hasPrefix("*") ? fields[1].dropFirst() : fields[1]
            if name == asset { return fields[0].lowercased() }
        }
        return nil
    }

    public static func check(digest: String, sums: String, asset: String) -> Check {
        guard let expected = expectedDigest(sums: sums, asset: asset) else { return .notListed }
        let actual = digest.lowercased()
        return actual == expected ? .verified : .mismatch(expected: expected, actual: actual)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func prefix(home: String) -> String { home + "/.local" }
    public static func limactl(home: String) -> String { prefix(home: home) + "/bin/limactl" }

    public static func extractArguments(tarball: String, home: String) -> [String] {
        ["-xzf", tarball, "-C", prefix(home: home)]
    }

    public static func methods(brew: String?) -> [Method] {
        [.release] + (brew.map { [.homebrew(brew: $0)] } ?? [])
    }

    /// The CLI runs `limactl` by name, so the folder Lima was unpacked into
    /// goes first on the PATH it gets.
    public static func environment(base: [String: String], home: String) -> [String: String] {
        var environment = base
        let bin = prefix(home: home) + "/bin"
        let path = base["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let parts = path.split(separator: ":").map(String.init)
        environment["PATH"] = parts.contains(bin) ? path : bin + ":" + path
        return environment
    }
}
