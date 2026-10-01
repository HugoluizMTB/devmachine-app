import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DMComponentsRenderTests: XCTestCase {
    /// `DEVMACHINE_RENDER=1` writes the gallery to /tmp so every shared
    /// component can be looked at side by side.
    func testTheGalleryRenders() throws {
        let view = DMComponentsGallery()
            .frame(width: 640)
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
    @State private var tab = "Sites"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DMIconButton(systemImage: "arrow.clockwise", size: 11, hitSize: DMHitSize.compact) {}
                DMIconButton(systemImage: "plus", tint: nil) {}
                DMIconButton(systemImage: "star.fill", tint: .yellow) {}
                DMIconButton(systemImage: "xmark", size: 10) {}.disabled(true)
                Button("Commit") {}.buttonStyle(.dmChip).font(.dm(11))
            }
            DMButtonGallery()
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
            HStack(spacing: 10) {
                ForEach(PRStateKind.allCases, id: \.self) { state in
                    HStack(spacing: 4) {
                        DMPRStateIcon(state: state)
                        Text(state.rawValue).font(.dm(11)).foregroundStyle(Color.dmMuted)
                    }
                }
                DMKindLabel(text: "ISSUE")
                DMKindLabel(text: "DOC")
                DMKindLabel(text: "CNAME")
            }
            DMCommandBlock(["devmachine packages add docker --machine main", "devmachine sync --machine main"])
            DMTabStrip(
                tabs: ["Sites", "cloudflare"], selection: $tab, title: { $0 },
                fontSize: 12, cornerRadius: DMRadius.row, spacing: 2, grouped: true)
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    DMTableRow(index: index) {
                        Text(verbatim: "app\(index).example.com")
                            .font(.dm(12))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            DMHairline()
            Text(verbatim: "Glass panel")
                .font(.dm(12))
                .padding(12)
                .frame(maxWidth: .infinity)
                .dmGlass(radius: DMRadius.panel)
            DMProgressBar(done: 3, total: 5)
            HStack(alignment: .top, spacing: 8) {
                DMJobCard(title: "Publishing app.example.com…", status: .running, steps: [
                    DMJobStep(id: "dns", title: "DNS record set", state: .done),
                    DMJobStep(id: "caddy", title: "Caddy route", state: .running),
                ])
                DMAgeLabel(since: Date().addingTimeInterval(-300))
            }
            DMBanner(message: "Couldn't refresh: ssh: connect to host timed out", lineLimit: 2) {
                DMIconButton(systemImage: "arrow.clockwise", tint: nil) {}
            }
            DMSkeleton {
                VStack(alignment: .leading, spacing: 6) {
                    DMSkeletonText(size: 13, width: .fraction(0.6))
                    DMSkeletonText(size: 11, width: .fixed(80))
                    DMSkeletonBlock(height: 5, radius: 3)
                }
            }
            DMErrorStateView(
                state: DMErrorState(
                    title: "Codex usage isn't available", cause: "Codex doesn't seem to be signed in.",
                    details: "error: not signed in, run `codex login`"),
                retry: {}, startsExpanded: true)
            HStack(alignment: .top, spacing: 0) {
                DMStatusView(kind: .loading("Reading context…"), fillsHeight: false)
                DMStatusView(
                    kind: .empty(systemImage: "text.bubble", text: "Nothing to show yet"),
                    fillsHeight: false)
                DMStatusView(
                    kind: .failed(
                        title: "Couldn't read the context", message: "ssh: host unreachable",
                        retry: {}),
                    fillsHeight: false)
            }
        }
        .padding(16)
    }
}

private struct DMButtonGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(DMButtonSize.allCases, id: \.self) { size in
                HStack(spacing: 6) {
                    DMButton("Save", size: size) {}
                    DMButton("Cancel", variant: .outline, size: size) {}
                    DMButton("Delete", systemImage: "trash", variant: .danger, size: size) {}
                    DMButton("Remove", variant: .dangerOutline, size: size) {}
                    DMButton("Details", systemImage: "chevron.down", variant: .ghost, size: size) {}
                    DMButton("Use remote fallback", variant: .link, size: size) {}
                    DMButton(icon: "arrow.clockwise", label: "Refresh", size: size) {}
                }
            }
            HStack(spacing: 6) {
                ForEach([DMButtonVariant.primary, .outline, .danger, .ghost, .ghostDanger], id: \.self) { variant in
                    Button("Hover") {}.buttonStyle(DMButtonStyle(variant: variant, simulated: .hovered))
                }
                Button("Pressed") {}.buttonStyle(DMButtonStyle(simulated: .pressed))
                Button("Focused") {}.buttonStyle(DMButtonStyle(variant: .outline, simulated: .focused))
            }
            HStack(spacing: 6) {
                DMButton("Save", size: .small) {}.disabled(true)
                DMButton("Cancel", variant: .outline, size: .small) {}.disabled(true)
                DMButton("Run again", systemImage: "arrow.clockwise", variant: .outline, size: .small,
                         isLoading: true) {}
                DMButton("Save", isLoading: true) {}
                DMButton(icon: "arrow.clockwise", label: "Refresh", isLoading: true) {}
            }
        }
    }
}
