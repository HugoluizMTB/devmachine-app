import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

/// Renders the publish card in every state, and the Publish a port… sheet
/// opened from cached ports, in a window that is never shown (native
/// controls draw there, unlike in `ImageRenderer`).
/// `DEVMACHINE_SHOTS_DIR=<folder>` writes each one there as a PNG.
@MainActor
final class PublishFeedbackRenderTests: XCTestCase {
    private let host = "app.example.com"

    private func job(_ progress: PublishProgress) -> PublishJob {
        PublishJob(id: UUID(), request: .publish(workspace: "alice", port: 3000, host: host), progress: progress)
    }

    private func finished(_ stdout: String, stderr: String = "", exit: Int32 = 0) -> PublishProgress {
        .finished(.publish, host: host, output: CLIOutput(stdout: stdout, stderr: stderr, exitCode: exit))
    }

    private var states: [(String, PublishJob)] {
        [
            ("publish-1-running", job(.running(.publish, host: host))),
            ("publish-2-live", job(finished(
                #"{"host":"app.example.com","port":3000,"workspace":"alice","applied":true,"status":"published"}"#))),
            ("publish-3-pending", job(finished(
                #"{"host":"app.example.com","port":3000,"workspace":"alice","applied":false,"status":"pending","note":"box could not be reached"}"#,
                stderr: "No installed provider holds example.com. Create this record by hand:\n\n  app\tA\t203.0.113.10\n"))),
            ("publish-4-failed", job(finished(
                #"{"host":"app.example.com","port":3000,"workspace":"alice","applied":false,"status":"pending","note":"caddy refused"}"#,
                stderr: "caddy refused the new /etc/caddy/sites.d/alice.caddy, so the old one stays:\nError: adapting config using caddyfile: unrecognized directive: reverse_prox\nhttps://app.example.com is recorded in the configuration and pending: fix it and run `devmachine sync`",
                exit: 1))),
            ("publish-5-removing", PublishJob(
                id: UUID(), request: .remove(host: host, machine: "box"), progress: .running(.remove, host: host))),
            ("publish-6-removed", PublishJob(
                id: UUID(), request: .remove(host: host, machine: "box"),
                progress: .finished(.remove, host: host, output: CLIOutput(
                    stdout: #"{"host":"app.example.com","workspace":"alice","applied":true,"status":"removed"}"#,
                    stderr: "", exitCode: 0)))),
        ]
    }

    func testEveryPublishCardStateRenders() throws {
        for (name, job) in states {
            let card = PublishJobCard(job: job, onRetry: {}, onDismiss: {})
                .padding(18)
                .background(Color.dmContentBg)
            try render(card, name: name)
        }
    }

    func testPublishAPortRendersWithCachedPortsTheMomentItOpens() throws {
        let clock = CacheClock()
        clock.now = Date()
        let cache = DataCache(now: { clock.now })
        cache.put(MachineDataKeys.workspaces, [CLIWorkspace(name: "alice", machine: "box", user: "alice", packages: [])])
        let stats = FakePortStats()
        stats.states["box"] = MachineStatsState(
            snapshot: portsSnapshot([3000, 5173, 8080]), refreshedAt: clock.now.addingTimeInterval(-180))
        let data = WorkspaceMachineData(
            cache: cache, listWorkspaces: { [] }, listExposures: { _ in ExposureListing(sites: [], warning: nil) })
        let state = QuickPublishState(data: data, now: { clock.now })

        state.start(workspace: "alice", stats: stats)

        XCTAssertEqual(state.workspace, "alice")
        XCTAssertEqual(state.ports.map(\.port), [3000, 5173, 8080])
        XCTAssertTrue(state.isRefreshingPorts)
        var settings = AppSettings.empty
        settings.baseDomain = "example.com"
        let sheet = AddSubdomainSheet(
            settings: settings, workspaces: [Workspace(name: "alice", alias: "alice-devmachine")],
            preselectedWorkspace: "alice", suggestedPorts: state.ports, suggestedLabel: "alice",
            portsAsOf: state.portsAsOf, isRefreshingPorts: state.isRefreshingPorts)
            .environmentObject(CaddyStore())
        try render(sheet, name: "publish-a-port-instant")
    }

    private func render(_ view: some View, name: String) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let size = hosting.fittingSize
        XCTAssertGreaterThan(size.width, 0, name)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.contentView = nil }
        guard let folder = ProcessInfo.processInfo.environment["DEVMACHINE_SHOTS_DIR"],
              let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]), name)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }
}
