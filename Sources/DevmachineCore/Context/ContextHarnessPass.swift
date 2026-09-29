import Foundation

/// What one harness-specific parser pulls out of a transcript, before the
/// shared regex extraction and PR resolution run over it.
public struct ContextHarnessPass: Sendable {
    public var blobs: [ContextRefBlob] = []
    public var touchedMarkdown: [String] = []
    public var todoItems: [ContextEngineResult.PlanItem] = []
    public var agents: [ContextEngineResult.Agent] = []
    public var monitors: [ContextEngineResult.Agent] = []
    public var shells: [ContextEngineResult.Agent] = []
    public var newestTimestamp: String = ""

    public init() {}
}

/// Parses one JSONL transcript file into loosely-typed event dictionaries,
/// skipping malformed lines (partial writes from a crashed session).
enum ContextJSONLReader {
    static func events(at path: URL) -> [[String: Any]] {
        guard let data = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        var events: [[String: Any]] = []
        data.enumerateLines { line, _ in
            guard !line.isEmpty, let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return }
            events.append(obj)
        }
        return events
    }
}

let contextTaskDoneRegex = try! NSRegularExpression(pattern: #"<task-id>([^<]+)</task-id>"#)

func contextFindTaskIDs(in text: String) -> [String] {
    contextTaskDoneRegex.matches(in: text).compactMap { contextTaskDoneRegex.group($0, 1, in: text) }
}
