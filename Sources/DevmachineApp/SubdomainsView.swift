import SwiftUI
import AppKit
import DevmachineCore

struct SubdomainsView: View {
    @EnvironmentObject var store: CaddyStore
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var tlsOnly = false
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .onAppear {
            if store.sites.isEmpty { refresh() }
        }
        .overlay(alignment: .bottomTrailing) {
            if let task = store.task {
                DMToastCard(task: task)
                    .padding(18)
            }
        }
        .sheet(isPresented: $showAdd) {
            if let settings = settingsStore.settings {
                AddSubdomainSheet(settings: settings, workspaces: model.visibleWorkspaces)
                    .environmentObject(store)
            }
        }
    }

    private func refresh() {
        guard let alias = settingsStore.settings?.hostAlias else { return }
        store.refresh(alias: alias)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Subdomains")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            DMIconButton(systemImage: "plus", tint: nil) { showAdd = true }
            .disabled(settingsStore.settings == nil)
            .help("Add subdomain")
            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { refresh() }
                .help("Refresh")
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let addError = store.addError {
                addErrorBanner(addError)
            }
            if let err = store.errorText {
                errorView(err)
            } else if store.sites.isEmpty && store.isLoading {
                loadingView
            } else if store.sites.isEmpty {
                emptyView
            } else {
                HSplitView {
                    sitesList
                        .frame(minWidth: 260)
                    logsPane
                        .frame(minWidth: 300)
                }
            }
        }
    }

    private func addErrorBanner(_ message: String) -> some View {
        DMBanner(message: message) {
            DMIconButton(systemImage: "xmark", tint: nil) { store.addError = nil }
        }
    }

    private func errorView(_ message: String) -> some View {
        DMStatusView(kind: .failed(message: message, retry: refresh))
    }

    private var loadingView: some View {
        DMStatusView(kind: .loading("Loading…"))
    }

    private var emptyView: some View {
        DMStatusView(kind: .empty(systemImage: "globe", text: "No subdomains found"))
    }

    /// A site whose port belongs to a workspace turned off in Settings is left
    /// out. A site the host cannot attribute — the apex, anything not started
    /// from a home folder — stays: hiding what has no owner would hide the
    /// machine's own pages.
    private var visibleSites: [CaddySite] {
        store.sites.filter { model.showsOwner($0.workspace) }
    }

    private var sitesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(visibleSites, id: \.address) { site in
                    DMRow(
                        systemImage: site.kind == "redir" ? "arrow.uturn.right" : "globe",
                        iconColor: .dmMuted,
                        title: site.address,
                        trailing: AnyView(
                            Text(site.target)
                                .font(.dm(11))
                                .foregroundStyle(Color.dmMuted)
                                .lineLimit(1)
                        ),
                        tap: { open(site) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var logsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Caddy log")
                    .font(.dm(12, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Spacer()
                Toggle("TLS only", isOn: $tlsOnly)
                    .toggleStyle(.checkbox)
                    .font(.dm(11))
            }
            .padding(10)
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            ScrollView {
                Text(filteredLogs)
                    .font(.dm(10, design: .monospaced))
                    .foregroundStyle(Color.dmRowText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
    }

    private var filteredLogs: String {
        guard tlsOnly else { return store.logs }
        let lines = store.logs.split(separator: "\n", omittingEmptySubsequences: false)
        let filtered = lines.filter {
            $0.localizedCaseInsensitiveContains("acme") || $0.localizedCaseInsensitiveContains("tls")
        }
        return filtered.isEmpty ? "No TLS/acme lines in the current tail." : filtered.joined(separator: "\n")
    }

    private func open(_ site: CaddySite) {
        guard let url = URL(string: "https://\(site.address)") else { return }
        NSWorkspace.shared.open(url)
    }
}
