import Foundation

/// The quick chat's global shortcut: a virtual key code and modifiers, the
/// two numbers Carbon's `RegisterEventHotKey` takes.
public struct ChatHotkey: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public static let spaceKeyCode: UInt32 = 49
    public static let defaultValue = ChatHotkey(keyCode: spaceKeyCode, modifiers: [.control, .option], key: "Space")

    public var keyCode: UInt32
    public var modifiers: Modifiers
    public var key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public var keyCaps: [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        return caps + [key]
    }

    public var display: String { keyCaps.joined() }

    /// Carbon's `cmdKey`, `shiftKey`, `optionKey` and `controlKey` bits.
    public var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= 0x0100 }
        if modifiers.contains(.shift) { mask |= 0x0200 }
        if modifiers.contains(.option) { mask |= 0x0800 }
        if modifiers.contains(.control) { mask |= 0x1000 }
        return mask
    }

    /// Shift alone would take a capital letter from every app.
    public var isValid: Bool {
        !modifiers.intersection([.control, .option, .command]).isEmpty && !key.isEmpty
    }

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]

    /// What a key cap reads for a key press: the key's name, else the
    /// character it types without modifiers.
    public static func keyName(keyCode: UInt32, characters: String?) -> String? {
        if let name = namedKeys[keyCode] { return name }
        guard let characters = characters?.trimmingCharacters(in: .whitespacesAndNewlines),
              !characters.isEmpty else { return nil }
        return characters.uppercased()
    }

    /// The shortcut a recorder makes of one key press, or nil when the press
    /// is not a usable shortcut.
    public static func recorded(keyCode: UInt32, modifiers: Modifiers, characters: String?) -> ChatHotkey? {
        guard let key = keyName(keyCode: keyCode, characters: characters) else { return nil }
        let hotkey = ChatHotkey(keyCode: keyCode, modifiers: modifiers, key: key)
        return hotkey.isValid ? hotkey : nil
    }
}
