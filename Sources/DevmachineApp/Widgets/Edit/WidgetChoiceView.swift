import SwiftUI
import DevmachineCore

enum WidgetChoiceOutcome: Equatable {
    case saved
    case refused(String)

    var closes: Bool { self == .saved }

    var message: String? {
        if case let .refused(message) = self { return message }
        return nil
    }
}

enum WidgetChoiceModel {
    @MainActor
    static func save(
        _ selection: ChoiceSelection, request: WidgetChoiceRequest, to target: WidgetEditTarget
    ) -> WidgetChoiceOutcome {
        guard target.canEdit else { return .refused("This board cannot change right now.") }
        let edit = EntryEdit.input(name: request.input.name, value: selection.value)
        if let problem = target.problem(with: edit, for: request.entryID) { return .refused(problem) }
        guard target.apply(edit, to: request.entryID) else { return .refused("The change could not be saved.") }
        return .saved
    }
}

/// The one chooser every choice input uses: a checklist for a list, a
/// picker for one value. It reads only the input and its options.
struct WidgetChoiceView: View {
    let request: WidgetChoiceRequest
    let options: [ChoiceOption]
    let onSave: (ChoiceSelection) -> Void
    let error: String?
    let onCancel: () -> Void
    @State private var selection: ChoiceSelection
    @Environment(\.dmMetrics) private var m

    init(
        request: WidgetChoiceRequest, current: BoardScalar?, options: [ChoiceOption], error: String? = nil,
        onSave: @escaping (ChoiceSelection) -> Void, onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.options = options
        self.onSave = onSave
        self.error = error
        self.onCancel = onCancel
        _selection = State(initialValue: ChoiceSelection(input: request.input, current: current, options: options))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: request.title).font(.dm(13, weight: .semibold))
            Text(verbatim: request.input.menuTitle.replacingOccurrences(of: "…", with: ""))
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            if selection.options.isEmpty {
                Text(verbatim: "Nothing to choose from yet.").font(.dm(11)).foregroundStyle(Color.dmMuted)
            } else if request.input.many {
                ScrollView {
                    VStack(alignment: .leading, spacing: m.space.xs) {
                        ForEach(selection.options) { option in
                            Toggle(isOn: Binding(
                                get: { selection.isChosen(option.id) }, set: { _ in selection.toggle(option.id) }
                            )) {
                                Text(verbatim: option.label).font(.dm(12))
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: m.pt(280))
                if selection.isAll {
                    Text(verbatim: "All of them, including any added later.").font(.dm(11)).foregroundStyle(Color.dmMuted)
                }
            } else {
                Picker(selection: Binding(get: { selection.chosen.first ?? "" }, set: { selection.pick($0) })) {
                    ForEach(selection.options) { option in Text(verbatim: option.label).tag(option.id) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.radioGroup)
            }
            if let error { DMBanner(message: error) {} }
            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline, size: .small, action: onCancel)
                DMButton("Save", variant: .primary, size: .small) { onSave(selection) }
            }
        }
        .padding(m.space.lg)
        .frame(minWidth: 0, idealWidth: m.card.sheet, maxWidth: m.card.sheet)
        .onChange(of: options) { _, fresh in
            selection = ChoiceSelection(input: request.input, current: selection.value, options: fresh)
        }
    }
}

/// A chooser for one entry of one board, with the live options.
struct WidgetChoiceSheet: View {
    let request: WidgetChoiceRequest
    let target: WidgetEditTarget
    let onDone: () -> Void
    @Environment(\.widgetOptionSources) private var options
    @State private var error: String?

    var body: some View {
        WidgetChoiceView(
            request: request, current: target.value(of: request.input.name, in: request.entryID),
            options: options.options(request.input.source), error: error,
            onSave: { selection in
                let outcome = WidgetChoiceModel.save(selection, request: request, to: target)
                error = outcome.message
                if outcome.closes { onDone() }
            },
            onCancel: onDone)
    }
}
