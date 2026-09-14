import Foundation

public enum SSHConfigParser {
    public static func parse(_ text: String, suffix: String = "-devmachine") -> [Workspace] {
        var result: [Workspace] = []
        var seen: Set<String> = []

        for token in hostTokens(text) {
            guard token.hasSuffix(suffix) else { continue }
            let name = String(token.dropLast(suffix.count))
            guard !name.isEmpty else { continue }
            guard !name.contains("*"), !name.contains("?") else { continue }
            guard !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(Workspace(name: name, alias: token))
        }
        return result
    }

    public static func hostTokens(_ text: String) -> [String] {
        var tokens: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lowerLine = line.lowercased()
            guard lowerLine.hasPrefix("host ") || lowerLine.hasPrefix("host\t") else { continue }

            tokens += line.dropFirst("host".count)
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
        }
        return tokens
    }

    public static func hostname(inSSHDump dump: String) -> String? {
        for rawLine in dump.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("hostname ") else { continue }
            let value = line.dropFirst("hostname ".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
