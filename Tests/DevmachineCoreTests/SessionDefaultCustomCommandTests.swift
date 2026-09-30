import XCTest
@testable import DevmachineCore

final class SessionDefaultCustomCommandTests: XCTestCase {
    private func makeSettings(
        local: SessionLaunchChoice = .terminal,
        remote: SessionLaunchChoice = .terminal,
        workspaces: [String: SessionLaunchChoice] = [:]
    ) -> AppSettings {
        AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "devmachine",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.claude, .codex],
            localSessionProgram: local,
            remoteSessionProgram: remote,
            workspaceSessionPrograms: workspaces
        )
    }

    private func roundTrip(_ settings: AppSettings) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    }

    func testCustomDefaultsSurviveEncodingForThisMacFallbackAndWorkspace() throws {
        let settings = makeSettings(
            local: .custom("htop"),
            remote: .custom("npm run dev"),
            workspaces: ["acme-devmachine": .custom("claude --model opus --dangerously-skip-permissions")])

        let decoded = try roundTrip(settings)

        XCTAssertEqual(decoded.localSessionProgram, .custom("htop"))
        XCTAssertEqual(decoded.remoteSessionProgram, .custom("npm run dev"))
        XCTAssertEqual(
            decoded.sessionProgram(for: "acme-devmachine"),
            .custom("claude --model opus --dangerously-skip-permissions"))
    }

    func testWorkspaceWithoutOverrideInheritsTheFallbackCustomCommand() throws {
        let settings = try roundTrip(makeSettings(
            remote: .custom("npm run dev"),
            workspaces: ["beta-devmachine": .harness(.codex)]))

        XCTAssertEqual(settings.sessionProgram(for: "acme-devmachine"), .custom("npm run dev"))
        XCTAssertEqual(settings.sessionProgram(for: "beta-devmachine"), .harness(.codex))
    }

    func testEmptyCustomCommandBehavesAsTerminal() {
        let settings = makeSettings(
            local: .custom(""),
            remote: .custom("   "),
            workspaces: ["acme-devmachine": .custom("\n\t")])

        XCTAssertEqual(settings.localSessionProgram, .terminal)
        XCTAssertEqual(settings.remoteSessionProgram, .terminal)
        XCTAssertEqual(settings.sessionProgram(for: "acme-devmachine"), .terminal)
    }

    func testCustomCommandIsStoredTrimmedWithItsSymbolsIntact() {
        let raw = #"  echo "$HOME"; `date` && ls '*'  "#
        let settings = makeSettings(remote: .custom(raw))

        XCTAssertEqual(settings.remoteSessionProgram, .custom(#"echo "$HOME"; `date` && ls '*'"#))
    }

    func testDisablingEveryHarnessLeavesCustomDefaultsAlone() {
        var settings = makeSettings(
            local: .custom("htop"),
            workspaces: ["acme-devmachine": .custom("npm run dev")])

        settings.enabledHarnesses = []

        XCTAssertEqual(settings.localSessionProgram, .custom("htop"))
        XCTAssertEqual(settings.sessionProgram(for: "acme-devmachine"), .custom("npm run dev"))
    }

    func testSettingsSavedBeforeCustomCommandsStillDecode() throws {
        let saved = #"""
        {"opsRepoPath":"/tmp","hostAlias":"h","publicIP":"203.0.113.10","baseDomain":"example.com",
         "enabledHarnesses":["claude","codex"],
         "localSessionProgram":{"terminal":{}},
         "remoteSessionProgram":{"harness":{"_0":"claude"}},
         "workspaceSessionPrograms":{"acme-devmachine":{"harness":{"_0":"codex"}}}}
        """#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))

        XCTAssertEqual(settings.localSessionProgram, .terminal)
        XCTAssertEqual(settings.remoteSessionProgram, .harness(.claude))
        XCTAssertEqual(settings.sessionProgram(for: "acme-devmachine"), .harness(.codex))
    }

    func testTheExistingEncodingOfTerminalAndHarnessDoesNotChange() throws {
        let data = try JSONEncoder().encode([SessionLaunchChoice.terminal, .harness(.claude)])
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertEqual(decoded?.first?.keys.first, "terminal")
        XCTAssertEqual((decoded?.last?["harness"] as? [String: String])?["_0"], "claude")
    }
}
