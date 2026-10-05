import XCTest
@testable import DevmachineApp
import DevmachineCore

@MainActor
final class MachineDetailsStoreTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        var log: [String] = []
    }

    private func store(_ calls: Calls, fail: Bool = false, reloaded: @escaping @MainActor () -> Void = {}) -> MachineDetailsStore {
        struct Failure: LocalizedError { var errorDescription: String? { "unreachable" } }
        let service = MachineDetailsService(
            doctor: { machine, isSelf in
                calls.log.append("doctor \(machine) \(isSelf)")
                if fail { throw Failure() }
                return .report(DoctorReport(checks: [DoctorCheck(name: "ssh", status: .pass, detail: "ok")], ok: true))
            },
            addresses: { machine in
                calls.log.append("resolve \(machine)")
                return MachineAddresses.parse(#"{"machine":"main","addresses":[],"dropped":[]}"#)!
            },
            credentials: { machine in
                calls.log.append("credentials \(machine)")
                return MachineCredentials.parse(#"{"credentials":[]}"#)!
            },
            editLocation: { machine, location in calls.log.append("edit \(machine) \(location)") })
        return MachineDetailsStore(service: service, reload: reloaded)
    }

    func testAPanelReadsWhenItOpensAndClosesOnASecondClick() async {
        let calls = Calls()
        let details = store(calls)
        await details.toggle(.check, machine: "main", isSelf: false)
        XCTAssertEqual(details.open["main"], .check)
        XCTAssertNotNil(details.checks["main"]?.value)
        await details.toggle(.check, machine: "main", isSelf: false)
        XCTAssertNil(details.open["main"])
        XCTAssertEqual(calls.log, ["doctor main false"])
    }

    func testOpeningAnotherPanelReadsItInstead() async {
        let calls = Calls()
        let details = store(calls)
        await details.toggle(.check, machine: "laptop", isSelf: true)
        await details.toggle(.addresses, machine: "main", isSelf: false)
        await details.toggle(.credentials, machine: "main", isSelf: false)
        XCTAssertEqual(details.open, ["laptop": .check, "main": .credentials])
        XCTAssertEqual(calls.log, ["doctor laptop true", "resolve main", "credentials main"])
    }

    func testAFailedReadSaysWhy() async {
        let details = store(Calls(), fail: true)
        await details.toggle(.check, machine: "main", isSelf: false)
        guard case let .failed(message) = details.checks["main"] else { return XCTFail("not failed") }
        XCTAssertFalse(message.isEmpty)
    }

    func testSavingALocationEditsTheConfigurationAndReloads() async {
        let calls = Calls()
        var reloads = 0
        let details = store(calls, reloaded: { reloads += 1 })
        let saved = await details.saveLocation("Home", machine: "main")
        XCTAssertTrue(saved)
        XCTAssertEqual(calls.log, ["edit main Home"])
        XCTAssertEqual(reloads, 1)
    }

    func testAnInvalidLocationIsNeverSent() async {
        let calls = Calls()
        let details = store(calls)
        let saved = await details.saveLocation("  ", machine: "main")
        XCTAssertFalse(saved)
        XCTAssertTrue(calls.log.isEmpty)
        XCTAssertNotNil(details.locationError["main"])
    }
}

final class MachineSitesTests: XCTestCase {
    private func row(_ host: String, _ workspace: String) -> SubdomainRow {
        SubdomainRow(site: ExposedSite(host: host, port: 80, workspace: workspace, status: .published),
                     resolvedWorkspace: workspace, containerName: nil)
    }

    func testAMachineListsWhatItServesAndWhatAnotherServesForIt() {
        let machines = [
            ConfiguredMachine(name: "main", hosts: [], adminUser: "root", port: 22, workspaces: ["acme"],
                              packages: ["essentials"], isSelf: false),
            ConfiguredMachine(name: "homebox", hosts: [], adminUser: "root", port: 22, workspaces: ["umbrella"],
                              packages: [], isSelf: false),
        ]
        let sites = ["main": MachineSitesState(rows: [row("app.example.com", "acme"), row("media.example.com", "umbrella")])]
        XCTAssertEqual(MachineSites.list(for: machines[0], machines: machines, sites: sites).map(\.host),
                       ["app.example.com", "media.example.com"])
        XCTAssertEqual(MachineSites.list(for: machines[1], machines: machines, sites: sites),
                       [MachineSites.Entry(host: "media.example.com", via: "main")])
    }

    @MainActor
    func testDeletingAVMIsToldApartFromRemovingIt() {
        let lab = ConfiguredMachine(name: "lab", hosts: ["127.0.0.1"], adminUser: "root", port: 60022, workspaces: [],
                                    packages: [], isSelf: false)
        XCTAssertTrue(MachineActions.deleteMessage(lab).contains("delete-local lab"))
        XCTAssertTrue(MachineActions.deleteMessage(lab).contains("destroyed"))
        XCTAssertTrue(MachineActions.removeMessage(lab).contains("machines rm lab"))
        XCTAssertTrue(MachineActions.removeMessage(lab).contains("Delete VM"))
    }
}
