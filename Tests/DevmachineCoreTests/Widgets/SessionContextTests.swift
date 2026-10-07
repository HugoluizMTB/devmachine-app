import XCTest
@testable import DevmachineCore

final class SessionContextTests: XCTestCase {
    func testEveryKeyIsSetEvenWhenUnknown() {
        XCTAssertEqual(SessionContextFacts().values, [
            "machine": "", "session": "", "workspace": "", "path": "", "repo": "", "branch": "", "harness": "",
        ])
        let facts = SessionContextFacts(
            machine: "main", session: "api", workspace: "alice-dev", path: "/home/alice/api", repo: "acme/api",
            branch: "main", harness: "claude")
        XCTAssertEqual(facts.values["repo"], "acme/api")
        XCTAssertEqual(facts.values.count, 7)
        XCTAssertEqual(Set(facts.values.keys), Set(WidgetContract.current.surfaces["context-sidebar"]!.context.keys))
    }

    func testTheSidebarGivesTheSelectedWorkspace() {
        XCTAssertEqual(SidebarContext.values(selectedWorkspace: "alice-dev"), ["selected": "alice-dev"])
        XCTAssertEqual(SidebarContext.values(selectedWorkspace: nil), ["selected": ""])
        XCTAssertEqual(
            Set(SidebarContext.values(selectedWorkspace: nil).keys),
            Set(WidgetContract.current.surfaces["sidebar"]!.context.keys))
    }

    func testTheProbePrintsTwoLines() {
        XCTAssertTrue(ContextGitProbe.body.contains("rev-parse --abbrev-ref HEAD"))
        XCTAssertTrue(ContextGitProbe.body.contains("remote.origin.url"))
    }

    func testParsesBranchAndRepo() {
        XCTAssertEqual(
            ContextGitProbe.parse("main\nhttps://github.com/acme/api.git\n"),
            ContextGitStatus(branch: "main", repo: "acme/api"))
        XCTAssertEqual(ContextGitProbe.parse("HEAD\ngit@github.com:acme/api.git\n"), ContextGitStatus(branch: "", repo: "acme/api"))
        XCTAssertEqual(ContextGitProbe.parse("\n\n"), ContextGitStatus(branch: "", repo: ""))
        XCTAssertEqual(ContextGitProbe.parse(""), ContextGitStatus(branch: "", repo: ""))
    }

    func testReadsOwnerAndNameFromAnyRemoteForm() {
        XCTAssertEqual(ContextGitProbe.repo(fromRemote: "ssh://git@example.com:2222/acme/api.git"), "acme/api")
        XCTAssertEqual(ContextGitProbe.repo(fromRemote: "https://example.com/acme/api/"), "acme/api")
        XCTAssertEqual(ContextGitProbe.repo(fromRemote: "https://example.com/group/acme/api.git"), "acme/api")
        XCTAssertEqual(ContextGitProbe.repo(fromRemote: "/srv/git/api.git"), "git/api")
        XCTAssertEqual(ContextGitProbe.repo(fromRemote: "api"), "")
        XCTAssertEqual(ContextGitProbe.repo(fromRemote: ""), "")
    }

    private func source(
        _ run: String?, script: String? = nil, args: [String] = [], shell: Bool = false, keys: Set<String>? = nil
    ) -> ResolvedSource {
        let command = WidgetSource.command(CommandSource(
            run: run, script: script, args: args, shell: shell, target: .local, every: .interval(30), timeout: 30,
            mode: .poll, keep: 200, parse: .text))
        return ResolvedSource(
            source: command, view: WidgetView(kind: "text"), every: .interval(30), needsApproval: keys == nil,
            package: keys == nil ? nil : "acme", packagePath: nil, contextKeys: keys)
    }

    func testAPackageWidgetReadsWhatItDeclares() {
        XCTAssertTrue(source("git", keys: ["branch"]).reads(contextKey: "branch"))
        XCTAssertFalse(source("git", keys: ["branch"]).reads(contextKey: "repo"))
    }

