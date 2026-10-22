import XCTest
import SwiftUI
@testable import DevmachineApp

@MainActor
final class DMRowLeadingAlignmentTests: XCTestCase {
    func testLeadingAlignsWithTheTitleLineOnlyWhenThereIsASubtitle() {
        XCTAssertEqual(DMRow.stackAlignment(leadingOnTitleLine: true, hasSubtitle: true), .top)
        XCTAssertEqual(DMRow.stackAlignment(leadingOnTitleLine: true, hasSubtitle: false), .center)
        XCTAssertEqual(DMRow.stackAlignment(leadingOnTitleLine: false, hasSubtitle: true), .center)
        XCTAssertEqual(DMRow.stackAlignment(leadingOnTitleLine: false, hasSubtitle: false), .center)
    }

    func testTheSessionGlyphIsSmallerThanItsLine() {
        XCTAssertEqual(DMIconSize.sessionGlyph, 12)
        XCTAssertGreaterThan(DMIconSize.sessionGlyphLine, DMIconSize.sessionGlyph)
    }

    /// `DEVMACHINE_RENDER=1` writes the rows to /tmp for a look.
    func testASessionRowWithSubtitleRenders() throws {
        let rows = VStack(spacing: 1) {
            DMRow(
                leading: AnyView(Image(systemName: "apple.terminal").resizable().scaledToFit()
                    .frame(width: 12, height: 12)),
                title: "claude — payments refactor", subtitle: "feature/payments", selected: true,
                leadingOnTitleLine: true)
            DMRow(
                leading: AnyView(Circle().fill(Color.orange).frame(width: 8, height: 8).frame(width: 12, height: 12)),
                title: "dev server", subtitle: "main", leadingOnTitleLine: true)
            DMRow(leading: AnyView(Color.clear.frame(width: 12, height: 12)), title: "shell", leadingOnTitleLine: true)
        }
        .frame(width: 260)
        .background(Color.dmSidebarBg)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: rows)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.height, 60)

        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-session-row.png"))
        }
    }
}
