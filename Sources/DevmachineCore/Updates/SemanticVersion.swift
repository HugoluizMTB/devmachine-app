import Foundation

public struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        var prerelease: String?
        if let dash = text.firstIndex(of: "-") {
            prerelease = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
            if prerelease?.isEmpty ?? true { return nil }
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1])
        else { return nil }
        let patch = parts.count == 3 ? Int(parts[2]) : 0
        guard let patch else { return nil }
        self.init(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    public static func first(in text: String) -> SemanticVersion? {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ")" || $0 == "," })
            .lazy
            .compactMap { SemanticVersion(String($0)) }
            .first
    }

    public var isPrerelease: Bool { prerelease != nil }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (left?, right?): return prereleasePrecedes(left, right)
        }
    }

    private static func prereleasePrecedes(_ left: String, _ right: String) -> Bool {
        let a = left.split(separator: "."), b = right.split(separator: ".")
        for (x, y) in zip(a, b) where x != y {
            switch (Int(x), Int(y)) {
            case let (m?, n?): return m < n
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return x < y
            }
        }
        return a.count < b.count
    }
}
