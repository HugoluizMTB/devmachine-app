import Foundation

/// Settings → Chats. The app passes these as flags on every new chat, so
/// a chat starts where Settings says whatever the CLI's own defaults are.
public struct ChatSettings: Codable, Equatable, Sendable {
    public static let defaultFolder = "~/chats"
    public static let `default` = ChatSettings()

    /// A workspace name, `"local"` for this Mac, or empty for the first
    /// workspace.
    public var defaultWorkspace: String
    public var folder: String
    /// Nil when the person cleared the shortcut.
    public var hotkey: ChatHotkey?
    public var showsInMenuBar: Bool
    public var enabledHarnesses: [HarnessID]

    public init(
        defaultWorkspace: String = "", folder: String = ChatSettings.defaultFolder,
        hotkey: ChatHotkey? = .defaultValue, showsInMenuBar: Bool = true,
        enabledHarnesses: [HarnessID] = ChatHarness.supported
    ) {
        self.defaultWorkspace = defaultWorkspace
        self.folder = folder
        self.hotkey = hotkey
        self.showsInMenuBar = showsInMenuBar
        self.enabledHarnesses = enabledHarnesses
    }

    enum CodingKeys: String, CodingKey {
        case defaultWorkspace, folder, hotkey, showsInMenuBar, enabledHarnesses
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultWorkspace = (try? values.decodeIfPresent(String.self, forKey: .defaultWorkspace)) ?? ""
        let folder = (try? values.decodeIfPresent(String.self, forKey: .folder)) ?? ""
        self.folder = folder.isEmpty ? Self.defaultFolder : folder
        hotkey = values.contains(.hotkey)
            ? (try? values.decodeIfPresent(ChatHotkey.self, forKey: .hotkey)) ?? nil
            : .defaultValue
        showsInMenuBar = (try? values.decodeIfPresent(Bool.self, forKey: .showsInMenuBar)) ?? true
        enabledHarnesses = (try? values.decodeIfPresent([HarnessID].self, forKey: .enabledHarnesses))
            ?? ChatHarness.supported
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(defaultWorkspace, forKey: .defaultWorkspace)
        try values.encode(folder, forKey: .folder)
        try values.encode(hotkey, forKey: .hotkey)
        try values.encode(showsInMenuBar, forKey: .showsInMenuBar)
        try values.encode(enabledHarnesses, forKey: .enabledHarnesses)
    }

    /// The harnesses a new chat may pick, in the picker's order. Never
    /// empty: with every switch off, Claude stays.
    public var harnesses: [HarnessID] {
        let enabled = ChatHarness.supported.filter(enabledHarnesses.contains)
        return enabled.isEmpty ? [.claude] : enabled
    }

    /// Where a new chat starts: the saved workspace while it still exists,
    /// else the first workspace, else this Mac.
    public func defaultPlace(workspaces: [String]) -> ChatPlace {
        if defaultWorkspace == ChatRecord.localWorkspace { return .local }
        if workspaces.contains(defaultWorkspace) { return .workspace(defaultWorkspace) }
        return workspaces.first.map(ChatPlace.workspace) ?? .local
    }
}
