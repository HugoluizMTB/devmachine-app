import Foundation
import DevmachineCore

protocol MachineJobRunning: Sendable {
    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32
}

/// Runs a `devmachine` command in the background, never in a terminal
/// session, with the same ssh agent the rest of the app hands the CLI.
struct ProcessJobRunner: MachineJobRunning {
    var cli: @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }

    func run(arguments: [String], output: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        guard !DemoMode.isActive else {
            throw DevmachineCLIError.commandFailed("Demo mode never runs a devmachine command.")
        }
        let instance = try cli()
        return try await StreamingProcess.run(
            executable: instance.executable, arguments: arguments,
            environment: LimaInstall.environment(
                base: CLISelfUpdate.environment(base: instance.environment()), home: NSHomeDirectory()),
            output: output)
    }
}