    func testAnInlineWidgetReadsWhatItsTemplatesOrShellVariablesName() {
        XCTAssertTrue(source("gh", args: ["pr", "list", "-R", "{{ context.repo }}"]).reads(contextKey: "repo"))
        XCTAssertTrue(source("echo \"$DM_CONTEXT_BRANCH\"", shell: true).reads(contextKey: "branch"))
        XCTAssertFalse(source("ls", args: ["{{context.path}}"]).reads(contextKey: "repo"))
    }

    func testAnInlineWidgetDoesNotReadAKeyThatOnlyStartsTheSame() {
        XCTAssertFalse(source("echo", args: ["{{ context.repository }}"]).reads(contextKey: "repo"))
        XCTAssertFalse(source("echo \"$DM_CONTEXT_REPO_NAME\"", shell: true).reads(contextKey: "repo"))
        XCTAssertTrue(source("echo \"${DM_CONTEXT_REPO}x\"", shell: true).reads(contextKey: "repo"))
    }

    func testAnInlineScriptReadsEveryKey() {
        XCTAssertTrue(source(nil, script: "/home/alice/bin/status").reads(contextKey: "repo"))
        XCTAssertTrue(source(nil, script: "/home/alice/bin/status").reads(contextKey: "branch"))
        XCTAssertFalse(source(nil, script: "status.sh", keys: ["path"]).reads(contextKey: "repo"))
    }

    func testReadContextKeepsOnlyTheKeysTheSourceReads() {
        let context = ["path": "/home/alice/api", "branch": "main", "repo": "acme/api"]
        XCTAssertEqual(source("ls", args: ["{{context.path}}"]).readContext(context), ["path": "/home/alice/api"])
        XCTAssertEqual(source("git", keys: ["branch"]).readContext(context), ["branch": "main"])
        XCTAssertEqual(source(nil, script: "/home/alice/bin/status").readContext(context), context)
    }

    func testAShellLineGetsOnlyTheContextVariablesItNames() throws {
        let line = source("echo \"$DM_CONTEXT_PATH\"", shell: true)
        let context = ["path": "/home/alice/api", "branch": "main", "repo": "acme/api"]
        guard case let .shell(_, environment)? = try line.command(context: context) else { return XCTFail("not a shell line") }
        XCTAssertEqual(environment, ["DM_CONTEXT_PATH": "/home/alice/api"])
    }

    func testAShellLinesHashCoversOnlyTheValuesItNames() throws {
        let line = source("echo \"$DM_CONTEXT_PATH\"", shell: true)
        let api = ["path": "/home/alice/api", "branch": "main"]
        XCTAssertEqual(
            try ApprovalSubject.hash(for: line, context: api),
            try ApprovalSubject.hash(for: line, context: api.merging(["branch": "feature"]) { $1 }))
        XCTAssertNotEqual(
            try ApprovalSubject.hash(for: line, context: api),
            try ApprovalSubject.hash(for: line, context: api.merging(["path": "/home/alice/web"]) { $1 }))
    }

    func testAScriptKeepsEveryContextValue() {
        let script = source(nil, script: "/home/alice/bin/status")
        let context = ["path": "/home/alice/api", "branch": "main"]
        XCTAssertEqual(script.values(context: context).context, context)
    }

    func testAHomeShellLinesHashIsTheOneItWasBeforeTheContextFilter() throws {
        let command = WidgetSource.command(CommandSource(
            run: "df -h \"$DM_CONTEXT_PATH\" | tail -1", script: nil, args: [], shell: true, target: .local,
            every: .interval(30), timeout: 30, mode: .poll, keep: 200, parse: .text))
        let line = ResolvedSource(
            source: command, view: WidgetView(kind: "text"), every: .interval(30), needsApproval: true,
            package: nil, packagePath: nil)
        XCTAssertEqual(
            try ApprovalSubject.hash(for: line, context: [:]), "625d028eb873541277e9c6dde666568dc777b73dce12bb62cab44cdc30cd9a62")
    }
}
