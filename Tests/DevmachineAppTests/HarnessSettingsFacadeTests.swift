import XCTest
import DevmachineCore
@testable import DevmachineApp

private struct FakeLocator: ExecutableLocating {
    let available: Set<String>

    func executable(named name: String) -> URL? {
        available.contains(name) ? URL(fileURLWithPath: "/usr/local/bin/\(name)") : nil
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

    func testMissingCLIIsNotEnabled() {
        let facade = HarnessSettingsFacade(registry: registry, locator: FakeLocator(available: []))
        var settings = makeSettings()

        let result = facade.enable(.codex, in: &settings)

        XCTAssertEqual(result, .failure(.cliNotFound("OpenAI Codex")))
        XCTAssertFalse(settings.enabledHarnesses.contains(.codex))
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

        let options = facade.launchOptions(for: makeSettings(enabledHarnesses: [.codex]))

        XCTAssertEqual(options.map(\.choice), [.terminal, .harness(.codex)])
        XCTAssertEqual(options.map(\.title), ["Terminal", "OpenAI Codex"])
        XCTAssertEqual(options.last?.descriptor?.id, .codex)
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
