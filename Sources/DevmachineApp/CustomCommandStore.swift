import Foundation
import DevmachineCore

/// User-defined launch commands, persisted on their own — never inside
/// `AppSettings` — so this feature never touches that file.
@MainActor
final class CustomCommandStore: ObservableObject {
    @Published private(set) var commands: [CustomCommand]

    /// Versioned so a future shape change can migrate instead of guessing.
    private static let key = "customCommands.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.commands = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> [CustomCommand] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.key)
    }

    @discardableResult
    func add(_ command: CustomCommand) -> Bool {
        guard command.isValid else { return false }
        commands.append(normalizingShortcut(command))
        persist()
        return true
    }

    @discardableResult
    func update(_ command: CustomCommand) -> Bool {
        guard command.isValid, let index = commands.firstIndex(where: { $0.id == command.id }) else { return false }
        commands[index] = normalizingShortcut(command)
        persist()
        return true
    }

    func remove(_ id: UUID) {
        commands.removeAll { $0.id == id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// A slot already used by another command is freed on it first: two
    /// commands never share ⌘⌥N.
    private func normalizingShortcut(_ command: CustomCommand) -> CustomCommand {
        guard let slot = command.shortcutSlot else { return command }
        for index in commands.indices where commands[index].id != command.id && commands[index].shortcutSlot == slot {
            commands[index].shortcutSlot = nil
        }
        return command
    }

    func applicable(toLocal isLocal: Bool, alias: String) -> [CustomCommand] {
        CustomCommand.applicable(in: commands, toLocal: isLocal, alias: alias)
    }
}
