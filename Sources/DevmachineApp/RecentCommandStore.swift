import Foundation
import DevmachineCore

/// The custom commands typed into the new-session menu or chosen as a session
/// default in Settings, kept per workspace so running one again is a single
/// click.
@MainActor
final class RecentCommandStore: ObservableObject {
    @Published private(set) var byWorkspace: [String: [String]]

    static let key = "recentCustomCommands.v1"
    /// Where the removed Custom commands page saved its list.
    static let legacyKey = "customCommands.v1"
    private static let legacyMigratedKey = "recentCustomCommands.legacyMigrated"
    /// Commands the old page offered in every workspace.
    nonisolated private static let everywhere = "*"
    /// The list behind Settings' "Remote fallback" row. Not an ssh alias.
    static let remoteFallback = "@remote-fallback"

    private let defaults: UserDefaults
    private let persists: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        persists = !DemoMode.isActive
        guard persists else {
            byWorkspace = DemoData.recentCommands
            return
        }
        byWorkspace = (defaults.dictionary(forKey: Self.key) as? [String: [String]]) ?? [:]
        migrateLegacyCommands()
    }

    func recents(for alias: String) -> [String] {
        RecentCommands.merged([byWorkspace[Self.bucket(alias)] ?? [], byWorkspace[Self.everywhere] ?? []])
    }

    /// Returns the command as it will run, or nil when the text is blank.
    @discardableResult
    func record(_ raw: String, for alias: String) -> String? {
        guard let command = CustomSessionCommand.normalized(raw) else { return nil }
        let bucket = Self.bucket(alias)
        byWorkspace[bucket] = RecentCommands.recording(command, in: byWorkspace[bucket] ?? [])
        persist()
        return command
    }

    /// Adds a command at the top unless the list already has it, which keeps
    /// the order a Settings save would otherwise shuffle.
    func remember(_ raw: String, for alias: String) {
        guard let command = CustomSessionCommand.normalized(raw),
              !recents(for: alias).contains(command) else { return }
        record(command, for: alias)
    }

    /// A command offered everywhere lives in one shared list, so removing it
    /// here removes it from every workspace.
    func remove(_ command: String, for alias: String) {
        for bucket in [Self.bucket(alias), Self.everywhere] {
            byWorkspace[bucket]?.removeAll { $0 == command }
        }
        persist()
    }

    /// Aliases are matched case-insensitively, the way the old page scoped
    /// commands: ssh alias casing does not always round-trip.
    nonisolated private static func bucket(_ alias: String) -> String { alias.lowercased() }

    private func persist() {
        guard persists else { return }
        defaults.set(byWorkspace, forKey: Self.key)
    }

    private func migrateLegacyCommands() {
        guard !defaults.bool(forKey: Self.legacyMigratedKey) else { return }
        defaults.set(true, forKey: Self.legacyMigratedKey)
        guard let data = defaults.data(forKey: Self.legacyKey),
              let legacy = try? JSONDecoder().decode([LegacyCommand].self, from: data) else { return }
        for item in legacy {
            guard let command = CustomSessionCommand.normalized(item.command) else { continue }
            for bucket in item.scope.buckets {
                let existing = byWorkspace[bucket] ?? []
                guard !existing.contains(command) else { continue }
                byWorkspace[bucket] = Array((existing + [command]).prefix(RecentCommands.capacity))
            }
        }
        persist()
    }

    private struct LegacyCommand: Decodable {
        let command: String
        let scope: LegacyScope
    }

    private enum LegacyScope: Decodable {
        case all
        case localOnly
        case workspaces([String])

        var buckets: [String] {
            switch self {
            case .all: return [RecentCommandStore.everywhere]
            case .localOnly: return [RecentCommandStore.bucket(Workspace.local.alias)]
            case let .workspaces(aliases): return aliases.map(RecentCommandStore.bucket)
            }
        }
    }
}
