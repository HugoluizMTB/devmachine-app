import AppKit
import Carbon
import Combine
import DevmachineCore

/// Registers one system-wide shortcut. The live one uses Carbon, which
/// needs no Accessibility permission; tests hand in a fake.
@MainActor
protocol HotkeyRegistering: AnyObject {
    func register(_ hotkey: ChatHotkey, action: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}

@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private static let signature: OSType = 0x444D_4348
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    func register(_ hotkey: ChatHotkey, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        installHandlerIfNeeded()
        self.action = action
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        hotKey = reference
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        action = nil
    }

    fileprivate func fire() {
        action?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { registrar.fire() }
            return noErr
        }, 1, &spec, context, &handler)
    }
}

/// Keeps the registered shortcut in step with Settings → Chats.
@MainActor
final class QuickChatHotkeyController {
    private let registrar: any HotkeyRegistering
    private let onPress: @MainActor () -> Void
    private(set) var registered: ChatHotkey?
    private(set) var failed: ChatHotkey?

    init(registrar: any HotkeyRegistering, onPress: @escaping @MainActor () -> Void) {
        self.registrar = registrar
        self.onPress = onPress
    }

    /// While Settings records a new shortcut the old one must not fire.
    func suspend() {
        registrar.unregister()
        registered = nil
        failed = nil
    }

    func apply(_ settings: ChatSettings) {
        let wanted = settings.hotkey.flatMap { $0.isValid ? $0 : nil }
        guard wanted != registered || (wanted != nil && failed == wanted) else { return }
        registrar.unregister()
        registered = nil
        failed = nil
        guard let wanted else { return }
        if registrar.register(wanted, action: onPress) {
            registered = wanted
        } else {
            failed = wanted
        }
    }
}
