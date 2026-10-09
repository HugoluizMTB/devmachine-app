import Foundation

public struct SessionRowIndicators: Equatable, Sendable {
    public enum Leading: Equatable, Sendable { case none, spinner, attention }

    public let leading: Leading
    public let subtitle: String?
    public let age: String?

    public init(_ indicators: SessionIndicators?, settings: AppSettings) {
        guard let indicators else {
            leading = .none
            subtitle = nil
            age = nil
            return
        }
        if settings.showsAttention && indicators.attention {
            leading = .attention
        } else if settings.showsBusySpinner && indicators.busy {
            leading = .spinner
        } else {
            leading = .none
        }
        subtitle = settings.showsBranch ? Self.subtitle(branch: indicators.branch, path: indicators.path) : nil
        age = settings.showsSessionAge ? indicators.ageSeconds.map(Self.formatAge) : nil
    }

    public static func formatAge(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "<1m"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }

    private static func subtitle(branch: String?, path: String?) -> String? {
        if let branch, !branch.isEmpty { return branch }
        guard let path, !path.isEmpty, path != "/" else { return nil }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty || last == "/" ? nil : last
    }
}
