import Foundation

/// Where a chat runs: a workspace by its CLI name, or this Mac.
public enum ChatPlace: Hashable, Sendable {
    case workspace(String)
    case local

    public var workspaceName: String? {
        if case let .workspace(name) = self { return name }
        return nil
    }

    public var flags: [String] {
        switch self {
        case let .workspace(name): return ["--workspace", name]
        case .local: return ["--local"]
        }
    }
}

/// The `devmachine chat` arguments the app runs. A message always comes
/// after `--`, so text that starts with a dash is never read as a flag.
public enum ChatCommand {
    public static func send(
        chatID: String?, place: ChatPlace, harness: HarnessID, folder: String, message: String
    ) -> [String] {
        var arguments = ["chat", "send"]
        if let chatID {
            arguments += ["--chat", chatID]
        } else {
            arguments += place.flags + ["--harness", harness.rawValue]
            let folder = folder.trimmingCharacters(in: .whitespaces)
            if !folder.isEmpty { arguments += ["--folder", folder] }
        }
        return arguments + ["--", message]
    }

    public static func ask(place: ChatPlace, session: String, chatID: String?, question: String) -> [String] {
        var arguments = ["chat", "ask"] + place.flags + ["--session", session]
        if let chatID { arguments += ["--chat", chatID] }
        return arguments + ["--", question]
    }

    public static func list() -> [String] { ["chat", "list", "--all", "--json"] }

    public static func show(id: String) -> [String] { ["chat", "show", id, "--json"] }

    public static func rename(id: String, title: String) -> [String] { ["chat", "rename", id, "--", title] }

    public static func delete(id: String) -> [String] { ["chat", "delete", id] }
}
