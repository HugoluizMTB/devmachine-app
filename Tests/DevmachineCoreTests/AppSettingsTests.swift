import XCTest
@testable import DevmachineCore

private let goodSettings = AppSettings(
    opsRepoPath: "/Users/alice/dev/devmachine",
    hostAlias: "devmachine",
    publicIP: "203.0.113.7",
    baseDomain: "example.com"
)

private func existing(_ paths: String...) -> (String) -> Bool {
    let set = Set(paths)
    return { set.contains($0) }
}

private func fullRepo() -> (String) -> Bool {
    existing("/Users/alice/dev/devmachine", "/Users/alice/dev/devmachine/ansible/site.yml")
}

final class AppSettingsTests: XCTestCase {
    func testWorkspaceSuffixIsDashPlusAlias() {
        XCTAssertEqual(goodSettings.workspaceSuffix, "-devmachine")
    }

    func testValidateAcceptsCompleteSettings() {
        XCTAssertTrue(AppSettings.validate(goodSettings, fileExists: fullRepo()).isEmpty)
    }

    func testValidateRejectsEmptyRepoPath() {
        var settings = goodSettings
        settings.opsRepoPath = ""
        let fields = AppSettings.validate(settings, fileExists: fullRepo()).map(\.field)
        XCTAssertEqual(fields, [.opsRepoPath])
    }

    func testValidateRejectsMissingRepoFolder() {
        let fields = AppSettings.validate(goodSettings, fileExists: existing()).map(\.field)
        XCTAssertEqual(fields, [.opsRepoPath])
    }

    func testValidateRejectsFolderWithoutAnsibleSiteYml() {
        let fields = AppSettings.validate(goodSettings, fileExists: existing("/Users/alice/dev/devmachine")).map(\.field)
        XCTAssertEqual(fields, [.opsRepoPath])
    }

    func testValidateRejectsEmptyAlias() {
        var settings = goodSettings
        settings.hostAlias = ""
        let fields = AppSettings.validate(settings, fileExists: fullRepo()).map(\.field)
        XCTAssertEqual(fields, [.hostAlias])
    }

    func testValidateRejectsAliasWithSpace() {
        var settings = goodSettings
        settings.hostAlias = "my host"
        let fields = AppSettings.validate(settings, fileExists: fullRepo()).map(\.field)
        XCTAssertEqual(fields, [.hostAlias])
    }

    func testValidateAcceptsAliasWithDotDashUnderscore() {
        var settings = goodSettings
        settings.hostAlias = "box-1_a.dev"
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }

    func testValidateRejectsNonIPv4() {
        for bad in ["", "1.2.3", "256.1.1.1", "1.2.3.4.5", "abc", "1.2.3.4 "] {
            var settings = goodSettings
            settings.publicIP = bad
            let fields = AppSettings.validate(settings, fileExists: fullRepo()).map(\.field)
            XCTAssertEqual(fields, [.publicIP], "expected \(bad) to be rejected")
        }
    }

    func testValidateRejectsBadDomain() {
        for bad in ["", "nodot", "Example.com", "exa mple.com", "example.com."] {
            var settings = goodSettings
            settings.baseDomain = bad
            let fields = AppSettings.validate(settings, fileExists: fullRepo()).map(\.field)
            XCTAssertEqual(fields, [.baseDomain], "expected \(bad) to be rejected")
        }
    }

    func testValidateAcceptsDeepDomain() {
        var settings = goodSettings
        settings.baseDomain = "apps.example.co.uk"
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }

    func testValidateReportsEveryBadFieldAtOnce() {
        let fields = AppSettings.validate(AppSettings.empty, fileExists: existing()).map(\.field)
        XCTAssertEqual(fields, [.opsRepoPath, .hostAlias, .publicIP, .baseDomain])
    }

    func testPrefillProposesAliasAndPublicIPFromPubHost() {
        let config = """
        Host devmachine
            HostName 100.64.0.1

        Host acme-devmachine
            User acme
        """
        var asked: [String] = []
        let settings = AppSettings.prefill(
            sshConfig: config,
            sshResolve: { alias in
                asked.append(alias)
                return alias == "devmachine-pub" ? "203.0.113.7" : "100.64.0.1"
            },
            fileExists: { _ in false }
        )

        XCTAssertEqual(settings.hostAlias, "devmachine")
        XCTAssertEqual(settings.publicIP, "203.0.113.7")
        XCTAssertEqual(asked, ["devmachine-pub"])
        XCTAssertEqual(settings.baseDomain, "")
        XCTAssertEqual(settings.opsRepoPath, "")
    }

    func testPrefillFallsBackToTheBaseAliasWhenPubIsNotAnAddress() {
        let settings = AppSettings.prefill(
            sshConfig: "Host devmachine\n",
            sshResolve: { alias in alias == "devmachine-pub" ? "devmachine-pub" : "100.64.0.1" },
            fileExists: { _ in false }
        )
        XCTAssertEqual(settings.publicIP, "100.64.0.1")
    }

    func testPrefillLeavesIPEmptyWhenNothingResolves() {
        let settings = AppSettings.prefill(
            sshConfig: "Host devmachine\n",
            sshResolve: { _ in nil },
            fileExists: { _ in false }
        )
        XCTAssertEqual(settings.publicIP, "")
    }

