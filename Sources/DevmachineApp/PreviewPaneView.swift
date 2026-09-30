import SwiftUI
import AppKit
import DevmachineCore

/// One preview tab: a small browser toolbar over the page. The address shown
/// is the page's real one, read from the web view, never the one asked for.
struct PreviewPaneView: View {
    let tab: PreviewTab
    @ObservedObject private var previews = PreviewStore.shared

    var body: some View {
        switch tab.state {
        case let .connecting(message):
            VStack(spacing: 0) {
                PreviewToolbarPlaceholder(address: tab.title)
                DMStatusView(kind: .loading(message.isEmpty ? "Opening…" : message))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .failed(message):
            VStack(spacing: 0) {
                PreviewToolbarPlaceholder(address: tab.title)
                DMErrorStateView(
                    state: DMErrorState(title: "Couldn't open \(tab.title)", message: message),
                    retry: { previews.retry(tab.id) })
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .ready, .page:
            PreviewLoadedView(tab: tab, page: PreviewWebViews.shared.page(for: tab.id))
        }
    }
}

private struct PreviewLoadedView: View {
    let tab: PreviewTab
    @ObservedObject var page: PreviewPage

    var body: some View {
        VStack(spacing: 0) {
            PreviewToolbar(page: page, fallbackAddress: tab.title)
            ZStack(alignment: .top) {
                PreviewWebViewHost(page: page)
                if let failure = page.failure {
                    DMErrorStateView(
                        state: DMErrorState(title: "The page didn't load", message: failure),
                        retry: { page.reload() })
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.dmContentBg)
                }
                if let blocked = page.blocked {
                    DMBanner(message: "Blocked a link to \(blocked.absoluteString): previews open web pages only.",
                             lineLimit: 2) {
                        DMIconButton(systemImage: "xmark", size: 10, weight: .semibold) { page.dismissBlocked() }
                            .help("Dismiss")
                    }
                    .background(Color.dmSidebarBg)
                }
            }
        }
        .onAppear { page.show(tab.state) }
        .onChange(of: tab.state) { _, state in page.show(state) }
    }
}

/// The toolbar of a tab that has no page yet: the same row, nothing to press.
private struct PreviewToolbarPlaceholder: View {
    let address: String
    @ObservedObject private var split = DocumentSplitState.shared

    var body: some View {
        PreviewToolbarRow(
            address: .constant(address), canGoBack: false, canGoForward: false, isLoading: false,
            canOpenInBrowser: false, enabled: false, isMaximized: split.isMaximized,
            onEditingChanged: { _ in }, back: {}, forward: {},
            reloadOrStop: {}, submit: {}, openInBrowser: {}, toggleMaximized: split.toggleMaximized)
    }
}

private struct PreviewToolbar: View {
    @ObservedObject var page: PreviewPage
    let fallbackAddress: String
    @ObservedObject private var split = DocumentSplitState.shared
    @State private var typed = ""
    @State private var editing = false

    private var address: String { page.url?.absoluteString ?? fallbackAddress }

    var body: some View {
        PreviewToolbarRow(
            address: Binding(get: { editing ? typed : address }, set: { typed = $0 }),
            canGoBack: page.canGoBack, canGoForward: page.canGoForward, isLoading: page.isLoading,
            canOpenInBrowser: page.url.map(PreviewURLPolicy.isWeb) == true, enabled: true,
            isMaximized: split.isMaximized,
            onEditingChanged: { isEditing in
                editing = isEditing
                if isEditing { typed = address }
            },
            back: page.goBack, forward: page.goForward,
            reloadOrStop: { page.isLoading ? page.webView.stopLoading() : page.reload() },
            submit: go,
            openInBrowser: {
                if let url = page.url, PreviewURLPolicy.isWeb(url) { NSWorkspace.shared.open(url) }
            },
            toggleMaximized: toggleMaximized)
    }

    /// The terminal stays under a maximized preview, so the keyboard moves to
    /// the page: typing must not reach a shell nobody can see.
    private func toggleMaximized() {
        split.toggleMaximized()
        if split.isMaximized { page.webView.window?.makeFirstResponder(page.webView) }
    }

    /// The address bar is this Mac's browser: `localhost` here is this Mac.
    /// A workspace port is opened from the Preview tab, which tunnels it.
    private func go() {
        guard let input = PreviewInput.parse(typed) else { return }
        switch input {
        case let .url(url): page.go(to: url)
        case let .port(port, path): page.go(to: PreviewResolution.localhost(port, path: path))
        }
    }
}

private struct PreviewToolbarRow: View {
    @Binding var address: String
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let canOpenInBrowser: Bool
    let enabled: Bool
    let isMaximized: Bool
    let onEditingChanged: (Bool) -> Void
    let back: () -> Void
    let forward: () -> Void
    let reloadOrStop: () -> Void
    let submit: () -> Void
    let openInBrowser: () -> Void
    let toggleMaximized: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            DMButton(icon: "chevron.left", label: "Back", size: .small, action: back)
                .disabled(!canGoBack)
            DMButton(icon: "chevron.right", label: "Forward", size: .small, action: forward)
                .disabled(!canGoForward)
            DMButton(icon: isLoading ? "xmark" : "arrow.clockwise", label: isLoading ? "Stop" : "Reload",
                     size: .small, action: reloadOrStop)
                .disabled(!enabled)
            TextField("Address", text: $address)
                .textFieldStyle(.plain)
                .font(.dm(11.5, design: .monospaced))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .dmSurface(Color.dmSelection, radius: DMRadius.row, style: .continuous)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in onEditingChanged(isFocused) }
                .onSubmit {
                    submit()
                    focused = false
                }
                .disabled(!enabled)
            DMButton("Open in browser", systemImage: "safari", variant: .ghost, size: .small, action: openInBrowser)
                .disabled(!canOpenInBrowser)
            DMButton(
                icon: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: isMaximized ? "Restore the terminal" : "Maximize preview",
                size: .small, action: toggleMaximized)
                .help(isMaximized ? "Restore the terminal (⇧⌘↩)" : "Maximize preview (⇧⌘↩)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.dmContentBg)
    }
}
