import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Opt-in: `DEVMACHINE_PREPARE_E2E=<devmachine binary>` with
/// `DEVMACHINE_CONFIG` naming a throwaway configuration whose one machine is
/// a `devmachine-accept-*` VM without devmachine-app. Runs the real Prepare.
@MainActor
final class MachinePrepareEndToEndTests: XCTestCase {
    func testPrepareMakesARealMachineReady() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let binary = environment["DEVMACHINE_PREPARE_E2E"], let config = environment["DEVMACHINE_CONFIG"] else {
            throw XCTSkip("set DEVMACHINE_PREPARE_E2E and DEVMACHINE_CONFIG to run against a throwaway VM")
        }
        var overrides = environment
        overrides["DEVMACHINE_KEYCHAIN"] = "off"
        overrides["DEVMACHINE_CONFIG"] = config
        overrides["SSH_AUTH_SOCK"] = nil
        let processEnvironment = overrides
        let cli: @Sendable () throws -> DevmachineCLI = {
            DevmachineCLI(
                executable: binary, socketFileExists: { _ in false }, processEnvironment: processEnvironment)
        }
        let center = MachineJobCenter(runner: ProcessJobRunner(cli: cli), successSeconds: 2)
        let store = MachineReadinessStore(
            read: { await Task.detached { ReadinessReader.read(cli: cli) }.value },
            jobs: { center },
            listensForReports: false)

        await store.check()
        let machine = try XCTUnwrap(store.snapshot?.machines.first)
        XCTAssertTrue(machine.hasPrefix("devmachine-accept-"))
        print("E2E state before: \(store.state(for: machine)), cli \(String(describing: store.snapshot?.cliVersion))")
        XCTAssertTrue(store.state(for: machine).needsPrepare)
        XCTAssertEqual(store.machinesNeedingAttention, [machine])
        XCTAssertTrue(store.canPrepareInApp)

        var streamedWhileRunning = 0
        let id = try XCTUnwrap(store.prepare(machine))
        while store.prepareStatus(machine) == .running {
            streamedWhileRunning = max(streamedWhileRunning, center.job(id)?.log.lines.count ?? 0)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let lines = center.job(id)?.log.lines ?? []
        print("E2E log:\n" + lines.joined(separator: "\n"))
        print("E2E lines seen while running: \(streamedWhileRunning) of \(lines.count)")
        XCTAssertGreaterThan(streamedWhileRunning, 2)
        let deadline = Date().addingTimeInterval(60)
        while store.state(for: machine) != .ready, store.prepareFailure[machine] == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(store.prepareStatus(machine), .succeeded)
        XCTAssertEqual(store.state(for: machine), .ready)

        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertNil(store.preparing[machine])
        XCTAssertEqual(store.machinesNeedingAttention, [])
    }
}
