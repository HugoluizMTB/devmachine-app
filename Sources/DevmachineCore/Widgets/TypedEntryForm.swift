import Foundation

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
        for (name, value) in choices { with[name] = value }
        let titleText = title.trimmingCharacters(in: .whitespaces)
        let everyText = every.trimmingCharacters(in: .whitespaces)
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
            if case let .ready(resolved) = WidgetResolution.resolve(plain, in: catalog, contract: contract),
               let problem = EntryOverrideRules.everyProblem(
                   id: entry.id, type: entry.type, every: everyOverride, resolved: resolved, catalog: catalog, contract: contract) {
                return .failure(FormProblem(field: "every", message: InlineWidgetForm.plain(problem, id: entry.id)))
            }
        }
        return .success(.typed(title: candidate.titleOverride, with: with, every: candidate.everyOverride))
    }

    private func value(_ name: String, _ input: CatalogInput) -> Result<BoardScalar?, FormProblem> {
        if input.type == "boolean" {
            let flag = flags[name] ?? false
            return .success(flag == (input.defaultValue?.text == "true") ? nil : .bool(flag))
        }
        let text = (texts[name] ?? "").trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == input.defaultValue?.text { return .success(nil) }
        guard input.type == "number" else { return .success(.string(text)) }
        if let number = Int(text) { return .success(.int(number)) }
        if let number = Double(text) { return .success(.double(number)) }
        let label = WidgetTitle.make(type: name)
        let example = input.defaultValue?.text ?? "5"
        return .failure(FormProblem(field: "input.\(name)", message: "\(label) is a number, such as \(example)."))
    }

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
            let line = problem.line.flatMap { text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst($0 - 1).first }
            let field = line.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { line -> String? in
                if line.hasPrefix("title:") { return "title" }
                if line.hasPrefix("every:") { return "every" }
                return nil
            }
            return FormProblem(field: field, message: InlineWidgetForm.plain(problem.message, id: entry.id))
        } catch {
            return FormProblem(field: nil, message: "\(error)")
        }
    }
}
