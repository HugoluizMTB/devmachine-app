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
    /// A new chat names where and with what; its folder is the CLI's
    /// `chat.folder`. A continued chat takes all three from its record.
    /// `mcp` nil leaves the chat's own choice (off for a new chat); see
    /// `ChatMCP.flag`.
    public static func send(
        chatID: String?, place: ChatPlace, harness: HarnessID, message: String, mcp: Bool? = nil
    ) -> [String] {
        var arguments = ["chat", "send"]
        if let chatID {
            arguments += ["--chat", chatID]
        } else {
            arguments += place.flags + ["--harness", harness.rawValue]
        }
        arguments += ChatMCP.arguments(mcp)
        return arguments + ["--", message]
    }

    /// `folder` is the session's own folder, which a session on this Mac
    /// outside tmux needs; `harness` is the app's guess at what runs there.
    public static func ask(
        place: ChatPlace, session: String, folder: String? = nil, harness: HarnessID? = nil, chatID: String?,
        question: String
    ) -> [String] {
        var arguments = ["chat", "ask"] + place.flags + ["--session", session]
        if let folder, !folder.isEmpty { arguments += ["--folder", folder] }
        if let harness { arguments += ["--harness", harness.rawValue] }
        if let chatID { arguments += ["--chat", chatID] }
        return arguments + ["--", question]
    }

    public static func configShow() -> [String] { ["--format", "json", "config", "show"] }

    public static func list() -> [String] { ["chat", "list", "--all", "--json"] }

    public static func show(id: String) -> [String] { ["chat", "show", id, "--json"] }

    public static func rename(id: String, title: String) -> [String] { ["chat", "rename", id, "--", title] }

    public static func delete(id: String) -> [String] { ["chat", "delete", id] }
}

/// MCP servers, hooks and plugins are off in a chat unless asked for; the
/// CLI keeps the choice on the chat.
public enum ChatMCP {
    /// What to pass for a message: nil when the chat already has `chosen`,
    /// so an older CLI without `--mcp` still works. A new chat says it
    /// whenever MCP is in play (`chat.mcp` on, or the chip on), whichever
    /// default the CLI applies.
    public static func flag(chosen: Bool, record: ChatRecord?, configDefault: Bool = false) -> Bool? {
        guard let record else { return chosen || configDefault ? chosen : nil }
        return chosen == record.mcp ? nil : chosen
    }

    static func arguments(_ mcp: Bool?) -> [String] {
        switch mcp {
        case true?: return ["--mcp"]
        case false?: return ["--mcp=false"]
        case nil: return []
        }
    }
}
