import Foundation

/// The widget engine contract this app implements. The CLI owns it
/// (`devmachine widgets schema --json`); `engine10` must equal the vendored
/// golden copy, which `WidgetContractTests` checks.
public struct WidgetContract: Decodable, Equatable, Sendable {
    public struct Surface: Decodable, Equatable, Sendable {
        public let layout: String
        public let status: String
        public let context: [String: ContextSlot]
    }

    public struct ContextSlot: Decodable, Equatable, Sendable {
        public let type: String
        public let presence: String
    }

    public struct ProviderArg: Decodable, Equatable, Sendable {
        public let type: String
        public let required: Bool
    }

    public struct Provider: Decodable, Equatable, Sendable {
        public let args: [String: ProviderArg]
        public let minEvery: String
        public let returns: [String: String]

        enum CodingKeys: String, CodingKey {
            case args, returns
            case minEvery = "min_every"
        }
    }

    public struct ViewSpec: Decodable, Equatable, Sendable {
        public let accepts: [String]
    }

    public struct Formats: Decodable, Equatable, Sendable {
        public let widget: Int
        public let board: Int
    }

    public let engine: String
    public let layouts: [String]
    public let unit: Int
    public let snap: Int
    public let presets: [String: [Int]]
    public let surfaces: [String: Surface]
    public let contextTypes: [String: [String: String]]
    public let providers: [String: Provider]
    public let views: [String: ViewSpec]
    public let sourceKinds: [String]
    public let formats: Formats

    enum CodingKeys: String, CodingKey {
        case engine, layouts, unit, snap, presets, surfaces, providers, views, formats
        case contextTypes = "context_types"
        case sourceKinds = "source_kinds"
    }

    public static let presetOrder = ["small", "medium", "large", "wide", "tall"]

    public func presetCells(_ name: String) -> (columns: Int, rows: Int)? {
        guard let cells = presets[name], cells.count == 2 else { return nil }
        return (cells[0], cells[1])
    }

    public func minimumInterval(for provider: String) -> TimeInterval? {
        providers[provider].flatMap { GoDuration.seconds($0.minEvery) }
    }

    public func view(_ kind: String, accepts provider: String) -> Bool {
        views[kind]?.accepts.contains(provider) ?? false
    }
}

extension WidgetContract {
    public static let engine10 = WidgetContract(
        engine: "1.0",
        layouts: ["canvas", "stack", "slot"],
        unit: 80,
        snap: 8,
        presets: ["small": [2, 2], "medium": [4, 2], "large": [4, 4], "wide": [8, 2], "tall": [2, 4]],
        surfaces: [
            "home": Surface(layout: "canvas", status: "available", context: [:]),
            "sidebar": Surface(
                layout: "stack", status: "planned",
                context: ["selected": ContextSlot(type: "workspace", presence: "optional")]),
            "context-sidebar": Surface(
                layout: "stack", status: "planned",
                context: [
                    "machine": ContextSlot(type: "machine", presence: "always"),
                    "session": ContextSlot(type: "session", presence: "always"),
                    "workspace": ContextSlot(type: "workspace", presence: "optional"),
                    "path": ContextSlot(type: "path", presence: "optional"),
                    "repo": ContextSlot(type: "repo", presence: "optional"),
                    "branch": ContextSlot(type: "string", presence: "optional"),
                    "harness": ContextSlot(type: "string", presence: "optional"),
                ]),
        ],
        contextTypes: [
            "machine": ["name": "string"],
            "workspace": ["name": "string", "machine": "machine", "user": "string", "path": "path"],
            "session": ["name": "string", "kind": "string", "harness": "string?"],
            "repo": ["owner": "string", "name": "string"],
            "path": [:],
            "string": [:],
        ],
        providers: [
            "app/clock": Provider(
                args: [:], minEvery: "5s", returns: ["time": "string", "date": "string", "host": "string"]),
            "app/summary": Provider(
                args: [:], minEvery: "5s",
                returns: ["sessions": "int", "harness_sessions": "int", "workspaces": "int"]),
            "app/machines": Provider(args: [:], minEvery: "5s", returns: ["list": "machine_stats"]),
            "app/harness-usage": Provider(
                args: ["harness": ProviderArg(type: "string", required: true)], minEvery: "5s",
                returns: ["harness": "string", "windows": "list", "error": "string?"]),
        ],
        views: [
            "app.clock": ViewSpec(accepts: ["app/clock"]),
            "app.summary": ViewSpec(accepts: ["app/summary"]),
            "app.machines": ViewSpec(accepts: ["app/machines"]),
            "app.harness-usage": ViewSpec(accepts: ["app/harness-usage"]),
        ],
        sourceKinds: ["provider"],
        formats: Formats(widget: 1, board: 1))
}
