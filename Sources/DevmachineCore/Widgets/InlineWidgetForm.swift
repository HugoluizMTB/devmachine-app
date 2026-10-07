import Foundation

/// The five kinds of widget the app can make by itself.
public enum InlineWidgetTemplate: String, CaseIterable, Sendable, Identifiable {
    case command
    case urlStatus = "url-status"
    case webPage = "web-page"
    case prompt
    case session

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .command: return "Command"
        case .urlStatus: return "URL status"
        case .webPage: return "Web page"
        case .prompt: return "Prompt"
        case .session: return "Session"
        }
    }

    public var summary: String {
        switch self {
        case .command: return "Run a command here or on a machine and show its output."
        case .urlStatus: return "Check that an address answers."
        case .webPage: return "Show a web page."
        case .prompt: return "Ask a coding harness and show the answer."
        case .session: return "Show the screen of a session."
        }
    }

    public var preset: String { self == .webPage || self == .session ? "large" : "medium" }

    /// The menu bar draws one line, so only what can end in one is offered.
    public static func offered(on layout: String) -> [InlineWidgetTemplate] {
        layout == "slot" ? [.command, .urlStatus] : allCases
    }
}

public enum CommandStyle: String, Sendable {
    case program, shell
}

/// A problem the owner can fix, on its form field when the reader named one.
public struct FormProblem: Error, Equatable, Sendable {
    public let field: String?
    public let message: String

    public init(field: String?, message: String) {
        self.field = field
        self.message = message
    }
}

/// The new-widget and edit form. It never builds a widget by itself: it
/// writes a one-entry board and lets `BoardCodec` and the resolver read it,
/// so what the app saves is what the CLI and the board reader accept.
public struct InlineWidgetForm: Equatable, Sendable {
    public var template: InlineWidgetTemplate
    public var title = ""
    public var commandStyle = CommandStyle.program
    public var run = ""
    public var args = ""
    public var shellLine = ""
    public var target = WidgetTarget.local
    public var every = "60s"
    public var parse = "text"
    public var view = "text"
    public var value = ""
    public var url = ""
    public var zoom = "1"
    public var harness = "claude"
    public var prompt = ""
    public var session = ""

    public init(template: InlineWidgetTemplate) {
        self.template = template
        switch template {
        case .command: break
        case .urlStatus:
            parse = "status"
            view = "status"
        case .webPage:
            every = "manual"
            view = "web"
        case .prompt:
            every = "manual"
            view = "markdown"
        case .session:
            every = "5s"
            view = "terminal"
        }
    }

    /// Nil when the templates cannot show this widget as it is; the editor
    /// then offers the title only and keeps the rest as written.
    public init?(inline: InlineWidget, surface: String, contract: WidgetContract = .current) {
        var form: InlineWidgetForm
        switch inline.source {
        case let .command(command):
            guard command.script == nil, command.mode == .poll else { return nil }
            form = InlineWidgetForm(template: .command)
            if command.shell {
                form.commandStyle = .shell
                form.shellLine = command.run ?? ""
            } else {
                form.run = command.run ?? ""
                form.args = command.args.joined(separator: "\n")
            }
            form.target = command.target
            form.parse = command.parse.rawValue
        case let .url(url):
            form = InlineWidgetForm(template: inline.view.kind == "web" ? .webPage : .urlStatus)
            form.url = url.url
            form.zoom = inline.viewTree.value["zoom"]?.text ?? "1"
        case let .prompt(prompt):
            form = InlineWidgetForm(template: .prompt)
            form.harness = prompt.harness.rawValue
            form.prompt = prompt.prompt
            form.target = prompt.target
        case let .session(session):
            form = InlineWidgetForm(template: .session)
            form.target = session.target
            form.session = session.session
        default:
            return nil
        }
        guard let every = Self.text(of: inline.source.every) else { return nil }
        form.title = inline.title
        form.every = every
        form.view = inline.view.kind
        form.value = inline.view.value ?? ""
        guard let again = try? form.read(surface: surface, id: "check", contract: contract).get(),
              again.source == inline.source, again.view == inline.view
        else { return nil }
        self = form
    }

    public static func views(for parse: String, layout: String, contract: WidgetContract = .current) -> [String] {
        contract.views.keys.filter { kind in
            !kind.hasPrefix("app.") && contract.view(kind, accepts: parse, sourceKind: "command")
                && (layout != "slot" || contract.slotEntry.views.contains(kind))
                && (contract.views[kind]?.layouts.map { $0.contains(layout) } ?? true)
        }.sorted()
    }

