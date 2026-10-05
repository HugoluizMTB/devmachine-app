import XCTest
@testable import DevmachineCore

private let goodSettings = AppSettings(
    opsRepoPath: "/Users/alice/.config/devmachine",
    hostAlias: "devmachine",
    publicIP: "203.0.113.7",
    baseDomain: "example.com"
)

private func existing(_ paths: String...) -> (String) -> Bool {
    let set = Set(paths)
    return { set.contains($0) }
}

private func fullRepo() -> (String) -> Bool {
    existing("/Users/alice/.config/devmachine", "/Users/alice/.config/devmachine/config.yml")
}

final class AppSettingsTests: XCTestCase {
    func testWorkspaceSuffixIsDashPlusAlias() {
        XCTAssertEqual(goodSettings.workspaceSuffix, "-devmachine")
    }

    func testWorkspaceSuffixFallsBackToDevmachineWhenAliasIsEmpty() {
        var settings = goodSettings
        settings.hostAlias = ""
        XCTAssertEqual(settings.workspaceSuffix, "-devmachine")
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

    func testValidateAcceptsEmptyAlias() {
        var settings = goodSettings
        settings.hostAlias = ""
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }

    func testValidateAcceptsAliasWithDotDashUnderscore() {
        var settings = goodSettings
        settings.hostAlias = "box-1_a.dev"
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }

    func testValidateRejectsBadDomain() {
        for bad in ["nodot", "Example.com", "exa mple.com", "example.com."] {
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

    func testValidateReportsEveryBadFieldAtOnceExceptTheOptionalOnes() {
        let fields = AppSettings.validate(AppSettings.empty, fileExists: existing()).map(\.field)
        XCTAssertEqual(fields, [.opsRepoPath])
    }

    func testWithoutAServerTheIPAndDomainStayEmpty() {
        var settings = goodSettings
        settings.publicIP = ""
        settings.baseDomain = ""
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }

    func testTheCLIsOwnFolderIsAcceptedBeforeItsFirstMachineWritesIt() {
        var settings = goodSettings
        settings.opsRepoPath = "/Users/alice/.config/devmachine"
        let nothing: (String) -> Bool = { _ in false }
        XCTAssertEqual(AppSettings.validate(settings, fileExists: nothing).map(\.field), [.opsRepoPath])
        XCTAssertTrue(AppSettings.validate(
            settings, fileExists: nothing, cliConfigDirectory: "/Users/alice/.config/devmachine").isEmpty)
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
        let dir = NSHomeDirectory() + "/.config/devmachine"
        let settings = AppSettings.prefill(
            sshConfig: "",
            sshResolve: { _ in nil },
            fileExists: { $0 == dir + "/config.yml" }
        )
        XCTAssertEqual(settings.opsRepoPath, dir)
    }

    func testPrefillIgnoresAConfigurationFolderWithNoConfiguration() {
        let dir = NSHomeDirectory() + "/.config/devmachine"
        let settings = AppSettings.prefill(
            sshConfig: "",
            sshResolve: { _ in nil },
            fileExists: { $0 == dir }
        )
        XCTAssertEqual(settings.opsRepoPath, "")
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
          "opsRepoPath": "/Users/alice/.config/devmachine",
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

    func testSshAgentSocketDefaultsToEmpty() {
        XCTAssertEqual(goodSettings.sshAgentSocket, "")
        XCTAssertEqual(AppSettings.empty.sshAgentSocket, "")
    }

    func testSshAgentSocketSurvivesARoundTrip() throws {
        var settings = goodSettings
        settings.sshAgentSocket = "/tmp/custom.sock"
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testSettingsSavedBeforeTheSshAgentSocketStillDecodeToEmpty() throws {
        let old = Data("""
        {
          "opsRepoPath": "/Users/alice/.config/devmachine",
          "hostAlias": "devmachine",
          "publicIP": "203.0.113.7",
          "baseDomain": "example.com"
        }
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).sshAgentSocket, "")
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

    func testAMissingFolderWithTheCLIInstalledSaysSetupHasNotRun() {
        let issues = AppSettings.validate(goodSettings, fileExists: existing())
        XCTAssertEqual(issues.map(\.field), [.opsRepoPath])
        XCTAssertEqual(issues.first?.remedy, .runSetup)
        XCTAssertTrue(issues.first?.message.contains("devmachine setup has not run yet") ?? false)
        XCTAssertFalse(issues.first?.message.contains("brew") ?? true)
    }

    func testAMissingConfigYmlWithTheCLIInstalledSaysSetupHasNotRun() {
        let issues = AppSettings.validate(
            goodSettings, fileExists: existing("/Users/alice/.config/devmachine"))
        XCTAssertEqual(issues.map(\.field), [.opsRepoPath])
        XCTAssertEqual(issues.first?.remedy, .runSetup)
        XCTAssertTrue(issues.first?.message.contains("config.yml") ?? false)
        XCTAssertTrue(issues.first?.message.contains("devmachine setup has not run yet") ?? false)
        XCTAssertFalse(issues.first?.message.contains("brew") ?? true)
    }

    func testAMissingCLIGivesTheInstallLineWithoutHomebrew() {
        let issues = AppSettings.validate(goodSettings, fileExists: fullRepo(), cliExecutableFound: false)
        XCTAssertEqual(issues.map(\.field), [.opsRepoPath])
        XCTAssertEqual(issues.first?.remedy, .installCLI)
        XCTAssertTrue(issues.first?.message.contains("not installed") ?? false)
        XCTAssertTrue(issues.first?.message.contains(
            "curl -fsSL https://mydevmachine.sh/install.sh | DEVMACHINE_NO_BREW=1 sh") ?? false)
        XCTAssertFalse(issues.first?.message.contains("brew install") ?? true)
    }

    func testAMissingCLIIsTheOneIssueEvenWhenTheFolderIsMissingToo() {
        let issues = AppSettings.validate(goodSettings, fileExists: existing(), cliExecutableFound: false)
        XCTAssertEqual(issues.map(\.remedy), [.installCLI])
    }

    func testTheCLIsOwnFolderStillNeedsTheCLIItself() {
        var settings = goodSettings
        settings.opsRepoPath = "/Users/alice/.config/devmachine"
        let issues = AppSettings.validate(
            settings, fileExists: existing(), cliExecutableFound: false,
            cliConfigDirectory: "/Users/alice/.config/devmachine")
        XCTAssertEqual(issues.map(\.remedy), [.installCLI])
    }

    func testAnotherFolderWithoutConfigYmlStillOffersTheSetup() {
        let issues = AppSettings.validate(
            goodSettings, fileExists: existing("/Users/alice/.config/devmachine"),
            cliConfigDirectory: "/Users/alice/.config/devmachine-other")
        XCTAssertEqual(issues.map(\.remedy), [.runSetup])
    }

    func testTheCLIsOwnFolderWithoutConfigYmlSaysNoMachineYetWithoutBlockingSave() {
        let folder = "/Users/alice/.config/devmachine"
        var settings = goodSettings
        settings.opsRepoPath = folder
        for fileExists in [existing(), existing(folder)] {
            XCTAssertTrue(AppSettings.validate(
                settings, fileExists: fileExists, cliConfigDirectory: folder).isEmpty)
            let notices = AppSettings.notices(settings, fileExists: fileExists, cliConfigDirectory: folder)
            XCTAssertEqual(notices.map(\.kind), [.noMachineYet])
            XCTAssertEqual(notices.first?.field, .opsRepoPath)
            XCTAssertTrue(notices.first?.message.contains("No machine yet") ?? false)
        }
    }

    func testAConfiguredFolderHasNoNotice() {
        XCTAssertTrue(AppSettings.notices(
            goodSettings, fileExists: fullRepo(), cliConfigDirectory: "/Users/alice/.config/devmachine").isEmpty)
    }

    func testNoMachineYetIsNotShownBesideABlockingIssue() {
        let folder = "/Users/alice/.config/devmachine"
        XCTAssertTrue(AppSettings.notices(
            goodSettings, fileExists: existing(), cliExecutableFound: false, cliConfigDirectory: folder).isEmpty)
        XCTAssertTrue(AppSettings.notices(
            goodSettings, fileExists: existing(), cliConfigDirectory: folder + "-other").isEmpty)
    }

    func testAnIssueTheAppCannotFixCarriesNoRemedy() {
        var settings = goodSettings
        settings.baseDomain = "Not A Domain"
        let issues = AppSettings.validate(settings, fileExists: fullRepo())
        XCTAssertEqual(issues.map(\.field), [.baseDomain])
        XCTAssertNil(issues.first?.remedy)
    }

    func testAStaleHostAliasOrPublicIPNeverBlocksSaving() {
        var settings = goodSettings
        settings.publicIP = "not an ip"
        settings.hostAlias = "bad alias!"
        XCTAssertTrue(AppSettings.validate(settings, fileExists: fullRepo()).isEmpty)
    }

    func testValidatePassesWhenTheCLIExecutableIsFound() {
        XCTAssertTrue(
            AppSettings.validate(goodSettings, fileExists: fullRepo(), cliExecutableFound: true).isEmpty)
    }

    func testValidateRejectsTheOldAnsibleRepository() {
        var settings = goodSettings
        settings.opsRepoPath = "/Users/alice/dev/devmachine"
        let old = existing("/Users/alice/dev/devmachine", "/Users/alice/dev/devmachine/ansible/site.yml")
        let issues = AppSettings.validate(settings, fileExists: old)
        XCTAssertEqual(issues.map(\.field), [.opsRepoPath])
        XCTAssertTrue(issues.first?.message.contains("config.yml") ?? false)
    }

    func testHostAliasUsesTheDetectedMapWhenPresent() {
        var settings = goodSettings
        settings.workspaceAliases = ["acme": "acme-devmachine"]
        XCTAssertEqual(settings.hostAlias(forWorkspace: "acme"), "acme-devmachine")
    }

    func testHostAliasFallsBackToTheGuessedSuffixWhenUndetected() {
        var settings = goodSettings
        settings.workspaceAliases = [:]
        XCTAssertEqual(settings.hostAlias(forWorkspace: "acme"), "acme" + settings.workspaceSuffix)
    }

    func testWorkspaceNameReversesTheDetectedMap() {
        var settings = goodSettings
        settings.workspaceAliases = ["acme": "acme-devmachine"]
        XCTAssertEqual(settings.workspaceName(forAlias: "acme-devmachine"), "acme")
    }

    func testWorkspaceNameFallsBackToStrippingTheGuessedSuffix() {
        var settings = goodSettings
        settings.workspaceAliases = [:]
        XCTAssertEqual(settings.workspaceName(forAlias: "acme" + settings.workspaceSuffix), "acme")
    }

    func testWorkspaceAliasesRoundTripThroughEncoding() throws {
        var settings = goodSettings
        settings.workspaceAliases = ["acme": "acme-devmachine"]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.workspaceAliases, ["acme": "acme-devmachine"])
    }

    func testSettingsSavedBeforeWorkspaceAliasesExistedDecodeToEmpty() throws {
        var values = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(goodSettings)) as! [String: Any]
        values.removeValue(forKey: "workspaceAliases")
        let data = try JSONSerialization.data(withJSONObject: values)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.workspaceAliases, [:])
    }
}

final class CopyOnSelectSettingTests: XCTestCase {
    func testCopyOnSelectIsOnByDefault() {
        XCTAssertTrue(goodSettings.copyOnSelect)
    }

    func testSettingsSavedBeforeItExistedCopyOnSelect() throws {
        let saved = #"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"devmachine","publicIP":"203.0.113.7","baseDomain":"example.com"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))
        XCTAssertTrue(decoded.copyOnSelect)
    }

    func testTurningItOffSurvivesASave() throws {
        var settings = goodSettings
        settings.copyOnSelect = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.copyOnSelect)
    }
}

final class HarnessIconSettingTests: XCTestCase {
    func testHarnessIconsAreOffByDefault() {
        XCTAssertFalse(goodSettings.showsHarnessIcons)
    }

    func testSettingsSavedBeforeItExistedKeepTheDot() throws {
        let saved = #"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"devmachine","publicIP":"203.0.113.7","baseDomain":"example.com","copyOnSelect":false}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))
        XCTAssertFalse(decoded.showsHarnessIcons)
        XCTAssertFalse(decoded.copyOnSelect)
    }

    func testTurningItOnSurvivesASave() throws {
        var settings = goodSettings
        settings.showsHarnessIcons = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.showsHarnessIcons)
    }

    func testTheInitializerTakesIt() {
        let settings = AppSettings(
            opsRepoPath: "/Users/alice/.config/devmachine", hostAlias: "devmachine",
            publicIP: "203.0.113.7", baseDomain: "example.com", showsHarnessIcons: true)
        XCTAssertTrue(settings.showsHarnessIcons)
    }
}

final class HarnessIconStyleSettingTests: XCTestCase {
    func testIconsKeepTheirBrandColorsByDefault() {
        XCTAssertEqual(goodSettings.harnessIconStyle, .color)
        XCTAssertEqual(AppSettings.empty.harnessIconStyle, .color)
    }

    func testSettingsSavedBeforeItExistedReadAsColor() throws {
        let saved = #"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"devmachine","publicIP":"203.0.113.7","baseDomain":"example.com","showsHarnessIcons":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))
        XCTAssertEqual(decoded.harnessIconStyle, .color)
        XCTAssertTrue(decoded.showsHarnessIcons)
    }

    func testAnUnknownStyleReadsAsColor() throws {
        let saved = #"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"devmachine","publicIP":"203.0.113.7","baseDomain":"example.com","harnessIconStyle":"neon"}"#
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8)).harnessIconStyle, .color)
    }

    func testMonochromeSurvivesASave() throws {
        var settings = goodSettings
        settings.harnessIconStyle = .monochrome
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.harnessIconStyle, .monochrome)
    }

    func testTheInitializerTakesIt() {
        let settings = AppSettings(
            opsRepoPath: "/Users/alice/.config/devmachine", hostAlias: "devmachine",
            publicIP: "203.0.113.7", baseDomain: "example.com", harnessIconStyle: .monochrome)
        XCTAssertEqual(settings.harnessIconStyle, .monochrome)
    }
}

final class AppSettingsLinkOpeningTests: XCTestCase {
    func testLinksOpenInTheDefaultBrowserByDefault() {
        XCTAssertEqual(AppSettings.empty.linkOpening, .defaultBrowser)
    }

    func testSettingsWrittenBeforeTheChoiceDecodeToTheDefaultBrowser() throws {
        let json = #"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"","publicIP":"203.0.113.10","baseDomain":"example.com"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.linkOpening, .defaultBrowser)
    }

    func testTheChoiceSurvivesARoundTrip() throws {
        var settings = AppSettings.empty
        settings.linkOpening = .inApp
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.linkOpening, .inApp)
    }
}
