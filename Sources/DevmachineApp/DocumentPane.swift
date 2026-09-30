import SwiftUI
import AppKit
import DevmachineCore

/// The pane beside the terminal: the open file and the preview tabs, each a
/// tab in one strip, the way an editor keeps a file next to a browser.
struct DocumentPane: View {
    @EnvironmentObject private var viewerStore: FileViewerStore
    @ObservedObject private var previews = PreviewStore.shared

    static func isVisible(fileOpen: Bool, previewTabs: Int) -> Bool {
        fileOpen || previewTabs > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            strip
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.dmSidebarBg)
        .environment(\.colorScheme, .dark)
        .onChange(of: viewerStore.path) { _, path in
            if path != nil { previews.select(nil) }
        }
        .onChange(of: viewerStore.isOpen) { _, open in
            if !open, previews.selectedTabID == nil { previews.select(previews.tabs.last?.id) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tab = previews.selectedTab {
            PreviewPaneView(tab: tab)
                .id(tab.id)
        } else if viewerStore.isOpen {
            FileViewerView(showsTab: false)
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if viewerStore.isOpen {
                    DocumentTabChip(
                        systemImage: FileViewerView.icon(for: viewerStore.preview?.kind),
                        title: viewerStore.preview?.name
                            ?? (viewerStore.path as NSString?)?.lastPathComponent ?? "Viewer",
                        selected: previews.selectedTabID == nil,
                        closeHelp: "Close the file",
                        select: { previews.select(nil) },
                        close: { viewerStore.close() })
                }
                ForEach(previews.tabs) { tab in
                    DocumentTabChip(
                        systemImage: "globe",
                        title: tab.title,
                        selected: previews.selectedTabID == tab.id,
                        closeHelp: "Close the preview",
                        select: { previews.select(tab.id) },
                        close: { previews.close(tab.id) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dmSidebarBg)
    }
}

/// The close mark sits beside the part that selects, never inside it: a tap
/// gesture on the whole chip took the click before the mark's button ever
/// saw it, so a tab could not be closed.
struct DocumentTabChip: View {
    let systemImage: String
    let title: String
    let selected: Bool
    let closeHelp: String
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.dm(10))
                    .foregroundStyle(Color(hex: 0x5AA9E6))
                Text(verbatim: title)
                    .font(.dm(11.5))
                    .foregroundStyle(.white.opacity(selected ? 0.9 : 0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .contextMenu {
                Button(closeHelp, action: close)
            }
            DMIconButton(
                systemImage: "xmark", size: 9, weight: .semibold, tint: .white.opacity(0.45),
                hitSize: DMHitSize.compact, action: close)
                .help(closeHelp)
                .padding(.trailing, 4)
        }
        .background(selected ? Color.dmContentBg : (hovering ? Color.dmHover : Color.clear))
        .onHover { hovering = $0 }
        .onMiddleClick(while: hovering, perform: close)
    }
}

private extension View {
    /// A middle click closes a tab, as in a browser. A local event monitor
    /// that acts only while the pointer is over the chip, so nothing is laid
    /// over the close mark to take its clicks.
    func onMiddleClick(while active: Bool, perform action: @escaping () -> Void) -> some View {
        modifier(MiddleClickModifier(active: active, action: action))
    }
}

private struct MiddleClickModifier: ViewModifier {
    let active: Bool
    let action: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, isActive in isActive ? install() : remove() }
            .onDisappear(perform: remove)
    }

    private func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2 else { return event }
            action()
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
