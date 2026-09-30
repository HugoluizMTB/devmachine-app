import XCTest
import DevmachineCore
@testable import DevmachineApp

final class FakeTunnelProcess: TunnelProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var terminated = false
    private let stderr: String

    init(running: Bool = true, stderr: String = "") {
        self.running = running
        self.stderr = stderr
    }

    var isRunning: Bool { lock.withLock { running } }
    var errorOutput: String { stderr }
    var wasTerminated: Bool { lock.withLock { terminated } }

    func terminate() {
        lock.withLock {
            running = false
            terminated = true
        }
    }
}

final class FakeTunnelLauncher: TunnelLaunching, @unchecked Sendable {
    struct Launch: Equatable {
        let workspace: String
        let remotePort: Int
        let localPort: Int
    }

    private let lock = NSLock()
    private var storedLaunches: [Launch] = []
    private var storedProcesses: [FakeTunnelProcess] = []
    var nextProcess: () -> FakeTunnelProcess = { FakeTunnelProcess() }
    var failure: Error?

    func launch(workspace: String, remotePort: Int, localPort: Int) throws -> any TunnelProcess {
        if let failure { throw failure }
        let process = nextProcess()
        lock.withLock {
            storedLaunches.append(Launch(workspace: workspace, remotePort: remotePort, localPort: localPort))
            storedProcesses.append(process)
        }
        return process
    }

    var launches: [Launch] { lock.withLock { storedLaunches } }
    var processes: [FakeTunnelProcess] { lock.withLock { storedProcesses } }
}

final class FakePortProbe: LocalPortProbing, @unchecked Sendable {
    var taken: Set<Int> = []
    var accepting = true
    var nextFree = 55000

    func isFree(_ port: Int) -> Bool { !taken.contains(port) }
    func freePort() -> Int? { nextFree }
    func isAccepting(_ port: Int) -> Bool { accepting }
}

@MainActor
final class TunnelManagerTests: XCTestCase {
    private let acme3000 = TunnelKey(workspace: "acme", remotePort: 3000)

    private func manager(
        _ launcher: FakeTunnelLauncher, _ probe: FakePortProbe, timeout: TimeInterval = 1
    ) -> TunnelManager {
        TunnelManager(launcher: launcher, probe: probe, readyTimeout: timeout, pollInterval: 0.01)
    }

    func testStartsATunnelOnTheSamePortWhenItIsFreeHere() async throws {
        let launcher = FakeTunnelLauncher()
        let tunnels = manager(launcher, FakePortProbe())

        let port = try await tunnels.open(acme3000, holder: "tab-1")

        XCTAssertEqual(port, 3000)
        XCTAssertEqual(launcher.launches, [.init(workspace: "acme", remotePort: 3000, localPort: 3000)])
        XCTAssertEqual(tunnels.tunnel(for: acme3000)?.state, .open)
    }

    func testPicksAnotherLocalPortWhenTheRemoteOneIsTakenHere() async throws {
        let launcher = FakeTunnelLauncher()
        let probe = FakePortProbe()
        probe.taken = [3000]
        let tunnels = manager(launcher, probe)

        let port = try await tunnels.open(acme3000, holder: "tab-1")

        XCTAssertEqual(port, 55000)
        XCTAssertEqual(launcher.launches.first?.localPort, 55000)
    }

    func testASecondPreviewOfThePortReusesTheTunnel() async throws {
        let launcher = FakeTunnelLauncher()
        let tunnels = manager(launcher, FakePortProbe())

        _ = try await tunnels.open(acme3000, holder: "tab-1")
        let port = try await tunnels.open(acme3000, holder: "tab-2")

        XCTAssertEqual(port, 3000)
        XCTAssertEqual(launcher.launches.count, 1)
    }

    func testTheTunnelStaysWhileAnotherPreviewStillUsesIt() async throws {
        let launcher = FakeTunnelLauncher()
        let tunnels = manager(launcher, FakePortProbe())
        _ = try await tunnels.open(acme3000, holder: "tab-1")
        _ = try await tunnels.open(acme3000, holder: "tab-2")

        tunnels.release(holder: "tab-1")

        XCTAssertFalse(launcher.processes[0].wasTerminated)
        tunnels.release(holder: "tab-2")
        XCTAssertTrue(launcher.processes[0].wasTerminated)
        XCTAssertNil(tunnels.tunnel(for: acme3000))
    }

