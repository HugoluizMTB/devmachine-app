import Foundation

/// The contract's `option_sources`: where a `choice` input's options come
/// from. The app fills each from its own stores.
public enum WidgetOptionSource: String, CaseIterable, Sendable {
    case machines, workspaces, harnesses
}

public struct ChoiceOption: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let isMissing: Bool

    public init(id: String, label: String, isMissing: Bool = false) {
        self.id = id
        self.label = label
        self.isMissing = isMissing
    }
}

/// One `choice` input of a widget, as the chooser needs it. Nothing here
/// names a widget: the menu, the chooser and the write all read this.
public struct ChoiceInput: Equatable, Sendable, Identifiable {
    public let name: String
    public let source: WidgetOptionSource
    public let many: Bool
    public let summary: String
    public let defaultValue: BoardScalar?

    public var id: String { name }

    public init?(name: String, input: CatalogInput) {
        guard input.isChoice, let from = input.from, let source = WidgetOptionSource(rawValue: from) else { return nil }
        self.name = name
        self.source = source
        self.many = input.many
        self.summary = input.summary
        self.defaultValue = input.defaultValue
    }

    public static func all(of widget: CatalogWidget) -> [ChoiceInput] {
        widget.inputs.keys.sorted().compactMap { name in widget.inputs[name].flatMap { ChoiceInput(name: name, input: $0) } }
    }

    /// The summary's first clause: "Which machines to show; none picked
    /// shows them all." reads "Choose which machines to show…".
    public var menuTitle: String {
        let clause = summary.split(whereSeparator: { $0 == ";" || $0 == "." }).first.map(String.init) ?? ""
        var phrase = clause.trimmingCharacters(in: .whitespaces)
        if phrase.isEmpty { phrase = name }
        return "Choose " + phrase.prefix(1).lowercased() + phrase.dropFirst() + "…"
    }
}

/// What the chooser shows and writes. Many: no value, `[]` and every
/// option ticked all mean "all" and write nothing, so a new machine shows
/// too. A chosen name the source no longer has stays, marked, to untick.
public struct ChoiceSelection: Equatable, Sendable {
    public let input: ChoiceInput
    public let options: [ChoiceOption]
    public private(set) var chosen: [String]

    public init(input: ChoiceInput, current: BoardScalar?, options: [ChoiceOption]) {
        self.input = input
        let start = current ?? input.defaultValue
        var picked: [String] = []
        if input.many {
            picked = start?.listValue ?? []
        } else if let start, start.listValue == nil, !start.text.isEmpty {
            picked = [start.text]
        }
        let known = Set(options.map(\.id))
        let rows = options + picked.filter { !known.contains($0) }.map {
            ChoiceOption(id: $0, label: "\($0) (not found)", isMissing: true)
        }
        self.options = rows
        chosen = rows.map(\.id).filter(picked.contains)
    }

    public var isAll: Bool { input.many && chosen.isEmpty }

    public func isChosen(_ id: String) -> Bool { isAll || chosen.contains(id) }

    public mutating func toggle(_ id: String) {
        guard input.many else { return pick(id) }
        let present = options.filter { !$0.isMissing }.map(\.id)
        var next = Set(isAll ? present : chosen)
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        let ordered = options.map(\.id).filter(next.contains)
        chosen = Set(ordered) == Set(present) ? [] : ordered
    }

    public mutating func pick(_ id: String) {
        chosen = [id]
    }

    public var value: BoardScalar? {
        if input.many { return chosen.isEmpty ? nil : .list(chosen) }
        return chosen.first.map(BoardScalar.string)
    }
}
