import Foundation
import DevmachineCore

/// Whether every configured machine has what the app needs to read stats,
/// Caddy logs, and subdomain logs through the CLI instead of raw ssh. `.ok`
/// also covers "could not tell" (offline, `packages` too old): the gate fails
/// open rather than locking the person out of a Mac that just lost network.
enum PackageGateState: Equatable, Sendable {
    case ok
    case missing(machines: [String])
}

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

enum PackageGateChecker {
    static func check(cli: @Sendable () throws -> DevmachineCLI) -> PackageGateState {
        guard let instance = try? cli() else { return .ok }
        guard let machines = try? instance.nonSelfMachines(), !machines.isEmpty else { return .ok }
        guard let packages = try? instance.packages() else { return .ok }
        let devmachineApp = packages.first { $0.name == "devmachine-app" }
        let missing = machines
            .map(\.name)
            .filter { !(devmachineApp?.isInstalled(onMachine: $0) ?? false) }
        return missing.isEmpty ? .ok : .missing(machines: missing)
    }
}
