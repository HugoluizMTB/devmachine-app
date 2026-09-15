import Foundation

/// Ranked file paths for a search field: typing `apmd` finds `AppModel.swift`.
public enum FileSearch {
    public struct Hit: Equatable, Identifiable, Sendable {
        public let path: String
        public let score: Int
        /// Which characters of the path the query matched, for highlighting.
        public let matches: [Int]
        public var id: String { path }

        public init(path: String, score: Int, matches: [Int] = []) {
            self.path = path
            self.score = score
            self.matches = matches
        }
    }

    /// The best matches first, by score, and by shorter path when scores tie so
    /// the answer is stable rather than whatever order the listing arrived in.
    public static func rank(_ paths: [String], query: String, limit: Int = 50) -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return paths.prefix(limit).map { Hit(path: $0, score: 0) }
        }
        var hits: [Hit] = []
        hits.reserveCapacity(min(paths.count, limit * 4))
        for path in paths {
            guard let found = match(path: path, query: trimmed) else { continue }
            hits.append(Hit(path: path, score: found.score, matches: found.matches))
        }
        return hits.sorted {
            $0.score == $1.score
                ? ($0.path.count == $1.path.count ? $0.path < $1.path : $0.path.count < $1.path.count)
                : $0.score > $1.score
        }.prefix(limit).map { $0 }
    }

    /// Nil when the query's letters do not appear in order. Otherwise a score
    /// that rewards letters found next to each other, matches in the file's own
    /// name rather than a folder above it, and a match right at a word start.
    public static func score(path: String, query: String) -> Int? {
        match(path: path, query: query)?.score
    }

    /// Nil when the query's letters do not appear in order. Otherwise the score
    /// and where each letter landed.
    public static func match(path: String, query: String) -> (score: Int, matches: [Int])? {
        let haystack = Array(path.lowercased())
        let needle = Array(query.lowercased())
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        let nameStart = path.lastIndex(of: "/").map { path.distance(from: path.startIndex, to: $0) + 1 } ?? 0
        var score = 0
        var haystackIndex = 0
        var previousMatch = -2
        var matches: [Int] = []
        matches.reserveCapacity(needle.count)

        for character in needle {
            var found = -1
            var index = haystackIndex
            while index < haystack.count {
                if haystack[index] == character { found = index; break }
                index += 1
            }
            guard found >= 0 else { return nil }
            score += 1
            if found == previousMatch + 1 { score += 5 }
            if found >= nameStart { score += 3 }
            if found == 0 || haystack[found - 1] == "/" || haystack[found - 1] == "_"
                || haystack[found - 1] == "-" || haystack[found - 1] == "." {
                score += 4
            }
            matches.append(found)
            previousMatch = found
            haystackIndex = found + 1
        }
        // A short path carrying the same letters is the better answer.
        return (score * 100 - haystack.count, matches)
    }
}
