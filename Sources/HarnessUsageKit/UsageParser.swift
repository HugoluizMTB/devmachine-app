import Foundation

public enum UsageParser {
    private static let usageLinePattern = #"^(.+?):\s*(\d+)% used(?:.*?resets (.+))?$"#

    private static func regexMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).map {
            let r = m.range(at: $0)
            return r.location == NSNotFound ? "" : (text as NSString).substring(with: r)
        }
    }

    public static func parseUsage(_ text: String) -> [UsageBlock] {
        var blocks: [UsageBlock] = []
        let modelWords = ["opus", "sonnet", "haiku", "fable"]
        for line in text.components(separatedBy: "\n") {
            guard let m = regexMatch(usageLinePattern, in: line) else { continue }
            let label = m[0].trimmingCharacters(in: .whitespaces)
            let percent = Int(m[1]) ?? 0
            let resets = m[2]
            let lowered = label.lowercased()

            let kind: UsageBlockKind
            if lowered.contains("session") {
                kind = .session
            } else if modelWords.contains(where: { lowered.contains($0) }) {
                kind = .weeklyModel
            } else {
                kind = .weeklyAll
            }

            blocks.append(UsageBlock(kind: kind, label: label, percent: percent, resets: resets))
        }
        return blocks
    }

    public static func planName(fromClaudeJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["oauthAccount"] as? [String: Any],
              let tier = oauth["organizationRateLimitTier"] as? String,
              !tier.isEmpty
        else { return nil }
        return tier
    }
}
