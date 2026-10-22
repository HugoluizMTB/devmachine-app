import XCTest
import SwiftUI
@testable import DevmachineApp

@MainActor
final class CenterTabStripRenderTests: XCTestCase {
    func testShowsOnlyInCodeModeWithTheSettingOn() {
        XCTAssertTrue(CenterTabStrip.shows(enabled: true, mode: .code))
        XCTAssertFalse(CenterTabStrip.shows(enabled: false, mode: .code))
        XCTAssertFalse(CenterTabStrip.shows(enabled: true, mode: .chats))
        XCTAssertFalse(CenterTabStrip.shows(enabled: true, mode: .schedule))
    }

    func testTheStripMovesOutFromUnderTheWindowButtonsOnlyWhileTheSidebarIsClosed() {
        XCTAssertEqual(CenterTabStrip.leadingInset(toggle: nil, gap: 8), 0)
        XCTAssertEqual(CenterTabStrip.stripHeight(toggle: nil, titleLine: 22, row: 34), 34)
        let toggle = CGRect(x: 86, y: 10, width: 24, height: 24)
        XCTAssertEqual(CenterTabStrip.leadingInset(toggle: toggle, gap: 8), 118)
        XCTAssertEqual(CenterTabStrip.stripHeight(toggle: toggle, titleLine: 22, row: 34), 44)
        XCTAssertEqual(CenterTabStrip.stripHeight(toggle: toggle, titleLine: 10, row: 34), 34)
        XCTAssertEqual(CenterTabStrip.rowTop(row: 34, strip: 44), 5)
        XCTAssertEqual(CenterTabStrip.rowTop(row: 34, strip: 34), 0)
    }

    func testAFileTabIconFollowsTheExtension() {
        XCTAssertEqual(CenterTabStrip.fileIcon(path: "/home/alice/dash/README.md"), "doc.richtext")
        XCTAssertEqual(CenterTabStrip.fileIcon(path: "/home/alice/dash/logo.PNG"), "photo")
        XCTAssertEqual(CenterTabStrip.fileIcon(path: "/home/alice/dash/main.go"), "doc.text")
    }

    /// `DEVMACHINE_RENDER=1` writes the strip to /tmp for a look.
    func testTheStripRendersSessionAndFileTabs() throws {
        let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        let strip = HStack(spacing: 2) {
            DocumentTabChip(systemImage: "apple.terminal", title: "claude — payments refactor", selected: true,
                            closeHelp: "Close the tab", select: {}, close: {}, image: icon, imageIsTemplate: true,
                            iconColor: Color.dmRowText.opacity(0.8))
            DocumentTabChip(systemImage: "apple.terminal", title: "dev server", selected: false,
                            closeHelp: "Close the tab", select: {}, close: {}, iconColor: Color.dmRowText.opacity(0.8))
            DocumentTabChip(systemImage: "doc.richtext", title: "README.md", selected: false,
                            closeHelp: "Close the file tab", select: {}, close: {})
            Spacer(minLength: 0)
        }
        .frame(width: 720, height: 34)
        .background(Color.dmSidebarBg)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.height, 20)

        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-center-tabs.png"))
        }
    }
}