    func testPrefillProposesNoAliasWithoutAHostDevmachineEntry() {
        let settings = AppSettings.prefill(
            sshConfig: "Host other\n    HostName 10.0.0.1\n",
            sshResolve: { _ in "203.0.113.7" },
            fileExists: { _ in false }
        )
        XCTAssertEqual(settings.hostAlias, "")
        XCTAssertEqual(settings.publicIP, "")
    }

    func testPrefillProposesTheOpsRepoWhenItExists() {
        let repo = NSHomeDirectory() + "/dev/devmachine"
        let settings = AppSettings.prefill(
            sshConfig: "",
            sshResolve: { _ in nil },
            fileExists: { $0 == repo }
        )
        XCTAssertEqual(settings.opsRepoPath, repo)
    }

    func testNewSettingsStartOnTheBundledWallpaper() {
        XCTAssertEqual(AppSettings.empty.wallpaper, .bundled)
        XCTAssertEqual(goodSettings.wallpaper, .bundled)
        XCTAssertEqual(
            AppSettings.prefill(sshConfig: "", sshResolve: { _ in nil }, fileExists: { _ in false }).wallpaper,
            .bundled
        )
    }

    func testWallpaperSurvivesARoundTrip() throws {
        var settings = goodSettings
        settings.wallpaper = .unsplash(id: "aaa111")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testSettingsSavedBeforeWallpapersStillDecode() throws {
        let old = Data("""
        {
          "opsRepoPath": "/Users/alice/dev/devmachine",
          "hostAlias": "devmachine",
          "publicIP": "203.0.113.7",
          "baseDomain": "example.com"
        }
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old), goodSettings)
    }

    func testValidateIgnoresTheWallpaper() {
        var settings = goodSettings
        settings.wallpaper = .gradient(name: "midnight")
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }
}

final class NewSessionProgramTests: XCTestCase {
    func testAPlainTerminalTypesNothing() {
        XCTAssertNil(NewSessionProgram.shell.startupLine)
        XCTAssertEqual(NewSessionProgram.shell.title, "Normal terminal")
    }

    func testTheAgentIsTypedIntoTheShell() {
        XCTAssertEqual(NewSessionProgram.claude.startupLine, "claude")
        XCTAssertEqual(NewSessionProgram.claude.title, "Claude Code session")
    }

    func testTheSettingDefaultsToAPlainTerminal() throws {
        let json = #"{"opsRepoPath":"/tmp","hostAlias":"h","publicIP":"203.0.113.10","baseDomain":"example.com"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.newSessionProgram, .shell)
    }

    func testTheChoiceSurvivesAWriteAndARead() throws {
        let settings = AppSettings(
            opsRepoPath: "/tmp", hostAlias: "h", publicIP: "203.0.113.10",
            baseDomain: "example.com", newSessionProgram: .claude)
        let round = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.newSessionProgram, .claude)
    }

    func testBothChoicesAreOffered() {
        XCTAssertEqual(NewSessionProgram.allCases, [.shell, .claude])
    }
}

extension AppSettingsTests {
    func testEnabledHarnessesRoundTripWithoutLegacyProgram() throws {
        let settings = AppSettings(
            opsRepoPath: "/tmp",
            hostAlias: "h",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.claude, .codex]
        )

        let data = try JSONEncoder().encode(settings)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).enabledHarnesses, [.claude, .codex])
        XCTAssertNil(payload["newSessionProgram"])
    }

    func testLocalAndWorkspaceSessionProgramsAreIndependent() {
        let settings = AppSettings(
            opsRepoPath: "/tmp",
            hostAlias: "h",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.claude, .codex],
            localSessionProgram: .harness(.codex),
            remoteSessionProgram: .terminal,
            workspaceSessionPrograms: ["acme": .harness(.claude)]
        )

        XCTAssertEqual(settings.localSessionProgram, .harness(.codex))
        XCTAssertEqual(settings.sessionProgram(for: "acme"), .harness(.claude))
    }

    func testWorkspaceWithoutOverrideUsesRemoteSessionProgram() {
        let settings = AppSettings(
            opsRepoPath: "/tmp",
            hostAlias: "h",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.codex],
            remoteSessionProgram: .harness(.codex)
        )

        XCTAssertEqual(settings.sessionProgram(for: "beta"), .harness(.codex))
    }

    func testDisablingHarnessNormalizesSessionProgramsToTerminal() {
        var settings = AppSettings(
            opsRepoPath: "/tmp",
            hostAlias: "h",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.claude, .codex],
            localSessionProgram: .harness(.claude),
            remoteSessionProgram: .harness(.codex),
            workspaceSessionPrograms: ["acme": .harness(.claude)]
        )

        settings.enabledHarnesses = []

        XCTAssertEqual(settings.localSessionProgram, .terminal)
        XCTAssertEqual(settings.remoteSessionProgram, .terminal)
        XCTAssertEqual(settings.workspaceSessionPrograms, ["acme": .terminal])
    }

    func testLegacyClaudeProgramMigratesToHarnessSettings() throws {
        let data = Data(#"{"opsRepoPath":"/tmp","hostAlias":"h","publicIP":"203.0.113.10","baseDomain":"example.com","newSessionProgram":"claude"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.enabledHarnesses, [.claude])
        XCTAssertEqual(settings.localSessionProgram, .harness(.claude))
        XCTAssertEqual(settings.remoteSessionProgram, .harness(.claude))
    }
}
