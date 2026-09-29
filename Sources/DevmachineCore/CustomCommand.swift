import Foundation

/// Where a custom command is offered: everywhere, only from this Mac, or only
/// from the chosen workspaces.
public enum CustomCommandScope: Codable, Equatable, Sendable {
    case all
    case localOnly
    case workspaces([String])

    /// Whether this scope offers the command for the given target: the local
    /// machine, or a remote workspace by its alias.
    public func applies(toLocal isLocal: Bool, alias: String) -> Bool {
        switch self {
        case .all:
            return true
        case .localOnly:
            return isLocal
        case let .workspaces(aliases):
            // Case-insensitively, the way `Workspace.isHidden` matches an
            // alias: ssh alias casing is not guaranteed to round-trip.
            return !isLocal && aliases.contains { $0.lowercased() == alias.lowercased() }
        }
    }
}

/// A small, fixed set of SF Symbols so a command's icon always renders — no
/// icon name typed by hand.
public enum CustomCommandIcon: String, Codable, Sendable, CaseIterable {
    case terminal
    case bolt
    case hammer
    case sparkles
    case play
    case gearshape
    case flask
    case star
    case command
    case wandAndStars

    public var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .bolt: return "bolt.fill"
        case .hammer: return "hammer.fill"
        case .sparkles: return "sparkles"
        case .play: return "play.fill"
        case .gearshape: return "gearshape.fill"
        case .flask: return "flask.fill"
        case .star: return "star.fill"
        case .command: return "command"
        case .wandAndStars: return "wand.and.stars"
        }
    }
}

/// A user-defined launch command: a name and a command line, run in a brand
/// new session the same way a coding harness starts one.
public struct CustomCommand: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var icon: CustomCommandIcon
    public var scope: CustomCommandScope
    /// One slot in ⌘⌥1…⌘⌥9, unique among commands. Nil means no shortcut.
    public var shortcutSlot: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        icon: CustomCommandIcon = .terminal,
        scope: CustomCommandScope = .all,
        shortcutSlot: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.icon = icon
        self.scope = scope
        self.shortcutSlot = shortcutSlot
    }

    public static let shortcutSlotRange = 1...9

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedCommand: String { command.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool { !trimmedName.isEmpty && !trimmedCommand.isEmpty }

    public func applies(toLocal isLocal: Bool, alias: String) -> Bool {
        scope.applies(toLocal: isLocal, alias: alias)
    }

    /// Commands with a shortcut slot, in slot order — the order ⌘⌥1…⌘⌥9 fire.
    public static func shortcutEntries(in commands: [CustomCommand]) -> [CustomCommand] {
        commands
            .filter { $0.shortcutSlot != nil }
            .sorted { $0.shortcutSlot! < $1.shortcutSlot! }
    }

    /// Every command offered for this target, in list order.
    public static func applicable(in commands: [CustomCommand], toLocal isLocal: Bool, alias: String) -> [CustomCommand] {
        commands.filter { $0.applies(toLocal: isLocal, alias: alias) }
    }
}
