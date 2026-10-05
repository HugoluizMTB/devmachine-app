import XCTest
import DevmachineCore
@testable import DevmachineApp

private let shipped = WallpaperPhoto(
    id: "aaa111", user: "alice", name: "Alice Stone", cdn: "photo-1", bundled: true
)
private let remote = WallpaperPhoto(id: "ccc333", user: "carol", name: "Carol Vine", cdn: "photo-3")

private let library = WallpaperLibrary(themes: [
    WallpaperTheme(id: "ocean", title: "Ocean", photos: [shipped]),
    WallpaperTheme(id: "space", title: "Space", photos: [remote])
])

private struct SetupPageLocator: ExecutableLocating {
    let available: Set<String>

    func executable(named name: String) -> URL? {
        available.contains(name) ? URL(fileURLWithPath: "/usr/local/bin/\(name)") : nil
    }
}

final class SetupPageTests: XCTestCase {
    func testThePackagesAndWorkspacesSectionsHaveNoSaveFooter() {
        XCTAssertFalse(SetupPage.showsFooter(for: .packages))
        XCTAssertFalse(SetupPage.showsFooter(for: .workspaces), "its switches save at once, its flows have buttons")
        XCTAssertTrue(SetupPage.showsFooter(for: .general))
    }

    private let facade = HarnessSettingsFacade(
        registry: .builtIn,
        locator: SetupPageLocator(available: [])
    )

    func testLaunchOptionsContainTerminalAndEnabledHarnessesOnly() {
        let settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "example-host",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.codex]
        )
        let draft = SettingsDraft(value: settings)

        let options = draft.launchOptions(using: facade, on: .remote)

        XCTAssertEqual(options.map(\.choice), [.terminal, .harness(.codex)])
        XCTAssertEqual(options.map(\.title), ["Terminal", "OpenAI Codex"])
    }

    @MainActor
    func testTheDemoShowsNoMachineYetOnlyForItsOwnShot() {
        var draft = AppSettings.empty
        draft.opsRepoPath = "/Users/alice/.config/devmachine"
        defer { DemoSnapshots.settingsNoMachine = false }
        DemoSnapshots.settingsNoMachine = false
        XCTAssertTrue(SetupPage.notices(for: draft, demo: true).isEmpty)
        DemoSnapshots.settingsNoMachine = true
        XCTAssertEqual(SetupPage.notices(for: draft, demo: true).map(\.kind), [.noMachineYet])
        XCTAssertTrue(SetupPage.issues(for: draft, demo: true).isEmpty)
    }

    func testTheThisMacPickerShowsAPlainShellForAHarnessItCannotStart() {
        let settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops", hostAlias: "example-host",
            publicIP: "203.0.113.10", baseDomain: "example.com",
            enabledHarnesses: [.claude, .opencode], localSessionProgram: .harness(.opencode))
        let local = SettingsDraft(value: settings).launchOptions(using: facade, on: .thisMac)
        let remote = SettingsDraft(value: settings).launchOptions(using: facade, on: .remote)

        XCTAssertEqual(SetupPage.offered(settings.localSessionProgram, in: local), .terminal)
        XCTAssertEqual(SetupPage.offered(.harness(.opencode), in: remote), .harness(.opencode))
        XCTAssertEqual(SetupPage.offered(.custom("npm run dev"), in: local), .custom("npm run dev"))
        XCTAssertEqual(
            facade.remoteOnlyNote(for: .opencode, in: settings), HarnessSettingsFacade.remoteOnlyNote)
    }

    func testDisablingHarnessNormalizesEveryAffectedDraftChoice() {
        let settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "example-host",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            enabledHarnesses: [.claude, .codex],
            localSessionProgram: .harness(.codex),
            remoteSessionProgram: .harness(.codex),
            workspaceSessionPrograms: [
                "acme-devmachine": .harness(.codex),
                "beta-devmachine": .harness(.claude),
            ]
        )
        var draft = SettingsDraft(value: settings)

        let result = draft.setHarness(.codex, enabled: false, using: facade)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(draft.value.enabledHarnesses, [.claude])
        XCTAssertEqual(draft.value.localSessionProgram, .terminal)
        XCTAssertEqual(draft.value.remoteSessionProgram, .terminal)
        XCTAssertEqual(draft.value.workspaceSessionPrograms, [
            "acme-devmachine": .terminal,
            "beta-devmachine": .harness(.claude),
        ])
    }

    func testHarnessOverridesUseOnlyVisibleWorkspaces() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevmachineApp/SetupPage.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let harnessBlock = try XCTUnwrap(
            source.range(of: "private var harnessesBlock"))
        let nextBlock = try XCTUnwrap(
            source.range(of: "private func settingsHeading", range: harnessBlock.upperBound..<source.endIndex))
        let body = source[harnessBlock.lowerBound..<nextBlock.lowerBound]

        XCTAssertTrue(body.contains("model.visibleWorkspaces"))
        XCTAssertFalse(body.contains("ForEach(model.workspaces)"))
    }
}

