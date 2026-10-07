import Foundation

/// Reads a widget's source with the rules the CLI validator also applies,
/// so the app never runs something the CLI would have refused.
public enum WidgetSourceReader {
    static var templatePattern: Regex<(Substring, Substring)> { /\{\{\s*([^}]*?)\s*\}\}/ }
    private static var referencePattern: Regex<(Substring, Substring, Substring)> {
        /(inputs|context)\.([a-z][a-z0-9_-]*)/
    }
    private static var listReferencePattern: Regex<Substring> { /item(?:\.[A-Za-z0-9_-]+)*/ }

    public static func read(
        _ value: WidgetValue, scope: WidgetScope, contract: WidgetContract = .current
    ) throws -> WidgetSource {
        guard let fields = value.object else {
            throw WidgetSpecProblem([], "source must be a mapping with a kind")
        }
        let kinds = contract.sourceKinds.joined(separator: ", ")
        guard let kind = fields["kind"]?.string else {
            throw WidgetSpecProblem(["kind"], "source.kind is missing; it is one of \(kinds)")
        }
        guard contract.sourceKinds.contains(kind), let spec = contract.sources[kind] else {
            throw WidgetSpecProblem(["kind"], "source.kind \"\(kind)\" is not one of \(kinds)")
        }
        for key in fields.keys.sorted() where key != "kind" && spec.fields[key] == nil {
            throw WidgetSpecProblem([key], "source.\(key) is not a field of a \(kind) source")
        }
        try checkTemplates(fields.filter { $0.key != "script" }, path: [], scope: scope)
        let reader = Fields(fields: fields, spec: spec, kind: kind, contract: contract)
        switch kind {
        case "provider": return .provider(try reader.provider())
        case "command": return .command(try reader.command(scope: scope))
        case "url": return .url(try reader.url())
        case "prompt": return .prompt(try reader.prompt())
        default: return .session(try reader.session())
        }
    }

    private static func checkTemplates(_ fields: [String: WidgetValue], path: [String], scope: WidgetScope) throws {
        for key in fields.keys.sorted() {
            try checkTemplates(in: fields[key] ?? .null, path: path + [key], scope: scope)
        }
    }

    private static func checkTemplates(in value: WidgetValue, path: [String], scope: WidgetScope) throws {
        switch value {
        case let .string(text):
            for match in text.matches(of: templatePattern) {
                let template = String(match.0)
                let field = "source." + path.joined(separator: ".")
                if match.1.wholeMatch(of: listReferencePattern) != nil {
                    throw WidgetSpecProblem(
                        path, "template \(template) in \(field): item only works inside a list view's item")
                }
                guard let reference = match.1.wholeMatch(of: referencePattern) else {
                    throw WidgetSpecProblem(
                        path, "template \(template) in \(field) names neither inputs.<name> nor context.<name>")
                }
                guard case let .inline(keys) = scope else { continue }
                if reference.1 == "inputs" {
                    throw WidgetSpecProblem(
                        path, "template \(template) in \(field): a widget written in a board has no inputs")
                }
                if !keys.contains(String(reference.2)) {
                    throw WidgetSpecProblem(
                        path, "template \(template) in \(field) needs context.\(reference.2), which this board does not give")
                }
            }
        case let .list(items):
            for (index, item) in items.enumerated() {
                try checkTemplates(in: item, path: path + [String(index)], scope: scope)
            }
        case let .object(fields):
            try checkTemplates(fields, path: path, scope: scope)
        default:
            break
        }
    }

    private struct Fields {
        let fields: [String: WidgetValue]
        let spec: WidgetContract.SourceSpec
        let kind: String
        let contract: WidgetContract

        func has(_ key: String) -> Bool { fields[key] != nil }

        func text(_ key: String) throws -> String? {
            guard let value = fields[key] else { return nil }
            switch value {
            case .string, .int, .double: return value.text
            default: throw WidgetSpecProblem([key], "source.\(key) must be text")
            }
        }

        func required(_ key: String) throws -> String {
            guard let value = try text(key), !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw WidgetSpecProblem([key], "a \(kind) source needs source.\(key)")
            }
            return value
        }

        func bool(_ key: String) throws -> Bool {
            guard let value = fields[key] else { return spec.fields[key]?.defaultValue?.bool ?? false }
            guard let flag = value.bool else { throw WidgetSpecProblem([key], "source.\(key) must be true or false") }
            return flag
        }

        func choice(_ key: String) throws -> String {
            let allowed = spec.fields[key]?.values ?? []
            guard let value = try text(key) ?? spec.fields[key]?.defaultValue?.string else {
                throw WidgetSpecProblem([key], "a \(kind) source needs source.\(key): \(allowed.joined(separator: ", "))")
            }
            guard allowed.contains(value) else {
                throw WidgetSpecProblem([key], "source.\(key) \"\(value)\" is one of \(allowed.joined(separator: ", "))")
            }
            return value
        }

        func list(_ key: String) throws -> [String] {
            guard let value = fields[key] else { return [] }
            guard let items = value.list else { throw WidgetSpecProblem([key], "source.\(key) must be a list") }
            return try items.enumerated().map { index, item in
                switch item {
                case .string, .int, .double, .bool: return item.text
                default: throw WidgetSpecProblem([key, String(index)], "source.\(key)[\(index)] must be one value")
                }
            }
        }

        func every(required: Bool) throws -> WidgetEvery {
            let minimum = contract.sources[kind]?.minEvery
            guard let text = try text("every") ?? spec.fields["every"]?.defaultValue?.string else {
                guard !required else {
                    let floor = minimum.map { ", at least \($0)," } ?? ""
                    throw WidgetSpecProblem(["every"], "a \(kind) source needs source.every\(floor) or manual")
                }
                return .manual
            }
            if text == "manual" { return .manual }
            guard let seconds = GoDuration.seconds(text) else {
                throw WidgetSpecProblem(["every"], "source.every \"\(text)\" is a duration such as 60s, or manual")
            }
            if let minimum, let floor = GoDuration.seconds(minimum), seconds < floor {
                throw WidgetSpecProblem(["every"], "source.every \(text) is below the \(kind) minimum of \(minimum)")
            }
            return .interval(seconds)
        }

        func timeout() throws -> TimeInterval {
            let field = spec.fields["timeout"]
            let text = try text("timeout") ?? field?.defaultValue?.string ?? "30s"
            guard let seconds = GoDuration.seconds(text) else {
                throw WidgetSpecProblem(["timeout"], "source.timeout \"\(text)\" is a duration such as 30s")
            }
            guard seconds > 0 else { throw WidgetSpecProblem(["timeout"], "source.timeout must be above 0") }
            if let maxText = field?.max?.string, let max = GoDuration.seconds(maxText), seconds > max {
                throw WidgetSpecProblem(["timeout"], "source.timeout \(text) is above the maximum of \(maxText)")
            }
            return seconds
        }

        func target() throws -> WidgetTarget {
            let shape = "source.target is local, {machine: <name>} or {workspace: <name>}"
            guard let value = fields["target"] else { return .local }
            if value.string == "local" { return .local }
            guard let object = value.object, object.count == 1, let (key, name) = object.first,
                  let text = name.string, !text.isEmpty
            else { throw WidgetSpecProblem(["target"], shape) }
            switch key {
            case "machine": return .machine(text)
            case "workspace": return .workspace(text)
            default: throw WidgetSpecProblem(["target"], shape)
            }
        }

        func provider() throws -> ProviderSource {
            let with = fields["with"]?.object?.mapValues(\.text) ?? [:]
            guard let every = try text("every") else {
                throw WidgetSpecProblem(["every"], "every widget needs source.every")
            }
            guard GoDuration.seconds(every) != nil else {
                throw WidgetSpecProblem(["every"], "source.every \"\(every)\" is a duration such as 60s")
            }
            return ProviderSource(name: try required("name"), with: with, every: every)
        }

        func command(scope: WidgetScope) throws -> CommandSource {
            let run = try text("run")
            let script = try text("script")
            switch (run, script) {
            case (.some, .some): throw WidgetSpecProblem(["script"], "a command source takes run or script, not both")
            case (nil, nil): throw WidgetSpecProblem([], "a command source needs run or script")
            default: break
            }
            let shell = try bool("shell")
            if let run, !shell, Self.hasSpaceOutsideTemplates(run) {
                throw WidgetSpecProblem(
                    ["run"], "source.run \"\(run)\" has spaces: put the arguments in args, or set shell: true")
            }
            if let script { try checkScript(script, scope: scope) }
            let mode = CommandMode(rawValue: try choice("mode")) ?? .poll
            let parse = ParseMode(rawValue: try choice("parse")) ?? .text
            let keepValue = spec.fields["keep"]?.defaultValue?.number.map(Int.init) ?? 200
            var keep = keepValue
            if let value = fields["keep"] {
                guard mode == .stream else { throw WidgetSpecProblem(["keep"], "source.keep is only for mode: stream") }
                guard let number = value.number, number == number.rounded(), (1...2000).contains(Int(number)) else {
                    throw WidgetSpecProblem(["keep"], "source.keep \(value.text) is outside 1 to 2000 lines")
                }
                keep = Int(number)
            }
            let every: WidgetEvery
            let timeout: TimeInterval
            if mode == .stream {
                if has("every") {
                    throw WidgetSpecProblem(["every"], "a stream runs while the widget is on screen: remove source.every")
                }
                if has("timeout") { throw WidgetSpecProblem(["timeout"], "a stream has no timeout: remove source.timeout") }
                guard [.text, .lines, .ansi].contains(parse) else {
                    throw WidgetSpecProblem(["parse"], "a stream reads text, lines or ansi, not \(parse.rawValue)")
                }
                every = .continuous
                timeout = 0
            } else {
                every = try self.every(required: true)
                timeout = try self.timeout()
            }
            return CommandSource(
                run: run, script: script, args: try list("args"), shell: shell, target: try target(), every: every,
                timeout: timeout, mode: mode, keep: keep, parse: parse)
        }

        private func checkScript(_ script: String, scope: WidgetScope) throws {
            if script.contains(WidgetSourceReader.templatePattern) {
                throw WidgetSpecProblem(["script"], "source.script cannot hold a template: it names one file")
            }
            switch scope {
            case .inline:
                guard script.hasPrefix("/") else {
                    throw WidgetSpecProblem(
                        ["script"], "source.script \"\(script)\": a widget written in a board names an absolute path on the target")
                }
            case .package:
                guard !script.hasPrefix("/"), Self.staysInside(script) else {
                    throw WidgetSpecProblem(
                        ["script"],
                        "source.script \"\(script)\": a package widget names a file inside its package, relative to package.yml")
                }
            }
        }

        static func staysInside(_ relative: String) -> Bool {
            var depth = 0
            for part in relative.split(separator: "/") where part != "." {
                depth += part == ".." ? -1 : 1
                if depth < 0 { return false }
            }
            return depth > 0
        }

        static func hasSpaceOutsideTemplates(_ text: String) -> Bool {
            text.replacing(WidgetSourceReader.templatePattern, with: "x")
                .trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isWhitespace)
        }

        func url() throws -> URLSource {
            let address = try required("url")
            guard address.hasPrefix("http://") || address.hasPrefix("https://") else {
                throw WidgetSpecProblem(["url"], "source.url \"\(address)\" starts with http:// or https://")
            }
            return URLSource(
                url: address, every: try every(required: true), timeout: try timeout(),
                parse: ParseMode(rawValue: try choice("parse")) ?? .status)
        }

        func prompt() throws -> PromptSource {
            PromptSource(
                harness: PromptHarness(rawValue: try choice("harness")) ?? .claude, prompt: try required("prompt"),
                target: try target(), every: try every(required: false), timeout: try timeout())
        }

        func session() throws -> SessionSource {
            SessionSource(target: try target(), session: try required("session"), every: try every(required: true))
        }
    }
}
