import XCTest
@testable import DevmachineCore

final class ContainersStateTests: XCTestCase {
    private let web = ContainerStat(name: "web", memUsedBytes: 1, memLimitBytes: 2, cpuPercent: 0.5, owner: "acme")

    func testAMachineWithoutDockerHasNoDockerRatherThanZeroContainers() {
        let state = ContainersState(docker: .init(available: false, containers: []), visible: [])

        XCTAssertEqual(state, .noDocker)
        XCTAssertEqual(state.tileValue, "—")
        XCTAssertEqual(state.tileLabel, "No Docker")
        XCTAssertEqual(state.cardValue, "—")
    }

    func testDockerWithNothingRunningSaysSo() {
        let state = ContainersState(docker: .init(available: true, containers: []), visible: [])

        XCTAssertEqual(state, .empty)
        XCTAssertEqual(state.tileValue, "0")
        XCTAssertEqual(state.tileLabel, "Containers")
        XCTAssertEqual(state.cardValue, "0")
        XCTAssertEqual(ContainersState.emptyText, "No containers running.")
    }

    func testRunningContainersAreTheVisibleOnes() {
        let hidden = ContainerStat(name: "db", memUsedBytes: 1, memLimitBytes: 2, cpuPercent: 0, owner: "beta")
        let state = ContainersState(docker: .init(available: true, containers: [web, hidden]), visible: [web])

        XCTAssertEqual(state, .running([web]))
        XCTAssertEqual(state.tileValue, "1")
        XCTAssertEqual(state.tileLabel, "Containers")
        XCTAssertEqual(state.cardValue, "1")
    }

    func testTheInstallHintNamesTheMachine() {
        XCTAssertEqual(DockerInstallHint.message(machine: "backup"), "Docker isn't installed on backup.")
        XCTAssertEqual(DockerInstallHint.commands(machine: "backup"), [
            "devmachine packages add docker --machine backup",
            "devmachine sync --machine backup",
        ])
    }
}