    public func read(
        surface: String, id: String, keeping old: InlineWidget? = nil, catalog: WidgetCatalog? = nil,
        contract: WidgetContract = .current
    ) -> Result<InlineWidget, FormProblem> {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(FormProblem(field: "title", message: "Give the widget a title."))
        }
        let built = yaml(surface: surface, id: id, contract: contract)
        let canvas = contract.layout(of: surface) == "canvas"
        let inline: InlineWidget
        do {
            let read = canvas
                ? try BoardCodec.decode(built.text, contract: contract).widgets.first?.inline
                : try BoardCodec.decodeStack(built.text, contract: contract).entries.first?.inline
            guard let read else { return .failure(FormProblem(field: nil, message: "The widget could not be read.")) }
            inline = read
        } catch let problem as BoardProblem {
            return .failure(FormProblem(field: problem.line.flatMap { built.fields[$0] }, message: Self.plain(problem.message, id: id)))
        } catch {
            return .failure(FormProblem(field: nil, message: "\(error)"))
        }
        if let reason = refusal(of: inline, surface: surface, id: id, catalog: catalog, contract: contract) {
            return .failure(FormProblem(field: nil, message: Self.plain(reason, id: id)))
        }
        guard let old else { return .success(inline) }
        return .success(InlineWidget(
            title: inline.title,
            sourceTree: old.source == inline.source ? old.sourceTree : inline.sourceTree,
            viewTree: old.view == inline.view ? old.viewTree : inline.viewTree,
            sizes: old.sizes, fits: old.fits, source: inline.source, view: inline.view))
    }

    private func refusal(
        of inline: InlineWidget, surface: String, id: String, catalog: WidgetCatalog?, contract: WidgetContract
    ) -> String? {
        let resolution: WidgetResolution?
        if contract.layout(of: surface) == "canvas" {
            resolution = WidgetResolution.resolveInline(
                BoardWidget(id: id, type: "", frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 0, inline: inline),
                catalog: catalog, contract: contract)
        } else {
            let board = StackBoard(surface: surface, entries: [StackEntry(id: id, type: "", inline: inline)])
            resolution = StackResolution.resolve(board.entries[0], on: board, catalog: catalog, contract: contract)
        }
        switch resolution {
        case let .refused(_, reason)?, let .needsNewerApp(_, reason)?: return reason
        default: return nil
        }
    }

    /// One form field per line, so a reader's line names its field.
    public func yaml(surface: String, id: String, contract: WidgetContract = .current) -> (text: String, fields: [Int: String]) {
        var lines = ["format: 1", "surface: \(Self.block(surface))", "widgets:", "  - id: \(Self.block(id))"]
        var fields: [Int: String] = [:]
        func add(_ line: String, _ field: String?) {
            lines.append(line)
            if let field { fields[lines.count] = field }
        }
        add("    title: \(Self.block(title))", "title")
        let mainField: String
        switch template {
        case .command: mainField = commandStyle == .shell ? "shellLine" : "run"
        case .urlStatus, .webPage: mainField = "url"
        case .prompt: mainField = "prompt"
        case .session: mainField = "session"
        }
        add("    source:", mainField)
        switch template {
        case .command:
            add("      kind: command", commandStyle == .shell ? "shellLine" : "run")
            if commandStyle == .shell {
                add("      run: \(Self.block(shellLine))", "shellLine")
                add("      shell: true", "shellLine")
            } else {
                add("      run: \(Self.block(run))", "run")
                let words = args.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !words.isEmpty { add("      args: [\(words.map(Self.flow).joined(separator: ", "))]", "args") }
            }
            add("      target: \(targetText)", "target")
            add("      every: \(Self.block(every))", "every")
            add("      parse: \(Self.block(parse))", "parse")
        case .urlStatus, .webPage:
            add("      kind: url", "url")
            add("      url: \(Self.block(url))", "url")
            add("      every: \(Self.block(every))", "every")
            if template == .urlStatus { add("      parse: status", nil) }
        case .prompt:
            add("      kind: prompt", "prompt")
            add("      harness: \(Self.block(harness))", "harness")
            add("      prompt: \(Self.block(prompt))", "prompt")
            add("      target: \(targetText)", "target")
            add("      every: \(Self.block(every))", "every")
        case .session:
            add("      kind: session", "session")
            add("      target: \(targetText)", "target")
            add("      session: \(Self.block(session))", "session")
            add("      every: \(Self.block(every))", "every")
        }
        add("    view:", "view")
        add("      kind: \(Self.block(view))", "view")
        if template == .webPage { add("      zoom: \(zoomText)", "zoom") }
        if !value.isEmpty { add("      value: \(Self.block(value))", "value") }
        if contract.layout(of: surface) == "canvas" {
            add("    frame: {x: 0, y: 0, w: 320, h: 160}", nil)
            add("    size: medium", nil)
            add("    minimized: false", nil)
            add("    z: 1", nil)
        }
        return (lines.joined(separator: "\n") + "\n", fields)
    }

    private var zoomText: String {
        guard let number = Double(zoom), number.isFinite else { return Self.block(zoom) }
        return String(format: "%g", number)
    }

    private var targetText: String {
        switch target {
        case .local: return "local"
        case let .machine(name): return "{machine: \(Self.flow(name))}"
        case let .workspace(name): return "{workspace: \(Self.flow(name))}"
        }
    }

    private static func block(_ value: String) -> String { YAMLScalarStyle.text(value, in: .block, quoteYAML11Words: true) }
    private static func flow(_ value: String) -> String { YAMLScalarStyle.text(value, in: .flow, quoteYAML11Words: true) }

    static func text(of every: WidgetEvery) -> String? {
        switch every {
        case .manual: return "manual"
        case let .interval(seconds): return GoDurationText.short(seconds)
        case .continuous: return nil
        }
    }

    /// The reader names the widget; the form already shows which one.
    static func plain(_ message: String, id: String) -> String {
        for prefix in ["widget \"\(id)\" written in the board ", "widget \"\(id)\": ", "\(id): "] where message.hasPrefix(prefix) {
            let rest = message.dropFirst(prefix.count)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return message.prefix(1).uppercased() + message.dropFirst()
    }
}
