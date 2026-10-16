import SwiftUI
import DevmachineCore

/// Where a message is typed: Return sends, ⇧Return starts a new line, Esc
/// stops an answer. The harness and workspace chips are pickers until the
/// chat's first message, then they only say what the chat uses.
struct ChatComposer: View {
    @Binding var text: String
    var placeholder = "Reply…"
    var minHeight: CGFloat = 46
    let harness: HarnessID
    let place: ChatPlace
    var locked = false
    var streaming = false
    var openPicker: ChatPicker?
    var togglePicker: (ChatPicker) -> Void = { _ in }
    let send: () -> Void
    var stop: () -> Void = {}
    @Environment(\.dmMetrics) private var m
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !streaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.dm(13.5))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1...12)
                .focused($focused)
                .frame(maxWidth: .infinity, minHeight: m.pt(minHeight), alignment: .topLeading)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                        text += "\n"
                        return .handled
                    }
                    if canSend { send() }
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard streaming else { return .ignored }
                    stop()
                    return .handled
                }
                .demoClickTarget("chat:composer")
            HStack(spacing: m.pt(6)) {
                Button { if !locked { togglePicker(.harness) } } label: {
                    ChatChip(harness: harness, title: ChatHarness.title(harness), menu: !locked,
                             open: openPicker == .harness)
                }
                .buttonStyle(.plain)
                .anchorPreference(key: ChatAnchorKey.self, value: .bounds) { ["harness": $0] }
                .help(locked ? "A chat keeps its coding agent." : "Coding agent")
                Button { if !locked { togglePicker(.workspace) } } label: {
                    ChatChip(systemImage: ChatPlaceLabel.symbol(place), title: ChatPlaceLabel.title(place),
                             menu: !locked, open: openPicker == .workspace)
                }
                .buttonStyle(.plain)
                .anchorPreference(key: ChatAnchorKey.self, value: .bounds) { ["workspace": $0] }
                .help(locked ? "A chat keeps its workspace." : "Where the chat runs")
                ChatReadOnlyLabel()
                    .padding(.leading, m.pt(4))
                Spacer()
                ChatSendButton(enabled: canSend, stops: streaming) {
                    if streaming { stop() } else if canSend { send() }
                }
            }
        }
        .padding(m.pt(14))
        .dmSurface(Color(hex: 0x1A2027), radius: DMRadius.card, style: .continuous)
        .shadow(color: .black.opacity(0.25), radius: m.pt(12), y: m.pt(4))
        .onAppear { if !DemoMode.isActive { focused = true } }
    }
}

/// Draws the open picker above its chip, and closes it on a click
/// anywhere else.
struct ChatPickerOverlay: ViewModifier {
    @ObservedObject var store: ChatStore
    let harness: HarnessID
    let place: ChatPlace
    var opensBelow = false
    let pickHarness: (HarnessID) -> Void
    let pickPlace: (ChatPlace) -> Void
    @Environment(\.dmMetrics) private var m

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ChatAnchorKey.self) { anchors in
            if let picker = store.openPicker,
               let anchor = anchors[picker == .harness ? "harness" : "workspace"] {
                GeometryReader { proxy in
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.001)
                            .onTapGesture { store.openPicker = nil }
                        if opensBelow {
                            ChatMenuCard(items: items(picker), width: 230, highlighted: highlighted(picker))
                                .offset(x: rect.minX - m.pt(6), y: rect.maxY + m.pt(6))
                        } else {
                            ChatMenuCard(items: items(picker), width: 230, highlighted: highlighted(picker))
                                .frame(height: max(0, rect.minY - m.pt(6)), alignment: .bottom)
                                .offset(x: rect.minX - m.pt(6))
                        }
                    }
                }
            }
        }
    }

    private func items(_ picker: ChatPicker) -> [ChatMenuItem] {
        switch picker {
        case .harness:
            return ChatMenus.harnesses(selected: harness, available: store.settings.harnesses) { id in
                pickHarness(id)
                store.openPicker = nil
            }
        case .workspace:
            return ChatMenus.places(selected: place, workspaces: store.workspaces, defaultPlace: store.defaultPlace) {
                pickPlace($0)
                store.openPicker = nil
            }
        }
    }

    private func highlighted(_ picker: ChatPicker) -> String {
        switch picker {
        case .harness: return "harness-" + harness.rawValue
        case .workspace: return "workspace-" + (place.workspaceName ?? "local")
        }
    }
}
