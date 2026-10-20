import Foundation
import DevmachineCore

/// Everything the first-run setup checks before deciding what to show: the
/// CLI and its version, a configured machine, and the `devmachine-app`
/// package on every configured machine.
struct OnboardingDetection: Equatable, Sendable {
    var cliFound: Bool
    var adminMachine: String?
    /// Configured (non-self) machines that do not have `devmachine-app` yet —
    /// empty once every machine has it.
    var missingPackageMachines: [String]
    /// The CLI's version: the setup wizard needs `MachineUnattendedAdd.minimumCLIVersion`.
    var cliVersion: SemanticVersion? = nil

    var addsWithoutTerminal: Bool { MachineUnattendedAdd.isSupported(cliVersion: cliVersion) }

    static let empty = OnboardingDetection(cliFound: false, adminMachine: nil, missingPackageMachines: [])

    var isComplete: Bool { cliFound && adminMachine != nil && missingPackageMachines.isEmpty }
}

enum OnboardingDetector {
    static func detect(cli: () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }) -> OnboardingDetection {
        guard let instance = try? cli() else { return .empty }
        let cliVersion = (try? instance.version()).flatMap { SemanticVersion.first(in: $0) }
        let adminMachine = try? instance.resolveAdminMachine()
        var missingPackageMachines: [String] = []
        // Fails open, same as the machine readiness check: a `packages` read that
        // itself fails (offline, too old) leaves nothing "missing" rather
        // than blocking the setup on a flaky CLI.
        if let machines = try? instance.nonSelfMachines(), !machines.isEmpty,
           let packages = try? instance.packages() {
            let devmachineApp = packages.first { $0.name == MachinePackageCatalog.appPackage }
            missingPackageMachines = machines
                .map(\.name)
                .filter { !(devmachineApp?.isInstalled(onMachine: $0) ?? false) }
        }
        return OnboardingDetection(
            cliFound: true, adminMachine: adminMachine,
            missingPackageMachines: missingPackageMachines, cliVersion: cliVersion)
    }
}

/// The steps the Mac needs outside the wizard: the CLI first (the wizard
/// reads keys and packages through it), or, on a Mac already set up, the
/// package this app needs on each machine still missing it.
enum OnboardingPlan {
    static func prepareSteps(for detection: OnboardingDetection) -> [MachinePlanStep] {
        guard detection.cliFound else { return [.installCLI] }
        return detection.missingPackageMachines.flatMap { machine in
            [
                MachinePlanStep(
                    kind: .addPackage(MachinePackageCatalog.appPackage),
                    title: "Add \(MachinePackageCatalog.appPackage) to \(machine)",
                    arguments: ["packages", "add", MachinePackageCatalog.appPackage, "--machine", machine, "--yes"],
                    asksInTerminal: false),
                MachinePlanStep(
                    kind: .sync, title: "Sync \(machine)", arguments: ["sync", "--machine", machine, "--yes"],
                    asksInTerminal: false),
            ]
        }
    }

    /// What runs once the Mac is set up, before "You are all set": the
    /// packages release Home's widgets come from, then the machine answering.
    /// Home opens complete only after both.
    static func finishSteps(for detection: OnboardingDetection) -> [MachinePlanStep] {
        [.fetchPackages] + (detection.adminMachine.map { [.checkReady($0)] } ?? [])
    }
}
