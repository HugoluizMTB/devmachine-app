import SwiftUI
import DevmachineCore

struct HarnessBadgePresentation: Identifiable, Sendable {
    let id: HarnessID
    let shortTitle: String
    let systemImage: String
    let color: Color
    let helpText: String
}

struct SessionHarnessFacade: Sendable {
    let registry: HarnessRegistry

    init(registry: HarnessRegistry = .builtIn) {
        self.registry = registry
    }

    /// Every registered harness is detected, enabled or not: enabling one
    /// only adds it to the launch choices, and a harness that runs only on a
    /// remote host has no CLI here to enable.
    var processNames: [HarnessID: Set<String>] {
        registry.processNames
    }

    func detect(
        sessions: [ZmxSession],
        entries: [ProcessTree.Entry]
    ) -> [String: Set<HarnessID>] {
        let catalog = processNames
        let recognizedPrograms = Set(catalog.values.flatMap { $0 })
        let programsByRoot = ProcessTree.matchingPrograms(
            recognizedPrograms, roots: sessions.map(\.pid), in: entries)

        var result: [String: Set<HarnessID>] = [:]
        for session in sessions {
            let programs = programsByRoot[session.pid] ?? []
            result[session.name] = Set(catalog.compactMap { harness, names in
                names.isDisjoint(with: programs) ? nil : harness
            })
        }
        return result
    }

    func badges(for harnesses: Set<HarnessID>) -> [HarnessBadgePresentation] {
        registry.adapters.compactMap { adapter in
            guard harnesses.contains(adapter.id) else { return nil }
            let descriptor = adapter.descriptor
            return HarnessBadgePresentation(
                id: descriptor.id,
                shortTitle: descriptor.shortTitle,
                systemImage: descriptor.systemImage,
                color: descriptor.color,
                helpText: descriptor.helpText)
        }
    }

    func uploadStoragePolicy(for harnesses: Set<HarnessID>) -> UploadStoragePolicy {
        registry.adapters.first { harnesses.contains($0.id) }?.uploadStoragePolicy ?? .appManaged
    }
}

extension TmuxSession {
    /// Compatibility for views that Task 5 will migrate to generic badges.
    var hasClaude: Bool {
        harnesses.contains(.claude)
    }
}
