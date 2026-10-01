import SwiftUI
import AppKit
import DevmachineCore

/// The context panel's Preview tab: what the selected session's workspace
/// can show in a browser, and a field for anything else.
struct PreviewSidebarTab: View {
    @Environment(\.dmMetrics) private var m
    let place: PreviewPlace
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @ObservedObject private var targets = PreviewTargetsStore.shared
    @ObservedObject private var previews = PreviewStore.shared
    @ObservedObject private var tunnels = TunnelManager.shared
    @State private var address = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    listBody
                    tunnelsSection
                    hint
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            load(force: false)
            takePendingFocus()
        }
        .onChange(of: place) { _, _ in load(force: false) }
        .onChange(of: model.pendingPreviewField) { _, _ in takePendingFocus() }
    }

    private var parsed: PreviewInput? { PreviewInput.parse(address) }

    private var field: some View {
        VStack(alignment: .leading, spacing: m.pt(5)) {
            HStack(spacing: m.space.sm) {
                TextField("Port or URL", text: $address)
                    .dmField()
                    .font(.dm(12, design: .monospaced))
                    .focused($fieldFocused)
                    .onSubmit { openTyped() }
                DMButton("Open", variant: .outline, size: .small) { openTyped() }
                    .disabled(parsed == nil)
            }
            if !address.isEmpty, parsed == nil {
                Text(verbatim: "Type a port like 3000, or an http(s) address.")
                    .font(.dm(10.5))
                    .foregroundStyle(Color.dmMuted)
            }
        }
        .padding(.horizontal, m.pt(14))
        .padding(.top, m.pt(10))
        .padding(.bottom, m.space.xs)
    }

    @ViewBuilder
    private var listBody: some View {
        switch targets.phase(for: place) {
        case .loading, nil:
            DMStatusView(kind: .loading("Looking for sites and dev servers…"))
                .frame(minHeight: m.pt(160))
        case let .failed(message):
            DMStatusView(kind: .failed(
                title: "Couldn't list what to preview", message: message, retry: { load(force: true) }))
                .frame(minHeight: m.pt(200))
        case let .loaded(list):
            let sites = list.filter { $0.siteURL != nil }
            let ports = list.filter { $0.siteURL == nil }
            if !sites.isEmpty {
                section("SITES", count: sites.count) {
                    ForEach(sites) { targetRow($0) }
                }
            }
            section(place == .thisMac ? "LISTENING ON THIS MAC" : "DEV SERVERS", count: ports.count, refreshes: true) {
                if ports.isEmpty {
                    Text(verbatim: "Nothing is listening yet. Start a dev server, or type its port above.")
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, m.space.xs)
                } else {
                    ForEach(ports) { targetRow($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var tunnelsSection: some View {
        let open = tunnels.openTunnels.filter { place == .workspace($0.key.workspace) }
        if !open.isEmpty {
            section("TUNNELS", count: open.count) {
                ForEach(open) { tunnel in
                    HStack(spacing: m.space.md) {
                        Image(systemName: tunnel.state == .open ? "arrow.left.arrow.right" : "hourglass")
                            .font(.dm(10))
                            .foregroundStyle(tunnel.state == .open ? Color.green : Color.dmMuted)
                            .frame(width: m.pt(14))
                        Text(verbatim: "localhost:\(tunnel.localPort) → \(tunnel.key.remotePort)")
                            .font(.dm(12, design: .monospaced))
                            .foregroundStyle(Color.dmRowText)
                            .lineLimit(1)
                        Spacer(minLength: m.space.xs)
                        DMIconButton(systemImage: "stop.circle", size: 12) { tunnels.stop(tunnel.key) }
                            .help("Close the tunnel")
                    }
                    .padding(.vertical, m.space.xs)
                }
            }
        }
    }

    private var hint: some View {
        let other = (model.settings?.linkOpening ?? .defaultBrowser).opposite
        return Text(verbatim: "⌥-click opens in \(other == .inApp ? "Devmachine" : "the default browser").")
            .font(.dm(10.5))
            .foregroundStyle(Color.dmMuted)
            .padding(.horizontal, m.pt(14))
            .padding(.vertical, m.space.lg)
    }

    private func section<Content: View>(
        _ title: String, count: Int, refreshes: Bool = false, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DMSection(
            contentSpacing: 6,
            padding: EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 14),
            label: { DMSectionLabel(text: title) },
            trailing: {
                HStack(spacing: m.space.sm) {
                    if refreshes {
                        DMAgeLabel(
                            since: targets.refreshedAt[place.key],
                            staleAfter: CachePolicy.standard.ttl(for: .ports),
                            isRefreshing: targets.isRefreshing(place))
                        DMIconButton(systemImage: "arrow.clockwise", size: 10, weight: .semibold) { load(force: true) }
                            .help("Look again")
                    }
                    DMSectionValue(text: "\(count)")
                }
            },
            content: { VStack(alignment: .leading, spacing: 0) { content() } })
    }

    private func targetRow(_ target: PreviewTarget) -> some View {
        HStack(spacing: m.space.md) {
            Image(systemName: target.siteURL == nil ? "play.display" : "globe")
                .font(.dm(11))
                .foregroundStyle(Color(hex: 0x5AA9E6))
                .frame(width: m.pt(14))
            Text(verbatim: target.title)
                .font(.dm(12, design: target.siteURL == nil ? .monospaced : .default))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.middle)
            if !target.label.isEmpty {
                Text(verbatim: target.siteURL == nil ? "· \(target.label)" : "→ \(target.label)")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: m.space.xs)
            if hasTunnel(target) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.dm(9))
                    .foregroundStyle(Color.green)
                    .help("A tunnel to this port is open")
            }
        }
        .padding(.vertical, m.pt(5))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            open(target, inverted: NSEvent.modifierFlags.contains(.option))
        }
        .contextMenu {
            Button("Open in Devmachine") { open(target, forced: .inApp) }
            Button("Open in Default Browser") { open(target, forced: .defaultBrowser) }
        }
    }

    private func hasTunnel(_ target: PreviewTarget) -> Bool {
        guard case let .port(port) = target.kind, case let .workspace(name) = place else { return false }
        return tunnels.tunnel(for: TunnelKey(workspace: name, remotePort: port))?.state == .open
    }

    private func request(for target: PreviewTarget) -> PreviewRequest {
        switch target.kind {
        case let .port(port):
            return PreviewRequest(place: place, input: .port(port, path: ""))
        case .site:
            return PreviewRequest(place: place, input: .url(target.siteURL!))
        }
    }

    private func open(_ target: PreviewTarget, inverted: Bool) {
        previews.open(request(for: target), inverted: inverted)
    }

    private func open(_ target: PreviewTarget, forced: LinkOpening) {
        let preference = model.settings?.linkOpening ?? .defaultBrowser
        previews.open(request(for: target), inverted: preference != forced)
    }

    private func openTyped() {
        guard let parsed else { return }
        previews.open(PreviewRequest(place: place, input: parsed),
                      inverted: NSEvent.modifierFlags.contains(.option))
        address = ""
    }

    private func load(force: Bool) {
        targets.load(place, stats: stats, force: force)
    }

    private func takePendingFocus() {
        guard model.pendingPreviewField else { return }
        model.pendingPreviewField = false
        DispatchQueue.main.async { fieldFocused = true }
    }
}
