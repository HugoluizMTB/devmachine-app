import XCTest
import DevmachineCore
@testable import DevmachineApp

private struct FakeFailure: Error {}

private final class LocalFakeRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    let listing: String
    let psOutput: String?
    let branches: [String: String]
    let failingGit: Bool

    init(
        listing: String, psOutput: String? = nil, branches: [String: String] = [:],
        failingGit: Bool = false
    ) {
        self.listing = listing
        self.psOutput = psOutput
        self.branches = branches
        self.failingGit = failingGit
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        recorded.append(Call(executable: executable, args: args))
        lock.unlock()
        switch executable {
        case "/fake/zmx":
            return listing
        case "/bin/ps":
            if args.first == "-o" {
                guard let psOutput else { throw FakeFailure() }
                return psOutput
            }
            return ""
        case "/usr/bin/git":
            if failingGit { throw FakeFailure() }
            guard args.count == 5, args[3] == "--abbrev-ref" || args[3] == "--short" else { return "" }
            if args[3] == "--short" { return "abc1234\n" }
            return branches[args[1]].map { "\($0)\n" } ?? ""
        default:
            return ""
        }
    }
}

final class SessionListSourceTests: XCTestCase {
    private let web = "/Users/acme/dev/acme-web"

    private func line(_ name: String, pid: Int, cwd: String?) -> String {
        var fields = ["name=\(name)", "pid=\(pid)", "clients=0"]
        if let cwd { fields.append("cwd=\(cwd)") }
        return fields.joined(separator: "\t")
    }

    private func source(_ runner: LocalFakeRunner) -> CommandSessionSource {
        CommandSessionSource(
            store: SessionStore(runner: runner), localRunner: runner, zmxPath: "/fake/zmx",
            facade: SessionHarnessFacade())
    }

    private func gitCalls(_ runner: LocalFakeRunner) -> [LocalFakeRunner.Call] {
        runner.calls.filter { $0.executable == "/usr/bin/git" }
    }

    func testEverySessionGetsItsAgeAndBranchAndGitRunsOncePerDirectory() throws {
        let runner = LocalFakeRunner(
            listing: [line("one", pid: 11, cwd: web), line("two", pid: 22, cwd: web)]
                .joined(separator: "\n"),
            psOutput: "  11 01:05\n  22 3-02:01:05\n",
            branches: [web: "main"])

        let snapshot = try source(runner).localSessions(settings: AppSettings.empty)

        XCTAssertEqual(
            snapshot.indicators["one"],
            SessionIndicators(path: web, branch: "main", ageSeconds: 65))
        XCTAssertEqual(
            snapshot.indicators["two"],
            SessionIndicators(path: web, branch: "main", ageSeconds: 266_465))
        XCTAssertEqual(gitCalls(runner).count, 1)
    }

    func testADetachedHeadShowsTheShortSHA() throws {
        let runner = LocalFakeRunner(
            listing: line("one", pid: 11, cwd: web), psOutput: "11 00:09\n", branches: [web: "HEAD"])

        let snapshot = try source(runner).localSessions(settings: AppSettings.empty)

        XCTAssertEqual(snapshot.indicators["one"]?.branch, "abc1234")
    }

    func testAFailingGitLeavesTheBranchNilAndKeepsTheRest() throws {
        let runner = LocalFakeRunner(
            listing: line("one", pid: 11, cwd: web), psOutput: "11 00:09\n", failingGit: true)

        let snapshot = try source(runner).localSessions(settings: AppSettings.empty)

        XCTAssertEqual(
            snapshot.indicators["one"], SessionIndicators(path: web, branch: nil, ageSeconds: 9))
    }

    func testADirectoryThatIsNotARepositoryHasNoBranch() throws {
        let runner = LocalFakeRunner(
            listing: line("one", pid: 11, cwd: web), psOutput: "11 00:09\n")

        let snapshot = try source(runner).localSessions(settings: AppSettings.empty)

        XCTAssertEqual(
            snapshot.indicators["one"], SessionIndicators(path: web, branch: nil, ageSeconds: 9))
    }

    func testAFailingPsLeavesTheAgeNilAndKeepsTheSession() throws {
        let runner = LocalFakeRunner(
            listing: line("one", pid: 11, cwd: web), psOutput: nil, branches: [web: "main"])

        let snapshot = try source(runner).localSessions(settings: AppSettings.empty)

        XCTAssertEqual(snapshot.sessions.map(\.name), ["one"])
        XCTAssertEqual(
            snapshot.indicators["one"], SessionIndicators(path: web, branch: "main", ageSeconds: nil))
    }

    func testASessionWithoutADirectoryStillHasItsAge() throws {
        let runner = LocalFakeRunner(
            listing: line("one", pid: 11, cwd: nil), psOutput: "11 00:09\n")

        let snapshot = try source(runner).localSessions(settings: AppSettings.empty)

        XCTAssertEqual(
            snapshot.indicators["one"], SessionIndicators(path: nil, branch: nil, ageSeconds: 9))
        XCTAssertTrue(gitCalls(runner).isEmpty)
    }
}
