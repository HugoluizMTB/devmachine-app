import XCTest
@testable import DevmachineCore

final class OperatorLaunchTests: XCTestCase {
    func testTheFirstOpenOffersEveryInstalledHarnessInOrder() {
        XCTAssertEqual(
            OperatorLaunch.plan(isRunning: false, saved: nil, installed: [.claude, .codex, .pi]),
            .choose([.claude, .codex, .pi]))
    }

    func testWithNoHarnessInstalledItOpensTheTerminalWithoutAsking() {
        XCTAssertEqual(OperatorLaunch.plan(isRunning: false, saved: nil, installed: []), .start(.terminal))
    }

    func testAChoiceAlreadyMadeStartsStraightAway() {
        XCTAssertEqual(
            OperatorLaunch.plan(isRunning: false, saved: .harness(.codex), installed: [.claude, .codex]),
            .start(.harness(.codex)))
        XCTAssertEqual(
            OperatorLaunch.plan(isRunning: false, saved: .terminal, installed: [.claude]), .start(.terminal))
    }

    func testARunningSessionIsShownAndNothingIsTyped() {
        XCTAssertEqual(OperatorLaunch.plan(isRunning: true, saved: nil, installed: [.claude]), .attach)
        XCTAssertEqual(OperatorLaunch.plan(isRunning: true, saved: .harness(.claude), installed: [.claude]), .attach)
    }
}

final class AppSettingsOperatorTests: XCTestCase {
    private let legacy = #"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"","publicIP":"203.0.113.10","baseDomain":"example.com"}"#

    func testSettingsWrittenBeforeTheOperatorChoiceDecodeAsNotChosen() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertNil(settings.operatorProgram)
    }

    func testANewSettingsValueHasTheOperatorNotChosen() {
        XCTAssertNil(AppSettings.empty.operatorProgram)
    }

    func testTheOperatorChoiceSurvivesARoundTrip() throws {
        var settings = AppSettings.empty
        settings.operatorProgram = .harness(.codex)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.operatorProgram, .harness(.codex))
    }

    func testTerminalOnlyIsAChoiceToo() throws {
        var settings = AppSettings.empty
        settings.operatorProgram = .terminal
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.operatorProgram, .terminal)
    }

    func testAHarnessNotTurnedOnIsKeptAsTheOperatorChoice() {
        var settings = AppSettings.empty
        settings.enabledHarnesses = [.claude]
        settings.operatorProgram = .harness(.pi)
        settings.enabledHarnesses = []
        XCTAssertEqual(settings.operatorProgram, .harness(.pi))
    }
}
