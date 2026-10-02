import XCTest
@testable import DevmachineCore

final class MachinePlanTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "B", count: 43)

    private var server: MachineDraft {
        var draft = MachineDraft()
        draft.name = "main"
        draft.address = "203.0.113.10"
        draft.fingerprint = "256 \(fingerprint) root@main (ED25519)"
        draft.keyFile = "~/.ssh/id_ed25519"
        return draft
    }

    func testAServerWithAKeyIsAddedWithoutAQuestionThenSynced() {
        let steps = MachinePlan.steps(for: server)
        XCTAssertEqual(steps.map(\.arguments), [
            ["machines", "add", "--name", "main", "--address", "203.0.113.10",
             "--fingerprint", fingerprint, "--key", "~/.ssh/id_ed25519", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
        XCTAssertEqual(steps.map(\.asksInTerminal), [false, false])
    }

    func testOnlyTheAnswersThatDifferFromTheCLIDefaultsBecomeFlags() {
        var draft = server
        draft.user = "deploy"
        draft.port = "2222"
        draft.essentials = false
        XCTAssertEqual(MachinePlan.steps(for: draft).first?.arguments, [
            "machines", "add", "--name", "main", "--address", "203.0.113.10",
            "--fingerprint", fingerprint, "--user", "deploy", "--port", "2222",
            "--key", "~/.ssh/id_ed25519", "--no-essentials", "--yes",
        ])
    }

    func testAPasswordServerIsAddedByTheCLIsOwnQuestions() {
        var draft = server
        draft.login = .password
        let add = MachinePlan.steps(for: draft).first
        XCTAssertEqual(add?.arguments, ["machines", "add", "--yes"])
        XCTAssertEqual(add?.asksInTerminal, true)
    }

    func testALocalMachineIsCreatedThenAddedThroughTheCLIsQuestions() {
        var draft = MachineDraft()
        draft.kind = .localVM
        draft.name = "lab"
        let steps = MachinePlan.steps(for: draft)
        XCTAssertEqual(steps.map(\.arguments), [
            ["machines", "create-local", "lab"],
            ["machines", "add", "--yes"],
            ["sync", "--machine", "lab", "--yes"],
        ])
        XCTAssertEqual(steps.map(\.asksInTerminal), [false, true, false])
    }

    func testTheFirstMachineOfAllIsWrittenBySetupWhichAsksEverything() {
        var draft = server
        draft.hasConfiguration = false
        draft.essentials = false
        let add = MachinePlan.steps(for: draft).first
        XCTAssertEqual(add?.arguments, ["setup", "--no-essentials", "--yes"])
        XCTAssertEqual(add?.asksInTerminal, true)
        let answers = MachinePlan.terminalAnswers(for: draft)
        XCTAssertTrue(answers.contains(MachinePlan.Answer(question: "domain", answer: "your domain, or leave it empty")))
        XCTAssertTrue(answers.contains(MachinePlan.Answer(
            question: "trust the fingerprint", answer: "yes, only if it shows \(fingerprint)")))
    }

    func testChosenPackagesAndAWorkspaceComeBeforeTheSync() {
        var draft = server
        draft.packages = ["docker", "tailscale"]
        draft.workspace = "acme"
        XCTAssertEqual(MachinePlan.steps(for: draft).dropFirst().map(\.arguments), [
            ["packages", "add", "docker", "--machine", "main", "--yes"],
            ["packages", "add", "tailscale", "--machine", "main", "--yes"],
            ["workspaces", "new", "acme", "--machine", "main", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
    }

    func testTheSyncCanBeLeftForLater() {
        var draft = server
        draft.sync = false
        XCTAssertEqual(MachinePlan.steps(for: draft).map(\.kind), [.addMachine])
    }

    func testTheReviewShowsEachCommandAsItWouldBeTyped() {
        var draft = server
        draft.keyFile = "/Users/alice/My Keys/id"
        XCTAssertEqual(
            MachinePlan.steps(for: draft).first?.displayLine,
            "devmachine machines add --name main --address 203.0.113.10 --fingerprint \(fingerprint) "
                + "--key '/Users/alice/My Keys/id' --yes")
    }

    func testTheAnswersForTheCLIsQuestionsNameWhatTheWizardWasTold() {
        var local = MachineDraft()
        local.kind = .localVM
        local.name = "lab"
        let answers = MachinePlan.terminalAnswers(for: local)
        XCTAssertEqual(answers.first, MachinePlan.Answer(question: "machine name", answer: "lab"))
        XCTAssertTrue(answers.contains(MachinePlan.Answer(question: "address", answer: "127.0.0.1")))
        XCTAssertTrue(answers.contains(MachinePlan.Answer(question: "password", answer: "devmachine")))

        var password = server
        password.login = .password
        XCTAssertTrue(MachinePlan.terminalAnswers(for: password)
            .contains(MachinePlan.Answer(question: "address", answer: "203.0.113.10")))
        XCTAssertEqual(MachinePlan.terminalAnswers(for: server), [])
    }

    func testTheScriptShowsTheCommandRunsItAndPrintsItsMarker() {
        let step = MachinePlan.steps(for: server)[0]
        let script = TerminalStepMarker.script(
            executable: "/opt/homebrew/bin/devmachine", step: step, nonce: "abc123")
        let lines = script.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "printf '%s\\n' " + FileUpload.singleQuoted("$ " + step.displayLine))
        XCTAssertTrue(lines[1].hasPrefix("/opt/homebrew/bin/devmachine machines add --name main"))
        XCTAssertEqual(lines[3], #"printf '__DM_%s_%s__\n' abc123 "$r""#)
        XCTAssertFalse(script.contains(TerminalStepMarker.ok(nonce: "abc123")))
    }

    func testOnlyTheScriptPathIsTyped() {
        XCTAssertEqual(TerminalStepMarker.typedLine(scriptPath: "/tmp/dm steps/1.sh"), "sh '/tmp/dm steps/1.sh'")
    }

    func testTheOutcomeIsTheMarkerThatShowedUp() {
        XCTAssertNil(TerminalStepMarker.outcome(okSeen: false, failSeen: false))
        XCTAssertEqual(TerminalStepMarker.outcome(okSeen: true, failSeen: false), true)
        XCTAssertEqual(TerminalStepMarker.outcome(okSeen: false, failSeen: true), false)
    }
}
