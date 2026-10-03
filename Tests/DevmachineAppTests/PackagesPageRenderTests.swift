import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class PackagesPageRenderTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)

    private func snapshot() -> PackagesSnapshot {
        PackagesSnapshot(
            entries: [
                PackageEntry(name: "docker", scope: "machine", source: "release", summary: "Containers on the machine.",
                             category: "Containers", platforms: ["linux"], needs: [], credentialNames: [],
                             installedOn: ["machine main"]),
                PackageEntry(name: "gh", scope: "workspace", source: "release", summary: "The GitHub CLI, logged in.",
                             category: "Tools", platforms: [], needs: ["git"], credentialNames: ["GITHUB_TOKEN"],
                             installedOn: ["workspace acme"]),
                PackageEntry(name: "node", scope: "machine", source: "local", summary: "Node.js from a local recipe.",
                             category: nil, platforms: [], needs: [], credentialNames: [], installedOn: []),
            ],
            targets: [main, .workspace("acme", machine: "main")],
            lock: PackagesLock(machines: ["main": [.init(name: "docker")]]),
            cliVersion: SemanticVersion(major: 0, minor: 7, patch: 30),
            configDirectory: "/Users/alice/.config/devmachine")
    }

    func testTheHeaderAndRowsRender() async throws {
        let snap = snapshot()
        let store = PackagesStore(read: { snap }, edit: { _ in }, jobs: { nil })
        await store.load()
        let loaded = try XCTUnwrap(store.snapshot)
        let main = self.main
        let statuses = loaded.statuses(for: main)
        let view = VStack(alignment: .leading, spacing: 12) {
            PackagesHeader(
                targets: loaded.targets, target: .constant(main),
                filter: .constant(PackageFilter(categories: ["Tools"])),
                categories: PackageFilter.categories(in: loaded.entries))
            ForEach(Array(loaded.entries.enumerated()), id: \.element.id) { index, entry in
                DMTableRow(index: index) {
                    PackageRow(
                        entry: entry, target: main, status: statuses[entry.name] ?? .available,
                        isSelected: index == 0, toggle: {})
                }
            }
            ForEach(Array(loaded.entries.enumerated()), id: \.element.id) { index, entry in
                DMTableRow(index: index) {
                    PackageRow(entry: entry, target: nil, status: nil, isSelected: false, toggle: {})
                }
            }
        }
        .padding(24)
        .frame(width: 820)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.dmContentBg)
        .environment(\.colorScheme, .dark)

        try snapshotPNG(view, name: "devmachine-packages")
    }

    func testTheWholePageRendersWithATargetThatWaitsForASync() async throws {
        let snap = snapshot()
        let store = PackagesStore(read: { snap }, edit: { _ in }, jobs: { nil })
        await store.load()
        let view = PackagesSettingsView(store: store, target: .workspace("acme", machine: "main"))
            .padding(24)
            .frame(width: 820)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.dmContentBg)
            .environment(\.colorScheme, .dark)
        try snapshotPNG(view, name: "devmachine-packages-page")
    }

    func testThePackagesSectionComesAfterWorkspaces() {
        let all = SettingsSection.allCases
        XCTAssertEqual(all.firstIndex(of: .packages), all.firstIndex(of: .workspaces).map { $0 + 1 })
        XCTAssertEqual(SettingsSection.packages.title, "Packages")
        XCTAssertEqual(SettingsSection.packages.systemImage, "shippingbox")
    }

    private func snapshotPNG(_ view: some View, name: String) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        XCTAssertGreaterThan(hosting.frame.width, 0)
        XCTAssertGreaterThan(hosting.frame.height, 0)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.contentView = nil }
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertFalse(png.isEmpty)
        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil {
            try png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
    }
}
