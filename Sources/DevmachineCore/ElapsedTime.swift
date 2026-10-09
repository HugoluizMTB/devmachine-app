import Foundation

public enum ElapsedTime {
    /// `ps -o etime=`: [[dd-]hh:]mm:ss
    public static func seconds(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var days = 0
        var clock = Substring(text)
        if let dash = text.firstIndex(of: "-") {
            guard let parsed = Int(text[text.startIndex..<dash]), parsed >= 0 else { return nil }
            days = parsed
            clock = text[text.index(after: dash)...]
        }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let value = Int(part), value >= 0
            else { return nil }
            total = total * 60 + value
        }
        return days * 86_400 + total
    }

    public static func psArguments(_ pids: [Int]) -> [String] {
        ["-o", "pid=,etime=", "-p", pids.map(String.init).joined(separator: ",")]
    }

    public static func parse(_ output: String) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int(fields[0]),
                  let seconds = seconds(String(fields[1]))
            else { continue }
            result[pid] = seconds
        }
        return result
    }
}
