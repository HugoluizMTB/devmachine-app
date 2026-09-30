import Foundation

/// Scores how well a typed query fits a line of text, the way a command
/// palette ranks: an exact name first, then a prefix, a word start, a
/// substring, word initials, and last letters found in order.
public enum FuzzyMatch {
    /// Points a match loses for each field after the first, so a hit in a
    /// title outranks the same hit in a subtitle or a keyword.
    public static let fieldPenalty = 150

    /// Nil when some word of the query is not in the text. An empty query
    /// matches with 0.
    public static func score(_ query: String, _ text: String) -> Int? {
        score(query, fields: [text])
    }

    /// Every word of the query must match one of the fields; each word takes
    /// its best field, and the total is the sum.
    public static func score(_ query: String, fields: [String]) -> Int? {
        let tokens = words(normalized(query))
        guard !tokens.isEmpty else { return 0 }
        let haystacks = fields.map(normalized)
        var total = 0
        for token in tokens {
            var best: Int?
            for (index, field) in haystacks.enumerated() {
                guard let hit = tokenScore(token, field) else { continue }
                let value = hit - index * fieldPenalty
                if best == nil || value > best! { best = value }
            }
            guard let best else { return nil }
            total += best
        }
        return total
    }

    static func tokenScore(_ query: String, _ text: String) -> Int? {
        if text == query { return 1000 }
        if text.hasPrefix(query) { return 900 - min(text.count - query.count, 50) }
        let parts = words(text)
        if let index = parts.firstIndex(where: { $0.hasPrefix(query) }) {
            return max(800 - index * 10, 700)
        }
        if String(parts.compactMap(\.first)).hasPrefix(query) { return 650 }
        if let range = text.range(of: query) {
            return 600 - min(text.distance(from: text.startIndex, to: range.lowerBound), 100)
        }
        return subsequenceScore(query, text)
    }

    private static func subsequenceScore(_ query: String, _ text: String) -> Int? {
        let chars = Array(text)
        var position = 0
        var previous: Int?
        var score = 100
        for ch in query {
            guard let found = chars[position...].firstIndex(of: ch) else { return nil }
            score += 1
            if let previous, found == previous + 1 { score += 8 }
            if found == 0 || !chars[found - 1].isLetter && !chars[found - 1].isNumber { score += 10 }
            if let previous { score -= min(found - previous - 1, 10) }
            previous = found
            position = found + 1
        }
        return min(max(score, 1), 499)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    private static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
