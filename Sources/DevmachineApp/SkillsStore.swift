import Foundation
import SwiftUI
import DevmachineCore

struct SkillCommand: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String
    var command: String
    var systemImage: String

    init(id: UUID = UUID(), label: String, command: String, systemImage: String) {
        self.id = id
        self.label = label
        self.command = command
        self.systemImage = systemImage
    }
}

@MainActor
final class SkillsStore: ObservableObject {
    @Published var skills: [SkillCommand]

    private static let defaultsKey = "skillShortcuts"

    static let defaultSkills: [SkillCommand] = [
        SkillCommand(label: "eoq", command: "/eoq", systemImage: "chart.bar"),
        SkillCommand(label: "bpp", command: "/bpp", systemImage: "list.bullet"),
        SkillCommand(label: "babysit-ci", command: "/babysit-ci", systemImage: "checkmark.seal"),
        SkillCommand(label: "pr-voice", command: "/pr-voice", systemImage: "text.bubble")
    ]

    private let remote: RemoteService
    private let defaults: UserDefaults

    init(remote: RemoteService = RemoteService(), defaults: UserDefaults = .standard) {
        self.remote = remote
        self.defaults = defaults
        self.skills = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> [SkillCommand] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SkillCommand].self, from: data) else {
            return defaultSkills
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(skills) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func add(label: String, command: String, systemImage: String) {
        skills.append(SkillCommand(label: label, command: command, systemImage: systemImage))
        persist()
    }

    func remove(_ skill: SkillCommand) {
        skills.removeAll { $0.id == skill.id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        skills.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func send(_ skill: SkillCommand, alias: String, session: String) {
        let remote = self.remote
        Task.detached {
            _ = try? remote.run(alias: alias, args: [RemoteCommands.sendKeys(session: session, text: skill.command)])
        }
    }
}
