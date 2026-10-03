import Foundation

/// One `settings:` entry of a workspace, as `workspaces edit --set` takes it:
/// `<package>.<name>` and a value the CLI reads as YAML.
public struct WorkspaceSetting: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }
    var trimmedValue: String { value.trimmingCharacters(in: .whitespaces) }

    /// The package part of the key, before its first dot.
    public var package: String? {
        let parts = trimmedKey.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return String(parts[0])
    }

    /// What the CLI would refuse: a key that is not `<package>.<name>`, a
    /// package the workspace does not install (its validation catches that),
    /// or no value (an empty `--set` removes the setting instead).
    public func problem(packages: [String]) -> String? {
        guard let package else { return "Write the setting as <package>.<name>, like zsh.theme." }
        if !packages.contains(package), package != WorkspacePackageCatalog.account {
            return "\(package) is not one of this workspace's packages, so the CLI refuses its setting."
        }
        if trimmedValue.isEmpty { return "Type a value, or remove the setting." }
        return nil
    }
}

/// What `workspaces edit` changes: packages to add and take off, settings to
/// write and take out. Nothing here is the machine, the account or a login.
public struct WorkspaceChanges: Equatable, Sendable {
    public var add: [String]
    public var remove: [String]
    public var set: [WorkspaceSetting]
    public var unset: [String]

    public init(add: [String] = [], remove: [String] = [], set: [WorkspaceSetting] = [], unset: [String] = []) {
        self.add = add
        self.remove = remove
        self.set = set
        self.unset = unset
    }

    public var isEmpty: Bool { add.isEmpty && remove.isEmpty && set.isEmpty && unset.isEmpty }

    /// The flags that turn `packages` and `settings` into the chosen ones.
    public static func between(
        packages: [String], settings: [String: String], chosenPackages: [String], chosenSettings: [WorkspaceSetting]
    ) -> WorkspaceChanges {
        let chosenKeys = Set(chosenSettings.map(\.trimmedKey))
        return WorkspaceChanges(
            add: chosenPackages.filter { !packages.contains($0) },
            remove: packages.filter { !chosenPackages.contains($0) },
            set: chosenSettings
                .filter { settings[$0.trimmedKey] != $0.trimmedValue }
                .map { WorkspaceSetting(key: $0.trimmedKey, value: $0.trimmedValue) },
            unset: settings.keys.filter { !chosenKeys.contains($0) }.sorted())
    }
}

/// The `devmachine` commands the Workspaces page runs. Each one only edits
/// the configuration on this Mac, except `sync` and `destroy`, which reach
/// the machine; nothing here reimplements the CLI.
public enum WorkspacePlan {
    public static func newSteps(name: String, machine: String, packages: [String], sync: Bool) -> [MachinePlanStep] {
        // `--packages=` with nothing chosen still overrides
        // `defaults.workspace`: the person unticked every card on purpose.
        let list = packages.isEmpty ? ["--packages="] : ["--packages", packages.joined(separator: ",")]
        let declare = MachinePlanStep(
            kind: .newWorkspace, title: "Add the workspace \(name) to \(machine)",
            arguments: ["workspaces", "new", name, "--machine", machine] + list + ["--yes"], asksInTerminal: false)
        return [declare] + (sync ? [syncStep(machine: machine)] : [])
    }

    /// `edit` is never given `--machine`: there it moves the workspace,
    /// which this page does not offer.
    public static func editSteps(
        name: String, machine: String, changes: WorkspaceChanges, sync: Bool
    ) -> [MachinePlanStep] {
        var arguments = ["workspaces", "edit", name]
        arguments += changes.add.flatMap { ["--add", $0] }
        arguments += changes.remove.flatMap { ["--rm", $0] }
        arguments += changes.set.flatMap { ["--set", "\($0.key)=\($0.value)"] }
        arguments += changes.unset.flatMap { ["--unset", $0] }
        let edit = MachinePlanStep(
            kind: .editWorkspace, title: "Change \(name)", arguments: arguments + ["--yes"], asksInTerminal: false)
        return [edit] + (sync ? [syncStep(machine: machine)] : [])
    }

    public static func forgetSteps(name: String) -> [MachinePlanStep] {
        [MachinePlanStep(
            kind: .forgetWorkspace, title: "Forget \(name)", arguments: ["workspaces", "rm", name, "--yes"],
            asksInTerminal: false)]
    }

    /// `--confirm` is the name typed again, which is what lets the command
    /// run without its own prompt; the page asks for it the same way.
    public static func destroySteps(name: String, keepDNS: Bool) -> [MachinePlanStep] {
        [MachinePlanStep(
            kind: .destroyWorkspace, title: "Destroy \(name)",
            arguments: ["workspaces", "destroy", name, "--confirm", name] + (keepDNS ? ["--keep-dns"] : []),
            asksInTerminal: false)]
    }

    static func syncStep(machine: String) -> MachinePlanStep {
        MachinePlanStep(
            kind: .sync, title: "Apply it on \(machine)", arguments: ["sync", "--machine", machine, "--yes"],
            asksInTerminal: false)
    }
}
