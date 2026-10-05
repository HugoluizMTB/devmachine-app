import Foundation

/// When the corner toast offers a newer devmachine CLI. "Later" hides one
/// version and every older one, so the toast comes back only for a newer
/// release. A running or just finished update stays on screen whatever
/// Later said: the person started it from there.
public enum CLIUpdateToast {
    public enum Stage: Equatable, Sendable {
        case idle
        case running
        case updated(closed: Bool)
        case failed
        case manual
    }

    public static func shows(stage: Stage, latest: SemanticVersion?, laterVersion: String?) -> Bool {
        switch stage {
        case .running:
            return true
        case .updated(let closed):
            return !closed
        case .idle, .failed, .manual:
            guard let latest else { return false }
            return !isPutOff(latest, laterVersion: laterVersion)
        }
    }

    public static func isPutOff(_ latest: SemanticVersion, laterVersion: String?) -> Bool {
        guard let later = laterVersion.flatMap({ SemanticVersion($0) }) else { return false }
        return latest <= later
    }
}
