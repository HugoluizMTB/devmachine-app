import Foundation
import DevmachineCore

/// The editor's state, without SwiftUI: which form it shows, the problem
/// the last save met, and the one save path through the board's controller.
@MainActor
final class WidgetEditorModel: ObservableObject {
    enum Form: Equatable {
        case inline(InlineWidgetForm, old: InlineWidget?)
        case basics(InlineBasicsForm)
        case typed(TypedEntryForm)
        case titleOnly(EditableEntry, title: String)
    }

    let request: WidgetEditRequest
    let surface: String
    let fileName: String
    @Published var form: Form
    @Published private(set) var problem: FormProblem?

    init?(request: WidgetEditRequest, target: WidgetEditTarget) {
        self.request = request
        surface = target.editSurface
        fileName = target.editFileName
        switch request {
        case let .new(template):
            form = .inline(InlineWidgetForm(template: template), old: nil)
        case let .edit(id):
            guard let entry = target.editableEntry(id) else { return nil }
            if let inline = entry.inline {
                form = InlineWidgetForm(inline: inline, surface: target.editSurface).map { .inline($0, old: inline) }
                    ?? .basics(InlineBasicsForm(inline: inline))
            } else if let widget = target.editCatalog?.widget(named: entry.type) {
                form = .typed(TypedEntryForm(entry: entry, widget: widget))
            } else {
                form = .titleOnly(entry, title: entry.titleOverride ?? "")
            }
        }
    }

    var heading: String {
        switch (request, form) {
        case let (.new(template), _): return "New \(template.noun) widget"
        case let (_, .inline(form, _)): return "Edit \(form.title)"
        case let (_, .basics(form)): return "Edit \(form.old.title)"
        case let (_, .typed(form)): return "Edit \(form.entry.titleOverride ?? WidgetTitle.make(type: form.entry.type))"
        case let (_, .titleOnly(entry, _)): return "Edit \(entry.titleOverride ?? WidgetTitle.make(type: entry.type))"
        }
    }

    var shownFields: Set<String> {
        switch form {
        case let .inline(form, _): return form.fields
        case let .basics(form): return form.fields
        case let .typed(form):
            let drawn = form.widget.inputs.filter { $0.value.type != "boolean" }.keys.map { "input.\($0)" }
            return Set(["title", "every"] + drawn)
        case .titleOnly: return ["title"]
        }
    }

    private var editedID: String? {
        if case let .edit(id) = request { return id }
        return nil
    }

    func problem(for field: String) -> String? {
        guard let problem, problem.field == field, shownFields.contains(field) else { return nil }
        return problem.message
    }

    /// Any problem with no field on screen, so Save never fails in silence.
    var formProblem: String? {
        guard let problem else { return nil }
        if let field = problem.field, shownFields.contains(field) { return nil }
        return problem.message
    }

    func save(to target: WidgetEditTarget) -> Bool {
        guard target.canEdit else {
            return refuse(FormProblem(field: nil, message: "\(fileName) cannot change right now: fix the file first."))
        }
        if let id = editedID, target.editableEntry(id) == nil {
            return refuse(FormProblem(field: nil, message: "This widget is no longer on the board."))
        }
        let edit: EntryEdit
        switch form {
        case let .inline(form, old):
            switch form.read(surface: surface, id: editedID ?? "new", keeping: old, catalog: target.editCatalog) {
            case let .failure(found):
                return refuse(found)
            case let .success(inline):
                guard editedID != nil else {
                    guard target.addInline(inline, title: form.title, preset: form.template.preset) != nil else {
                        return refuse(FormProblem(field: nil, message: "There is no room for another widget here."))
                    }
                    problem = nil
                    return true
                }
                edit = .inline(inline)
            }
        case let .basics(form):
            switch form.read(surface: surface, id: editedID ?? "new", catalog: target.editCatalog) {
            case let .failure(found): return refuse(found)
            case let .success(inline): edit = .inline(inline)
            }
        case let .typed(form):
            let catalog = target.editCatalog
                ?? WidgetCatalog(engine: WidgetContract.current.engine, packagesRelease: "", widgets: [])
            switch form.edit(surface: surface, catalog: catalog) {
            case let .failure(found): return refuse(found)
            case let .success(typed): edit = typed
            }
        case let .titleOnly(entry, title):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            edit = .typed(title: trimmed.isEmpty ? nil : trimmed, with: entry.with, every: entry.everyOverride)
        }
        if let refusal = apply(edit, to: target) { return refuse(refusal) }
        problem = nil
        return true
    }

    /// `apply` returning false after a clean check only means nothing changed.
    private func apply(_ edit: EntryEdit, to target: WidgetEditTarget) -> FormProblem? {
        guard let id = editedID else { return FormProblem(field: nil, message: "There is nothing to edit.") }
        if let reason = target.problem(with: edit, for: id) { return FormProblem(field: nil, message: reason) }
        target.apply(edit, to: id)
        return nil
    }

    private func refuse(_ found: FormProblem) -> Bool {
        problem = found
        return false
    }
}
