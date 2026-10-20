import AppKit
import SwiftUI
import XCTest
import DevmachineCore
@testable import DevmachineApp

/// `DEVMACHINE_RENDER=1` writes each state to /tmp/devmachine-add-machine-<name>.png to look at.
@MainActor
final class AddMachineRenderTests: XCTestCase {
    private let key = "SHA256:" + String(repeating: "R", count: 43)

    private func model(
        scan: @escaping @Sendable (String, String) async throws -> MachineScan, terminal: NeedsPasswordRunner = NeedsPasswordRunner()
    ) async -> AddMachineModel {
        let machines = MachinesStore(read: {
            MachinesSnapshot(
                hasConfiguration: true, machines: [], packages: [], cliVersion: MachineUnattendedAdd.minimumCLIVersion)
        }, remove: { _ in })
        await machines.load()
        let model = AddMachineModel(
            machines: machines, runner: MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000),
            findLima: { nil }, onAdded: {}, scanMachine: scan, listAgentKeys: { [] }, listSSHFolder: { [] },
            scanPause: 0)
        model.wizard.choose(.server)
        model.wizard.draft.name = "backup"
        model.wizard.draft.address = "203.0.113.20"
        model.wizard.draft.keyFile = "~/.ssh/id_ed25519"
        model.wizard.draft.sync = false
        model.wizard.draft.packages = []
        return model
    }

    private func render(_ view: some View, name: String) throws -> CGSize {
        let renderer = ImageRenderer(content: view
            .frame(width: 760, alignment: .topLeading)
            .padding(20)
            .background(Color.dmContentBg)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-add-machine-\(name).png"))
        }
        return image.size
    }

    func testTheDetailsWithAKeyReadAndWithAFailedReadRender() async throws {
        let key = key
        let read = await model(scan: { address, port in
            MachineScan(address: address, port: Int(port) ?? 22, keyType: "ssh-ed25519", fingerprint: key, verify: nil)
        })
        await read.scanAfterPause()
        XCTAssertGreaterThan(try render(AddMachineDetailsView(state: read), name: "details").height, 0)

        let failed = await model(scan: { _, _ in throw RenderScanError() })
        await failed.scanAfterPause()
        XCTAssertNotNil(failed.currentScanFailure)
        XCTAssertGreaterThan(try render(AddMachineScanView(state: failed), name: "scan-failed").height, 0)
    }

    func testAFailureThatNeedsThePasswordRendersItsField() async throws {
        let terminal = NeedsPasswordRunner()
        let key = key
        let model = await model(scan: { address, port in
            MachineScan(address: address, port: Int(port) ?? 22, keyType: "ssh-ed25519", fingerprint: key, verify: nil)
        }, terminal: terminal)
        model.wizard.next()
        model.wizard.next()
        await model.create()
        XCTAssertEqual(model.retryField, .password)

        let runner = model.runner
        let size = try render(
            VStack(alignment: .leading, spacing: 12) {
                SetupFailurePanel(
                    step: model.failedStep, lines: runner.lines, problem: runner.problem, exitCode: runner.exitCode,
                    onEditAnswers: {})
                AddMachinePasswordRetry(state: model)
            }
            .frame(width: 340),
            name: "needs-password")
        XCTAssertGreaterThan(size.height, 0)
    }
}

private struct RenderScanError: Error, LocalizedError {
    var errorDescription: String? {
        #"machine "203.0.113.20": no address answered while scanning its SSH host key: "#
            + "203.0.113.20 (dial tcp 203.0.113.20:22: connect: connection refused)"
    }
}

/// Every `machines add` ends as the CLI does for a key not on the server yet.
@MainActor
private final class NeedsPasswordRunner {
    var hooks: MachineStepRunner.Hooks {
        MachineStepRunner.Hooks(
            executable: { nil }, isReady: { _ in false }, type: { _, _ in }, matchCount: { _, _ in 0 },
            writeScript: { _, _ in "" }, isAtPrompt: { _ in nil },
            runProcess: { _, _, output in
                output("Error: the key does not log in yet and no password was given: pass the admin password on "
                    + "stdin with --password-stdin, or put the key's public half in the admin's authorized_keys first")
                return 1
            },
            beginTask: { _, _ in nil }, setTask: { _, _ in }, endTask: { _, _ in })
    }
}
