import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
private final class RecordingOpener: ExternalURLOpening {
    var opened: [URL] = []
    func open(_ url: URL) { opened.append(url) }
}

@MainActor
final class PreviewStoreTests: XCTestCase {
    private var launcher = FakeTunnelLauncher()
    private var probe = FakePortProbe()
    private var opener = RecordingOpener()
    private var reports: [String] = []
    private var preference = LinkOpening.inApp

    private func store() -> PreviewStore {
        let tunnels = TunnelManager(launcher: launcher, probe: probe, readyTimeout: 0.2, pollInterval: 0.01)
        return PreviewStore(
            tunnels: tunnels, preference: { [unowned self] in preference }, external: opener,
            report: { [unowned self] in reports.append($0) })
    }

    private func settle(_ store: PreviewStore) async {
        for _ in 0..<100 {
            let busy = store.tabs.contains { if case .connecting = $0.state { return true } else { return false } }
            if !busy && !store.isOpeningInBrowser { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testAPortOnThisMacOpensLocalhostInATab() {
        let previews = store()

        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))

        XCTAssertEqual(previews.tabs.map(\.state), [.ready(URL(string: "http://localhost:3000")!)])
        XCTAssertEqual(previews.tabs.first?.title, "localhost:3000")
        XCTAssertEqual(previews.selectedTabID, previews.tabs.first?.id)
        XCTAssertTrue(opener.opened.isEmpty)
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func testTheDefaultBrowserSettingSendsThePreviewToTheBrowser() {
        preference = .defaultBrowser
        let previews = store()

        previews.open(PreviewRequest(place: .thisMac, input: .port(5173, path: "/admin")))

        XCTAssertEqual(opener.opened, [URL(string: "http://localhost:5173/admin")!])
        XCTAssertTrue(previews.tabs.isEmpty)
    }

    func testOptionClickDoesTheOtherThingOnce() {
        preference = .defaultBrowser
        let previews = store()

        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")), inverted: true)

        XCTAssertEqual(previews.tabs.count, 1)
        XCTAssertTrue(opener.opened.isEmpty)
    }

    func testARemotePortOpensThroughATunnelHeldByItsTab() async {
        probe.taken = [3000]
        let previews = store()

        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "/login")))
        XCTAssertEqual(previews.tabs.first?.state, .connecting("Opening a tunnel to acme:3000…"))
        await settle(previews)

