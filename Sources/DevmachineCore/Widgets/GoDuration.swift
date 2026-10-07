import Foundation

/// A Go `time.Duration` as the CLI prints it ("60s", "1m30s", "500ms").
public enum GoDuration {
    private static let units: [(suffix: String, seconds: Double)] = [
        ("ns", 1e-9), ("us", 1e-6), ("µs", 1e-6), ("ms", 1e-3), ("h", 3600), ("m", 60), ("s", 1),
    ]

    public static func seconds(_ text: String) -> TimeInterval? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        guard !rest.isEmpty else { return nil }
        if rest == "0" { return 0 }
        var total = 0.0
        while !rest.isEmpty {
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard !number.isEmpty, let value = Double(number) else { return nil }
            rest = rest.dropFirst(number.count)
            guard let unit = units.first(where: { rest.hasPrefix($0.suffix) }) else { return nil }
            rest = rest.dropFirst(unit.suffix.count)
            total += value * unit.seconds
        }
        return total
    }
}
