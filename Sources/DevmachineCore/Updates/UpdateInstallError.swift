import Foundation

public enum UpdateInstallError: LocalizedError, Equatable {
    case noDiskImage(version: String)
    case digestMismatch(expected: String, actual: String)
    case mountFailed(String)
    case noAppInImage
    case wrongBundleID(String?)
    case wrongVersion(expected: String, found: String?)
    case signatureInvalid(String)
    case teamMismatch(expected: String, found: String?)
    case runningAppNotSigned
    case gatekeeperRejected(String)
    case swapFailed(rolledBack: Bool, reason: String)
    case homebrewFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .noDiskImage(let version):
            return "The \(version) release has no Devmachine-\(version).dmg."
        case let .digestMismatch(expected, actual):
            return "The download's sha256 is \(actual), but the release publishes \(expected)."
        case .mountFailed(let detail):
            return "The disk image did not open: \(detail)"
        case .noAppInImage:
            return "The disk image holds no Devmachine.app."
        case .wrongBundleID(let found):
            return "The app in the disk image is \(found ?? "unnamed"), not Devmachine."
        case let .wrongVersion(expected, found):
            return "The app in the disk image is version \(found ?? "unknown"), not \(expected)."
        case .signatureInvalid(let detail):
            return "The new app's code signature is not valid: \(detail)"
        case let .teamMismatch(expected, found):
            return "The new app is signed by team \(found ?? "none"), not \(expected)."
        case .runningAppNotSigned:
            return "This copy has no Developer ID signature, so it cannot tell a genuine update from another app."
        case .gatekeeperRejected(let detail):
            return "Gatekeeper refused the new app: \(detail)"
        case let .swapFailed(rolledBack, reason):
            return rolledBack
                ? "The new app could not be moved in, and the current one was put back: \(reason)"
                : "The new app could not be moved in: \(reason)"
        case .homebrewFailed(let status):
            return "brew exited with status \(status)."
        }
    }
}
