import Foundation

/// Reads a widget's source with the rules the CLI validator also applies,
/// so the app never runs something the CLI would have refused.
public enum WidgetSourceReader {
    /// Go's `\s` is ASCII only, and Go matches runes, not grapheme clusters.
    static var templatePattern: Regex<(Substring, Substring)> {
        /\{\{[\t\n\f\r ]*([^}]*?)[\t\n\f\r ]*\}\}/.matchingSemantics(.unicodeScalar)
    }
    static var referencePattern: Regex<(Substring, Substring, Substring)> {
        /(inputs|context)\.([a-z][a-z0-9_-]*)/.matchingSemantics(.unicodeScalar)
    }
    static var listReferencePattern: Regex<Substring> {
        /item(?:\.[A-Za-z0-9_-]+)*/.matchingSemantics(.unicodeScalar)
    }

    public static func read(
        _ value: WidgetValue, scope: WidgetScope, contract: WidgetContract = .current
    ) throws -> WidgetSource {
        guard let fields = value.object else {
            throw WidgetSpecProblem([], "source must be a mapping with a kind")
        }
        let kinds = contract.sourceKinds.joined(separator: ", ")
        guard let kind = fields["kind"]?.string, !kind.isEmpty else {
            throw WidgetSpecProblem(["kind"], "every widget needs source.kind: it is one of \(kinds)")
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

    /// The CLI's message for the first template in `text` it refuses, or nil.
    static func templateProblem(in text: String, label: String, scope: WidgetScope) -> String? {
        for match in text.matches(of: templatePattern) {
            let template = String(match.0)
            if match.1.wholeMatch(of: listReferencePattern) != nil {
                return "template \(template) in \(label): item only works inside a list view's item"
            }
            guard let reference = match.1.wholeMatch(of: referencePattern) else {
                return "template \(template) in \(label) names neither inputs.<name> nor context.<name>"
            }
            let name = String(reference.2)
            if reference.1 == "inputs" {
                guard let inputs = scope.inputs else {
                    return "template \(template) in \(label): a widget written in a board has no inputs"
                }
                if !inputs.contains(name) { return "template \(template) in \(label) needs inputs.\(name)" }
            } else if !scope.contextKeys.contains(name) {
                return "template \(template) in \(label) needs context.\(name) to be declared"
            }
        }
        return nil
    }

    private static func label(_ path: [String]) -> String {
        path.reduce("source") { label, part in
            Int(part) != nil ? "\(label)[\(part)]" : "\(label).\(part)"
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
            if let problem = templateProblem(in: text, label: label(path), scope: scope) {
                throw WidgetSpecProblem(path, problem)
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

        /// The CLI decodes into Go fields, so an empty or null value is the
        /// same as a field not written.
        func given(_ key: String) -> WidgetValue? {
            switch fields[key] {
            case nil, .null?, .string("")?: return nil
            case let value?: return value
            }
        }

        func text(_ key: String) throws -> String? {
            guard let value = given(key) else { return nil }
            guard let text = Self.scalar(value) else { throw WidgetSpecProblem([key], "source.\(key) must be text") }
            return text
        }

        static func scalar(_ value: WidgetValue) -> String? {
            switch value {
            case .string, .int, .double, .bool, .null: return value.text
            case .list, .object: return nil
            }
        }

        func required(_ key: String) throws -> String {
            guard let value = try text(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WidgetSpecProblem([key], "a \(kind) source needs source.\(key)")
            }
            return value
        }

        func bool(_ key: String) throws -> Bool {
            guard let value = given(key) else { return spec.fields[key]?.defaultValue?.bool ?? false }
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
            guard let value = given(key) else { return [] }
            guard let items = value.list else { throw WidgetSpecProblem([key], "source.\(key) must be a list") }
            return try items.enumerated().map { index, item in
                guard let text = Self.scalar(item) else {
                    throw WidgetSpecProblem([key, String(index)], "source.\(key)[\(index)] must be one value")
                }
                return text
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
            let help = "write local, {machine: <name>} or {workspace: <name>}"
            guard let value = fields["target"], value != .null else { return .local }
            switch value {
            case .string("local"):
                return .local
            case let .object(object):
                var machine = ""
                var workspace = ""
                for key in object.keys.sorted() {
                    guard let name = object[key].flatMap(Self.scalar) else {
                        throw WidgetSpecProblem(["target"], "source.target: \(help)")
                    }
                    switch key {
                    case "machine": machine = name
                    case "workspace": workspace = name
                    default: throw WidgetSpecProblem(["target"], "source.target has an unknown key \"\(key)\": \(help)")
                    }
                }
                guard machine.isEmpty != workspace.isEmpty else {
                    throw WidgetSpecProblem(["target"], "source.target names one machine or one workspace: \(help)")
                }
                return machine.isEmpty ? .workspace(workspace) : .machine(machine)
            case .list:
                throw WidgetSpecProblem(["target"], "source.target: \(help)")
            default:
                throw WidgetSpecProblem(["target"], "source.target \"\(value.text)\": \(help)")
            }
        }

        func provider() throws -> ProviderSource {
            let name = try text("name") ?? ""
            guard let provider = contract.providers[name] else {
                let known = contract.providers.keys.sorted().joined(separator: ", ")
                throw WidgetSpecProblem(
                    ["name"], "source.name \"\(name)\" is not a provider engine \(contract.engine) knows: \(known)")
            }
            var with: [String: String] = [:]
            if let value = given("with") {
                guard let arguments = value.object else {
                    throw WidgetSpecProblem(["with"], "source.with is a mapping of argument names to values")
                }
                for key in arguments.keys.sorted() {
                    guard provider.args[key] != nil else {
                        throw WidgetSpecProblem(["with", key], "source.with.\(key) is not an argument of \(name)")
                    }
                    guard let text = arguments[key].flatMap(Self.scalar) else {
                        throw WidgetSpecProblem(["with", key], "source.with.\(key) must be one value")
                    }
                    with[key] = text
                }
            }
            for key in provider.args.keys.sorted() where provider.args[key]?.required == true && with[key] == nil {
                throw WidgetSpecProblem(["with"], "source.with.\(key) is required by \(name)")
            }
            guard let every = try text("every") else {
                throw WidgetSpecProblem(
                    ["every"], "every widget needs source.every, at least \(provider.minEvery) for \(name)")
            }
            guard let seconds = GoDuration.seconds(every) else {
                throw WidgetSpecProblem(["every"], "source.every \"\(every)\" is not a duration: write it like 60s or 5m")
            }
            if let minimum = GoDuration.seconds(provider.minEvery), seconds < minimum {
                throw WidgetSpecProblem(
                    ["every"], "source.every \(every) is below the \(name) minimum of \(provider.minEvery)")
            }
            return ProviderSource(name: name, with: with, every: every)
        }

        func command(scope: WidgetScope) throws -> CommandSource {
            let run = try text("run")
            let script = try text("script")
            switch (run, script) {
            case (.some, .some): throw WidgetSpecProblem(["script"], "a command source has run or script, not both")
            case (nil, nil): throw WidgetSpecProblem([], "a command source needs run or script")
            default: break
            }
            let shell = try bool("shell")
            let args = try list("args")
            if let refused = ArgvBuilder.refusal(CommandSource(
                run: run, script: script, args: args, shell: shell, target: .local, every: .manual, timeout: 0, mode: .poll,
                keep: 0, parse: .text)) {
                throw WidgetSpecProblem([refused.field], refused.message)
            }
            if let run, !shell, Self.hasSpaceOutsideTemplates(run) {
                throw WidgetSpecProblem(
                    ["run"],
                    "source.run \"\(run)\" has spaces: put each argument in source.args, or set shell: true to run it as a shell line")
            }
            if let run, !shell { try checkProgramWord(run) }
            if let script { try checkScript(script, scope: scope) }
            let mode = CommandMode(rawValue: try choice("mode")) ?? .poll
            let parse = ParseMode(rawValue: try choice("parse")) ?? .text
            var keep = spec.fields["keep"]?.defaultValue?.number.map(Int.init) ?? 200
            if let value = given("keep"), value.number != 0 {
                guard mode == .stream else { throw WidgetSpecProblem(["keep"], "source.keep is only for mode: stream") }
                guard let number = value.number, number == number.rounded(), (1...2000).contains(Int(number)) else {
                    throw WidgetSpecProblem(["keep"], "source.keep \(value.text) is outside 1 to 2000 lines")
                }
                keep = Int(number)
            }
            let every: WidgetEvery
            let timeout: TimeInterval
            if mode == .stream {
                if given("every") != nil {
                    throw WidgetSpecProblem(["every"], "a stream runs while the widget is on screen: remove source.every")
                }
                if given("timeout") != nil {
                    throw WidgetSpecProblem(["timeout"], "a stream has no timeout: remove source.timeout")
                }
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
                run: run, script: script, args: args, shell: shell, target: try target(), every: every,
                timeout: timeout, mode: mode, keep: keep, parse: parse)
        }

        private func checkProgramWord(_ run: String) throws {
            let program = run.replacing(WidgetSourceReader.templatePattern, with: "x")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if program.hasPrefix("-") {
                throw WidgetSpecProblem(
                    ["run"],
                    "source.run \"\(run)\" starts with -: a program name never does — name the program, and put options in source.args")
            }
            if program.contains("=") {
                throw WidgetSpecProblem(
                    ["run"],
                    "source.run \"\(run)\" has =: it reads as a variable to set, not a program — name the program, or set shell: true")
            }
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
