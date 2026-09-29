import Foundation

/// A Markdown checklist (`- [ ] ...` / `- [x] ...`) read as a plan, used when
/// a transcript names no todo tool but did touch a plan-shaped `.md` file —
/// the fallback devmachine-infer's `parse_plan`/`collect_plans` use.
public enum ContextPlanFile {
    private static let checklistItem = try! NSRegularExpression(
        pattern: #"^\s*[-*] \[([ xX])\]\s+(.+)$"#, options: [.anchorsMatchLines]
    )

    public static func parse(_ path: URL) -> ContextEngineResult.Plan? {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let items = checklistItem.matches(in: text).compactMap { match -> ContextEngineResult.PlanItem? in
            guard let mark = checklistItem.group(match, 1, in: text),
                  let body = checklistItem.group(match, 2, in: text)
            else { return nil }
            let state = mark.lowercased() == "x" ? "done" : "pending"
            return ContextEngineResult.PlanItem(text: body.trimmingCharacters(in: .whitespaces), state: state)
        }
        guard !items.isEmpty else { return nil }
        return ContextEngineResult.Plan(title: path.lastPathComponent, source: "file", items: items)
    }

    /// The most recently modified plan among the project's standard spec/plan
    /// directories and any `.md` file the session itself touched.
    public static func mostRecent(
        project: URL, touchedMarkdown: [String], fileManager: FileManager = .default
    ) -> ContextEngineResult.Plan? {
        var candidates: [URL] = []
        for sub in ["docs/superpowers/specs", "docs/superpowers/plans"] {
            let dir = project.appendingPathComponent(sub)
            guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }
            candidates.append(contentsOf: entries.filter { $0.pathExtension == "md" })
        }
        for fp in touchedMarkdown where fileManager.fileExists(atPath: fp) {
            candidates.append(URL(fileURLWithPath: fp))
        }
        let unique = Array(Set(candidates.map(\.standardizedFileURL.path))).map(URL.init(fileURLWithPath:))
        let withDates = unique.compactMap { url -> (URL, Date)? in
            guard let mtime = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            else { return nil }
            return (url, mtime)
        }
        for (url, _) in withDates.sorted(by: { $0.1 > $1.1 }) {
            if let plan = parse(url) { return plan }
        }
        return nil
    }
}
