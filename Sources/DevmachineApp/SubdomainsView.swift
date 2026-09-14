import SwiftUI
import AppKit
import DevmachineCore

struct SubdomainsView: View {
    @EnvironmentObject var store: CaddyStore
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
                AddSubdomainSheet(settings: settings).environmentObject(store)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(settingsStore.settings == nil)
            .help("Add subdomain")
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.dmRowText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                store.addError = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { refresh() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No subdomains found")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sitesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(store.sites, id: \.address) { site in
                    DMRow(
                        systemImage: site.kind == "redir" ? "arrow.uturn.right" : "globe",
                        iconColor: .dmMuted,
                        title: site.address,
                        trailing: AnyView(
                            Text(site.target)
                                .font(.system(size: 11))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Spacer()
                Toggle("TLS only", isOn: $tlsOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
            .padding(10)
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            ScrollView {
                Text(filteredLogs)
                    .font(.system(size: 10, design: .monospaced))
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
