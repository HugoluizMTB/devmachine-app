import XCTest
@testable import ClaudeUsageKit

final class UsageStatsEngineTests: XCTestCase {
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private func assistantLine(timestamp: Date, model: String, tokens: Int) -> String {
        let ts = isoFormatter.string(from: timestamp)
        return """
        {"type":"assistant","timestamp":"\(ts)","message":{"model":"\(model)","usage":{"input_tokens":\(tokens),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    func testComputeSumsTokensByDayAndModel() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!.addingTimeInterval(3600)
        let today = todayStart.addingTimeInterval(3600)

        let recentFile = tempDir.appendingPathComponent("recent.jsonl")
        let recentLines = [
            assistantLine(timestamp: yesterday, model: "claude-opus-4", tokens: 100),
            assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 200),
            assistantLine(timestamp: today, model: "<synthetic>", tokens: 999),
            #"{"type":"user","timestamp":"\#(isoFormatter.string(from: today))","message":{"model":"claude-sonnet-4","usage":{"input_tokens":500,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        ]
        try recentLines.joined(separator: "\n").write(to: recentFile, atomically: true, encoding: .utf8)

        let subagentsDir = tempDir.appendingPathComponent("subagents")
        try fm.createDirectory(at: subagentsDir, withIntermediateDirectories: true)
        let subFile = subagentsDir.appendingPathComponent("sub.jsonl")
        try assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 50)
            .write(to: subFile, atomically: true, encoding: .utf8)

        let oldFile = tempDir.appendingPathComponent("old.jsonl")
        let oldTimestamp = calendar.date(byAdding: .day, value: -20, to: now)!
        try assistantLine(timestamp: oldTimestamp, model: "claude-opus-4", tokens: 12345)
            .write(to: oldFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: oldTimestamp], ofItemAtPath: oldFile.path)

        let stats = UsageStatsEngine.compute(logsRoot: tempDir, now: now)

        let todayKey = dayFormatter.string(from: todayStart)
        let yesterdayKey = dayFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: todayStart)!)

        XCTAssertEqual(stats.dailyTotals.count, 7)
        // Daily totals count every assistant line's tokens, `<synthetic>` included -
        // only the per-model breakdown excludes it (200 sonnet + 999 synthetic + 50 subagent sonnet).
        XCTAssertEqual(stats.dailyTotals.first(where: { $0.date == todayKey })?.tokens, 1249)
        XCTAssertEqual(stats.dailyTotals.first(where: { $0.date == yesterdayKey })?.tokens, 100)
        XCTAssertEqual(stats.todayTokens, 1249)

        XCTAssertEqual(stats.modelTotals.count, 2)
        XCTAssertEqual(stats.modelTotals.first?.model, "claude-sonnet-4")
        XCTAssertEqual(stats.modelTotals.first?.tokens, 250)
        XCTAssertEqual(stats.mostUsedModel, "claude-sonnet-4")
        XCTAssertFalse(stats.modelTotals.contains(where: { $0.model == "<synthetic>" }))
    }

    func testComputeSkipsUnchangedFileOnSecondRun() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let now = Date()
        let stamp = Date(timeIntervalSince1970: (now.timeIntervalSince1970 - 3600).rounded())
        let today = Calendar.current.startOfDay(for: now).addingTimeInterval(3600)

        let file = tempDir.appendingPathComponent("recent.jsonl")
        let content = assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 100)
        try content.write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)

        let cache = UsageStatsCache()
        let first = UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: cache)
        XCTAssertEqual(first.todayTokens, 100)

        // Same byte count and same mtime: the cached sums must win over the
        // rewritten content, which would otherwise parse to nothing.
        let garbage = String(repeating: "x", count: content.utf8.count)
        try garbage.write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)

        let second = UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: cache)

        XCTAssertEqual(second, first)
        XCTAssertEqual(second.todayTokens, 100)
    }

    func testComputeRereadsFileAfterItGrows() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now).addingTimeInterval(3600)
        let file = tempDir.appendingPathComponent("recent.jsonl")
        let firstLine = assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 100)
        try firstLine.write(to: file, atomically: true, encoding: .utf8)

        let cache = UsageStatsCache()
        XCTAssertEqual(UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: cache).todayTokens, 100)

        let grown = [firstLine, assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 200)]
            .joined(separator: "\n")
        try grown.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: cache).todayTokens, 300)
    }

    func testComputeDropsFilesThatLeftTheWindowFromTheCache() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now).addingTimeInterval(3600)
        let file = tempDir.appendingPathComponent("recent.jsonl")
        try assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 100)
            .write(to: file, atomically: true, encoding: .utf8)

        let cache = UsageStatsCache()
        _ = UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: cache)
        XCTAssertEqual(cache.count, 1)

        let oldTimestamp = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        try fm.setAttributes([.modificationDate: oldTimestamp], ofItemAtPath: file.path)

        let stats = UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: cache)

        XCTAssertEqual(stats.todayTokens, 0)
        XCTAssertEqual(cache.count, 0)
    }

    func testComputeReadsLinesAcrossChunkBoundaries() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now).addingTimeInterval(3600)
        let lineCount = 4000
        var lines: [String] = []
        for _ in 0..<lineCount {
            lines.append(assistantLine(timestamp: today, model: "claude-sonnet-4", tokens: 100))
        }
        lines.append("")
        lines.append("not json at all")

        let file = tempDir.appendingPathComponent("big.jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        let attributes = try fm.attributesOfItem(atPath: file.path)
        XCTAssertGreaterThan((attributes[.size] as? Int) ?? 0, 1 << 18)

        let stats = UsageStatsEngine.compute(logsRoot: tempDir, now: now, cache: UsageStatsCache())

        XCTAssertEqual(stats.todayTokens, Int64(lineCount) * 100)
        XCTAssertEqual(stats.modelTotals.first?.tokens, Int64(lineCount) * 100)
    }

    func testComputeExcludesFileOlderThanWindow() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let now = Date()
        let calendar = Calendar.current
        let oldTimestamp = calendar.date(byAdding: .day, value: -30, to: now)!

        let oldFile = tempDir.appendingPathComponent("old.jsonl")
        try assistantLine(timestamp: oldTimestamp, model: "claude-opus-4", tokens: 999)
            .write(to: oldFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: oldTimestamp], ofItemAtPath: oldFile.path)

        let stats = UsageStatsEngine.compute(logsRoot: tempDir, now: now)

        XCTAssertEqual(stats.todayTokens, 0)
        XCTAssertTrue(stats.modelTotals.isEmpty)
        XCTAssertNil(stats.mostUsedModel)
    }
}
