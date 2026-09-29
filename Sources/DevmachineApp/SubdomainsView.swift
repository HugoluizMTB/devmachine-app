import SwiftUI
import AppKit
import DevmachineCore

/// Column widths shared by the header row and every data row, so the two
/// stay aligned without measuring anything.
private enum SubdomainColumns {
    static let workspace: CGFloat = 130
    static let port: CGFloat = 64
    static let status: CGFloat = 110
    static let actions: CGFloat = 96
}

private enum DNSColumns {
    static let type: CGFloat = 64
    static let ttl: CGFloat = 64
}

private struct LogsRequest: Identifiable {
    let host: String
    var id: String { host }
}

struct SubdomainsView: View {
    @EnvironmentObject var store: CaddyStore
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showAdd = false
    @State private var searchText = ""
    @State private var selectedTab: SubdomainsTab
    @State private var logsRequest: LogsRequest?
    @State private var confirmRemoveHost: String?

    /// `initialTab` only ever differs from `.sites` for the website's demo
    /// screenshots, which need to open straight onto a DNS provider tab.
    init(initialTab: SubdomainsTab = .sites) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            tabsBar
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            body(for: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .onAppear {
            if store.rows.isEmpty { store.refresh() }
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
        .sheet(item: $logsRequest) { request in
            LogsSheet(host: request.host)
                .environmentObject(store)
        }
        .confirmationDialog(
            confirmRemoveHost.map { "Stop publishing \($0)?" } ?? "",
            isPresented: Binding(
                get: { confirmRemoveHost != nil },
                set: { if !$0 { confirmRemoveHost = nil } }),
            titleVisibility: .visible
        ) {
            Button("Stop publishing", role: .destructive) {
                if let host = confirmRemoveHost { store.remove(host: host) }
                confirmRemoveHost = nil
            }
            Button("Cancel", role: .cancel) { confirmRemoveHost = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Subdomains")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            DMSearchField(prompt: "Search subdomains", text: $searchText)
                .frame(maxWidth: 240)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .dmSurface(Color.dmSelection, radius: DMRadius.control)

            Spacer()

            if store.isLoading || store.isLoadingDNSProviders {
                ProgressView().controlSize(.small)
            }
            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { store.refresh() }
                .help("Refresh")
            Button {
                showAdd = true
            } label: {
                Label("Add subdomain", systemImage: "plus")
                    .font(.dm(12, weight: .semibold))
            }
            .buttonStyle(.dmChipProminent)
            .disabled(settingsStore.settings == nil)
        }
        .padding(10)
    }

    private var tabsBar: some View {
        DMTabStrip(
            tabs: SubdomainsTabs.build(providers: store.dnsProviders),
            selection: $selectedTab,
            title: { $0.title }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func body(for tab: SubdomainsTab) -> some View {
        switch tab {
        case .sites:
            sitesBody
        case .provider(let name):
            providerBody(name)
        }
    }

    // MARK: - Sites tab

    private var visibleRows: [SubdomainRow] {
        store.rows.filter { model.showsOwner($0.resolvedWorkspace ?? $0.site.workspace) }
    }

    private var searchedRows: [SubdomainRow] {
        RowSearch.filter(visibleRows, query: searchText) { row in
            [row.site.host, row.workspaceDisplay ?? "", String(row.site.port)]
        }
    }

    @ViewBuilder
    private var sitesBody: some View {
        if let err = store.errorText {
            DMStatusView(kind: .failed(message: err, retry: { store.refresh() }))
        } else if store.rows.isEmpty && store.isLoading {
            DMStatusView(kind: .loading("Loading…"))
        } else if visibleRows.isEmpty {
            DMStatusView(kind: .empty(systemImage: "globe", text: "No subdomains found"))
        } else {
            VStack(spacing: 0) {
                if let addError = store.addError {
                    DMBanner(message: addError) {
                        DMIconButton(systemImage: "xmark", tint: nil) { store.addError = nil }
                    }
                }
                if let removeError = store.removeError {
                    DMBanner(message: removeError) {
                        DMIconButton(systemImage: "xmark", tint: nil) { store.removeError = nil }
                    }
                }
                VStack(spacing: 0) {
                    sitesTableHeader
                    Rectangle().fill(Color.dmDivider).frame(height: 1)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchedRows) { row in
                                siteRow(row)
                                Rectangle().fill(Color.dmDivider).frame(height: 1)
                            }
                        }
                    }
                    footer(showing: searchedRows.count, of: visibleRows.count)
                }
                .dmSurface(Color.clear, radius: DMRadius.tile)
                .padding(10)
            }
        }
    }

    private var sitesTableHeader: some View {
        HStack(spacing: 10) {
            columnLabel("NAME").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("WORKSPACE").frame(width: SubdomainColumns.workspace, alignment: .leading)
            columnLabel("PORT").frame(width: SubdomainColumns.port, alignment: .leading)
            columnLabel("STATUS").frame(width: SubdomainColumns.status, alignment: .leading)
            columnLabel("").frame(width: SubdomainColumns.actions, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(.dm(10, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Color.dmMuted)
    }

    private func siteRow(_ row: SubdomainRow) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                Text(row.site.host)
                    .font(.dm(12))
                    .foregroundStyle(Color.dmRowText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.site.note ?? row.site.host)

            workspaceCell(row)
                .font(.dm(12))
                .lineLimit(1)
                .frame(width: SubdomainColumns.workspace, alignment: .leading)

            Text(verbatim: "\(row.site.port)")
                .font(.dm(12, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .frame(width: SubdomainColumns.port, alignment: .leading)

            statusPill(row.site.status)
                .frame(width: SubdomainColumns.status, alignment: .leading)

            actions(for: row)
                .frame(width: SubdomainColumns.actions, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func workspaceCell(_ row: SubdomainRow) -> some View {
        if let workspace = row.workspaceDisplay {
            if row.workspaceIsContainerHint {
                Text(workspace).foregroundStyle(Color.dmMuted).italic()
            } else {
                Text(workspace).foregroundStyle(Color.dmRowText)
            }
        } else {
            Text("—").foregroundStyle(Color.dmMuted)
        }
    }

    private func statusPill(_ status: ExposedSite.Status) -> some View {
        DMPill(text: status.title.uppercased(), color: statusColor(status))
    }

    private func statusColor(_ status: ExposedSite.Status) -> Color {
        switch status {
        case .published: return .green
        case .pending: return .yellow
        case .differs: return .red
        case .unmanaged: return .blue
        case .unknown: return .dmMuted
        }
    }

    private func actions(for row: SubdomainRow) -> some View {
        HStack(spacing: 2) {
            DMIconButton(systemImage: "arrow.up.right.square", size: 11, hitSize: DMHitSize.compact) {
                open(row.site.host)
            }
            .help("Open in browser")

            DMIconButton(systemImage: "doc.text", size: 11, hitSize: DMHitSize.compact) {
                logsRequest = LogsRequest(host: row.site.host)
            }
            .help("Logs")

            DMIconButton(systemImage: "trash", size: 11, tint: .red, hitSize: DMHitSize.compact) {
                confirmRemoveHost = row.site.host
            }
            .help("Stop publishing")
            .opacity(store.removingHost == row.site.host ? 0.4 : 1)
            .disabled(store.removingHost == row.site.host)
        }
    }

    private func footer(showing: Int, of total: Int) -> some View {
        HStack {
            Text(verbatim: "Showing \(showing) of \(total)")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func open(_ host: String) {
        guard let url = URL(string: "https://\(host)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Provider tabs

    @ViewBuilder
    private func providerBody(_ provider: String) -> some View {
        if store.dnsLoadingProviders.contains(provider) && store.dnsRecordsByProvider[provider] == nil {
            DMStatusView(kind: .loading("Loading \(provider) records…"))
                .onAppear { store.loadRecords(provider: provider) }
        } else if let err = store.dnsErrorByProvider[provider] {
            DMStatusView(kind: .failed(message: err, retry: { store.loadRecords(provider: provider, force: true) }))
        } else if let records = store.dnsRecordsByProvider[provider] {
            let searched = RowSearch.filter(records, query: searchText) { [$0.name, $0.type, $0.value] }
            if records.isEmpty {
                DMStatusView(kind: .empty(systemImage: "server.rack", text: "No records for this zone"))
            } else {
                VStack(spacing: 0) {
                    dnsTableHeader
                    Rectangle().fill(Color.dmDivider).frame(height: 1)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searched) { record in
                                dnsRow(record)
                                Rectangle().fill(Color.dmDivider).frame(height: 1)
                            }
                        }
                    }
                    footer(showing: searched.count, of: records.count)
                }
                .dmSurface(Color.clear, radius: DMRadius.tile)
                .padding(10)
            }
        } else {
            DMStatusView(kind: .loading("Loading \(provider) records…"))
                .onAppear { store.loadRecords(provider: provider) }
        }
    }

    private var dnsTableHeader: some View {
        HStack(spacing: 10) {
            columnLabel("NAME").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("TYPE").frame(width: DNSColumns.type, alignment: .leading)
            columnLabel("CONTENT").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("TTL").frame(width: DNSColumns.ttl, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func dnsRow(_ record: DNSRecordRow) -> some View {
        HStack(spacing: 10) {
            Text(record.name)
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DMPill(text: record.type, color: .dmTag(record.type))
                .frame(width: DNSColumns.type, alignment: .leading)
            Text(record.value)
                .font(.dm(12, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(record.ttl)")
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .frame(width: DNSColumns.ttl, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// One row's Caddy log tail, read on open and not kept once dismissed.
private struct LogsSheet: View {
    @EnvironmentObject var store: CaddyStore
    @Environment(\.dismiss) private var dismiss
    let host: String

    @State private var text = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(host)
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Spacer()
                Button("Close") { dismiss() }
            }
            Group {
                if loading {
                    DMStatusView(kind: .loading("Reading logs…"), fillsHeight: false)
                } else if let error {
                    DMStatusView(kind: .failed(message: error, retry: load), fillsHeight: false)
                } else {
                    ScrollView {
                        Text(text)
                            .font(.dm(10, design: .monospaced))
                            .foregroundStyle(Color.dmRowText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 320)
        }
        .padding(16)
        .frame(width: 520)
        .background(Color.dmContentBg)
        .task { load() }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            let result = await store.fetchLogs(host: host)
            switch result {
            case .success(let value):
                text = value
            case .failure(let err):
                error = (err as? LocalizedError)?.errorDescription ?? err.localizedDescription
            }
            loading = false
        }
    }
}
