import SwiftUI
import DevmachineCore

/// The new-widget and edit form, for every area. Each problem shows under
/// its field; a problem with no field shows above the buttons.
struct WidgetEditorView: View {
    @ObservedObject var model: WidgetEditorModel
    let target: WidgetEditTarget
    let onDone: () -> Void
    @State private var choosing: ChoiceInput?
    @Environment(\.widgetOptionSources) private var options
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if let choosing, case let .typed(form) = model.form {
            WidgetChoiceView(
                request: WidgetChoiceRequest(entryID: form.entry.id, input: choosing, title: model.heading),
                current: form.choices[choosing.name], options: options.options(choosing.source),
                onSave: { selection in
                    var next = form
                    next.choices[choosing.name] = selection.value
                    model.form = .typed(next)
                    self.choosing = nil
                },
                onCancel: { self.choosing = nil })
        } else {
            VStack(alignment: .leading, spacing: m.space.md) {
                Text(verbatim: model.heading).font(.dm(13, weight: .semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: m.space.md) { fields }
                }
                .frame(maxHeight: m.pt(420))
                if let message = model.formProblem {
                    DMBanner(message: message, lineLimit: 4) { EmptyView() }
                }
                HStack {
                    Spacer()
                    DMButton("Cancel", variant: .outline, size: .small, action: onDone)
                    DMButton("Save", variant: .primary, size: .small) { if model.save(to: target) { onDone() } }
                }
            }
            .padding(m.space.lg)
            .frame(minWidth: 0, idealWidth: m.card.sheet, maxWidth: m.card.sheet)
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch model.form {
        case let .inline(form, old):
            inlineFields(form, old: old)
        case let .basics(form):
            field("Title", "title") {
                TextField("Title", text: Binding(get: { form.title }, set: { v in
                    var next = form
                    next.title = v
                    model.form = .basics(next)
                })).dmField()
            }
            if let every = form.every {
                everyField(every) { v in
                    var next = form
                    next.every = v
                    model.form = .basics(next)
                }
            }
            Text(verbatim: "Edit the rest in \(model.fileName).").font(.dm(11)).foregroundStyle(Color.dmMuted)
        case let .typed(form):
            typedFields(form)
        case let .titleOnly(entry, title):
            field("Title", "title") {
                TextField(WidgetTitle.make(type: entry.type), text: Binding(
                    get: { title }, set: { model.form = .titleOnly(entry, title: $0) })).dmField()
            }
            Text(verbatim: "The packages release does not list this widget, so only its title can change here.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func inlineFields(_ form: InlineWidgetForm, old: InlineWidget?) -> some View {
        let set = { (change: (inout InlineWidgetForm) -> Void) in
            var next = form
            change(&next)
            model.form = .inline(next, old: old)
        }
        field("Title", "title") { TextField("Title", text: Binding(get: { form.title }, set: { v in set { $0.title = v } })).dmField() }
        switch form.template {
        case .command:
            Picker("Runs", selection: Binding(get: { form.commandStyle }, set: { v in set { $0.commandStyle = v } })) {
                Text(verbatim: "A program").tag(CommandStyle.program)
                Text(verbatim: "A shell line").tag(CommandStyle.shell)
            }
            .pickerStyle(.segmented)
            if form.commandStyle == .shell {
                field("Shell line", "shellLine") {
                    TextField("df -h | tail -1", text: Binding(get: { form.shellLine }, set: { v in set { $0.shellLine = v } })).dmField()
                }
            } else {
                field("Program", "run") { TextField("df", text: Binding(get: { form.run }, set: { v in set { $0.run = v } })).dmField() }
                field("Arguments, one per line", "args") {
                    TextField("-h", text: Binding(get: { form.args }, set: { v in set { $0.args = v } }), axis: .vertical)
                        .lineLimit(2...6).dmField()
                }
            }
            targetPicker(form.target) { v in set { $0.target = v } }
            everyField(form.every) { v in set { $0.every = v } }
            field("Output", "parse") {
                Picker(selection: Binding(get: { form.parse }, set: { v in set { $0.parse = v } })) {
                    ForEach(["text", "lines", "number", "json", "ansi"], id: \.self) { Text(verbatim: $0).tag($0) }
                } label: {
                    EmptyView()
                }
            }
            viewPicker(form) { v in set { $0.view = v } }
            if form.fields.contains("value") {
                field("Value", "value") {
                    TextField("{{json.used}}", text: Binding(get: { form.value }, set: { v in set { $0.value = v } })).dmField()
                }
            }
        case .urlStatus, .webPage:
            field("Address", "url") {
                TextField("https://example.com", text: Binding(get: { form.url }, set: { v in set { $0.url = v } })).dmField()
            }
            everyField(form.every) { v in set { $0.every = v } }
            if form.template == .webPage {
                field("Zoom", "zoom") { TextField("1", text: Binding(get: { form.zoom }, set: { v in set { $0.zoom = v } })).dmField() }
            }
        case .prompt:
            field("Harness", "harness") {
                Picker(selection: Binding(get: { form.harness }, set: { v in set { $0.chooseHarness(v) } })) {
                    ForEach(WidgetContract.current.sources["prompt"]?.fields["harness"]?.values ?? [], id: \.self) {
                        Text(verbatim: $0).tag($0)
                    }
                } label: {
                    EmptyView()
                }
            }
            permissionModePicker(form) { v in set { $0.choosePermissionMode(v) } }
            field("Prompt", "prompt") {
                TextField("Summarise the log", text: Binding(get: { form.prompt }, set: { v in set { $0.prompt = v } }), axis: .vertical)
                    .lineLimit(3...8).dmField()
            }
            targetPicker(form.target) { v in set { $0.target = v } }
            everyField(form.every, locked: form.everyLocked()) { v in set { $0.every = v } }
        case .session:
            targetPicker(form.target) { v in set { $0.target = v } }
            field("Session", "session") {
                TextField("main", text: Binding(get: { form.session }, set: { v in set { $0.session = v } })).dmField()
            }
            everyField(form.every) { v in set { $0.every = v } }
        }
    }

    @ViewBuilder
    private func typedFields(_ form: TypedEntryForm) -> some View {
        let set = { (change: (inout TypedEntryForm) -> Void) in
            var next = form
            change(&next)
            model.form = .typed(next)
        }
        field("Title", "title") {
            TextField(WidgetTitle.make(type: form.entry.type), text: Binding(get: { form.title }, set: { v in set { $0.title = v } })).dmField()
        }
        field("Every", "every") {
            TextField(form.everyPlaceholder, text: Binding(get: { form.every }, set: { v in set { $0.every = v } })).dmField()
        }
        ForEach(form.choiceInputs) { input in
            field(WidgetTitle.make(type: input.name), "input.\(input.name)") {
                HStack {
                    Text(verbatim: chosenText(form.choices[input.name], many: input.many)).font(.dm(12))
                    Spacer()
                    DMButton("Choose…", variant: .outline, size: .small) { choosing = input }
                }
            }
        }
        ForEach(form.plainInputs, id: \.name) { item in
            let name = item.name
            let input = item.input
            if input.type == "boolean" {
                Toggle(isOn: Binding(get: { form.flags[name] ?? false }, set: { v in set { $0.flags[name] = v } })) {
                    Text(verbatim: WidgetTitle.make(type: name))
                }
                .toggleStyle(.checkbox)
            } else {
                field(WidgetTitle.make(type: name), "input.\(name)") {
                    TextField(input.defaultValue?.text ?? input.summary, text: Binding(
                        get: { form.texts[name] ?? "" }, set: { v in set { $0.texts[name] = v } })).dmField()
                }
            }
        }
    }

    private func chosenText(_ value: BoardScalar?, many: Bool) -> String {
        guard let value else { return many ? "All" : "First available" }
        return value.listValue?.joined(separator: ", ") ?? value.text
    }

    private func field<Content: View>(_ label: String, _ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: m.space.xxs) {
            Text(verbatim: label).font(.dm(11, weight: .semibold))
            content()
            if let message = model.problem(for: key) {
                Text(verbatim: message).font(.dm(11)).foregroundStyle(Color.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func everyField(_ value: String, locked: Bool = false, set: @escaping (String) -> Void) -> some View {
        field("Every (60s, 5m or manual)", "every") {
            TextField("60s", text: Binding(get: { value }, set: set)).dmField().disabled(locked)
            if locked {
                Text(verbatim: "A mode with no checks runs only when you press ▶.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
        }
    }

    private func targetPicker(_ value: WidgetTarget, set: @escaping (WidgetTarget) -> Void) -> some View {
        field("Runs on", "target") {
            Picker(selection: Binding(get: { value }, set: set)) {
                Text(verbatim: "This Mac").tag(WidgetTarget.local)
                ForEach(options.options(.machines)) { Text(verbatim: "Machine \($0.label)").tag(WidgetTarget.machine($0.id)) }
                ForEach(options.options(.workspaces)) { Text(verbatim: "Workspace \($0.label)").tag(WidgetTarget.workspace($0.id)) }
            } label: {
                EmptyView()
            }
        }
    }

    private func permissionModePicker(_ form: InlineWidgetForm, set: @escaping (String) -> Void) -> some View {
        field("Permission mode", "permissionMode") {
            Picker(selection: Binding(get: { form.permissionMode }, set: set)) {
                Text(verbatim: "Harness default").tag("")
                ForEach(form.permissionModes(), id: \.self) { mode in
                    Text(verbatim: PermissionModes.isDangerous(mode) ? "\(mode) (no checks)" : mode).tag(mode)
                }
            } label: {
                EmptyView()
            }
            if form.everyLocked(), let harness = PromptHarness(rawValue: form.harness) {
                DMBanner(
                    message: PermissionModes.warning(form.permissionMode, harness: harness),
                    systemImage: "exclamationmark.octagon.fill", tint: .red, lineLimit: 4
                ) { EmptyView() }
            }
        }
    }

    private func viewPicker(_ form: InlineWidgetForm, set: @escaping (String) -> Void) -> some View {
        let layout = WidgetContract.current.layout(of: model.surface)
        return field("Shown as", "view") {
            Picker(selection: Binding(get: { form.view }, set: set)) {
                ForEach(InlineWidgetForm.views(for: form.parse, layout: layout), id: \.self) { Text(verbatim: $0).tag($0) }
            } label: {
                EmptyView()
            }
        }
    }
}

/// The editor for one request on one board; nil model means nothing to edit.
struct WidgetEditorSheet: View {
    let target: WidgetEditTarget
    let onDone: () -> Void
    @StateObject private var model: WidgetEditorModelBox

    init(request: WidgetEditRequest, target: WidgetEditTarget, onDone: @escaping () -> Void) {
        self.target = target
        self.onDone = onDone
        _model = StateObject(wrappedValue: WidgetEditorModelBox(WidgetEditorModel(request: request, target: target)))
    }

    var body: some View {
        if let editor = model.model {
            WidgetEditorView(model: editor, target: target, onDone: onDone)
        } else {
            WidgetPlaceholderView(
                icon: "pencil.slash", title: "Nothing to edit",
                detail: "This widget is no longer on the board.",
                actionTitle: "Close", action: onDone)
        }
    }
}

@MainActor
final class WidgetEditorModelBox: ObservableObject {
    let model: WidgetEditorModel?
    init(_ model: WidgetEditorModel?) { self.model = model }
}

extension NewWidgetHandoff {
    /// The gallery's "New widget" action: hold the pick, close the popover.
    static func chooser(
        _ handoff: Binding<NewWidgetHandoff>, closing shows: Binding<Bool>
    ) -> (InlineWidgetTemplate) -> Void {
        { template in
            handoff.wrappedValue.choose(template)
            shows.wrappedValue = false
        }
    }
}

extension View {
    /// On the gallery popover's content: when it disappears, open the editor
    /// for the template picked in it, if any.
    func opensNewWidget(_ handoff: Binding<NewWidgetHandoff>, into editing: Binding<WidgetEditRequest?>) -> some View {
        onDisappear {
            if let request = handoff.wrappedValue.galleryGone() { editing.wrappedValue = request }
        }
    }
}
