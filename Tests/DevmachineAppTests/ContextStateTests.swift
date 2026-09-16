import SwiftUI
import XCTest
@testable import DevmachineApp
import DevmachineCore

final class ContextStateTests: XCTestCase {
    func testDecodesSample() throws {
        let json = """
        {"cwd":"/home/acme/dev/dash","isClaude":true,"updatedAt":"2026-09-12T10:00:00Z",
         "plan":{"title":"panel","source":"superpowers","done":6,"total":10,
                 "items":[{"text":"SessionStore + runner","state":"done"},
                          {"text":"inference engine","state":"active"},
                          {"text":"right panel","state":"pending"}]},
         "prs":[{"number":4242,"repo":"acme/dash","title":"","url":"https://github.com/acme/dash/pull/4242",
                 "ci":"pass","review":"approved","state":"open"}],
         "links":[{"url":"https://linear.app/x/issue/LIN-1234","label":"LIN-1234 next tasks","kind":"linear"},
                   {"url":"https://github.com/acme/dash/pull/4240","label":"github.com/acme/dash/pull/4240","kind":"web"}]}
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ContextState.self, from: json)

        XCTAssertTrue(state.isClaude)
        XCTAssertEqual(state.plan?.done, 6)
        XCTAssertEqual(state.plan?.items.count, 3)
        XCTAssertEqual(state.plan?.items.first?.state, "done")
        XCTAssertEqual(state.prs.first?.number, 4242)
        XCTAssertEqual(state.links.first?.kind, "linear")
    }

    func testDecodesWithoutPlan() throws {
        let json = """
        {"cwd":"/home/dev","isClaude":false,"updatedAt":"2026-09-12T10:00:00Z",
         "plan":null,"prs":[],"links":[]}
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ContextState.self, from: json)

        XCTAssertNil(state.plan)
        XCTAssertFalse(state.isClaude)
    }

    func testPRIdentityKeepsRepositoriesApart() {
        let dash = ContextState.PR(
            number: 11062, repo: "acme/dash", title: "", url: "",
            ci: "none", review: "none", state: "open")
        let engineering = ContextState.PR(
            number: 11062, repo: "acme/engineering", title: "", url: "",
            ci: "none", review: "none", state: "open")
        XCTAssertNotEqual(dash.id, engineering.id)
        XCTAssertEqual(dash.id, "acme/dash#11062")
    }

    func testPRStateMapsToRowState() {
        func make(_ state: String, _ review: String, _ ci: String) -> ContextState.PR {
            ContextState.PR(number: 1, repo: "acme/dash", title: "t", url: "u",
                            ci: ci, review: review, state: state)
        }
        XCTAssertEqual(make("merged", "approved", "pass").rowState, .merged)
        XCTAssertEqual(make("closed", "none", "none").rowState, .closed)
        XCTAssertEqual(make("draft", "approved", "pending").rowState, .draft)
        XCTAssertEqual(make("open", "changes", "fail").rowState, .changesRequested)
        XCTAssertEqual(make("open", "none", "pending").rowState, .open)
        XCTAssertEqual(make("open", "none", "pending").ciState, .pending)
        XCTAssertEqual(make("open", "none", "pass").ciState, .success)
    }

    func testDecodesThreadCount() throws {
        let json = """
        {"cwd":"/home/dev","isClaude":true,"updatedAt":"2026-09-12T10:00:00Z",
         "plan":null,"links":[],
         "prs":[{"number":7,"repo":"acme/dash","title":"t","url":"u",
                 "ci":"pass","review":"changes","state":"open","threads":3}]}
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ContextState.self, from: json)

        XCTAssertEqual(state.prs.first?.threads, 3)
    }

    func testThreadCountIsOptional() throws {
        let json = """
        {"cwd":"/home/dev","isClaude":true,"updatedAt":"2026-09-12T10:00:00Z",
         "plan":null,"links":[],
         "prs":[{"number":7,"repo":"acme/dash","title":"t","url":"u",
                 "ci":"pass","review":"none","state":"open"}]}
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ContextState.self, from: json)

        XCTAssertNil(state.prs.first?.threads)
    }

    func testDecodesMonitorsAndShells() throws {
        let json = """
        {"cwd":"/home/dev","isClaude":true,"updatedAt":"2026-09-12T10:00:00Z",
         "plan":null,"prs":[],"links":[],
         "agents":[{"label":"Audit ship readiness","status":"running"}],
         "monitors":[{"label":"CI for PR 4982","status":"running"}],
         "shells":[{"label":"Deploy the thing","status":"running"}]}
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ContextState.self, from: json)

        XCTAssertEqual(state.monitors.map(\.label), ["CI for PR 4982"])
        XCTAssertEqual(state.shells.map(\.label), ["Deploy the thing"])
        XCTAssertEqual(state.agents.map(\.label), ["Audit ship readiness"])
    }

    /// An older engine on the VPS does not send the new keys; the panel still loads.
    func testDecodesWithoutMonitorsAndShells() throws {
        let json = """
        {"cwd":"/home/dev","isClaude":true,"updatedAt":"2026-09-12T10:00:00Z",
         "plan":null,"prs":[],"links":[],"agents":[]}
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ContextState.self, from: json)

        XCTAssertEqual(state.monitors, [])
        XCTAssertEqual(state.shells, [])
    }

    func testTagColourIsStablePerName() {
        XCTAssertEqual(Color.dmTag("linear"), Color.dmTag("linear"))
        XCTAssertNotEqual(Color.dmTag("linear"), Color.dmTag("atlassian"))
        XCTAssertNotEqual(Color.dmTag("github"), Color.dmTag("openai"))
    }
}

final class RunningStatusTests: XCTestCase {
    func testTheEngineWordDecidesTheIcon() {
        XCTAssertEqual(RunningStatus("running"), .running)
        XCTAssertEqual(RunningStatus("done"), .done)
        XCTAssertEqual(RunningStatus("completed"), .done)
        XCTAssertEqual(RunningStatus("failed"), .failed)
        XCTAssertEqual(RunningStatus("killed"), .failed)
    }

    func testAnUnknownWordKeepsTheRowSpinning() {
        XCTAssertEqual(RunningStatus(""), .running)
        XCTAssertEqual(RunningStatus("whatever"), .running)
    }
}
