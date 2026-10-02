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
    @Environment(\.dmMetrics) private var m
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

    private static let tableInset: CGFloat = 6
    private static let cellInset: CGFloat = 8
    private static let cellVertical: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.showsMachinePicker {
                machinePicker
            }
            tabsBar
            body(for: selectedTab)
        }
        .animation(.easeOut(duration: 0.2), value: showsSkeleton)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .onAppear {
            store.appear()
            openRequestedAdd()
        }
        .onChange(of: model.pendingAddSubdomain) { _, _ in openRequestedAdd() }
        .onChange(of: store.dnsProviders) {
            if case .provider(let name) = selectedTab, !store.dnsProviders.contains(name) {
                selectedTab = .sites
            }
        }
        .sheet(isPresented: $showAdd) {
            if let settings = settingsStore.settings {
                AddSubdomainSheet(
                    settings: settings, workspaces: model.visibleWorkspaces,
                    onMachine: store.workspacesOnSelectedMachine)
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
        HStack(spacing: m.pt(10)) {
            Text("Subdomains")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            DMSearchField(prompt: "Search subdomains", text: $searchText)
                .frame(maxWidth: m.pt(240))
                .padding(.horizontal, m.space.md)
                .padding(.vertical, m.pt(5))
                .background(Color.dmSelection, in: RoundedRectangle(cornerRadius: m.radius.control, style: .continuous))

            Spacer()

            DMAgeLabel(since: store.selectedState?.refreshedAt, staleAfter: CachePolicy.standard.ttl(for: .sites))
            if (store.isLoading && !store.showsSitesSkeleton) || store.isLoadingDNSProviders {
                ProgressView().controlSize(.small)
            }
            DMIconButton(systemImage: "arrow.clockwise", size: DMMetrics.baseFontSize, tint: nil) { store.refresh() }
                .help("Refresh")
            DMButton("Add subdomain", systemImage: "plus", size: .small) {
                showAdd = true
            }
            .disabled(settingsStore.settings == nil)
        }
        .padding(.horizontal, m.pt(14))
        .padding(.top, m.pt(10))
        .padding(.bottom, m.space.sm)
    }

    /// One tab per configured machine; each loads, fails and counts on its
    /// own, so the tab says which one needs a look.
    private var machinePicker: some View {
        HStack(spacing: m.pt(10)) {
            columnLabel("MACHINE")
            DMTabStrip(
                tabs: store.machines.map(\.name),
                selection: Binding(
                    get: { store.selectedMachine ?? "" },
                    set: { store.select($0) }),
                title: machineTitle,
                systemImage: machineSymbol,
                fontSize: 12
            )
        }
        .padding(.horizontal, m.pt(14))
        .padding(.vertical, m.space.xs)
    }

    private func machineTitle(_ name: String) -> String {
        guard let state = store.sitesByMachine[name], state.hasLoaded,
              state.errorText == nil, state.notSetUpMessage == nil else { return name }
        return "\(name) · \(state.rows.count)"
    }

    private func machineSymbol(_ name: String) -> String? {
        if store.sitesByMachine[name]?.errorText != nil { return "exclamationmark.triangle" }
        return store.machines.first { $0.name == name }?.isSelf == true ? "laptopcomputer" : "server.rack"
    }

    private var tabsBar: some View {
        DMTabStrip(
            tabs: SubdomainsTabs.build(providers: store.dnsProviders),
            selection: $selectedTab,
            title: { $0.title },
            fontSize: 12,
            horizontalPadding: 10,
            verticalPadding: 4,
            cornerRadius: DMRadius.row,
            spacing: 2,
            grouped: true
        )
        .padding(.horizontal, m.pt(14))
        .padding(.top, m.space.xs)
        .padding(.bottom, m.pt(10))
    }

    private var showsSkeleton: Bool {
        switch selectedTab {
        case .sites: return store.showsSitesSkeleton
        case .provider(let name): return store.dnsPhase(for: name) == .skeleton
        }
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
        if let err = store.machinesError {
            DMStatusView(kind: .failed(
                title: "Couldn't read the machines", message: err, retry: { store.refresh() }))
        } else if let err = store.selectedState?.errorText {
            DMStatusView(kind: .failed(
                title: store.selectedMachine.map { "\($0) could not be read" },
                message: err, retry: retrySelectedMachine))
        } else if let message = store.notSetUpMessage {
            DMStatusView(kind: .empty(systemImage: "server.rack", text: message))
        } else if store.showsSitesSkeleton {
            skeletonTable(header: sitesTableHeader) { siteSkeletonRow($0) }
        } else if visibleRows.isEmpty {
            DMStatusView(kind: .empty(systemImage: "globe", text: emptySitesText))
        } else {
            VStack(spacing: 0) {
                if let refreshError = store.selectedState?.refreshError {
                    DMBanner(message: "Couldn't refresh: \(refreshError)", lineLimit: 2) {
                        DMIconButton(systemImage: "arrow.clockwise", size: DMMetrics.baseFontSize, tint: nil) { retrySelectedMachine() }
                            .help("Try again")
                    }
                }
                VStack(spacing: 0) {
                    sitesTableHeader
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(searchedRows.enumerated()), id: \.element.id) { index, row in
                                DMTableRow(index: index) { siteRow(row) }
                            }
                        }
                    }
                    footer(showing: searchedRows.count, of: visibleRows.count)
                }
                .padding(.horizontal, m.pt(Self.tableInset))
            }
            .transition(.opacity)
        }
    }

    /// A table before its first rows: the real column header, as many
    /// placeholder rows as the height holds, and the footer's place.
    private func skeletonTable<Header: View, Row: View>(
        header: Header, @ViewBuilder row: @escaping (Int) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            header
            DMSkeleton {
                DMSkeletonRows(rowHeight: 33) { index in
                    row(index)
                }
            }
            DMSkeleton {
                DMSkeletonText(size: 11, width: .fixed(96))
                    .padding(.horizontal, m.pt(Self.cellInset))
                    .padding(.top, m.pt(Self.cellVertical))
                    .padding(.bottom, m.pt(Self.cellVertical) + m.space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, m.pt(Self.tableInset))
        .transition(.opacity)
    }

    private func siteSkeletonRow(_ index: Int) -> some View {
        HStack(spacing: m.pt(10)) {
            HStack(spacing: m.space.sm) {
                DMSkeletonBlock(width: .fixed(11), height: 11, radius: 5.5)
                DMSkeletonText(size: 12, width: .varied(index, shares: [0.55, 0.38, 0.7, 0.46, 0.62]))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DMSkeletonText(size: 12, width: .varied(index + 2, shares: [0.7, 0.5, 0.85]))
                .frame(width: m.pt(SubdomainColumns.workspace), alignment: .leading)
            DMSkeletonText(size: 12, width: .fixed(36))
                .frame(width: m.pt(SubdomainColumns.port), alignment: .leading)
            DMSkeletonBlock(width: .fixed(72), height: 14, radius: 7)
                .frame(width: m.pt(SubdomainColumns.status), alignment: .leading)
            HStack(spacing: m.space.md) {
                ForEach(0..<3, id: \.self) { _ in
                    DMSkeletonBlock(width: .fixed(11), height: 11, radius: 3)
                }
            }
            .frame(width: m.pt(SubdomainColumns.actions), alignment: .trailing)
        }
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.vertical, m.pt(Self.cellVertical))
    }

    private func dnsSkeletonRow(_ index: Int) -> some View {
        HStack(spacing: m.pt(10)) {
            DMSkeletonText(size: 12, width: .varied(index, shares: [0.4, 0.62, 0.3, 0.52]))
                .frame(maxWidth: .infinity, alignment: .leading)
            DMSkeletonBlock(width: .fixed(34), height: 14, radius: 7)
                .frame(width: m.pt(DNSColumns.type), alignment: .leading)
            DMSkeletonText(size: 12, width: .varied(index + 1, shares: [0.8, 0.55, 0.7, 0.45]))
                .frame(maxWidth: .infinity, alignment: .leading)
            DMSkeletonText(size: 11, width: .fixed(28))
                .frame(width: m.pt(DNSColumns.ttl), alignment: .trailing)
        }
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.vertical, m.pt(Self.cellVertical))
    }

    private var emptySitesText: String {
        guard store.showsMachinePicker, let machine = store.selectedMachine else { return "No subdomains found" }
        return "No subdomains on \(machine)"
    }

    private func openRequestedAdd() {
        guard model.pendingAddSubdomain else { return }
        model.pendingAddSubdomain = false
        showAdd = true
    }

    private func retrySelectedMachine() {
        if let machine = store.selectedMachine {
            store.reload(machine: machine)
        } else {
            store.refresh()
        }
    }

    private var sitesTableHeader: some View {
        HStack(spacing: m.pt(10)) {
            columnLabel("NAME").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("WORKSPACE").frame(width: m.pt(SubdomainColumns.workspace), alignment: .leading)
            columnLabel("PORT").frame(width: m.pt(SubdomainColumns.port), alignment: .leading)
            columnLabel("STATUS").frame(width: m.pt(SubdomainColumns.status), alignment: .leading)
            columnLabel("").frame(width: m.pt(SubdomainColumns.actions), alignment: .trailing)
        }
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.vertical, m.pt(Self.cellVertical))
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(.dm(10, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Color.dmMuted)
    }

    private func siteRow(_ row: SubdomainRow) -> some View {
        HStack(spacing: m.pt(10)) {
            HStack(spacing: m.space.sm) {
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
                .frame(width: m.pt(SubdomainColumns.workspace), alignment: .leading)

            Text(verbatim: "\(row.site.port)")
                .font(.dm(12, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .frame(width: m.pt(SubdomainColumns.port), alignment: .leading)

            statusPill(row.site.status)
                .frame(width: m.pt(SubdomainColumns.status), alignment: .leading)

            actions(for: row)
                .frame(width: m.pt(SubdomainColumns.actions), alignment: .trailing)
        }
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.vertical, m.pt(Self.cellVertical))
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
        HStack(spacing: m.space.xxs) {
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
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.top, m.pt(Self.cellVertical))
        .padding(.bottom, m.pt(Self.cellVertical) + m.space.xs)
    }

    private func open(_ host: String) {
        guard let url = URL(string: "https://\(host)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Provider tabs

    @ViewBuilder
    private func providerBody(_ provider: String) -> some View {
        switch store.dnsPhase(for: provider) {
        case .skeleton:
            skeletonTable(header: dnsTableHeader) { dnsSkeletonRow($0) }
                .onAppear { store.loadRecords(provider: provider) }
                .onChange(of: store.domain) { store.loadRecords(provider: provider) }
        case .failed(let err):
            DMStatusView(kind: .failed(
                title: "Couldn't read the DNS records", message: err, retry: { retryRecords(provider) }))
        case .loaded(let records):
            recordsTable(records)
        }
    }

    private func retryRecords(_ provider: String) {
        if store.dnsErrorByProvider[provider] != nil || !store.domain.isEmpty {
            store.loadRecords(provider: provider, force: true)
        } else {
            store.refresh()
        }
    }

    @ViewBuilder
    private func recordsTable(_ records: [DNSRecordRow]) -> some View {
        let searched = RowSearch.filter(records, query: searchText) { [$0.name, $0.type, $0.value] }
        if records.isEmpty {
            DMStatusView(kind: .empty(systemImage: "server.rack", text: "No records for this zone"))
        } else {
            VStack(spacing: 0) {
                dnsTableHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searched.enumerated()), id: \.element.id) { index, record in
                            DMTableRow(index: index) { dnsRow(record) }
                        }
                    }
                }
                footer(showing: searched.count, of: records.count)
            }
            .padding(.horizontal, m.pt(Self.tableInset))
            .transition(.opacity)
        }
    }

    private var dnsTableHeader: some View {
        HStack(spacing: m.pt(10)) {
            columnLabel("NAME").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("TYPE").frame(width: m.pt(DNSColumns.type), alignment: .leading)
            columnLabel("CONTENT").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("TTL").frame(width: m.pt(DNSColumns.ttl), alignment: .trailing)
        }
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.vertical, m.pt(Self.cellVertical))
    }

    private func dnsRow(_ record: DNSRecordRow) -> some View {
        HStack(spacing: m.pt(10)) {
            Text(record.name)
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DMKindLabel(text: record.type)
                .frame(width: m.pt(DNSColumns.type), alignment: .leading)
            Text(record.value)
                .font(.dm(12, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(record.ttl)")
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .frame(width: m.pt(DNSColumns.ttl), alignment: .trailing)
        }
        .padding(.horizontal, m.pt(Self.cellInset))
        .padding(.vertical, m.pt(Self.cellVertical))
    }
}

/// One row's Caddy log tail, read on open and not kept once dismissed.
private struct LogsSheet: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var store: CaddyStore
    @Environment(\.dismiss) private var dismiss
    let host: String

    @State private var text = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            HStack {
                Text(host)
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Spacer()
                DMButton("Close", variant: .outline, size: .small) { dismiss() }
            }
            Group {
                if loading {
                    DMStatusView(kind: .loading("Reading logs…"), fillsHeight: false)
                } else if let error {
                    DMStatusView(
                        kind: .failed(title: "Couldn't read the logs", message: error, retry: load),
                        fillsHeight: false)
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
            .frame(height: m.pt(320))
        }
        .padding(m.space.xl)
        .frame(width: m.card.sheetWide)
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
