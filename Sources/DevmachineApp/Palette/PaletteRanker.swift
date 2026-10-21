import Foundation
import DevmachineCore

struct PaletteSection: Identifiable {
    let category: PaletteCategory
    let commands: [PaletteCommand]
    var id: Int { category.rawValue }
}

/// Orders the palette. With no query: what was run lately, then the
/// sessions, then the screens. With a query: fuzzy score plus a bonus for
/// recent use, for sessions and for the workspace in front of you, grouped
/// by category with the best group first.
enum PaletteRanker {
    static let recentLimit = 5
    static let sessionBonus = 20
    static let currentWorkspaceBonus = 30

    static func sections(
        _ commands: [PaletteCommand], query: String, mru: CommandMRU, currentWorkspace: String? = nil,
        inChats: Bool = false
    ) -> [PaletteSection] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? emptyQuerySections(commands, mru: mru)
            : matchedSections(
                commands, query: query, mru: mru, currentWorkspace: currentWorkspace, inChats: inChats)
    }

    static let chatsBonus = 40
    /// A screen that lists the whole query as a keyword beats another
    /// command whose title only starts with it ("dns" opens Published apps,
    /// not Settings → DNS providers).
    static let exactKeywordBonus = 400

    /// In Chats mode, the groups that start or open a chat come first, and
    /// inside a group so do those commands.
    static func isChatCommand(_ command: PaletteCommand) -> Bool {
        command.category == .chats || command.id.hasPrefix("action.new-chat")
    }

    private static func hasKeyword(_ command: PaletteCommand, equalTo query: String) -> Bool {
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        return command.keywords.contains { $0.lowercased() == wanted }
    }

    private static func emptyQuerySections(_ commands: [PaletteCommand], mru: CommandMRU) -> [PaletteSection] {
        let byID = Dictionary(commands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = mru.ids.compactMap { byID[$0] }.prefix(recentLimit)
        let recentIDs = Set(recent.map(\.id))
        let rest = commands.filter { !recentIDs.contains($0.id) }
        return [
            PaletteSection(category: .recent, commands: Array(recent)),
            PaletteSection(category: .goTo, commands: rest.filter { $0.category == .goTo }),
            PaletteSection(category: .session, commands: rest.filter { $0.category == .session }),
        ].filter { !$0.commands.isEmpty }
    }

    private static func matchedSections(
        _ commands: [PaletteCommand], query: String, mru: CommandMRU, currentWorkspace: String?, inChats: Bool
    ) -> [PaletteSection] {
        let scored = commands.compactMap { command -> (PaletteCommand, Int)? in
            let fields = [command.title, command.subtitle, command.keywords.joined(separator: " ")]
            guard let score = FuzzyMatch.score(query, fields: fields) else { return nil }
            var total = score + mru.boost(for: command.id)
            if command.category == .session { total += sessionBonus }
            if command.category == .goTo, hasKeyword(command, equalTo: query) { total += exactKeywordBonus }
            if inChats, isChatCommand(command) { total += chatsBonus }
            if let currentWorkspace, !command.subtitle.isEmpty, command.subtitle == currentWorkspace {
                total += currentWorkspaceBonus
            }
            return (command, total)
        }
        let groups = Dictionary(grouping: scored, by: { $0.0.category })
        return groups
            .map { category, members -> (PaletteSection, Int) in
                let sorted = members.sorted { lhs, rhs in
                    lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.title < rhs.0.title
                }
                return (PaletteSection(category: category, commands: sorted.map(\.0)), sorted[0].1)
            }
            .sorted { lhs, rhs in
                let left = inChats && lhs.0.commands.first.map(isChatCommand) == true
                let right = inChats && rhs.0.commands.first.map(isChatCommand) == true
                if left != right { return left }
                if left, lhs.0.category != rhs.0.category { return lhs.0.category == .action }
                return lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.category < rhs.0.category
            }
            .map(\.0)
    }
}
