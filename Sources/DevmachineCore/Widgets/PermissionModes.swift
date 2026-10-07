import Foundation

/// A prompt's permission mode, read from the contract: the harness's own
/// names, and which of them run without any check. The words match the CLI.
public enum PermissionModes {
    public static func names(for harness: String, contract: WidgetContract = .current) -> [String] {
        field(contract)?.byHarness?[harness] ?? []
    }

    public static func isDangerous(_ mode: String?, contract: WidgetContract = .current) -> Bool {
        guard let mode else { return false }
        return field(contract)?.dangerous?.contains(mode) ?? false
    }

    public static func listProblem(_ mode: String, harness: String, modes: [String]) -> String {
        "source.permission_mode \"\(mode)\": a \(harness) prompt takes \(modes.joined(separator: ", "))"
    }

    public static func timerProblem(_ mode: String) -> String {
        "permission_mode \(mode) runs without any check, so it runs only when you press refresh: write every: manual"
    }

    public static func warning(_ mode: String, harness: PromptHarness) -> String {
        "\(mode) runs without any check: \(harness == .claude ? "Claude" : "Codex") can change files and run commands without asking you."
    }

    private static func field(_ contract: WidgetContract) -> WidgetContract.FieldSpec? {
        contract.sources["prompt"]?.fields["permission_mode"]
    }
}
