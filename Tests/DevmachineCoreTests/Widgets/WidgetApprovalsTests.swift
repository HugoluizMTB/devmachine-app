import XCTest
@testable import DevmachineCore

final class WidgetApprovalsTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetApprovalsTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func command(_ changes: (inout CommandSource) -> Void = { _ in }) -> WidgetSource {
        var source = CommandSource(run: "df", script: nil, args: ["-h", "/"], shell: false, target: .workspace("alice"),
                                   every: .interval(60), timeout: 30, mode: .poll, keep: 200, parse: .text)
        changes(&source)
        return .command(source)
    }

    func testTheCanonicalSubjectHoldsOnlyWhatRuns() {
        XCTAssertEqual(ApprovalSubject.canonicalJSON(command()),
                       #"{"args":["-h","/"],"kind":"command","run":"df","shell":false,"target":{"workspace":"alice"}}"#)
        XCTAssertEqual(
            ApprovalSubject.canonicalJSON(.prompt(PromptSource(harness: .claude, prompt: "Hi", target: .local, every: .manual, timeout: 300))),
            #"{"harness":"claude","kind":"prompt","prompt":"Hi","target":"local"}"#)
        XCTAssertEqual(
            ApprovalSubject.canonicalJSON(.session(SessionSource(target: .machine("main"), session: "main", every: .interval(2)))),
            #"{"kind":"session","session":"main","target":{"machine":"main"}}"#)
        XCTAssertNil(ApprovalSubject.hash(.url(URLSource(url: "https://example.com", every: .interval(30), timeout: 30, parse: .status))))
        XCTAssertNil(ApprovalSubject.hash(.provider(ProviderSource(name: "app/clock", with: [:], every: "60s"))))
    }

    func testTheHashIsSHA256Hex() {
        let hash = ApprovalSubject.hash(command())
        XCTAssertEqual(hash?.count, 64)
        XCTAssertEqual(hash, ApprovalSubject.hash(command()))
    }

    func testKeyOrderAndEveryDoNotChangeTheHash() throws {
        let one = try WidgetSourceReader.read(.object([
            "kind": .string("command"), "run": .string("df"), "args": .list([.string("-h"), .string("/")]),
            "target": .object(["workspace": .string("alice")]), "every": .string("60s"),
        ]), scope: .inline(contextKeys: []))
        let two = try WidgetSourceReader.read(.object([
            "every": .string("5m"), "timeout": .string("1m"), "target": .object(["workspace": .string("alice")]),
            "args": .list([.string("-h"), .string("/")]), "run": .string("df"), "kind": .string("command"),
        ]), scope: .inline(contextKeys: []))
        XCTAssertEqual(ApprovalSubject.hash(one), ApprovalSubject.hash(two))
        XCTAssertEqual(ApprovalSubject.hash(command()), ApprovalSubject.hash(one))
    }

    func testEveryRunFieldChangesTheHash() {
        let base = ApprovalSubject.hash(command())
        let changed: [WidgetSource] = [
            command { $0.run = "du" },
            command { $0.run = nil; $0.script = "/opt/df" },
            command { $0.args = ["-h", "/home"] },
            command { $0.args = ["/", "-h"] },
            command { $0.shell = true },
            command { $0.target = .workspace("bob") },
            command { $0.target = .machine("alice") },
            command { $0.target = .local },
        ]
        for source in changed { XCTAssertNotEqual(ApprovalSubject.hash(source), base, "\(source)") }
        let prompt = PromptSource(harness: .claude, prompt: "Hi", target: .local, every: .manual, timeout: 300)
        var codex = prompt
        codex.harness = .codex
        var reworded = prompt
        reworded.prompt = "Hi!"
        XCTAssertNotEqual(ApprovalSubject.hash(.prompt(prompt)), ApprovalSubject.hash(.prompt(codex)))
        XCTAssertNotEqual(ApprovalSubject.hash(.prompt(prompt)), ApprovalSubject.hash(.prompt(reworded)))
        XCTAssertNotEqual(
            ApprovalSubject.hash(.session(SessionSource(target: .local, session: "a", every: .interval(2)))),
            ApprovalSubject.hash(.session(SessionSource(target: .local, session: "b", every: .interval(2)))))
    }

    func testStates() {
        var approvals = WidgetApprovals()
        XCTAssertEqual(approvals.state(needsApproval: false, hash: nil), .notNeeded)
        XCTAssertEqual(approvals.state(needsApproval: true, hash: "h1"), .waiting(hash: "h1"))
        approvals.record(.allowed, hash: "h1", summary: "df", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(approvals.state(needsApproval: true, hash: "h1"), .allowed)
        XCTAssertEqual(approvals.state(needsApproval: true, hash: "h2"), .waiting(hash: "h2"))
        approvals.record(.denied, hash: "h2", summary: "du", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(approvals.state(needsApproval: true, hash: "h2"), .denied(hash: "h2"))
        XCTAssertFalse(ApprovalState.denied(hash: "h2").canRun)
        XCTAssertTrue(ApprovalState.notNeeded.canRun)
    }

    func testTheFileRoundTripsAndCreatesItsFolder() throws {
        let file = WidgetApprovalsFile(fileURL: folder.appendingPathComponent("nested/widget-approvals.json"))
        var approvals = WidgetApprovals()
        approvals.record(.denied, hash: "abc", summary: "df -h / in workspace alice", at: Date(timeIntervalSince1970: 1_700_000_000))
        try file.save(approvals)
        XCTAssertEqual(file.load(), approvals)
        let text = try String(contentsOf: file.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\" : 1"))
        XCTAssertTrue(text.contains("\"decided_at\""))
    }

    func testAnUnreadableFileMeansEverythingWaits() throws {
        let file = WidgetApprovalsFile(fileURL: folder.appendingPathComponent("widget-approvals.json"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file.fileURL)
        XCTAssertEqual(file.load(), WidgetApprovals())
    }

    func testTheDefaultFileLivesInApplicationSupportNotTheConfigFolder() {
        let path = WidgetApprovalsFile.defaultFileURL.path
        XCTAssertTrue(path.hasSuffix("Library/Application Support/Devmachine/widget-approvals.json"), path)
        XCTAssertFalse(path.contains(".config/devmachine"))
    }

    func testCopy() {
        XCTAssertEqual(ApprovalCopy.what(command { $0.args = ["-h", "x y"] }), "df -h 'x y'")
        XCTAssertEqual(ApprovalCopy.what(command { $0.run = "df | tail -1"; $0.shell = true; $0.args = [] }), "df | tail -1")
        XCTAssertEqual(ApprovalCopy.place(.local), "on this Mac")
        XCTAssertEqual(ApprovalCopy.place(.machine("main")), "on machine main")
        XCTAssertEqual(ApprovalCopy.place(.workspace("alice")), "in workspace alice")
        XCTAssertEqual(ApprovalCopy.howOften(.interval(60)), "every 1m")
        XCTAssertEqual(ApprovalCopy.howOften(.interval(5)), "every 5s")
        XCTAssertEqual(ApprovalCopy.howOften(.manual), "when you press ▶")
        XCTAssertEqual(ApprovalCopy.howOften(.continuous), "all the time while it is on screen")
        XCTAssertEqual(
            ApprovalCopy.what(.prompt(PromptSource(harness: .codex, prompt: "Hi", target: .local, every: .manual, timeout: 300))),
            "Ask Codex: Hi")
        XCTAssertEqual(ApprovalCopy.what(.session(SessionSource(target: .local, session: "main", every: .interval(2)))),
                       "Read the screen of session main")
    }

    private func resolved(_ source: WidgetSource, inputs: [String: String] = [:]) -> ResolvedSource {
        ResolvedSource(source: source, view: WidgetView(kind: "text"), every: source.every, needsApproval: true,
                       package: nil, packagePath: nil, inputs: inputs)
    }

    func testThePromptShowsTheFilledValuesTheHashCovers() throws {
        let inline = resolved(command { $0.run = "ls"; $0.args = ["{{context.dir}}"]; $0.target = .local })
        XCTAssertEqual(ApprovalPrompt(inline, context: [:]).what, "ls ''")
        XCTAssertEqual(ApprovalPrompt(inline, context: ["dir": "/Users/alice/a b"]).what, "ls '/Users/alice/a b'")
        let placed = resolved(command { $0.target = .machine("{{inputs.machine}}") }, inputs: ["machine": "main"])
        let prompt = ApprovalPrompt(placed, context: [:])
        XCTAssertEqual(prompt.place, "on machine main")
        XCTAssertEqual(prompt.summary, "df -h / on machine main, every 1m")
        XCTAssertEqual(try ApprovalSubject.hash(for: placed, context: [:]),
                       ApprovalSubject.hash(command { $0.target = .machine("main") }))
    }

    func testAShellLineShowsTheValuesItReadsFromTheEnvironment() throws {
        func line(_ disk: String) -> ResolvedSource {
            resolved(command { $0.run = #"df -h "$DM_INPUT_DISK""#; $0.shell = true; $0.args = [] }, inputs: ["disk": disk])
        }
        XCTAssertEqual(ApprovalPrompt(line("/"), context: [:]).what, #"DM_INPUT_DISK=/ df -h "$DM_INPUT_DISK""#)
        XCTAssertEqual(ApprovalPrompt(line("/a b"), context: [:]).what, #"DM_INPUT_DISK='/a b' df -h "$DM_INPUT_DISK""#)
        XCTAssertNotEqual(try ApprovalSubject.hash(for: line("/"), context: [:]),
                          try ApprovalSubject.hash(for: line("/a b"), context: [:]))
    }

    func testARefusedSourceShowsItAsWritten() {
        let refused = resolved(command { $0.run = "{{inputs.tool}}" }, inputs: ["tool": "rm"])
        XCTAssertEqual(ApprovalPrompt(refused, context: [:]).what, "{{inputs.tool}} -h /")
    }

    private func load(with: [String: String] = ["window": "5m"], target: WidgetTarget = .machine("main")) -> WidgetSource {
        .packageProvider(PackageProviderSource(name: "acme-tools/load", with: with, target: target, every: .interval(30), timeout: 30))
    }

    func testAPackageProvidersSubjectIsTheArgvItRuns() {
        XCTAssertEqual(ApprovalSubject.canonicalJSON(load()),
                       #"{"args":["--window","5m"],"kind":"provider","name":"acme-tools/load","target":{"machine":"main"}}"#)
        XCTAssertNotEqual(ApprovalSubject.hash(load()), ApprovalSubject.hash(load(with: ["window": "1m"])))
        XCTAssertNotEqual(ApprovalSubject.hash(load()), ApprovalSubject.hash(load(target: .workspace("alice-dev"))))
        XCTAssertNil(ApprovalSubject.hash(load(with: ["x; rm": "v"])))
    }

    func testAPackageCommitJoinsTheSubjectOnlyWhenGiven() {
        XCTAssertEqual(
            ApprovalSubject.canonicalJSON(command(), packageCommit: "1111"),
            #"{"args":["-h","/"],"kind":"command","package_commit":"1111","run":"df","shell":false,"target":{"workspace":"alice"}}"#)
        XCTAssertEqual(
            ApprovalSubject.canonicalJSON(command()),
            #"{"args":["-h","/"],"kind":"command","run":"df","shell":false,"target":{"workspace":"alice"}}"#)
        XCTAssertNotEqual(ApprovalSubject.hash(load(), packageCommit: ""), ApprovalSubject.hash(load()))
        XCTAssertNotEqual(ApprovalSubject.hash(load(), packageCommit: "1111"), ApprovalSubject.hash(load(), packageCommit: "2222"))
        XCTAssertNil(ApprovalSubject.hash(.url(URLSource(url: "https://example.com", every: .interval(30), timeout: 30, parse: .status)),
                                          packageCommit: "1111"))
    }

    func testTheCardReadsAPackageProviderAsItsCommandLine() {
        XCTAssertEqual(ApprovalCopy.what(load(with: ["path": "/var/log/system log", "all": "yes"])),
                       "acme-tools/load --all yes --path '/var/log/system log'")
        XCTAssertEqual(ApprovalCopy.place(load().target), "on machine main")
    }
}
