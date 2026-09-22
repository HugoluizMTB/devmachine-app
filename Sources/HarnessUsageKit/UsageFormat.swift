import Foundation

public enum UsageFormat {
    public static func tokens(_ n: Int64) -> String {
        let magnitude = abs(n)
        if magnitude >= 1_000_000_000 {
            return String(format: "%.2fB", Double(n) / 1e9)
        }
        if magnitude >= 1_000_000 {
            return String(format: "%.2fM", Double(n) / 1e6)
        }
        if magnitude >= 1_000 {
            return String(format: "%.2fK", Double(n) / 1e3)
        }
        return "\(n)"
    }

    public static func planLabel(_ rawTier: String) -> String {
        guard !rawTier.isEmpty else { return "" }
        var tier = rawTier
        if tier.hasPrefix("default_claude_") {
            tier.removeFirst("default_claude_".count)
        } else if tier.hasPrefix("claude_") {
            tier.removeFirst("claude_".count)
        }
        guard !tier.isEmpty else { return rawTier }

        let parts = tier.split(separator: "_")
        guard !parts.isEmpty else { return rawTier }

        let words = parts.map { part -> String in
            if part.hasSuffix("x"), Int(part.dropLast()) != nil {
                return String(part)
            }
            return part.prefix(1).uppercased() + part.dropFirst()
        }
        return words.joined(separator: " ")
    }
}