    func testADeadTunnelIsStartedAgain() async throws {
        let launcher = FakeTunnelLauncher()
        let tunnels = manager(launcher, FakePortProbe())
        _ = try await tunnels.open(acme3000, holder: "tab-1")
        launcher.processes[0].terminate()

        _ = try await tunnels.open(acme3000, holder: "tab-2")

        XCTAssertEqual(launcher.launches.count, 2)
    }

    func testTwoTunnelsNeverShareALocalPort() async throws {
        let launcher = FakeTunnelLauncher()
        let probe = FakePortProbe()
        let tunnels = manager(launcher, probe)
        _ = try await tunnels.open(acme3000, holder: "tab-1")
        probe.taken = [3000]

        let port = try await tunnels.open(TunnelKey(workspace: "beta", remotePort: 3000), holder: "tab-2")

        XCTAssertEqual(port, 55000)
    }

    func testATunnelThatExitsBeforeItIsReadyReportsWhatItSaid() async {
        let launcher = FakeTunnelLauncher()
        launcher.nextProcess = { FakeTunnelProcess(running: false, stderr: "workspace \"acme\" not found\n") }
        let probe = FakePortProbe()
        probe.accepting = false
        let tunnels = manager(launcher, probe)

        do {
            _ = try await tunnels.open(acme3000, holder: "tab-1")
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "workspace \"acme\" not found")
        }
        XCTAssertNil(tunnels.tunnel(for: acme3000))
    }

    func testATunnelThatNeverAnswersIsStoppedAfterTheTimeout() async {
        let launcher = FakeTunnelLauncher()
        let probe = FakePortProbe()
        probe.accepting = false
        let tunnels = manager(launcher, probe, timeout: 0.05)

        do {
            _ = try await tunnels.open(acme3000, holder: "tab-1")
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(launcher.processes[0].wasTerminated)
        }
    }

    func testStopAllEndsEveryTunnel() async throws {
        let launcher = FakeTunnelLauncher()
        let tunnels = manager(launcher, FakePortProbe())
        _ = try await tunnels.open(acme3000, holder: "tab-1")
        _ = try await tunnels.open(TunnelKey(workspace: "beta", remotePort: 5173), holder: "browser")

        tunnels.stopAll()

        XCTAssertTrue(launcher.processes.allSatisfy(\.wasTerminated))
        XCTAssertTrue(tunnels.openTunnels.isEmpty)
    }

    func testStoppingOneTunnelLeavesTheOthers() async throws {
        let launcher = FakeTunnelLauncher()
        let tunnels = manager(launcher, FakePortProbe())
        _ = try await tunnels.open(acme3000, holder: "browser")
        _ = try await tunnels.open(TunnelKey(workspace: "beta", remotePort: 5173), holder: "browser")

        tunnels.stop(acme3000)

        XCTAssertEqual(tunnels.openTunnels.map(\.key), [TunnelKey(workspace: "beta", remotePort: 5173)])
    }
}

final class DevmachineCLITunnelTests: XCTestCase {
    func testTheTunnelCommandNamesTheLocalPort() {
        let cli = DevmachineCLI(
            executable: "/opt/homebrew/bin/devmachine", customSocket: "/tmp/agent.sock",
            socketFileExists: { _ in true }, processEnvironment: ["PATH": "/usr/bin"])

        let command = cli.tunnelCommand(workspace: "acme", remotePort: 3000, localPort: 55000)

        XCTAssertEqual(command.executable, "/opt/homebrew/bin/devmachine")
        XCTAssertEqual(command.args, ["tunnel", "acme", "3000", "--local", "55000"])
        XCTAssertEqual(command.environment["SSH_AUTH_SOCK"], "/tmp/agent.sock")
    }
}

@MainActor
final class TunnelManagerReleaseTests: XCTestCase {
    func testATabClosedWhileItsTunnelStartsLeavesNoTunnel() async {
        let launcher = FakeTunnelLauncher()
        let probe = FakePortProbe()
        probe.accepting = false
        let tunnels = TunnelManager(launcher: launcher, probe: probe, readyTimeout: 2, pollInterval: 0.01)
        let key = TunnelKey(workspace: "acme", remotePort: 3000)

        let opening = Task { try await tunnels.open(key, holder: "tab-1") }
        try? await Task.sleep(nanoseconds: 30_000_000)
        tunnels.release(holder: "tab-1")
        probe.accepting = true
        _ = try? await opening.value

        XCTAssertNil(tunnels.tunnel(for: key))
        XCTAssertTrue(launcher.processes[0].wasTerminated)
    }
}
