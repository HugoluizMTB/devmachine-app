import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class QuietRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
private final class RecordingPreviews: PalettePreviewOpening {
    var opened: [PreviewRequest] = []
    func open(_ request: PreviewRequest, inverted: Bool) { opened.append(request) }
}

@MainActor
private final class NoStats: PaletteStatsControlling {
    func select(_ name: String) {}
    func refresh() {}
}

@MainActor
private final class NoSites: PaletteSitesControlling {
    func prefer(machine: String) {}
    func refresh() {}
}

@MainActor
private final class NoHealth: PaletteHealthChecking {
    func run() {}
}

@MainActor
private final class NoSaved: PaletteSavedCommandRecording {
    func record(_ raw: String, for alias: String) -> String? { raw }
}

@MainActor
private final class NoUpdates: PaletteUpdateChecking {
    func checkNow() {}
}

@MainActor
private final class NoSystem: PaletteSystem {
    func openFilesWindow(alias: String) {}
    func reveal(path: String) {}
    func open(_ url: URL) {}
    func quit() {}
    func chooseFileAndSend(to kind: TerminalKind) {}
    func pickScreenColor(onCopy: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class PreviewPaletteTests: XCTestCase {
    private func context(current: String? = "acme-devmachine") -> PaletteContext {
        var context = PaletteContext()
        context.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        context.currentWorkspaceAlias = current
        context.currentTerminal = current.map { .remote(alias: $0, session: "dash") }
        context.previewTargets = [
            PalettePreviewGroup(place: .workspace("acme"), targets: [
                PreviewTarget(kind: .site(host: "app.acme.example.com"), title: "app.acme.example.com", label: "3000"),
                PreviewTarget(kind: .port(5173), title: "5173", label: "vite"),
            ]),
            PalettePreviewGroup(place: .thisMac, targets: [
                PreviewTarget(kind: .port(3000), title: "3000", label: "web"),
            ]),
        ]
        return context
    }

    func testEveryKnownPortGetsAPreviewCommand() {
        let commands = CommandRegistry.commands(in: context())
        let port = commands.first { $0.id == "preview.ws:acme.port.5173" }
        XCTAssertEqual(port?.title, "Preview acme port 5173")
        XCTAssertEqual(port?.subtitle, "vite")
        XCTAssertEqual(port?.action, .preview(PreviewRequest(place: .workspace("acme"), input: .port(5173, path: ""))))

        let local = commands.first { $0.id == "preview.local.port.3000" }
        XCTAssertEqual(local?.title, "Preview This Mac port 3000")
    }

    func testAPublishedSiteGetsAPreviewCommand() {
        let site = CommandRegistry.commands(in: context()).first { $0.id == "preview.ws:acme.site.app.acme.example.com" }
        XCTAssertEqual(site?.title, "Preview app.acme.example.com")
        XCTAssertEqual(site?.action, .preview(PreviewRequest(
            place: .workspace("acme"), input: .url(URL(string: "https://app.acme.example.com")!))))
    }

    func testOpenPreviewNeedsASession() {
        XCTAssertNotNil(CommandRegistry.commands(in: context()).first { $0.id == "action.open-preview" })
        XCTAssertNil(CommandRegistry.commands(in: context(current: nil)).first { $0.id == "action.open-preview" })
    }

    func testTheDispatcherOpensThePreviewAndTheField() {
        let model = AppModel(store: SessionStore(runner: QuietRunner()))
        model.contextCollapsed = true
        let previews = RecordingPreviews()
        let dispatcher = PaletteDispatcher(
            model: model, stats: NoStats(), sites: NoSites(), health: NoHealth(), savedCommands: NoSaved(), updates: NoUpdates(),
            recents: PaletteRecentsStore(
                defaults: UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!),
            system: NoSystem(), previews: previews)
        let request = PreviewRequest(place: .workspace("acme"), input: .port(5173, path: ""))

        dispatcher.perform(PaletteCommand(
            id: "p", title: "t", subtitle: "", category: .action, systemImage: "globe", action: .preview(request)))
        dispatcher.perform(PaletteCommand(
            id: "f", title: "t", subtitle: "", category: .action, systemImage: "globe", action: .openPreviewField))

        XCTAssertEqual(previews.opened, [request])
        XCTAssertEqual(model.contextTab, .preview)
        XCTAssertFalse(model.contextCollapsed)
        XCTAssertTrue(model.pendingPreviewField)
    }
}

@MainActor
final class AppModelPreviewPlaceTests: XCTestCase {
    func testARemoteSessionPreviewsItsWorkspace() {
        let model = AppModel(store: SessionStore(runner: QuietRunner()))
        var settings = AppSettings.empty
        settings.workspaceAliases = ["acme": "acme-devmachine"]
        model.settings = settings
        model.selection = .session(alias: "acme-devmachine", name: "dash")

        XCTAssertEqual(model.selectedPreviewPlace, .workspace("acme"))
    }

    func testALocalSessionPreviewsThisMac() {
        let model = AppModel(store: SessionStore(runner: QuietRunner()))
        model.selection = .localSession(name: "notes", path: "/Users/alice/notes")

        XCTAssertEqual(model.selectedPreviewPlace, .thisMac)
    }

    func testNothingSelectedHasNoPlace() {
        XCTAssertNil(AppModel(store: SessionStore(runner: QuietRunner())).selectedPreviewPlace)
    }
}
