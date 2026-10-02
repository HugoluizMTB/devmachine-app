import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRuns: [(String, [String])] = []
    private var storedLines: [String] = []
    private var storedWrites = 0
    var runs: [(String, [String])] { lock.withLock { storedRuns } }
    var lines: [String] { lock.withLock { storedLines } }
    var writes: Int { lock.withLock { storedWrites } }
    func run(_ executable: String, _ arguments: [String]) { lock.withLock { storedRuns.append((executable, arguments)) } }
    func line(_ text: String) { lock.withLock { storedLines.append(text) } }
    func wrote() { lock.withLock { storedWrites += 1 } }
}

final class LimaInstallerTests: XCTestCase {
    private let tarball = Data("not really a tarball".utf8)

    private func installer(
        sums: String? = nil, limactlAppears: Bool = true, recorder: Recorder, tarStatus: Int32 = 0
    ) -> LimaInstaller {
        let digest = LimaInstall.sha256(tarball)
        let sums = sums ?? "\(digest)  lima-2.2.0-Darwin-arm64.tar.gz\n"
        let tarball = tarball
        return LimaInstaller(
            home: "/Users/alice", machine: "arm64",
            fetch: { url in
                switch url.lastPathComponent {
                case "latest": return Data(#"{"tag_name":"v2.2.0"}"#.utf8)
                case "SHA256SUMS": return Data(sums.utf8)
                case "lima-2.2.0-Darwin-arm64.tar.gz": return tarball
                default: throw URLError(.badURL)
                }
            },
            run: { executable, arguments, _ in
                recorder.run(executable, arguments)
                return executable == "/usr/bin/tar" ? tarStatus : 0
            },
            write: { _ in
                recorder.wrote()
                return "/tmp/lima.tar.gz"
            },
            makeDirectory: { _ in },
            exists: { limactlAppears && $0 == "/Users/alice/.local/bin/limactl" })
    }

    func testTheReleaseIsCheckedThenUnpackedIntoTheLocalFolder() async throws {
        let recorder = Recorder()
        try await installer(recorder: recorder).install(.release, output: recorder.line)

        XCTAssertEqual(recorder.runs.first?.0, "/usr/bin/tar")
        XCTAssertEqual(recorder.runs.first?.1, ["-xzf", "/tmp/lima.tar.gz", "-C", "/Users/alice/.local"])
        XCTAssertEqual(recorder.runs.last?.0, "/Users/alice/.local/bin/limactl")
        XCTAssertTrue(recorder.lines.contains { $0.hasPrefix("SHA-256 matches") })
    }

    func testADownloadThatDoesNotMatchItsChecksumIsNeverWrittenOrUnpacked() async {
        let recorder = Recorder()
        let wrong = String(repeating: "0", count: 64) + "  lima-2.2.0-Darwin-arm64.tar.gz\n"
        do {
            try await installer(sums: wrong, recorder: recorder).install(.release, output: recorder.line)
            XCTFail("a mismatch must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("does not match"))
        }
        XCTAssertEqual(recorder.writes, 0)
        XCTAssertTrue(recorder.runs.isEmpty)
    }

    func testAFileTheChecksumsDoNotListIsRefused() async {
        let recorder = Recorder()
        do {
            try await installer(sums: "", recorder: recorder).install(.release, output: recorder.line)
            XCTFail("an unlisted file must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("SHA256SUMS"))
        }
        XCTAssertTrue(recorder.runs.isEmpty)
    }

    func testHomebrewInstallsLimaWhenAskedTo() async throws {
        let recorder = Recorder()
        try await installer(recorder: recorder).install(.homebrew(brew: "/opt/homebrew/bin/brew"), output: recorder.line)
        XCTAssertEqual(recorder.runs.first?.0, "/opt/homebrew/bin/brew")
        XCTAssertEqual(recorder.runs.first?.1, ["install", "lima"])
    }

    func testAnInstallThatLeavesNoLimactlFails() async {
        let recorder = Recorder()
        do {
            try await installer(limactlAppears: false, recorder: recorder).install(.release, output: recorder.line)
            XCTFail("no limactl must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("limactl"))
        }
    }
}

@MainActor
final class AddMachineLimaTests: XCTestCase {
    func testALocalMachineWithoutLimaInstallsItFirstAndOffersHomebrewWhenTheDownloadFails() async {
        var methods: [LimaInstall.Method] = []
        var ran: [[String]] = []
        var fail = true
        let hooks = MachineStepRunner.Hooks(
            executable: { "/opt/homebrew/bin/devmachine" }, isReady: { _ in true }, type: { _, _ in },
            matchCount: { _, _ in 0 }, writeScript: { _, _ in "/tmp/x.sh" }, isAtPrompt: { _ in nil },
            runProcess: { arguments, _, _ in
                ran.append(arguments)
                return 0
            },
            beginTask: { _, _ in nil }, setTask: { _, _ in }, endTask: { _, _ in },
            installLima: { method, output in
                methods.append(method)
                if fail {
                    fail = false
                    output("The Internet connection appears to be offline.")
                    throw LimaInstallError(message: "The Internet connection appears to be offline.")
                }
            })
        let snapshot = MachinesSnapshot(
            hasConfiguration: true, machines: [], packages: [], cliVersion: MachineUnattendedAdd.minimumCLIVersion)
        let model = AddMachineModel(
            machines: MachinesStore(read: { snapshot }, remove: { _ in }),
            runner: MachineStepRunner(hooks: hooks, pollInterval: 1_000_000),
            findLima: { nil }, findBrew: { "/opt/homebrew/bin/brew" }, onAdded: {})
        await model.prepareFirstRun()
        model.wizard.choose(.localVM)
        model.wizard.draft.name = "lab"
        model.wizard.draft.sync = false
        model.wizard.next()
        model.wizard.next()

        await model.create()

        XCTAssertEqual(model.failedStep?.kind, .installLima)
        XCTAssertEqual(SetupFailureHelp.help(for: model.failedStep!, lines: model.runner.lines).cause, .limaDownload)
        XCTAssertTrue(model.offersHomebrewLima)
        XCTAssertTrue(ran.isEmpty)

        await model.retryLimaWithHomebrew()

        XCTAssertEqual(methods, [.release, .homebrew(brew: "/opt/homebrew/bin/brew")])
        XCTAssertEqual(ran, [["machines", "create-local", "lab", "--add"]])
        XCTAssertEqual(model.runner.phase, .succeeded)
    }
}
