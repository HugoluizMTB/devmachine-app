public struct Workspace: Equatable, Identifiable, Sendable {
    public let name: String
    public let alias: String
    public var id: String { alias }

    public init(name: String, alias: String) {
        self.name = name
        self.alias = alias
    }
}
