import XCTest
import DevmachineCore
import HarnessUsageKit
@testable import DevmachineApp

private struct FakeLocator: ExecutableLocating {
    let available: Set<String>

    func executable(named name: String) -> URL? {
        available.contains(name) ? URL(fileURLWithPath: "/usr/local/bin/\(name)") : nil
    }
}

private final class CountingLocator: ExecutableLocating, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func executable(named name: String) -> URL? {
        lock.lock()
        calls += 1
        lock.unlock()
        return nil
    }
}

final class HarnessSettingsFacadeTests: XCTestCase {
    private let registry = HarnessRegistry.builtIn

    private func makeSettings(enabledHarnesses: [HarnessID] = [.claude]) -> AppSettings {
        AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "example-host",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: enabledHarnesses
        )
    }

    func testAHarnessWithoutItsCLIOnThisMacIsStillTurnedOn() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: ["claude"]))
        var settings = makeSettings()

        let result = facade.enable(.opencode, in: &settings)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(settings.enabledHarnesses, [.claude, .opencode])
        XCTAssertFalse(facade.isOnThisMac(.opencode))
        XCTAssertTrue(facade.isOnThisMac(.claude))
    }

    func testAHarnessWithoutItsCLIIsOfferedForRemoteWorkspacesOnly() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: ["claude"]))
        let settings = makeSettings(enabledHarnesses: [.claude, .opencode])

        XCTAssertEqual(
            facade.launchOptions(for: settings, on: .remote).map(\.choice),
            [.terminal, .harness(.claude), .harness(.opencode)])
        XCTAssertEqual(
            facade.launchOptions(for: settings, on: .thisMac).map(\.choice),
            [.terminal, .harness(.claude)])
    }

    func testOnlyAnEnabledHarnessWithoutItsCLIGetsTheRemoteOnlyNote() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: ["claude"]))
        let settings = makeSettings(enabledHarnesses: [.claude, .opencode])

        XCTAssertEqual(facade.remoteOnlyNote(for: .opencode, in: settings), "Not on this Mac — remote workspaces only")
        XCTAssertNil(facade.remoteOnlyNote(for: .claude, in: settings))
        XCTAssertNil(facade.remoteOnlyNote(for: .kimi, in: settings))
    }

    func testALocalDefaultWithoutItsCLIStartsAPlainShell() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: ["claude"]))
        var settings = makeSettings(enabledHarnesses: [.claude, .opencode])
        settings.localSessionProgram = .harness(.opencode)
        settings.remoteSessionProgram = .harness(.opencode)

        XCTAssertEqual(settings.localSessionProgram, .harness(.opencode))
        XCTAssertEqual(facade.localSessionProgram(for: settings), .terminal)
        XCTAssertNil(facade.startupCommand(for: facade.localSessionProgram(for: settings)))
        XCTAssertEqual(facade.startupCommand(for: settings.sessionProgram(for: "acme-devmachine")), "opencode")

        settings.localSessionProgram = .harness(.claude)
        XCTAssertEqual(facade.localSessionProgram(for: settings), .harness(.claude))
        settings.localSessionProgram = .custom("npm run dev")
        XCTAssertEqual(facade.localSessionProgram(for: settings), .custom("npm run dev"))
    }

    func testTheCLIIsLookedUpOnceUntilEveryCLIIsLookedUpAgain() {
        let locator = CountingLocator()
        let facade = HarnessSettingsFacade(registry: registry, locator: locator)

        _ = facade.isOnThisMac(.opencode)
        _ = facade.isOnThisMac(.opencode)
        XCTAssertEqual(locator.count, 1)
        facade.refreshAvailability()
        XCTAssertEqual(locator.count, 1 + registry.adapters.count)
        _ = facade.isOnThisMac(.opencode)
        XCTAssertEqual(locator.count, 1 + registry.adapters.count)
    }

    func testAvailableCLIIsEnabled() {
        let facade = HarnessSettingsFacade(
            registry: registry,
            locator: FakeLocator(available: ["codex"])
        )
        var settings = makeSettings()

        let result = facade.enable(.codex, in: &settings)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(settings.enabledHarnesses, [.claude, .codex])
    }

    func testLaunchOptionsContainTerminalAndOnlyEnabledDescriptors() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))

        let options = facade.launchOptions(for: makeSettings(enabledHarnesses: [.codex]), on: .remote)

        XCTAssertEqual(options.map(\.choice), [.terminal, .harness(.codex)])
        XCTAssertEqual(options.map(\.title), ["Terminal", "OpenAI Codex"])
        XCTAssertEqual(options.last?.descriptor?.id, .codex)
    }

    func testEnabledHarnessWhoseCLIIsMissingStillShowsUsage() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))

        let registrations = facade.usageRegistrations(for: makeSettings(enabledHarnesses: [.claude, .codex]))

        XCTAssertEqual(registrations.map(\.id), [.claude, .codex])
    }

    func testMissingCodexCLIReportsCLINotFoundInsteadOfVanishing() throws {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))
        let codex = try XCTUnwrap(
            facade.usageRegistrations(for: makeSettings(enabledHarnesses: [.codex])).first)

        XCTAssertThrowsError(try codex.provider.fetchSnapshot(previous: nil)) { error in
            XCTAssertEqual(HarnessUsageErrorKind(error: error), .cliNotFound)
        }
    }

    func testDisabledHarnessHasNoUsage() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: ["codex"]))

        XCTAssertEqual(facade.usageRegistrations(for: makeSettings(enabledHarnesses: [.claude])).map(\.id), [.claude])
    }

    func testCustomDefaultStartsWithItsCommandVerbatim() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))
        let typed = #"claude --model opus -p "fix it" && echo '$HOME'; `date`"#

        XCTAssertEqual(facade.startupCommand(for: .custom(typed)), typed)
    }

    func testEmptyCustomDefaultStartsAPlainShell() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))

        XCTAssertNil(facade.startupCommand(for: .custom("   ")))
    }
}
