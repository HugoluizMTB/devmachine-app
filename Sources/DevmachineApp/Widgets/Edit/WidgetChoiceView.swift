import SwiftUI
import DevmachineCore

enum WidgetChoiceModel {
    @MainActor
    static func save(_ selection: ChoiceSelection, request: WidgetChoiceRequest, to target: WidgetEditTarget) -> Bool {
        guard target.canEdit else { return false }
        return target.apply(.input(name: request.input.name, value: selection.value), to: request.entryID)
    }
}

/// The one chooser every choice input uses: a checklist for a list, a
/// picker for one value. It reads only the input and its options.
struct WidgetChoiceView: View {
    let request: WidgetChoiceRequest
    let onSave: (BoardScalar?) -> Void
    let onCancel: () -> Void
    @State private var selection: ChoiceSelection
    @Environment(\.dmMetrics) private var m

    init(
        request: WidgetChoiceRequest, current: BoardScalar?, options: [ChoiceOption],
        onSave: @escaping (BoardScalar?) -> Void, onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSave = onSave
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
            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline, size: .small, action: onCancel)
                DMButton("Save", variant: .primary, size: .small) { onSave(selection.value) }
            }
        }
        .padding(m.space.lg)
        .frame(width: m.card.sheet)
    }
}

/// A chooser for one entry of one board, with the live options.
struct WidgetChoiceSheet: View {
    let request: WidgetChoiceRequest
    let target: WidgetEditTarget
    let onDone: () -> Void
    @Environment(\.widgetOptionSources) private var options

    var body: some View {
        WidgetChoiceView(
            request: request, current: target.value(of: request.input.name, in: request.entryID),
            options: options.options(request.input.source),
            onSave: { value in
                _ = target.apply(.input(name: request.input.name, value: value), to: request.entryID)
                onDone()
            },
            onCancel: onDone)
    }
}
