import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class PaletteRecentsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
    }

    func testStartsEmpty() {
        XCTAssertEqual(PaletteRecentsStore(defaults: freshDefaults()).mru.ids, [])
    }

    func testRecordingPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let store = PaletteRecentsStore(defaults: defaults)
        store.record("go.stats")
        store.record("go.home")
        XCTAssertEqual(PaletteRecentsStore(defaults: defaults).mru.ids, ["go.home", "go.stats"])
    }
}
