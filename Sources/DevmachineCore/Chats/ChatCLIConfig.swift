import Foundation

/// The CLI's chat settings (`chat.default_workspace`, `chat.folder`,
/// `chat.harness` in config.yml), as `config show` reports them with their
/// defaults filled in. The CLI owns them, so a chat started from a terminal
/// lands where one started from the app does.
public struct ChatCLIConfig: Codable, Equatable, Sendable {
    public static let keys = (
        workspace: "chat.default_workspace", folder: "chat.folder", harness: "chat.harness", mcp: "chat.mcp")

    public var defaultWorkspace: String
    public var folder: String
    public var harness: HarnessID
    /// Whether a new chat loads the account's MCP servers; off by default.
    public var mcp: Bool

    public init(
        defaultWorkspace: String = "", folder: String = "~/chats", harness: HarnessID = .claude, mcp: Bool = false
    ) {
        self.defaultWorkspace = defaultWorkspace
        self.folder = folder
        self.harness = harness
        self.mcp = mcp
    }

    enum CodingKeys: String, CodingKey {
        case defaultWorkspace = "default_workspace"
        case folder, harness, mcp
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultWorkspace = (try? values.decodeIfPresent(String.self, forKey: .defaultWorkspace)) ?? ""
        let folder = (try? values.decodeIfPresent(String.self, forKey: .folder)) ?? ""
        self.folder = folder.isEmpty ? "~/chats" : folder
        let harness = (try? values.decodeIfPresent(String.self, forKey: .harness)) ?? ""
        self.harness = harness.isEmpty ? .claude : HarnessID(rawValue: harness)
        mcp = (try? values.decodeIfPresent(Bool.self, forKey: .mcp)) ?? false
    }

    private struct Show: Decodable { let chat: ChatCLIConfig? }

    /// The `chat` part of `--format json config show`; nil from an older CLI.
    public static func fromConfigShow(_ data: Data) -> ChatCLIConfig? {
        (try? JSONDecoder().decode(Show.self, from: data))?.chat
    }

    /// Where a new chat starts: the saved workspace while it still exists,
    /// else the first workspace, else this Mac.
    public func defaultPlace(workspaces: [String]) -> ChatPlace {
        if defaultWorkspace == ChatRecord.localWorkspace { return .local }
        if workspaces.contains(defaultWorkspace) { return .workspace(defaultWorkspace) }
        return workspaces.first.map(ChatPlace.workspace) ?? .local
    }

    /// The `config set|unset` runs that turn `old` into `self`. An empty
    /// folder goes back to the CLI's default.
    public func changes(from old: ChatCLIConfig) -> [[String]] {
        var runs: [[String]] = []
        if defaultWorkspace != old.defaultWorkspace {
            runs.append(defaultWorkspace.isEmpty
                ? ["config", "unset", Self.keys.workspace] : ["config", "set", Self.keys.workspace, defaultWorkspace])
        }
        let folder = self.folder.trimmingCharacters(in: .whitespaces)
        if folder != old.folder {
            runs.append(folder.isEmpty ? ["config", "unset", Self.keys.folder] : ["config", "set", Self.keys.folder, folder])
        }
        if harness != old.harness {
            runs.append(["config", "set", Self.keys.harness, harness.rawValue])
        }
        if mcp != old.mcp {
            runs.append(mcp ? ["config", "set", Self.keys.mcp, "true"] : ["config", "unset", Self.keys.mcp])
        }
        return runs
    }
}
