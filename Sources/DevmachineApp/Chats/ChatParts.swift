import SwiftUI
import DevmachineCore

struct ChatHarnessGlyph: View {
    let harness: HarnessID
    var size: CGFloat = 14
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if let icon = HarnessIconLibrary.bundled.icon(for: harness, style: .color) {
            Image(nsImage: icon.image)
                .resizable()
                .renderingMode(icon.isTemplate ? .template : .original)
                .scaledToFit()
                .foregroundStyle(Color.dmRowText)
                .frame(width: m.pt(size), height: m.pt(size))
        } else {
            Image(systemName: "sparkle")
                .font(.dm(size * 0.8))
                .foregroundStyle(Color.dmMuted)
                .frame(width: m.pt(size), height: m.pt(size))
        }
    }
}

/// A small labelled pill: the header's facts and the composer's pickers.
struct ChatChip: View {
    var harness: HarnessID?
    var systemImage: String?
    let title: String
    var menu = false
    var tint: Color = .dmRowText
    var open = false
    var height: CGFloat = 24
    var fontSize: CGFloat = 11.5
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(spacing: m.pt(5)) {
            if let harness { ChatHarnessGlyph(harness: harness, size: fontSize + 0.5) }
            if let systemImage {
                Image(systemName: systemImage).font(.dm(fontSize - 1.5)).foregroundStyle(Color.dmMuted)
            }
            Text(verbatim: title).font(.dm(fontSize, weight: .medium)).foregroundStyle(tint).lineLimit(1)
            if menu {
                Image(systemName: "chevron.down").font(.dm(fontSize - 3.5, weight: .bold)).foregroundStyle(Color.dmMuted)
            }
        }
        .padding(.horizontal, m.pt(8))
        .frame(height: m.pt(height))
        .dmSurface(open ? Color.white.opacity(0.14) : Color.white.opacity(0.06), radius: DMRadius.row,
                   stroke: open ? Color.accentColor.opacity(0.7) : .dmStroke)
    }
}

struct ChatReadOnlyLabel: View {
    var fontSize: CGFloat = 10.5
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(spacing: m.pt(4)) {
            Image(systemName: "eye").font(.dm(fontSize - 1))
            Text(verbatim: "Read only").font(.dm(fontSize))
        }
        .foregroundStyle(Color.dmMuted)
        .help("Chats can read files and run read-only commands. They never edit files.")
    }
}

struct ChatSpinner: View {
    var size: CGFloat = 10
    @Environment(\.dmMetrics) private var m
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: m.pt(1.6))
            Circle().trim(from: 0, to: 0.3)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: m.pt(1.6), lineCap: .round))
                .rotationEffect(.degrees(turning ? 330 : -30))
        }
        .frame(width: m.pt(size), height: m.pt(size))
        .onAppear {
            guard !DemoMode.isActive else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
        }
        .accessibilityLabel("Answering")
    }
}

struct ChatSendButton: View {
    var size: CGFloat = 26
    var enabled = true
    var stops = false
    var tint: Color = .accentColor
    let action: () -> Void
    @Environment(\.dmMetrics) private var m

    var body: some View {
        Button(action: action) {
            Image(systemName: stops ? "stop.fill" : "arrow.up")
                .font(.dm(size * (stops ? 0.38 : 0.48), weight: .bold))
                .foregroundStyle(.white.opacity(enabled || stops ? 1 : 0.5))
                .frame(width: m.pt(size), height: m.pt(size))
                .background(stops ? Color.white.opacity(0.14) : (enabled ? tint : Color.white.opacity(0.1)), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !stops)
        .accessibilityLabel(stops ? "Stop" : "Send")
    }
}

struct ChatMenuItem: Identifiable {
    enum Kind { case item, separator, header }
    var id: String
    var kind: Kind = .item
    var title = ""
    var detail: String?
    var harness: HarnessID?
    var systemImage: String?
    var checked = false
    var disabled = false
    var shortcut: String?
    var action: (() -> Void)?

