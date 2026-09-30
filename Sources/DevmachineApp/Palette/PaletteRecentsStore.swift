import Foundation
import DevmachineCore

/// The commands run from ⌘K lately, kept across launches so the palette
/// opens on them.
@MainActor
final class PaletteRecentsStore: ObservableObject {
    static let key = "paletteRecents.v1"

    @Published private(set) var mru: CommandMRU

    private let defaults: UserDefaults
    private let persists: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        persists = !DemoMode.isActive
        guard persists else {
            mru = CommandMRU(ids: DemoData.paletteRecents)
            return
        }
        mru = CommandMRU(ids: defaults.stringArray(forKey: Self.key) ?? [])
    }

    func record(_ id: String) {
        mru = mru.recording(id)
        guard persists else { return }
        defaults.set(mru.ids, forKey: Self.key)
    }
}
