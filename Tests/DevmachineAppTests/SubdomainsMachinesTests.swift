import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
private func eventually(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("condition never became true"); return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class SubdomainsMachinesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "dev.devmachine.app.subdomains.machines.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(_ runner: MultiMachineCLIRunner) -> CaddyStore {
        CaddyStore(
            service: CaddyService(cli: DevmachineCLI(executable: "/fake/devmachine", runner: runner)),
            selection: SitesMachineSelection(defaults: defaults))
    }

    private func loadedStore(_ runner: MultiMachineCLIRunner) async throws -> CaddyStore {
        let store = makeStore(runner)
        store.refresh()
        try await eventually { !store.machines.isEmpty && store.machines.allSatisfy { !(store.sitesByMachine[$0.name]?.isLoading ?? true) } }
        return store
    }

    func testEveryMachineLoadsOnItsOwnAndNoCallGoesWithoutATarget() async throws {
        let runner = MultiMachineCLIRunner()

        let store = try await loadedStore(runner)

        XCTAssertEqual(store.machines.map(\.name), ["laptop", "box", "spare"])
        XCTAssertEqual(store.sitesByMachine["box"]?.rows.map(\.site.host), ["app.example.com", "old.example.com"])
        XCTAssertNotNil(store.sitesByMachine["laptop"]?.notSetUpMessage)
        XCTAssertNotNil(store.sitesByMachine["spare"]?.notSetUpMessage)
        XCTAssertEqual(store.domain, "example.com")
        XCTAssertEqual(runner.callsWithoutATarget, [])
    }

    func testAMachineThatFailsShowsItsOwnErrorAndLeavesTheOthersAlone() async throws {
        let runner = MultiMachineCLIRunner(failing: ["--machine box --format json expose list"])

        let store = try await loadedStore(runner)

        XCTAssertNotNil(store.sitesByMachine["box"]?.errorText)
        XCTAssertNil(store.sitesByMachine["spare"]?.errorText)
        XCTAssertNotNil(store.sitesByMachine["spare"]?.notSetUpMessage)
        XCTAssertNil(store.sitesByMachine["laptop"]?.errorText)
    }

    func testTheFirstServerIsSelectedWhenNothingIsRemembered() async throws {
        let store = try await loadedStore(MultiMachineCLIRunner())

        XCTAssertEqual(store.selectedMachine, "box")
        XCTAssertEqual(store.rows.count, 2)
        XCTAssertTrue(store.showsMachinePicker)
    }

    func testTheSelectionIsRememberedAcrossLaunches() async throws {
        let first = try await loadedStore(MultiMachineCLIRunner())
        first.select("spare")
        XCTAssertEqual(first.selectedMachine, "spare")
        XCTAssertEqual(first.notSetUpMessage, first.sitesByMachine["spare"]?.notSetUpMessage)

        let second = try await loadedStore(MultiMachineCLIRunner())

        XCTAssertEqual(second.selectedMachine, "spare")
    }

    func testARememberedMachineThatIsGoneFallsBackToTheFirstServer() async throws {
        SitesMachineSelection(defaults: defaults).machineName = "retired"

        let store = try await loadedStore(MultiMachineCLIRunner())

        XCTAssertEqual(store.selectedMachine, "box")
    }

    func testDNSProvidersAreReadOnTheSelectedServerOnly() async throws {
        let runner = MultiMachineCLIRunner()
        let store = try await loadedStore(runner)
        try await eventually { !store.isLoadingDNSProviders }

        XCTAssertEqual(store.dnsProviders, ["Cloudflare"])
        XCTAssertEqual(store.dnsMachine, "box")

        store.select("laptop")

        XCTAssertNil(store.dnsMachine)
        XCTAssertEqual(store.dnsProviders, [])
        XCTAssertFalse(runner.calls.contains { $0.contains("dns") && $0.contains("laptop") })
        XCTAssertEqual(runner.callsWithoutATarget, [])
    }

    func testRemovingASiteNamesTheSelectedMachine() async throws {
        let runner = MultiMachineCLIRunner()
        let store = try await loadedStore(runner)

        store.remove(host: "old.example.com")
        try await eventually { store.removingHost == nil }

        XCTAssertTrue(runner.calls.contains(["--machine", "box", "--format", "json", "expose", "rm", "old.example.com", "--yes"]))
    }

    func testTheAddSheetOffersOnlyTheSelectedMachinesWorkspaces() async throws {
        let store = try await loadedStore(MultiMachineCLIRunner())

        XCTAssertEqual(store.workspacesOnSelectedMachine, ["alice"])
        store.select("spare")
        XCTAssertEqual(store.workspacesOnSelectedMachine, ["bob"])
    }

    func testOneMachineShowsNoPicker() {
        let store = makeStore(MultiMachineCLIRunner())
        store.show(
            machines: [CLIMachine(name: "box", isSelf: false)],
            states: ["box": MachineSitesState(hasLoaded: true)],
            selected: "box")

        XCTAssertFalse(store.showsMachinePicker)
    }
}
