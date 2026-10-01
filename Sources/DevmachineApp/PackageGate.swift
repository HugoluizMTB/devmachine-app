import Foundation
import DevmachineCore

enum PackageGateMessage {
    /// An old release of `devmachine-app` does not know a command yet — not a
    /// connection error, and the fix is `packages pin` + `sync`, never "add
    /// the package" (it is already there).
    static func friendly(for error: Error) -> String {
        if let cliError = error as? DevmachineCLIError, cliError.isUnknownPackageCommand {
            return "This machine's devmachine-app package is out of date. "
                + "Run `devmachine packages pin` then `devmachine sync --machine <machine>`."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Whether the Subdomains icon has anything to show for: at least one
/// configured (non-self) machine has Caddy, directly or through
/// `essentials`. A read that itself fails leaves the icon as it was, the
/// same fail-open the package gate uses — a flaky CLI should not hide a
/// working feature.
enum CaddyAvailabilityChecker {
    static func check(cli: @Sendable () throws -> DevmachineCLI) -> Bool? {
        guard let instance = try? cli() else { return nil }
        guard let machines = try? instance.nonSelfMachines() else { return nil }
        guard let packages = try? instance.packages() else { return nil }
        let installedByMachine = machines.map { machine in
            Set(packages.filter { $0.isInstalled(onMachine: machine.name) }.map(\.name))
        }
        return CaddyDetection.anyMachineHasCaddy(installedPackageNamesByMachine: installedByMachine)
    }
}