final class SetupPageWallpaperTests: XCTestCase {
    func testTheShippedPhotoSelectsTheBundledChoice() {
        XCTAssertEqual(SetupPage.choice(for: shipped), .bundled)
    }

    func testAnyOtherPhotoSelectsItsUnsplashID() {
        XCTAssertEqual(SetupPage.choice(for: remote), .unsplash(id: "ccc333"))
    }

    func testAGradientChoiceOpensTheGradientChip() {
        XCTAssertEqual(
            SetupPage.openThemeID(for: .gradient(name: "ember"), in: library),
            SetupPage.gradientTheme
        )
    }

    func testTheNetworkMapChoiceOpensItsOwnChip() {
        XCTAssertEqual(SetupPage.openThemeID(for: .networkMap, in: library), SetupPage.networkMapTheme)
        XCTAssertNotEqual(SetupPage.networkMapTheme, SetupPage.gradientTheme)
    }

    func testTheBundledChoiceOpensTheThemeOfTheShippedPhoto() {
        XCTAssertEqual(SetupPage.openThemeID(for: .bundled, in: library), "ocean")
    }

    func testAPhotoChoiceOpensItsOwnTheme() {
        XCTAssertEqual(SetupPage.openThemeID(for: .unsplash(id: "ccc333"), in: library), "space")
    }

    func testAnUnknownPhotoOpensTheFirstTheme() {
        XCTAssertEqual(SetupPage.openThemeID(for: .unsplash(id: "zzz999"), in: library), "ocean")
    }

    func testWithoutAnyThemeTheGradientChipOpens() {
        XCTAssertEqual(
            SetupPage.openThemeID(for: .bundled, in: .empty),
            SetupPage.gradientTheme
        )
    }

    @MainActor
    func testTheGradientChipIDIsNotAThemeOfTheShippedLibrary() {
        let library = WallpaperStore.shippedLibrary()
        XCTAssertFalse(library.themes.map(\.id).contains(SetupPage.gradientTheme))
        XCTAssertFalse(library.themes.map(\.id).contains(SetupPage.networkMapTheme))
    }

    func testTheDomainHintSaysItIsOptionalAndWhenNoMachineCanUseItYet() {
        XCTAssertTrue(SetupPage.domainHint(hasCaddyMachine: true).hasPrefix("Optional."))
        XCTAssertFalse(SetupPage.domainHint(hasCaddyMachine: true).contains("No machine has Caddy"))
        XCTAssertTrue(SetupPage.domainHint(hasCaddyMachine: false).contains("No machine has Caddy yet"))
    }

    func testSettingsHasGeneralAppearanceAndHealthCheckButNoTerminalPreviewsOrAdvanced() {
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["General", "Machines", "Workspaces", "Packages", "Harnesses", "Appearance", "Health check", "About"])
    }
}
