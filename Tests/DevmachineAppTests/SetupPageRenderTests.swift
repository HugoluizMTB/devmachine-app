import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

private final class QuietRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) { ("", "", 0) }
}

private struct RenderLocator: ExecutableLocating {
    func executable(named name: String) -> URL? { nil }
}

@MainActor
final class SetupPageRenderTests: XCTestCase {
    /// `DEVMACHINE_RENDER=1` writes the screen to /tmp so its layout can be
    /// looked at. Panes that scroll show empty here: `ImageRenderer` does not
    /// lay out a `ScrollView`.
    func testTheScreenRenders() throws {
        let model = AppModel(store: SessionStore(runner: QuietRunner()))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "globex", alias: "globex-devmachine"),
        ]
        let view = SetupPage()
            .environmentObject(model)
            .environmentObject(SettingsStore.shared)
            .environment(
                \.harnessSettingsFacade,
                HarnessSettingsFacade(registry: .builtIn, locator: RenderLocator())
            )
            .environmentObject(WallpaperStore())
            .frame(width: 940, height: 640)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 0)

        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-settings.png"))
        }
    }
}
