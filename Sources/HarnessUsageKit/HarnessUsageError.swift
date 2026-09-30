import SwiftUI

/// Why a harness could not report its usage, as far as the error lets us
/// tell. Only the likely cause shown to the person depends on it; the exact
/// error text is always kept next to it.
public enum HarnessUsageErrorKind: String, Equatable, Sendable, CaseIterable {
    case notSignedIn
    case cliNotFound
    case timedOut
    case unreadable
    case unknown

    public init(error: Error) {
        switch error {
        case CodexTransportError.executableUnavailable, UsageProviderError.executableNotFound:
            self = .cliNotFound
        case CodexTransportError.timedOut, UsageProviderError.timedOut:
            self = .timedOut
        case CodexTransportError.malformedResponse, CodexTransportError.missingResponse,
             UsageProviderError.decodeFailed:
            self = .unreadable
        case let CodexTransportError.rpcError(_, message):
            self.init(text: message)
        case let CodexTransportError.processFailed(_, stderr),
             let UsageProviderError.processFailed(_, stderr):
            self.init(text: stderr)
        default:
            self.init(text: HarnessUsageErrorKind.text(of: error))
        }
    }

    public init(text: String) {
        let lowered = text.lowercased()
        func mentions(_ needles: [String]) -> Bool { needles.contains { lowered.contains($0) } }
        if mentions(["not logged in", "not signed in", "log in", "login", "sign in", "unauthorized",
                     "unauthenticated", "authentication", "401"]) {
            self = .notSignedIn
        } else if mentions(["command not found", "no such file", "not found", "doesn't exist",
                            "doesn’t exist", "is unavailable"]) {
            self = .cliNotFound
        } else if mentions(["timed out", "timeout"]) {
            self = .timedOut
        } else if mentions(["malformed", "decode", "omitted response", "invalid json"]) {
            self = .unreadable
        } else {
            self = .unknown
        }
    }

    public func cause(tool: String) -> String? {
        switch self {
        case .notSignedIn: "\(tool) doesn't seem to be signed in."
        case .cliNotFound: "The \(tool) CLI wasn't found on this Mac."
        case .timedOut: "\(tool) took too long to answer."
        case .unreadable: "\(tool) sent back usage that couldn't be read."
        case .unknown: nil
        }
    }

    public var systemImage: String {
        switch self {
        case .notSignedIn: "person.crop.circle.badge.exclamationmark"
        case .cliNotFound: "terminal"
        case .timedOut: "clock.badge.exclamationmark"
        case .unreadable, .unknown: "exclamationmark.triangle"
        }
    }

    static func text(of error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// What a usage card shows in place of its numbers when the read failed.
public struct HarnessUsageErrorPresentation: Equatable, Sendable {
    public let title: String
    public let cause: String?
    public let details: String
    public let kind: HarnessUsageErrorKind

    public init(title: String, cause: String?, details: String, kind: HarnessUsageErrorKind) {
        self.title = title
        self.cause = cause
        self.details = details
        self.kind = kind
    }
}

/// Lets the app draw the error with its own components; the kit keeps a
/// plain fallback so it still works on its own.
public struct HarnessUsageErrorViewBuilder {
    let build: (HarnessUsageErrorPresentation, @escaping () -> Void) -> AnyView

    public init<V: View>(
        _ build: @escaping (HarnessUsageErrorPresentation, @escaping () -> Void) -> V
    ) {
        self.build = { AnyView(build($0, $1)) }
    }
}

private struct HarnessUsageErrorViewKey: EnvironmentKey {
    static var defaultValue: HarnessUsageErrorViewBuilder? { nil }
}

extension EnvironmentValues {
    public var harnessUsageErrorView: HarnessUsageErrorViewBuilder? {
        get { self[HarnessUsageErrorViewKey.self] }
        set { self[HarnessUsageErrorViewKey.self] = newValue }
    }
}

extension View {
    public func harnessUsageErrorView<V: View>(
        _ build: @escaping (HarnessUsageErrorPresentation, @escaping () -> Void) -> V
    ) -> some View {
        environment(\.harnessUsageErrorView, HarnessUsageErrorViewBuilder(build))
    }
}

struct HarnessUsageErrorFallback: View {
    let error: HarnessUsageErrorPresentation
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: error.kind.systemImage)
                .font(.title2)
                .foregroundColor(UsagePalette.secondaryText)
            Text(verbatim: error.title)
                .font(.headline)
                .foregroundColor(UsagePalette.primaryText)
            if let cause = error.cause {
                Text(verbatim: cause)
                    .font(.caption)
                    .foregroundColor(UsagePalette.secondaryText)
            }
            Button("Try again", action: onRetry)
        }
        .multilineTextAlignment(.center)
        .help(error.details)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