    static func separator(_ id: String) -> ChatMenuItem { ChatMenuItem(id: id, kind: .separator) }
    static func header(_ title: String) -> ChatMenuItem { ChatMenuItem(id: "header-" + title, kind: .header, title: title) }
}

/// A menu drawn in the view, not an `NSMenu`: it sits where the mockups
/// put it and a demo frame can show it open.
struct ChatMenuCard: View {
    let items: [ChatMenuItem]
    var width: CGFloat = 240
    var highlighted: String?
    @Environment(\.dmMetrics) private var m
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(1)) {
            ForEach(items) { item in
                switch item.kind {
                case .separator:
                    Rectangle().fill(Color.dmDivider).frame(height: 1)
                        .padding(.vertical, m.pt(4)).padding(.horizontal, m.pt(6))
                case .header:
                    DMSectionLabel(text: item.title.uppercased())
                        .padding(.horizontal, m.pt(10)).padding(.top, m.pt(6)).padding(.bottom, m.pt(2))
                case .item:
                    row(item)
                }
            }
        }
        .padding(m.pt(5))
        .frame(width: m.pt(width))
        .background(Color(hex: 0x1D232B), in: RoundedRectangle(cornerRadius: m.pt(DMRadius.tile)))
        .overlay(RoundedRectangle(cornerRadius: m.pt(DMRadius.tile)).stroke(Color.dmStroke, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: m.pt(18), y: m.pt(8))
    }

    private func row(_ item: ChatMenuItem) -> some View {
        let lit = !item.disabled && (hovered == item.id || (hovered == nil && highlighted == item.id))
        return HStack(spacing: m.pt(8)) {
            Image(systemName: "checkmark")
                .font(.dm(10, weight: .bold))
                .opacity(item.checked ? 1 : 0)
                .frame(width: m.pt(12))
            if let harness = item.harness { ChatHarnessGlyph(harness: harness, size: 14) }
            if let systemImage = item.systemImage {
                Image(systemName: systemImage).font(.dm(11)).foregroundStyle(lit ? .white : Color.dmMuted)
                    .frame(width: m.pt(14))
            }
            Text(verbatim: item.title).font(.dm(12.5)).lineLimit(1)
            if let detail = item.detail {
                Text(verbatim: detail).font(.dm(11))
                    .foregroundStyle(lit ? Color.white.opacity(0.7) : Color.dmMuted).lineLimit(1)
            }
            Spacer(minLength: m.pt(8))
            if let shortcut = item.shortcut {
                Text(verbatim: shortcut).font(.dm(11)).foregroundStyle(Color.dmMuted)
            }
        }
        .foregroundStyle(item.disabled ? Color.dmMuted.opacity(0.7) : Color.white.opacity(0.92))
        .padding(.horizontal, m.pt(6))
        .frame(height: m.pt(26))
        .background(RoundedRectangle(cornerRadius: m.pt(DMRadius.row)).fill(lit ? Color.accentColor.opacity(0.85) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
        .onTapGesture { if !item.disabled { item.action?() } }
    }
}

struct ChatAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The picker menus' contents, shared by the chat pane and the quick panel.
@MainActor
enum ChatMenus {
    static func harnesses(selected: HarnessID, available: [HarnessID], pick: @escaping (HarnessID) -> Void)
        -> [ChatMenuItem] {
        available.map { id in
            ChatMenuItem(
                id: "harness-" + id.rawValue, title: ChatHarness.title(id), harness: id, checked: id == selected,
                action: { pick(id) })
        } + [.separator("harness-sep"), ChatMenuItem(id: "more", title: "More coming soon", disabled: true)]
    }

    static func places(
        selected: ChatPlace, workspaces: [String], defaultPlace: ChatPlace, pick: @escaping (ChatPlace) -> Void
    ) -> [ChatMenuItem] {
        var items: [ChatMenuItem] = []
        if !workspaces.isEmpty { items.append(.header("Workspaces")) }
        for name in workspaces {
            let place = ChatPlace.workspace(name)
            items.append(ChatMenuItem(
                id: "workspace-" + name, title: name, detail: place == defaultPlace ? "(default)" : nil,
                systemImage: "server.rack", checked: place == selected, action: { pick(place) }))
        }
        if !workspaces.isEmpty { items.append(.separator("place-sep")) }
        items.append(ChatMenuItem(
            id: "workspace-local", title: ChatPlaceLabel.thisMac,
            detail: defaultPlace == .local ? "(default)" : nil, systemImage: "laptopcomputer",
            checked: selected == .local, action: { pick(.local) }))
        return items
    }
}

enum ChatPlaceLabel {
    static let thisMac = "This Mac"

    static func title(_ place: ChatPlace) -> String {
        place.workspaceName ?? thisMac
    }

    static func symbol(_ place: ChatPlace) -> String {
        place == .local ? "laptopcomputer" : "server.rack"
    }
}
