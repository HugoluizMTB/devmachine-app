import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class RecentCommandStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "RecentCommandStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testStartsEmpty() {
        let store = RecentCommandStore(defaults: makeDefaults())
        XCTAssertEqual(store.recents(for: "acme-devmachine"), [])
    }

    func testRecordedCommandsAreKeptPerWorkspace() {
        let store = RecentCommandStore(defaults: makeDefaults())

        store.record("npm run dev", for: "acme-devmachine")
        store.record("htop", for: "globex-devmachine")

        XCTAssertEqual(store.recents(for: "acme-devmachine"), ["npm run dev"])
        XCTAssertEqual(store.recents(for: "globex-devmachine"), ["htop"])
    }

    func testRecordingDedupesMostRecentFirstAndCaps() {
        let store = RecentCommandStore(defaults: makeDefaults())
        for index in 1...(RecentCommands.capacity + 2) {
            store.record("cmd \(index)", for: "acme-devmachine")
        }
        store.record("cmd 4", for: "acme-devmachine")

        let recents = store.recents(for: "acme-devmachine")

        XCTAssertEqual(recents.count, RecentCommands.capacity)
        XCTAssertEqual(recents.first, "cmd 4")
        XCTAssertEqual(recents.filter { $0 == "cmd 4" }.count, 1)
    }

    func testRecordingIgnoresBlankInputAndReturnsTheCleanCommand() {
        let store = RecentCommandStore(defaults: makeDefaults())

        XCTAssertNil(store.record("   ", for: "acme-devmachine"))
        XCTAssertEqual(store.record("  htop  ", for: "acme-devmachine"), "htop")
        XCTAssertEqual(store.recents(for: "acme-devmachine"), ["htop"])
    }

    func testRememberAddsANewCommandWithoutReorderingTheOthers() {
        let store = RecentCommandStore(defaults: makeDefaults())
        store.record("htop", for: "acme-devmachine")
        store.record("npm run dev", for: "acme-devmachine")

        store.remember("htop", for: "acme-devmachine")
        store.remember(" make test ", for: "acme-devmachine")
        store.remember("  ", for: "acme-devmachine")

        XCTAssertEqual(store.recents(for: "acme-devmachine"), ["make test", "npm run dev", "htop"])
    }

    func testRemoveDropsTheCommandFromThatWorkspaceOnly() {
        let store = RecentCommandStore(defaults: makeDefaults())
        store.record("htop", for: "acme-devmachine")
        store.record("npm run dev", for: "acme-devmachine")
        store.record("htop", for: "globex-devmachine")

        store.remove("htop", for: "acme-devmachine")

        XCTAssertEqual(store.recents(for: "acme-devmachine"), ["npm run dev"])
        XCTAssertEqual(store.recents(for: "globex-devmachine"), ["htop"])
    }

    func testRemoveAlsoDropsACommandTheOldPageOfferedEverywhere() throws {
        let defaults = makeDefaults()
        defaults.set(Data(Self.legacyJSON.utf8), forKey: RecentCommandStore.legacyKey)
        let store = RecentCommandStore(defaults: defaults)
        let everywhere = try XCTUnwrap(store.recents(for: "beta-devmachine").first)

        store.remove(everywhere, for: "beta-devmachine")

        XCTAssertFalse(store.recents(for: "beta-devmachine").contains(everywhere))
    }

    func testTheRemoteFallbackKeepsItsOwnList() {
        let store = RecentCommandStore(defaults: makeDefaults())

        store.record("npm run dev", for: RecentCommandStore.remoteFallback)

        XCTAssertEqual(store.recents(for: RecentCommandStore.remoteFallback), ["npm run dev"])
        XCTAssertEqual(store.recents(for: "acme-devmachine"), [])
    }

    func testRecentsSurviveARelaunch() {
        let defaults = makeDefaults()
        RecentCommandStore(defaults: defaults).record("npm run dev", for: "acme-devmachine")

        XCTAssertEqual(RecentCommandStore(defaults: defaults).recents(for: "acme-devmachine"), ["npm run dev"])
    }

    func testSavedCustomCommandsAreSeededIntoRecentsByTheirOldScope() throws {
        let defaults = makeDefaults()
        defaults.set(Data(Self.legacyJSON.utf8), forKey: RecentCommandStore.legacyKey)

        let store = RecentCommandStore(defaults: defaults)

        XCTAssertEqual(store.recents(for: "acme-devmachine"), ["npm run dev", "claude --model opus"])
        XCTAssertEqual(store.recents(for: "globex-devmachine"), ["claude --model opus"])
        XCTAssertEqual(store.recents(for: Workspace.local.alias), ["htop", "claude --model opus"])
    }

    func testTheOldKeyIsReadOnlyOnce() {
        let defaults = makeDefaults()
        defaults.set(Data(Self.legacyJSON.utf8), forKey: RecentCommandStore.legacyKey)
        _ = RecentCommandStore(defaults: defaults)
        let later = #"[{"id":"27F62E1A-68B7-46E7-B897-C220FC3B0F6A","name":"Late","command":"make","icon":"terminal","scope":{"all":{}}}]"#
        defaults.set(Data(later.utf8), forKey: RecentCommandStore.legacyKey)

        let second = RecentCommandStore(defaults: defaults)

        XCTAssertFalse(second.recents(for: "globex-devmachine").contains("make"))
        XCTAssertEqual(second.recents(for: "globex-devmachine"), ["claude --model opus"])
    }

    func testUnreadableOldDataIsIgnored() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: RecentCommandStore.legacyKey)

        XCTAssertEqual(RecentCommandStore(defaults: defaults).recents(for: "acme-devmachine"), [])
    }

    private static let legacyJSON = """
    [
      {"id":"01D49EE3-F29B-4B50-9916-3E94D94A28DD","name":"Dev server","command":"npm run dev",
       "icon":"play","scope":{"workspaces":{"_0":["Acme-Devmachine"]}},"shortcutSlot":1},
      {"id":"86CAFDEE-BDE3-46B7-97A3-E41CDF5C353B","name":"Top","command":"htop",
       "icon":"terminal","scope":{"localOnly":{}}},
      {"id":"07F62E1A-68B7-46E7-B897-C220FC3B0F6A","name":"Claude","command":"claude --model opus",
       "icon":"sparkles","scope":{"all":{}}},
      {"id":"17F62E1A-68B7-46E7-B897-C220FC3B0F6A","name":"Blank","command":"   ",
       "icon":"terminal","scope":{"all":{}}}
    ]
    """
}
