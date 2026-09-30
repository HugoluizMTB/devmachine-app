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

private struct DocumentTabChip: View {
    let systemImage: String
    let title: String
    let selected: Bool
    let closeHelp: String
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.dm(10))
                .foregroundStyle(Color(hex: 0x5AA9E6))
            Text(verbatim: title)
                .font(.dm(11.5))
                .foregroundStyle(.white.opacity(selected ? 0.9 : 0.55))
                .lineLimit(1)
            DMIconButton(systemImage: "xmark", size: 9, weight: .semibold, tint: .white.opacity(0.45), action: close)
                .help(closeHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Color.dmContentBg : (hovering ? Color.dmHover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: select)
    }
}
