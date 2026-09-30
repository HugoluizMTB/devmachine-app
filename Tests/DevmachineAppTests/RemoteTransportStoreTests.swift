import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class RemoteTransportStoreTests: XCTestCase {
    private let kind = TerminalKind.remote(alias: "acme-devmachine", session: "dev")
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> RemoteTransportStore {
        RemoteTransportStore(now: { [unowned self] in self.clock })
    }

    func testAPaneIsConnectingUntilItsTransportIsKnown() {
        let store = makeStore()
        store.connecting(kind, machine: "main")
        XCTAssertNil(store.panes[kind]?.transport)
        store.usingMosh(kind, machine: "main")
        XCTAssertEqual(store.panes[kind]?.transport, .mosh)
        XCTAssertEqual(store.panes[kind]?.showsNotice, false)
    }

    func testAFreshUDPFailureShowsTheNoticeAndIsRemembered() {
        let store = makeStore()
        store.usingSSH(kind, machine: "main", reason: .udpBlocked, detail: "nothing back", fresh: true)
        XCTAssertEqual(store.panes[kind]?.transport, .ssh)
        XCTAssertEqual(store.panes[kind]?.showsNotice, true)
        XCTAssertEqual(store.remembered(for: "main"), .udpBlocked)
        XCTAssertEqual(store.panes[kind]?.errorState?.details, "nothing back")
    }

    func testARememberedFailureIsQuietAndDoesNotPushTheReprobeBack() {
        let store = makeStore()
        store.usingSSH(kind, machine: "main", reason: .udpBlocked, detail: "", fresh: true)
        clock.addTimeInterval(29 * 60)
        store.usingSSH(kind, machine: "main", reason: .udpBlocked, detail: "", fresh: false)
        XCTAssertEqual(store.panes[kind]?.showsNotice, false)
        clock.addTimeInterval(60)
        XCTAssertNil(store.remembered(for: "main"))
    }

    func testAMissingServerIsRememberedWithoutANotice() {
        let store = makeStore()
        store.usingSSH(kind, machine: "main", reason: .noServer, detail: "command not found", fresh: true)
        XCTAssertEqual(store.panes[kind]?.showsNotice, false)
        XCTAssertEqual(store.remembered(for: "main"), .noServer)
        XCTAssertEqual(store.panes[kind]?.badgeHelp, "ssh: main has no mosh-server")
    }

    func testAWorkingMoshClearsTheMachine() {
        let store = makeStore()
        store.usingSSH(kind, machine: "main", reason: .udpBlocked, detail: "", fresh: true)
        store.moshConfirmed(machine: "main")
        XCTAssertNil(store.remembered(for: "main"))
    }

    func testDismissAndForget() {
        let store = makeStore()
        store.usingSSH(kind, machine: "main", reason: .udpBlocked, detail: "", fresh: true)
        store.dismissNotice(kind)
        XCTAssertEqual(store.panes[kind]?.showsNotice, false)
        store.forget(kind)
        XCTAssertNil(store.panes[kind])
    }

    func testTheEmbeddedClientLivesInHelpers() {
        let bundle = Bundle(path: "/Applications") ?? .main
        XCTAssertTrue(LocalTools.moshClientPath(bundle: bundle).hasSuffix("/Contents/Helpers/mosh-client"))
    }
}
