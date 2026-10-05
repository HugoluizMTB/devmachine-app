import SwiftUI
import DevmachineCore

/// The host key walk (`DEVMACHINE_DEMO_WALK=host-key`): the review sheet in
/// each state a check can end in, on a fake CLI that never scans a host.
@MainActor
enum DemoHostKey {
    static let machine = "main"

    static let screens: [DemoSnapshots.Screen] = [
        DemoSnapshots.Screen(id: "hostkey-review", fileName: "150-hostkey-review.png", settleNanoseconds: 300_000_000),
        DemoSnapshots.Screen(id: "hostkey-matching", fileName: "151-hostkey-matching.png", settleNanoseconds: 300_000_000),
        DemoSnapshots.Screen(id: "hostkey-older-cli", fileName: "152-hostkey-older-cli.png", settleNanoseconds: 300_000_000),
        DemoSnapshots.Screen(id: "hostkey-failed", fileName: "153-hostkey-failed.png", settleNanoseconds: 300_000_000),
    ]

    static func handles(_ id: String) -> Bool { screens.contains { $0.id == id } }

    private static let presented = "SHA256:newNEWnew1111111111111111111111111111111111"

    static func output(for id: String) -> CLIOutput {
        switch id {
        case "hostkey-matching":
            return CLIOutput(stdout: report(status: "matching", presented: trusted), stderr: "", exitCode: 0)
        case "hostkey-older-cli":
            return CLIOutput(
                stdout: "",
                stderr: "error: host key changed for machine \"\(machine)\" at 203.0.113.10: trusted a, presented b",
                exitCode: 1)
        case "hostkey-failed":
            return CLIOutput(
                stdout: "", stderr: "error: no address answered while scanning \(machine): i/o timeout", exitCode: 1)
        default:
            return CLIOutput(stdout: report(status: "changed", presented: presented), stderr: "", exitCode: 0)
        }
    }

    /// The review shows the console output already pasted, so the trust
    /// button is on.
    static func pasted(for id: String) -> String {
        id == "hostkey-review" ? "256 \(presented) root@\(machine) (ECDSA)" : ""
    }

    static func sheet(_ id: String, model: AppModel) -> some View {
        let store = HostKeyStore(runner: Runner(output: output(for: id)))
        return HostKeySheet(store: store, machine: machine, pasted: pasted(for: id))
            .background(Color(nsColor: .windowBackgroundColor))
            .environmentObject(model)
    }

    private static let trusted = "SHA256:oldOLDold0000000000000000000000000000000000"

    private static func report(status: String, presented: String) -> String {
        """
        {"machine":"\(machine)","address":"203.0.113.10","status":"\(status)","key_type":"ecdsa-sha2-nistp256",
         "current_key_type":"ecdsa-sha2-nistp256","current_fingerprint":"\(trusted)",
         "presented_fingerprint":"\(presented)","check":true,"changed":false,
         "verify":"ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub"}
        """
    }

    private struct Runner: HostKeyRunning {
        let output: CLIOutput
        func run(_ arguments: [String]) async throws -> CLIOutput { output }
    }
}
