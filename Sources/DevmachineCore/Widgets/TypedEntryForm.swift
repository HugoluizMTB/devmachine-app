import Foundation

/// The edit form of a widget from a package: its title and refresh, and
/// its inputs as the catalog declares them. Choice inputs come from the
/// chooser; the rest are fields. Keys the widget does not declare stay.
public struct TypedEntryForm: Equatable, Sendable {
    public let entry: EditableEntry
    public let widget: CatalogWidget
    public var title: String
    public var every: String
    public var texts: [String: String] = [:]
    public var flags: [String: Bool] = [:]
    public var choices: [String: BoardScalar] = [:]

    public init(entry: EditableEntry, widget: CatalogWidget) {
        self.entry = entry
        self.widget = widget
        title = entry.titleOverride ?? ""
        every = entry.everyOverride ?? ""
        for (name, input) in widget.inputs {
            let value = entry.with[name]
            if input.isChoice {
                if let value { choices[name] = value }
            } else if input.type == "boolean" {
                flags[name] = (value ?? input.defaultValue)?.text == "true"
            } else {
                texts[name] = value?.text ?? ""
            }
        }
    }

    public var plainInputs: [(name: String, input: CatalogInput)] {
        widget.inputs.keys.sorted().compactMap { name in
            widget.inputs[name].flatMap { $0.isChoice ? nil : (name, $0) }
        }
    }

    public var choiceInputs: [ChoiceInput] { ChoiceInput.all(of: widget) }

    /// The label names this widget's own minimum, and drops `manual` for a provider.
    public func everyLabel(catalog: WidgetCatalog, contract: WidgetContract = .current) -> String {
        let plain = BoardWidget(
            id: entry.id, type: entry.type, with: entry.with, frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0)
        guard case let .ready(resolved) = WidgetResolution.resolve(plain, in: catalog, contract: contract) else { return "Every" }
        return EntryOverrideRules.everyLabel(
            floor: EntryOverrideRules.floorText(of: resolved, catalog: catalog, contract: contract),
            allowsManual: widget.source.kind != "provider")
    }

    public var everyPlaceholder: String { widget.source.every }

    public func edit(
        surface: String, catalog: WidgetCatalog, contract: WidgetContract = .current
    ) -> Result<EntryEdit, FormProblem> {
        var with = entry.with.filter { widget.inputs[$0.key] == nil }
        for (name, input) in plainInputs {
            switch value(name, input) {
            case let .success(value?): with[name] = value
            case .success(nil): break
            case let .failure(problem): return .failure(problem)
            }
        }
        for (name, value) in choices where widget.inputs[name]?.isChoice == true {
            if value.listValue?.isEmpty == true { continue }
            with[name] = value
        }
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let everyText = every.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = BoardWidget(
            id: entry.id, type: entry.type, with: with, frame: BoardFrame(x: 0, y: 0, w: 1, h: 1), size: "medium", z: 0,
            titleOverride: titleText.isEmpty ? nil : titleText, everyOverride: everyText.isEmpty ? nil : everyText)
        if let problem = readProblem(candidate, surface: surface, contract: contract) { return .failure(problem) }
        if let shape = InputShapes.problem(with, inputs: widget.inputs, id: entry.id) {
            return .failure(FormProblem(field: "input.\(shape.input)", message: InlineWidgetForm.plain(shape.message, id: entry.id)))
        }
        if let everyOverride = candidate.everyOverride {
            var plain = candidate
            plain.everyOverride = nil
            switch WidgetResolution.resolve(plain, in: catalog, contract: contract) {
            case let .ready(resolved):
                if let problem = EntryOverrideRules.everyProblem(
                    id: entry.id, type: entry.type, every: everyOverride, resolved: resolved, catalog: catalog, contract: contract) {
                    return .failure(FormProblem(field: "every", message: InlineWidgetForm.plain(problem, id: entry.id)))
                }
            case let resolution:
                let detail = WidgetResolutionCopy.detail(resolution, release: catalog.packagesRelease)
                let reason = detail.isEmpty ? WidgetResolutionCopy.title(resolution) : detail
                return .failure(FormProblem(field: "every", message: InlineWidgetForm.plain(reason, id: entry.id)))
            }
        }
        return .success(.typed(title: candidate.titleOverride, with: with, every: candidate.everyOverride))
    }

    private func value(_ name: String, _ input: CatalogInput) -> Result<BoardScalar?, FormProblem> {
        if input.type == "boolean" {
            let flag = flags[name] ?? false
            return .success(flag == (input.defaultValue?.text == "true") ? nil : .bool(flag))
        }
        let text = (texts[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == input.defaultValue?.text { return .success(nil) }
        guard input.type == "number" else { return .success(.string(text)) }
        if let number = Int(text) { return .success(.int(number)) }
        if let number = Double(text), number.isFinite {
            if let base = input.defaultValue.flatMap({ Double($0.text) }), base == number { return .success(nil) }
            return .success(.double(number))
        }
        let label = WidgetTitle.make(type: name)
        let example = input.defaultValue?.text ?? "5"
        return .failure(FormProblem(field: "input.\(name)", message: "\(label) is a number, such as \(example)."))
    }

    /// The board reader sees the entry as the file will hold it.
    private func readProblem(_ candidate: BoardWidget, surface: String, contract: WidgetContract) -> FormProblem? {
        let canvas = contract.layout(of: surface) == "canvas"
        let text: String
        if canvas {
            text = BoardCodec.encode(Board(surface: surface, widgets: [candidate]))
        } else {
            text = BoardCodec.encodeStack(StackBoard(surface: surface, entries: [StackEntry(
                id: candidate.id, type: candidate.type, with: candidate.with,
                titleOverride: candidate.titleOverride, everyOverride: candidate.everyOverride)]))
        }
        do {
            if canvas { _ = try BoardCodec.decode(text, contract: contract) } else { _ = try BoardCodec.decodeStack(text, contract: contract) }
            return nil
        } catch let problem as BoardProblem {
            let field = problem.line.flatMap { Self.field(atLine: $0, in: text) }
            return FormProblem(field: field, message: InlineWidgetForm.plain(problem.message, id: entry.id))
        } catch {
            return FormProblem(field: nil, message: "The board file could not be checked: \(error.localizedDescription)")
        }
    }

    static func field(atLine number: Int, in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard number >= 1, number <= lines.count else { return nil }
        let line = lines[number - 1]
        let indent = line.prefix { $0 == " " }.count
        let key = line.dropFirst(indent).prefix { $0 != ":" }
        switch indent {
        case 4 where key == "title" || key == "every": return String(key)
        case 6 where !key.isEmpty && lines[..<(number - 1)].last(where: { $0.hasPrefix("    ") && !$0.hasPrefix("     ") })?.hasPrefix("    with:") == true:
            return "input.\(key)"
        default: return nil
        }
    }
}