        XCTAssertEqual(launcher.launches, [.init(workspace: "acme", remotePort: 3000, localPort: 55000)])
        XCTAssertEqual(previews.tabs.first?.state, .ready(URL(string: "http://localhost:55000/login")!))
        XCTAssertEqual(previews.tabs.first?.title, "acme:3000")
    }

    func testClosingTheTabStopsItsTunnel() async {
        let previews = store()
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        await settle(previews)

        previews.close(previews.tabs[0].id)

        XCTAssertTrue(previews.tabs.isEmpty)
        XCTAssertTrue(launcher.processes[0].wasTerminated)
    }

    func testARemotePortSentToTheBrowserKeepsItsTunnelOpen() async {
        preference = .defaultBrowser
        let previews = store()

        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(5173, path: "")))
        await settle(previews)

        XCTAssertEqual(opener.opened, [URL(string: "http://localhost:5173")!])
        XCTAssertEqual(previews.tunnels.tunnel(for: TunnelKey(workspace: "acme", remotePort: 5173))?.holders,
                       [PreviewStore.browserHolder])
    }

    func testATunnelThatFailsShowsItsErrorInTheTab() async {
        launcher.nextProcess = { FakeTunnelProcess(running: false, stderr: "ssh: connect refused") }
        probe.accepting = false
        let previews = store()

        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        await settle(previews)

        XCTAssertEqual(previews.tabs.first?.state, .failed("ssh: connect refused"))
    }

    func testATunnelThatFailsForTheBrowserIsReported() async {
        preference = .defaultBrowser
        launcher.nextProcess = { FakeTunnelProcess(running: false, stderr: "ssh: connect refused") }
        probe.accepting = false
        let previews = store()

        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        await settle(previews)

        XCTAssertTrue(opener.opened.isEmpty)
        XCTAssertEqual(reports, ["Couldn't open acme:3000: ssh: connect refused"])
    }

    func testRetryStartsTheTunnelAgain() async {
        launcher.nextProcess = { FakeTunnelProcess(running: false, stderr: "down") }
        probe.accepting = false
        let previews = store()
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        await settle(previews)

        launcher.nextProcess = { FakeTunnelProcess() }
        probe.accepting = true
        previews.retry(previews.tabs[0].id)
        await settle(previews)

        XCTAssertEqual(previews.tabs.first?.state, .ready(URL(string: "http://localhost:3000")!))
    }

    func testAPublishedSiteOpensItsHTTPSAddress() {
        let previews = store()

        previews.open(PreviewRequest(
            place: .workspace("acme"), input: .url(URL(string: "https://app.acme.example.com")!)))

        XCTAssertEqual(previews.tabs.first?.state, .ready(URL(string: "https://app.acme.example.com")!))
        XCTAssertEqual(previews.tabs.first?.title, "app.acme.example.com")
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func testAContextLinkFollowsTheSetting() {
        let previews = store()
        let pr = URL(string: "https://github.com/acme/dash/pull/12")!

        previews.openLink(pr)
        previews.openLink(pr, inverted: true)

        XCTAssertEqual(previews.tabs.count, 1)
        XCTAssertEqual(opener.opened, [pr])
    }

    func testANonWebLinkAlwaysGoesToTheSystem() {
        let previews = store()
        let mail = URL(string: "mailto:alice@example.com")!

        previews.openLink(mail)

        XCTAssertEqual(opener.opened, [mail])
        XCTAssertTrue(previews.tabs.isEmpty)
    }

    func testSeveralTabsAndClosingOneSelectsItsNeighbour() {
        let previews = store()
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        previews.open(PreviewRequest(place: .thisMac, input: .port(5173, path: "")))
        previews.open(PreviewRequest(place: .thisMac, input: .port(8080, path: "")))
        XCTAssertEqual(previews.tabs.count, 3)

        previews.select(previews.tabs[1].id)
        previews.close(previews.tabs[1].id)

        XCTAssertEqual(previews.tabs.map(\.title), ["localhost:3000", "localhost:8080"])
        XCTAssertEqual(previews.selectedTabID, previews.tabs[1].id)
    }

    func testClosingTheLastTabLeavesNothingSelected() {
        let previews = store()
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))

        previews.close(previews.tabs[0].id)

        XCTAssertNil(previews.selectedTabID)
    }

    func testATunnelSharedByTwoTabsStopsOnlyWithTheLastOne() async {
        let previews = store()
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "/admin")))
        await settle(previews)
        XCTAssertEqual(launcher.launches.count, 1)
        let first = previews.tabs[0].id
        let second = previews.tabs[1].id

        previews.close(second)
        XCTAssertEqual(previews.selectedTabID, first)
        XCTAssertFalse(launcher.processes[0].wasTerminated)

        previews.close(first)
        XCTAssertNil(previews.selectedTabID)
        XCTAssertTrue(launcher.processes[0].wasTerminated)
    }

    func testClosingATabThatIsNotSelectedKeepsTheSelection() {
        let previews = store()
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        previews.open(PreviewRequest(place: .thisMac, input: .port(5173, path: "")))
        let selected = previews.selectedTabID

        previews.close(previews.tabs[0].id)

        XCTAssertEqual(previews.selectedTabID, selected)
        XCTAssertEqual(previews.tabs.map(\.title), ["localhost:5173"])
    }

    func testTheTabTitleFollowsThePage() {
        let previews = store()
        previews.openLink(URL(string: "https://docs.example.com/start")!)
        let id = previews.tabs[0].id
        XCTAssertEqual(previews.tabs[0].title, "docs.example.com")

        previews.pageChanged(id, title: "", url: URL(string: "https://www.example.net/search?q=x"))
        XCTAssertEqual(previews.tabs[0].title, "www.example.net")

        previews.pageChanged(id, title: "Search results", url: URL(string: "https://www.example.net/search?q=x"))
        XCTAssertEqual(previews.tabs[0].title, "Search results")
    }

    func testAPageWithNothingToNameItKeepsTheTabsName() {
        let previews = store()
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        let id = previews.tabs[0].id

        previews.pageChanged(id, title: nil, url: nil)

        XCTAssertEqual(previews.tabs[0].title, "acme:3000")
    }

    func testARetitleForAClosedTabIsIgnored() {
        let previews = store()
        previews.openLink(URL(string: "https://example.com")!)
        let id = previews.tabs[0].id
        previews.close(id)

        previews.pageChanged(id, title: "Late", url: nil)

        XCTAssertTrue(previews.tabs.isEmpty)
    }

    private let dash = SessionRef(alias: "acme-devmachine", name: "dash")
    private let api = SessionRef(alias: "acme-devmachine", name: "api")
    private let notes = SessionRef(alias: Workspace.local.alias, name: "notes")

    func testAPreviewBelongsToTheSessionItWasOpenedIn() {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))

        previews.setOwner(api)
        XCTAssertTrue(previews.tabs.isEmpty)
        XCTAssertNil(previews.selectedTab)

        previews.setOwner(dash)
        XCTAssertEqual(previews.tabs.map(\.title), ["localhost:3000"])
        XCTAssertEqual(previews.selectedTabID, previews.tabs[0].id)
    }

    func testEachSessionKeepsItsOwnSelectedTab() {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        previews.open(PreviewRequest(place: .thisMac, input: .port(5173, path: "")))
        previews.select(previews.tabs[0].id)
        let dashSelected = previews.selectedTabID

        previews.setOwner(notes)
        previews.open(PreviewRequest(place: .thisMac, input: .port(8080, path: "")))
        let notesSelected = previews.selectedTabID

        previews.setOwner(dash)
        XCTAssertEqual(previews.selectedTabID, dashSelected)
        previews.setOwner(notes)
        XCTAssertEqual(previews.selectedTabID, notesSelected)
    }

    func testClosingATabInOneSessionLeavesTheOtherAlone() {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        previews.setOwner(api)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))

        previews.close(previews.tabs[0].id)
        XCTAssertTrue(previews.tabs.isEmpty)

        previews.setOwner(dash)
        XCTAssertEqual(previews.tabs.count, 1)
        XCTAssertEqual(previews.selectedTabID, previews.tabs[0].id)
    }

    func testEndingASessionClosesItsPreviewsOnly() {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        previews.setOwner(api)
        previews.open(PreviewRequest(place: .thisMac, input: .port(5173, path: "")))

        previews.closeSession(dash)

        XCTAssertEqual(previews.tabs.map(\.title), ["localhost:5173"])
        previews.setOwner(dash)
        XCTAssertTrue(previews.tabs.isEmpty)
    }

    func testATunnelUsedByTwoSessionsStopsWithTheLastOne() async {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        previews.setOwner(api)
        previews.open(PreviewRequest(place: .workspace("acme"), input: .port(3000, path: "")))
        await settle(previews)
        XCTAssertEqual(launcher.launches.count, 1)

        previews.closeSession(dash)
        XCTAssertFalse(launcher.processes[0].wasTerminated)

        previews.close(previews.tabs[0].id)
        XCTAssertTrue(launcher.processes[0].wasTerminated)
    }

    func testHidingAWorkspaceClosesThePreviewsOfItsSessions() {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        previews.setOwner(notes)
        previews.open(PreviewRequest(place: .thisMac, input: .port(5173, path: "")))

        previews.closeWorkspace(alias: "acme-devmachine")

        XCTAssertEqual(previews.tabs.count, 1)
        previews.setOwner(dash)
        XCTAssertTrue(previews.tabs.isEmpty)
    }

    func testARenamedSessionKeepsItsPreviews() {
        let previews = store()
        previews.setOwner(dash)
        previews.open(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        let renamed = SessionRef(alias: dash.alias, name: "board")

        previews.moveSession(from: dash, to: renamed)
        previews.setOwner(renamed)

        XCTAssertEqual(previews.tabs.map(\.title), ["localhost:3000"])
        XCTAssertEqual(previews.selectedTabID, previews.tabs[0].id)
    }
}
