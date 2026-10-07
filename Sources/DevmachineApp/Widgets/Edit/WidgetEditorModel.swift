import Foundation
import DevmachineCore

/// The editor's state, without SwiftUI: which form it shows, the problem
/// the last save met, and the one save path through the board's controller.
@MainActor
final class WidgetEditorModel: ObservableObject {
    enum Form: Equatable {
        case inline(InlineWidgetForm, old: InlineWidget?)
        case titleOnly(String, old: InlineWidget)
        case typed(TypedEntryForm)
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
                    ?? .titleOnly(inline.title, old: inline)
            } else {
                guard let widget = target.editCatalog?.widget(named: entry.type) else { return nil }
                form = .typed(TypedEntryForm(entry: entry, widget: widget))
            }
        }
    }

    var heading: String {
        switch (request, form) {
        case let (.new(template), _): return "New \(template.title.lowercased()) widget"
        case let (_, .inline(form, _)): return "Edit \(form.title)"
        case let (_, .titleOnly(title, _)): return "Edit \(title)"
        case let (_, .typed(form)): return "Edit \(form.entry.titleOverride ?? WidgetTitle.make(type: form.entry.type))"
        }
    }

    private var editedID: String? {
        if case let .edit(id) = request { return id }
        return nil
    }

    func problem(for field: String) -> String? {
        problem?.field == field ? problem?.message : nil
    }

    var formProblem: String? {
        problem?.field == nil ? problem?.message : nil
    }

    func save(to target: WidgetEditTarget) -> Bool {
        guard target.canEdit else {
            return refuse(FormProblem(field: nil, message: "\(fileName) cannot change right now: fix the file first."))
        }
        if let id = editedID, target.editableEntry(id) == nil {
            return refuse(FormProblem(field: nil, message: "This widget is no longer on the board."))
        }
        switch form {
        case let .inline(form, old):
            switch form.read(surface: surface, id: editedID ?? "new", keeping: old, catalog: target.editCatalog) {
            case let .failure(found):
                return refuse(found)
            case let .success(inline):
                if editedID == nil {
                    guard target.addInline(inline, title: form.title, preset: form.template.preset) != nil else {
                        return refuse(FormProblem(field: nil, message: "There is no room for another widget here."))
                    }
                } else if let refusal = apply(.inline(inline), to: target) {
                    return refuse(refusal)
                }
            }
        case let .titleOnly(title, old):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return refuse(FormProblem(field: "title", message: "Give the widget a title.")) }
            var inline = old
            inline.title = trimmed
            if let refusal = apply(.inline(inline), to: target) { return refuse(refusal) }
        case let .typed(form):
            let catalog = target.editCatalog
                ?? WidgetCatalog(engine: WidgetContract.current.engine, packagesRelease: "", widgets: [])
            switch form.edit(surface: surface, catalog: catalog) {
            case let .failure(found):
                return refuse(found)
            case let .success(edit):
                if let refusal = apply(edit, to: target) { return refuse(refusal) }
            }
        }
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
