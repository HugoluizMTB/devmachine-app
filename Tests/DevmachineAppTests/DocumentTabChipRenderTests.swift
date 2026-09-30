import XCTest
import SwiftUI
@testable import DevmachineApp

@MainActor
final class DocumentTabChipRenderTests: XCTestCase {
    /// `DEVMACHINE_RENDER=1` writes the strip to /tmp for a look.
    func testTheTabStripRenders() throws {
        let strip = HStack(spacing: 2) {
            DocumentTabChip(systemImage: "doc.text", title: "notes.md", selected: false,
                            closeHelp: "Close the file", select: {}, close: {})
            DocumentTabChip(systemImage: "globe", title: "Acme Docs — Getting started with the dashboard",
                            selected: true, closeHelp: "Close the preview", select: {}, close: {})
            DocumentTabChip(systemImage: "globe", title: "localhost:5173", selected: false,
                            closeHelp: "Close the preview", select: {}, close: {})
            Spacer(minLength: 0)
        }
        .frame(width: 720)
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
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-tabs.png"))
        }
    }

    func testALongTitleIsShortenedSoTheStripFitsWithoutScrolling() {
        XCTAssertEqual(DocumentTabChip.shortened("localhost:5173"), "localhost:5173")
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(DocumentTabChip.shortened(long).count, DocumentTabChip.maxTitleLength)
        XCTAssertTrue(DocumentTabChip.shortened(long).hasSuffix("…"))
    }
}
