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

    func processNames(for settings: AppSettings) -> [HarnessID: Set<String>] {
        var catalog: [HarnessID: Set<String>] = [:]
        for adapter in registry.adapters where settings.enabledHarnesses.contains(adapter.id) {
            catalog[adapter.id, default: []].formUnion(adapter.processNames)
        }
        return catalog
    }

    func detect(
        sessions: [ZmxSession],
        entries: [ProcessTree.Entry],
        settings: AppSettings
    ) -> [String: Set<HarnessID>] {
        let catalog = processNames(for: settings)
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
}

extension TmuxSession {
    /// Compatibility for views that Task 5 will migrate to generic badges.
    var hasClaude: Bool {
        harnesses.contains(.claude)
    }
}
