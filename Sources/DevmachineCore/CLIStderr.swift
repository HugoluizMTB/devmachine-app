import Foundation

/// What a failed devmachine command printed about why. A command that syncs
/// prints the whole Ansible run on stderr first, so the reason is its last
/// `error:` line, not the start of the stream.
public enum CLIStderr {
    private static let prefix = "error: "

    public static func reason(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n", omittingEmptySubsequences: false)
        if let last = lines.last(where: { $0.hasPrefix(prefix) }) {
            return String(last.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
