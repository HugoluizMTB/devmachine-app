import Foundation

/// The app's half of Settings → Chats: the shortcut, the menu bar rows and
/// which harnesses the pickers offer. Where chats run is the CLI's
/// (`ChatCLIConfig`).
public struct ChatSettings: Codable, Equatable, Sendable {
    public static let defaultFolder = "~/chats"
    public static let `default` = ChatSettings()

    /// Nil when the person cleared the shortcut.
    public var hotkey: ChatHotkey?
    public var showsInMenuBar: Bool
    public var enabledHarnesses: [HarnessID]

    public init(
        hotkey: ChatHotkey? = .defaultValue, showsInMenuBar: Bool = true,
        enabledHarnesses: [HarnessID] = ChatHarness.supported
    ) {
        self.hotkey = hotkey
        self.showsInMenuBar = showsInMenuBar
        self.enabledHarnesses = enabledHarnesses
    }

    enum CodingKeys: String, CodingKey {
        case hotkey, showsInMenuBar, enabledHarnesses
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = values.contains(.hotkey)
            ? (try? values.decodeIfPresent(ChatHotkey.self, forKey: .hotkey)) ?? nil
            : .defaultValue
        showsInMenuBar = (try? values.decodeIfPresent(Bool.self, forKey: .showsInMenuBar)) ?? true
        enabledHarnesses = (try? values.decodeIfPresent([HarnessID].self, forKey: .enabledHarnesses))
            ?? ChatHarness.supported
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
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
}
