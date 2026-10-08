import Foundation

/// A Go `time.Duration` read the way `time.ParseDuration` reads it: ASCII
/// digits, an optional leading sign, no spaces, and a unit on every number.
/// A negative result is valid, so a caller that has a minimum refuses it.
public enum GoDuration {
    private static let units: [(suffix: String, seconds: Double)] = [
        ("ns", 1e-9), ("us", 1e-6), ("\u{B5}s", 1e-6), ("\u{3BC}s", 1e-6), ("ms", 1e-3), ("h", 3600), ("m", 60), ("s", 1),
    ]

    public static func seconds(_ text: String) -> TimeInterval? {
        var rest = Array(text.utf8)[...]
        var sign = 1.0
        if let first = rest.first, first == UInt8(ascii: "-") || first == UInt8(ascii: "+") {
            if first == UInt8(ascii: "-") { sign = -1 }
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty else { return nil }
        if rest.elementsEqual("0".utf8) { return 0 }
        var total = 0.0
        while !rest.isEmpty {
            let number = rest.prefix { isDigit($0) || $0 == UInt8(ascii: ".") }
            guard let value = value(of: number) else { return nil }
            rest = rest.dropFirst(number.count)
            guard let unit = units.first(where: { rest.starts(with: $0.suffix.utf8) }) else { return nil }
            rest = rest.dropFirst(unit.suffix.utf8.count)
            total += value * unit.seconds
        }
        return sign * total
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

    private static func value(of bytes: ArraySlice<UInt8>) -> Double? {
        let parts = bytes.split(separator: UInt8(ascii: "."), maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.contains(where: { !$0.isEmpty }) else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(decoding: parts[0], as: UTF8.self)
        let fraction = parts.count == 2 ? String(decoding: parts[1], as: UTF8.self) : ""
        return Double(fraction.isEmpty ? whole : whole + "." + fraction)
    }
}
