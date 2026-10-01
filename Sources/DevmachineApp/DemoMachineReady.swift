#if DEBUG
import DevmachineCore
import SwiftUI

/// Debug builds only. The machine readiness cards and onboarding's Install
/// CLI card, for the `DEVMACHINE_DEMO_WALK=machine-ready` capture. Prepare and
/// the install run real processes, but on fake scripts written to a temporary
/// folder, never the installed devmachine, Homebrew or the installer.
@MainActor
enum DemoMachineReady {
    enum Script {
        case prepareSlow, prepareFails, prepareSucceeds, installSlow, installFails
    }

    static let machine = "staging"

    static let workspaceMachines = [
        "acme": "main", "globex": "main", "initech": "backup", "umbrella": "staging",
    ]

    static func snapshot(cliVersion: String = "0.7.24", applied: Bool = false) -> ReadinessSnapshot {
        var snapshot = ReadinessSnapshot()
        snapshot.machines = ["main", "backup", "staging"]
        snapshot.declared = ["main": true, "backup": true, "staging": false]
        snapshot.lock = PackagesLock(appliedAt: applied ? "2" : "1", machines: [
            "main": [PackagesLock.Entry(name: MachinePrepare.package)],
            "backup": [PackagesLock.Entry(name: MachinePrepare.package)],
            "staging": applied ? [PackagesLock.Entry(name: MachinePrepare.package)] : [],
        ])
        if applied { snapshot.declared?["staging"] = true }
        snapshot.workspaceMachines = workspaceMachines
        snapshot.cliVersion = SemanticVersion(cliVersion)
        snapshot.sshAliasesWritten = true
        return snapshot
    }

    static func seed(_ store: MachineReadinessStore, model: AppModel, script: Script? = nil,
                     cliVersion: String = "0.7.24", outdated: Bool = false) {
        let runner = script.map { ProcessPrepareRunner(cli: { [path = write($0)] in
            DevmachineCLI(executable: path, runner: DemoMode.runner)
        }) }
        store.seedDemo(
            snapshot: snapshot(cliVersion: cliVersion),
            observed: outdated
                ? ["backup": .outdated(detail: #"error: devmachine-app does not accept "stats". It accepts context"#)]
                : [:],
            afterPrepare: snapshot(cliVersion: cliVersion, applied: true),
            runner: runner)
        model.seedDemoSessionProblem(.aliasMissing(alias: "initech-devmachine"), alias: "initech-devmachine")
    }

    static func card(_ store: MachineReadinessStore, model: AppModel, machine: String) -> some View {
        MachineReadinessCard(store: store, machine: machine)
            .environmentObject(model)
            .dmGlass(radius: DMRadius.panel, stroke: .white.opacity(0.15))
            .frame(width: 520)
            .padding(24)
            .background(Color.dmContentBg)
            .environment(\.colorScheme, .dark)
    }

    static func installer(_ script: Script?) -> CLIInstallModel {
        CLIInstallModel(
            plan: .homebrew(brew: "/opt/homebrew/bin/brew"),
            runner: DemoInstallRunner(script: script.map(write)),
            findsCLI: { false })
    }

    private static func write(_ script: Script) -> String {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("devmachine-demo-ready-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("devmachine").path
        try? Data(body(script).utf8).write(to: URL(fileURLWithPath: path))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private static func body(_ script: Script) -> String {
        let plan = """
            echo "staging: devmachine-app"
            echo ""
            echo "PLAY [devmachine] *************************************************"
            echo ""
            echo "TASK [Gathering Facts] ********************************************"
            echo "ok: [devmachine]"
            echo ""
            echo "TASK [devmachine-app : Create the config directory] ***************"
            echo "changed: [devmachine]"
            """
        let add = "if [ \"$1\" = packages ]; then echo 'added devmachine-app to machine staging'; exit 0; fi\n"
        switch script {
        case .prepareSlow:
            return "#!/bin/sh\n" + add + "\(plan)\nsleep 8\n"
        case .prepareFails:
            return "#!/bin/sh\n" + add + "\(plan)\n"
                + "echo 'fatal: [devmachine]: FAILED! => {\"msg\": \"Permission denied\"}'\n"
                + "echo 'error: 1 task(s) failed on staging: exit status 2' 1>&2\nexit 1\n"
        case .prepareSucceeds:
            return "#!/bin/sh\n" + add + "\(plan)\necho ''\necho 'staging: ok=3 changed=1 failed=0'\n"
        case .installSlow:
            return "#!/bin/sh\necho '==> Fetching mydevmachine/tap/devmachine'\n"
                + "echo '==> Downloading https://example.com/devmachine_0.7.24_darwin_arm64.tar.gz'\nsleep 8\n"
        case .installFails:
            return "#!/bin/sh\necho '==> Fetching mydevmachine/tap/devmachine'\n"
                + "echo 'Error: Failure while executing; `curl` exited with 6.' 1>&2\nexit 1\n"
        }
    }
}

private struct DemoInstallRunner: CLIInstallRunning {
    let script: String?

    func run(_ plan: CLIInstallPlan, output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        guard let script else { return 0 }
        return try await StreamingProcess.run(
            executable: script, arguments: [], environment: ProcessInfo.processInfo.environment, output: output)
    }
}
#endif
