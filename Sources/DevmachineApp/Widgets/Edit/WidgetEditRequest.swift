import Foundation
import DevmachineCore

/// What the chooser and the editor need from a board's controller. Home,
/// the sidebars and both menubar boards answer it the same way.
@MainActor
protocol WidgetEditTarget: AnyObject {
    var editSurface: String { get }
    var editFileName: String { get }
    var canEdit: Bool { get }
    var editCatalog: WidgetCatalog? { get }
    func editableEntry(_ id: String) -> EditableEntry?
    func choices(for id: String) -> [ChoiceInput]
    func value(of input: String, in id: String) -> BoardScalar?
    func problem(with edit: EntryEdit, for id: String) -> String?
    @discardableResult func apply(_ edit: EntryEdit, to id: String) -> Bool
    func addInline(_ inline: InlineWidget, title: String, preset: String) -> String?
}

extension WidgetEditTarget {
    func choices(for id: String) -> [ChoiceInput] {
        guard let entry = editableEntry(id), entry.inline == nil,
              let widget = editCatalog?.widget(named: entry.type) else { return [] }
        return ChoiceInput.all(of: widget)
    }

    func value(of input: String, in id: String) -> BoardScalar? {
        editableEntry(id)?.with[input]
    }
}

struct WidgetChoiceRequest: Identifiable, Equatable {
    let entryID: String
    let input: ChoiceInput
    let title: String

    var id: String { entryID + "/" + input.name }
}
