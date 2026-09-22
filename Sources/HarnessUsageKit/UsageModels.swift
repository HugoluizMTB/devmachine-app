import Foundation

public enum UsageBlockKind: Equatable, Sendable {
    case session
    case weeklyAll
    case weeklyModel
}

public struct UsageBlock: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: UsageBlockKind
    public let label: String
    public let percent: Int
    public let resets: String

    public init(id: UUID = UUID(), kind: UsageBlockKind, label: String, percent: Int, resets: String) {
        self.id = id
        self.kind = kind
        self.label = label
        self.percent = percent
        self.resets = resets
    }
}

public struct DayTokens: Equatable, Sendable, Identifiable {
    public let id: String
    public let date: String
    public let tokens: Int64

    public init(date: String, tokens: Int64) {
        self.id = date
        self.date = date
        self.tokens = tokens
    }
}

public struct ModelTokens: Equatable, Sendable, Identifiable {
    public let id: String
    public let model: String
    public let tokens: Int64

    public init(model: String, tokens: Int64) {
        self.id = model
        self.model = model
        self.tokens = tokens
    }
}

public struct UsageStats: Equatable, Sendable {
    public let dailyTotals: [DayTokens]
    public let modelTotals: [ModelTokens]
    public let todayTokens: Int64
    public let mostUsedModel: String?

    public init(dailyTotals: [DayTokens], modelTotals: [ModelTokens], todayTokens: Int64, mostUsedModel: String?) {
        self.dailyTotals = dailyTotals
        self.modelTotals = modelTotals
        self.todayTokens = todayTokens
        self.mostUsedModel = mostUsedModel
    }
}
