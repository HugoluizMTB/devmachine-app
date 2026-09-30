import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    let answer: ([String]) -> String

    init(answer: @escaping ([String]) -> String) {
        self.answer = answer
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.withLock { storedCalls.append([executable] + args) }
        return answer(args)
    }

    var calls: [[String]] { lock.withLock { storedCalls } }
}

final class PreviewTargetsServiceTests: XCTestCase {
    private static let workspaces = #"{"workspaces":[{"name":"acme","machine":"main","user":"acme","packages":[]}]}"#
    private static let sites = #"[{"host":"app.acme.example.com","port":3000,"workspace":"acme","status":"published"}]"#
    private static let stats = """
    {"collected_at":"2026-09-30T12:00:00Z","memory":{"total_bytes":1,"used_bytes":1,"available_bytes":1},
     "swap":{"total_bytes":0,"used_bytes":0},"disk":{"path":"/","used_bytes":1,"available_bytes":1,"used_percent":1},
     "load":{"load1":0,"load5":0,"load15":0},"docker":{"available":false,"containers":[]},"users":[],
     "ports":[{"port":5173,"owner":"acme"},{"port":4000,"owner":"beta"}],"errors":[]}
    """

    private func cliRunner() -> ScriptedRunner {
        ScriptedRunner { args in
            if args.contains("workspaces") { return Self.workspaces }
            if args.contains("expose") { return Self.sites }
            if args.contains("stats") { return Self.stats }
            return ""
        }
    }

    func testARemoteWorkspaceReadsItsMachinesSitesAndPorts() throws {
        let runner = cliRunner()
        let service = PreviewTargetsService(
            cli: DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner),
            localRunner: ScriptedRunner { _ in "" })

        let targets = try service.targets(for: .workspace("acme"), cachedStats: [:])

        XCTAssertEqual(targets.map(\.kind), [.site(host: "app.acme.example.com"), .port(5173)])
        XCTAssertTrue(runner.calls.contains { $0.contains("--machine") && $0.contains("main") && $0.contains("expose") })
    }

    func testTheStatsAlreadyReadForTheMachineAreReused() throws {
        let runner = cliRunner()
        let service = PreviewTargetsService(
            cli: DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner),
            localRunner: ScriptedRunner { _ in "" })
        let cached = try XCTUnwrap(StatsParser.parse(Self.stats))

        _ = try service.targets(for: .workspace("acme"), cachedStats: ["main": cached])

        XCTAssertFalse(runner.calls.contains { $0.contains("stats") })
    }

    func testAnUnknownWorkspaceIsAnError() {
        let service = PreviewTargetsService(
            cli: DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: cliRunner()),
            localRunner: ScriptedRunner { _ in "" })

        XCTAssertThrowsError(try service.targets(for: .workspace("beta"), cachedStats: [:]))
    }

    func testThisMacListsWhatItListensOn() throws {
        let local = ScriptedRunner { _ in "p1\ncnode\nn*:5173\n" }
        let service = PreviewTargetsService(cli: nil, localRunner: local)

        let targets = try service.targets(for: .thisMac, cachedStats: [:])

        XCTAssertEqual(targets.map(\.kind), [.port(5173)])
        XCTAssertEqual(local.calls.first?.first, "/usr/sbin/lsof")
    }
}
