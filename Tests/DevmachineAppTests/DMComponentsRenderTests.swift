import XCTest
import SwiftUI
@testable import DevmachineApp

@MainActor
final class DMComponentsRenderTests: XCTestCase {
    /// `DEVMACHINE_RENDER=1` writes the gallery to /tmp so every shared
    /// component can be looked at side by side.
    func testTheGalleryRenders() throws {
        let view = DMComponentsGallery()
            .frame(width: 520)
            .background(Color.dmContentBg)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)

        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-components.png"))
        }
    }

    func testRadiiGrowFromTheTerminalToTheBubble() {
        let radii = [
            DMRadius.terminal, DMRadius.keyCap, DMRadius.row, DMRadius.control, DMRadius.tile,
            DMRadius.pill, DMRadius.toast, DMRadius.panel, DMRadius.card, DMRadius.bubble,
        ]
        XCTAssertEqual(radii, radii.sorted())
        XCTAssertEqual(Set(radii).count, radii.count)
    }
}

private struct DMComponentsGallery: View {
    @State private var query = "dash"
    @State private var field = "example.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DMIconButton(systemImage: "arrow.clockwise", size: 11, hitSize: DMHitSize.compact) {}
                DMIconButton(systemImage: "plus", tint: nil) {}
                DMIconButton(systemImage: "star.fill", tint: .yellow) {}
                DMIconButton(systemImage: "xmark", size: 10) {}.disabled(true)
                Button("Open") {}.buttonStyle(.dmChipProminent).font(.dm(10, weight: .medium))
                Button("Commit") {}.buttonStyle(.dmChip).font(.dm(11))
                Button("Use remote fallback") {}.buttonStyle(.dmText()).font(.dm(10))
            }
            DMSearchField(prompt: "Find a file", text: $query) {
                Text(verbatim: "42").font(.dm(10)).foregroundStyle(Color.dmMuted)
            }
            TextField("example.com", text: $field).dmField()
            HStack(spacing: 6) {
                DMKeyCap(key: "⌘")
                DMKeyCap(key: "K")
                DMChip(title: "Nature", selected: true) {}
                DMChip(title: "Cities", selected: false) {}
                DMPill(text: "CI passing", color: .green)
            }
            DMRow(systemImage: "circle.fill", title: "acme / dash", selected: true)
            Text(verbatim: "Glass panel")
                .font(.dm(12))
                .padding(12)
                .frame(maxWidth: .infinity)
                .dmGlass(radius: DMRadius.panel)
            DMProgressBar(done: 3, total: 5)
        }
        .padding(16)
    }
}
