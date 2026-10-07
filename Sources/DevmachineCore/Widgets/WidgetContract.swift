import Foundation

/// The widget engine contract this app implements. The CLI owns it
/// (`devmachine widgets schema --json`); `current` must equal the vendored
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

    public struct FieldSpec: Decodable, Equatable, Sendable {
        public let type: String
        public let required: Bool
        public let defaultValue: WidgetValue?
        public let values: [String]?
        public let min: WidgetValue?
        public let max: WidgetValue?
        public let fields: [String: FieldSpec]?

        enum CodingKeys: String, CodingKey {
            case type, required, values, min, max, fields
            case defaultValue = "default"
        }

        public init(
            type: String, required: Bool = false, defaultValue: WidgetValue? = nil, values: [String]? = nil,
            min: WidgetValue? = nil, max: WidgetValue? = nil, fields: [String: FieldSpec]? = nil
        ) {
            self.type = type
            self.required = required
            self.defaultValue = defaultValue
            self.values = values
            self.min = min
            self.max = max
            self.fields = fields
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
            defaultValue = try c.decodeIfPresent(WidgetValue.self, forKey: .defaultValue)
            values = try c.decodeIfPresent([String].self, forKey: .values)
            min = try c.decodeIfPresent(WidgetValue.self, forKey: .min)
            max = try c.decodeIfPresent(WidgetValue.self, forKey: .max)
            fields = try c.decodeIfPresent([String: FieldSpec].self, forKey: .fields)
        }
    }

    public struct SourceSpec: Decodable, Equatable, Sendable {
        public let minEvery: String?
        public let approval: Bool
        public let fields: [String: FieldSpec]

        enum CodingKeys: String, CodingKey {
            case approval, fields
            case minEvery = "min_every"
        }

        public init(minEvery: String?, approval: Bool, fields: [String: FieldSpec]) {
            self.minEvery = minEvery
            self.approval = approval
            self.fields = fields
        }
    }

    public struct ViewSpec: Decodable, Equatable, Sendable {
        public let accepts: [String]
        public let fields: [String: FieldSpec]?

        public init(accepts: [String], fields: [String: FieldSpec]? = nil) {
            self.accepts = accepts
            self.fields = fields
        }
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
    public let sources: [String: SourceSpec]
    public let formats: Formats

    enum CodingKeys: String, CodingKey {
        case engine, layouts, unit, snap, presets, surfaces, providers, views, sources, formats
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

    public func minimumInterval(forSource kind: String) -> TimeInterval? {
        sources[kind]?.minEvery.flatMap(GoDuration.seconds)
    }

    public func needsApproval(_ kind: String) -> Bool {
        sources[kind]?.approval ?? false
    }

    /// A source's output token (a parse value, or a provider's name), or
    /// `kind:<source kind>` for a view that takes anything of that kind.
    public func view(_ kind: String, accepts token: String?, sourceKind: String) -> Bool {
        guard let accepts = views[kind]?.accepts else { return false }
        if let token, accepts.contains(token) { return true }
        return accepts.contains("kind:" + sourceKind)
    }
}

extension WidgetContract {
    public static let current = engine11

    private static let target = FieldSpec(type: "target", defaultValue: .string("local"))
    private static let timeout = FieldSpec(type: "duration", defaultValue: .string("30s"), max: .string("10m"))

    public static let engine11 = WidgetContract(
        engine: "1.1",
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
            "text": ViewSpec(accepts: ["text", "lines", "ansi"], fields: [
                "wrap": FieldSpec(type: "bool", defaultValue: .bool(true)),
                "tail": FieldSpec(type: "int", min: .int(1), max: .int(2000)),
            ]),
            "number": ViewSpec(accepts: ["number", "json"], fields: [
                "value": FieldSpec(type: "template"),
                "unit": FieldSpec(type: "string"),
                "format": FieldSpec(
                    type: "enum", defaultValue: .string("plain"), values: ["plain", "percent", "bytes", "duration"]),
            ]),
            "gauge": ViewSpec(accepts: ["number", "json"], fields: [
                "value": FieldSpec(type: "template"),
                "min": FieldSpec(type: "number", defaultValue: .int(0)),
                "max": FieldSpec(type: "number", defaultValue: .int(100)),
                "unit": FieldSpec(type: "string"),
                "warn": FieldSpec(type: "number"),
                "crit": FieldSpec(type: "number"),
            ]),
            "status": ViewSpec(accepts: ["status", "number", "json", "text"], fields: [
                "value": FieldSpec(type: "template"),
                "ok": FieldSpec(type: "rule"),
                "warn": FieldSpec(type: "rule"),
            ]),
            "list": ViewSpec(accepts: ["lines", "json"], fields: [
                "item": FieldSpec(type: "object", fields: [
                    "title": FieldSpec(type: "template", defaultValue: .string("{{item}}")),
                    "subtitle": FieldSpec(type: "template"),
                    "status": FieldSpec(type: "template"),
                    "link": FieldSpec(type: "template"),
                ]),
            ]),
            "sparkline": ViewSpec(accepts: ["number", "json"], fields: [
                "value": FieldSpec(type: "template"),
                "unit": FieldSpec(type: "string"),
                "max": FieldSpec(type: "number"),
            ]),
            "markdown": ViewSpec(accepts: ["text"]),
            "web": ViewSpec(accepts: ["kind:url"], fields: [
                "zoom": FieldSpec(type: "number", defaultValue: .int(1), min: .double(0.5), max: .int(2)),
            ]),
            "terminal": ViewSpec(accepts: ["ansi", "text", "kind:session"], fields: [
                "tail": FieldSpec(type: "int", min: .int(1), max: .int(2000)),
            ]),
        ],
        sourceKinds: ["provider", "command", "url", "prompt", "session"],
        sources: [
            "provider": SourceSpec(minEvery: nil, approval: false, fields: [
                "name": FieldSpec(type: "provider", required: true),
                "with": FieldSpec(type: "args"),
                "every": FieldSpec(type: "duration", required: true),
            ]),
            "command": SourceSpec(minEvery: "5s", approval: true, fields: [
                "run": FieldSpec(type: "string"),
                "script": FieldSpec(type: "path"),
                "args": FieldSpec(type: "list"),
                "shell": FieldSpec(type: "bool", defaultValue: .bool(false)),
                "target": target,
                "every": FieldSpec(type: "every"),
                "timeout": timeout,
                "mode": FieldSpec(type: "enum", defaultValue: .string("poll"), values: ["poll", "stream"]),
                "keep": FieldSpec(type: "int", defaultValue: .int(200), min: .int(1), max: .int(2000)),
                "parse": FieldSpec(
                    type: "enum", defaultValue: .string("text"), values: ["text", "lines", "number", "json", "ansi"]),
            ]),
            "url": SourceSpec(minEvery: "5s", approval: false, fields: [
                "url": FieldSpec(type: "url", required: true),
                "every": FieldSpec(type: "every", required: true),
                "timeout": timeout,
                "parse": FieldSpec(type: "enum", defaultValue: .string("status"), values: ["status", "text", "json"]),
            ]),
            "prompt": SourceSpec(minEvery: "15m", approval: true, fields: [
                "harness": FieldSpec(type: "enum", required: true, values: ["claude", "codex"]),
                "prompt": FieldSpec(type: "string", required: true),
                "target": target,
                "every": FieldSpec(type: "every", defaultValue: .string("manual")),
                "timeout": FieldSpec(type: "duration", defaultValue: .string("5m"), max: .string("10m")),
            ]),
            "session": SourceSpec(minEvery: "2s", approval: true, fields: [
                "target": target,
                "session": FieldSpec(type: "string", required: true),
                "every": FieldSpec(type: "every", required: true),
            ]),
        ],
        formats: Formats(widget: 1, board: 1))
}
