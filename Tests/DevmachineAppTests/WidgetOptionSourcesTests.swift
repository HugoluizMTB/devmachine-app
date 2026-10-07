import XCTest
import DevmachineCore
import HarnessUsageKit
@testable import DevmachineApp

@MainActor
final class WidgetOptionSourcesTests: XCTestCase {
    func testEachSourceReadsItsOwnClosure() {
        let sources = WidgetOptionSources(
            machines: { [ChoiceOption(id: "main", label: "main")] },
            workspaces: { [ChoiceOption(id: "alice-dev", label: "alice-dev")] },
            harnesses: { [ChoiceOption(id: "claude", label: "Claude")] })
        XCTAssertEqual(sources.options(.machines).map(\.id), ["main"])
        XCTAssertEqual(sources.options(.workspaces).map(\.id), ["alice-dev"])
        XCTAssertEqual(sources.options(.harnesses).map(\.label), ["Claude"])
        XCTAssertEqual(WidgetOptionSources.none.options(.machines), [])
    }

    func testAHarnessTheContractDoesNotListIsNotOffered() {
        let sources = WidgetOptionSources(
            machines: { [] }, workspaces: { [] },
            harnesses: { ["claude", "pi", "codex"].map { ChoiceOption(id: $0, label: $0) } })
        XCTAssertEqual(sources.options(.harnesses).map(\.id), ["claude", "codex"])
    }

    func testHarnessOptionsComeFromTheUsageStatesInOrder() {
        let options = WidgetOptionSources.harnessOptions(
            states: [HarnessUsageState(harnessID: "codex"), HarnessUsageState(harnessID: "claude")],
            title: { $0 == "claude" ? "Claude" : nil })
        XCTAssertEqual(options, [ChoiceOption(id: "codex", label: "codex"), ChoiceOption(id: "claude", label: "Claude")])
    }
}
