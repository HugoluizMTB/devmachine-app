public struct TmuxSession: Equatable, Identifiable, Sendable {
    public let name: String
    public let windows: Int
    public let hasClaude: Bool
    public var id: String { name }

    public init(name: String, windows: Int, hasClaude: Bool) {
        self.name = name
        self.windows = windows
        self.hasClaude = hasClaude
    }
}
