import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

/// Renders the host key page in each state in a window that is never shown.
/// `DEVMACHINE_SHOTS_DIR=<folder>` writes each one there as a PNG.
@MainActor
final class HostKeyPageRenderTests: XCTestCase {
    private static let changed = """
    {"machine":"box","address":"100.64.0.7","status":"changed","key_type":"ecdsa-sha2-nistp256",
     "current_key_type":"ecdsa-sha2-nistp256",
     "current_fingerprint":"SHA256:oldOLDold0000000000000000000000000000000000",
     "presented_fingerprint":"SHA256:newNEWnew1111111111111111111111111111111111","check":true,"changed":false,
     "verify":"ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub"}
    """

    private func store(_ output: CLIOutput) async -> HostKeyStore {
        let store = HostKeyStore(runner: StaticHostKeyRunner(output: output))
        await store.check("box")
        return store
    }

    func testEveryHostKeyPageStateRenders() async throws {
        let review = await store(CLIOutput(stdout: Self.changed, stderr: "", exitCode: 0))
        try render(HostKeyPage(store: review, machine: "box"), name: "hostkey-1-review")
        try render(
            HostKeyPage(store: review, machine: "box", pasted: "256 SHA256:oldOLDold0000000000000000000000000000000000 root@box (ECDSA)"),
            name: "hostkey-2-wrong-paste")
        try render(
            HostKeyPage(store: review, machine: "box", pasted: "256 SHA256:newNEWnew1111111111111111111111111111111111 root@box (ECDSA)"),
            name: "hostkey-3-confirmed")
        let older = await store(CLIOutput(
            stdout: "", stderr: "error: host key changed for machine \"box\" at 100.64.0.7: trusted a, presented b", exitCode: 1))
        try render(HostKeyPage(store: older, machine: "box"), name: "hostkey-4-older-cli")
        let failed = await store(CLIOutput(
            stdout: "", stderr: "error: no address answered while scanning box: i/o timeout", exitCode: 1))
        try render(HostKeyPage(store: failed, machine: "box"), name: "hostkey-5-failed")
        try render(
            HostKeySidebarCard(machine: "box").frame(width: 260).background(Color.dmSidebarBg),
            name: "hostkey-6-sidebar", size: nil)
    }

    private func render(_ view: some View, name: String, size: NSSize? = NSSize(width: 820, height: 640)) throws {
        let model = AppModel(store: SessionStore(runner: StaticCommandRunner()))
        let hosting = NSHostingView(rootView: view.environmentObject(model).environment(\.colorScheme, .dark))
        let frame = size ?? hosting.fittingSize
        XCTAssertGreaterThan(frame.width, 0, name)
        hosting.frame = NSRect(origin: .zero, size: frame)
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

private struct StaticHostKeyRunner: HostKeyRunning {
    let output: CLIOutput
    func run(_ arguments: [String]) async throws -> CLIOutput { output }
}

private struct StaticCommandRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) { ("", "", 0) }
}
