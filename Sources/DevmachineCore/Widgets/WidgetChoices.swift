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
        let clause = Self.firstSentence(of: summary)
        var phrase = clause.trimmingCharacters(in: .whitespaces)
        if phrase.isEmpty { phrase = name }
        return "Choose " + phrase.prefix(1).lowercased() + phrase.dropFirst() + "…"
    }

    private static func startsSentence(_ rest: Substring) -> Bool {
        guard rest.first == " " else { return false }
        return rest.dropFirst().first.map { $0.isUppercase || !$0.isLetter } ?? true
    }

    private static func firstSentence(of text: String) -> String {
        var end = text.endIndex
        for index in text.indices where text[index] == ";" {
            end = index
            break
        }
        let head = text[..<end]
        var cut = head.endIndex
        for index in head.indices where head[index] == "." {
            let next = head.index(after: index)
            if next == head.endIndex || Self.startsSentence(head[next...]) {
                cut = index
                break
            }
        }
        return String(head[..<cut])
    }
}

/// What the chooser shows and writes. Many: no value, `[]` and every
/// option ticked all mean "all" and write nothing, so a new machine shows
/// too. A chosen name the source no longer has stays, marked, to untick.
public struct ChoiceSelection: Equatable, Sendable {
    public let input: ChoiceInput
    public let options: [ChoiceOption]
    public private(set) var chosen: [String]
    private var isImplicit: Bool

    public init(input: ChoiceInput, current: BoardScalar?, options: [ChoiceOption]) {
        self.input = input
        let start = current ?? input.defaultValue
        var picked: [String] = []
        if let start {
            if let list = start.listValue {
                picked = input.many ? list : Array(list.prefix(1))
            } else if !start.text.isEmpty {
                picked = [start.text]
            }
        }
        var seen = Set<String>()
        let unique = options.filter { seen.insert($0.id).inserted }
        let known = Set(unique.map(\.id))
        var wanted = Set<String>()
        picked = picked.filter { wanted.insert($0).inserted }
        let rows = unique + picked.filter { !known.contains($0) }.map {
            ChoiceOption(id: $0, label: "\($0) (not found)", isMissing: true)
        }
        self.options = rows
        chosen = picked
        isImplicit = false
        if !input.many, picked.isEmpty, let first = unique.first {
            chosen = [first.id]
            isImplicit = true
        }
    }

    public var isAll: Bool { input.many && chosen.isEmpty }

    public func isChosen(_ id: String) -> Bool { isAll || chosen.contains(id) }

    public mutating func toggle(_ id: String) {
        guard input.many else { return pick(id) }
        let present = options.filter { !$0.isMissing }.map(\.id)
        var next = isAll ? present : chosen
        if let at = next.firstIndex(of: id) { next.remove(at: at) } else { next.append(id) }
        let hasMissing = next.contains { !present.contains($0) }
        chosen = !hasMissing && Set(next) == Set(present) ? [] : next
    }

    public mutating func pick(_ id: String) {
        chosen = [id]
        isImplicit = false
    }

    public var value: BoardScalar? {
        if input.many { return chosen.isEmpty ? nil : .list(chosen) }
        if isImplicit { return nil }
        return chosen.first.map(BoardScalar.string)
    }
}
