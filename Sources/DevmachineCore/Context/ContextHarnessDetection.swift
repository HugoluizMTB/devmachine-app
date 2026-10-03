import Foundation

/// Picks which harness a local session belongs to: the harnesses the caller
/// already knows run there (the session's processes, or the pane's current
/// command), else whichever harness has the most recently modified
/// transcript for this project directory.
public enum ContextHarnessDetection {
    public static func detect(
        project: URL, paneCommand: String?, harnesses: Set<HarnessID> = [],
        roots: ContextRoots = ContextRoots(), processNames: [HarnessID: Set<String>] = [:],
        fileManager: FileManager = .default
    ) -> (harness: HarnessID, transcripts: [ContextTranscriptFile])? {
        let readers = roots.readers
        func newest(of candidates: [any ContextHarnessReader]) -> (HarnessID, [ContextTranscriptFile])? {
            var best: (HarnessID, [ContextTranscriptFile])?
            for reader in candidates {
                let files = reader.recentTranscripts(for: project, limit: 4, fileManager: fileManager)
                guard let first = files.first else { continue }
                if best == nil || first.modified > best!.1[0].modified { best = (reader.harness, files) }
            }
            return best
        }

        let named = harnesses.union(paneCommand.map { self.harnesses(running: $0, processNames: processNames) } ?? [])
        if !named.isEmpty, let found = newest(of: readers.filter { named.contains($0.harness) }) {
            return found
        }
        return newest(of: readers)
    }

    /// The harnesses whose program the pane runs, by exact program name: a
    /// pane running `pip` is not Pi. A harness with no names given is known
    /// by its id.
    public static func harnesses(running paneCommand: String, processNames: [HarnessID: Set<String>]) -> Set<HarnessID> {
        let head = paneCommand.split(separator: " ").first.map(String.init) ?? paneCommand
        var program = (head as NSString).lastPathComponent
        if program.hasPrefix("-") { program.removeFirst() }
        guard !program.isEmpty else { return [] }
        let catalog = processNames.isEmpty
            ? Dictionary(uniqueKeysWithValues: ContextRoots.supportedHarnesses.map { ($0, Set([$0.rawValue])) })
            : processNames
        return Set(catalog.compactMap { $0.value.contains(program) ? $0.key : nil })
    }
}
