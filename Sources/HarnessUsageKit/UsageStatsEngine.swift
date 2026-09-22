import Foundation

// Per-file token sums, kept between runs. Transcripts are append-only JSONL,
// so a file whose size and modification date are unchanged has the same
// content and never needs parsing again.
public final class UsageStatsCache: @unchecked Sendable {
    struct Entry {
        let modified: Date
        let size: Int64
        let windowStart: String
        let perDay: [String: Int64]
        let perModel: [String: Int64]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func entry(path: String, modified: Date, size: Int64, windowStart: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path],
              entry.modified == modified,
              entry.size == size,
              entry.windowStart == windowStart
        else { return nil }
        return entry
    }

    func store(path: String, entry: Entry) {
        lock.lock()
        entries[path] = entry
        lock.unlock()
    }

    func keepOnly(_ paths: Set<String>) {
        lock.lock()
        entries = entries.filter { paths.contains($0.key) }
        lock.unlock()
    }
}

public enum UsageStatsEngine {
    public static let sharedCache = UsageStatsCache()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func compute(
        logsRoot: URL,
        now: Date,
        windowDays: Int = 7,
        cache: UsageStatsCache = sharedCache
    ) -> UsageStats {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: todayStart) else {
            return UsageStats(dailyTotals: [], modelTotals: [], todayTokens: 0, mostUsedModel: nil)
        }
        let windowStartKey = dayFormatter.string(from: windowStart)

        var perDay: [String: Int64] = [:]
        var perModel: [String: Int64] = [:]
        var seenPaths: Set<String> = []

        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
                      ),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= windowStart
                else { continue }

                let path = url.path
                let size = Int64(values.fileSize ?? 0)
                seenPaths.insert(path)

                let totals: (perDay: [String: Int64], perModel: [String: Int64])
                if let cached = cache.entry(path: path, modified: modified, size: size, windowStart: windowStartKey) {
                    totals = (cached.perDay, cached.perModel)
                } else {
                    totals = fileTotals(of: url, windowStart: windowStart)
                    cache.store(path: path, entry: UsageStatsCache.Entry(
                        modified: modified,
                        size: size,
                        windowStart: windowStartKey,
                        perDay: totals.perDay,
                        perModel: totals.perModel
                    ))
                }

                for (day, tokens) in totals.perDay { perDay[day, default: 0] += tokens }
                for (model, tokens) in totals.perModel { perModel[model, default: 0] += tokens }
            }
        }
        cache.keepOnly(seenPaths)

        var dailyTotals: [DayTokens] = []
        for offset in stride(from: windowDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let key = dayFormatter.string(from: date)
            dailyTotals.append(DayTokens(date: key, tokens: perDay[key] ?? 0))
        }

        let modelTotals = perModel
            .map { ModelTokens(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        let todayKey = dayFormatter.string(from: todayStart)
        let todayTokens = perDay[todayKey] ?? 0

        return UsageStats(
            dailyTotals: dailyTotals,
            modelTotals: modelTotals,
            todayTokens: todayTokens,
            mostUsedModel: modelTotals.first?.model
        )
    }

    private static func fileTotals(
        of url: URL,
        windowStart: Date
    ) -> (perDay: [String: Int64], perModel: [String: Int64]) {
        var perDay: [String: Int64] = [:]
        var perModel: [String: Int64] = [:]

        forEachLine(in: url) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any],
                  let timestampString = obj["timestamp"] as? String,
                  let timestamp = isoFormatter.date(from: timestampString),
                  timestamp >= windowStart
            else { return }

            let tokens = Int64(usage["input_tokens"] as? Int ?? 0)
                + Int64(usage["output_tokens"] as? Int ?? 0)
                + Int64(usage["cache_creation_input_tokens"] as? Int ?? 0)
                + Int64(usage["cache_read_input_tokens"] as? Int ?? 0)

            let day = dayFormatter.string(from: timestamp)
            perDay[day, default: 0] += tokens
            if model != "<synthetic>" {
                perModel[model, default: 0] += tokens
            }
        }

        return (perDay, perModel)
    }

    private static func forEachLine(in url: URL, _ body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var pending = Data()
        while let chunk = try? handle.read(upToCount: 1 << 18), !chunk.isEmpty {
            var start = chunk.startIndex
            while let newline = chunk[start...].firstIndex(of: 0x0A) {
                if pending.isEmpty {
                    body(chunk[start..<newline])
                } else {
                    pending.append(chunk[start..<newline])
                    body(pending)
                    pending.removeAll(keepingCapacity: true)
                }
                start = chunk.index(after: newline)
            }
            if start < chunk.endIndex {
                pending.append(chunk[start...])
            }
        }
        if !pending.isEmpty {
            body(pending)
        }
    }
}
