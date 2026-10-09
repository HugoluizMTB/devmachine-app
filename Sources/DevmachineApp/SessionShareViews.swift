import SwiftUI
import AppKit
import DevmachineCore

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum SessionShareText {
    static let guideURL = URL(string: "https://mydevmachine.sh/guides/share-a-session/")!

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func ended(_ reason: String?) -> String {
        switch reason {
        case "expired": return "Expired"
        case "revoked": return "Stopped"
        case "session-ended": return "Session ended"
        default: return "Ended"
        }
    }

    static func help(_ record: SessionShareRecord) -> String {
        "Shared (\(record.mode.title.lowercased())) until \(time(record.expiresAt))"
    }
}

/// The mark beside a shared session's name. Orange when the guest can type.
struct SessionShareBadge: View {
    let record: SessionShareRecord

    var body: some View {
        Image(systemName: "person.2.fill")
            .font(.dm(9))
            .foregroundStyle(record.mode == .write ? Color.orange : Color.dmRowText)
            .help(SessionShareText.help(record))
            .accessibilityLabel(SessionShareText.help(record))
    }
}

struct ShareSessionSheet: View {
    @Environment(\.dmMetrics) private var m
    let request: SessionShareRequest
    var isSharing = false
    let onCancel: () -> Void
    let onShare: (String, SessionShareMode, SessionShareDuration) -> Void
    @State private var name: String
    @State private var mode: SessionShareMode = .read
    @State private var duration: SessionShareDuration = .oneHour

    init(
        request: SessionShareRequest, isSharing: Bool = false, onCancel: @escaping () -> Void,
        onShare: @escaping (String, SessionShareMode, SessionShareDuration) -> Void
    ) {
        self.request = request
        self.isSharing = isSharing
        self.onCancel = onCancel
        self.onShare = onShare
        _name = State(initialValue: request.session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            VStack(alignment: .leading, spacing: m.space.xs) {
                Text("Share \(request.session)").font(.headline)
                Text("Whoever has the link and the password joins this session as it is, on \(request.workspace), until the time runs out.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Name", text: $name)
            Picker("For", selection: $duration) {
                ForEach(SessionShareDuration.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("They", selection: $mode) {
                Text("Watch").tag(SessionShareMode.read)
                Text("Can type").tag(SessionShareMode.write)
            }
            .pickerStyle(.segmented)
            if mode == .write {
                Text("They can type into this session. In a shell, or by approving a tool in a coding harness, they run commands as \(request.workspace)'s account.")
                    .font(.dm(11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline, action: onCancel)
                DMButton("Share", systemImage: "person.2", isLoading: isSharing) { onShare(name, mode, duration) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(m.pt(20))
        .frame(width: m.pt(400))
    }
}

/// The Share sheet and what it answered, in one sheet: a second sheet opened
/// while the first is closing can be dropped by SwiftUI on macOS, and the
/// password is shown only there.
struct ShareFlowSheet: View {
    let request: SessionShareRequest
    @ObservedObject var shares: SessionShareStore
    let onClose: () -> Void
    @State private var sharing = false
    @State private var outcomeID: UUID?

    var body: some View {
        if let outcome = shares.outcome, outcome.id == outcomeID {
            ShareOutcomeSheet(
                outcome: outcome,
                onStop: { record in
                    close()
                    Task { await shares.stop(record) }
                },
                onClose: close)
        } else {
            ShareSessionSheet(
                request: request, isSharing: sharing, onCancel: onClose,
                onShare: { name, mode, duration in
                    sharing = true
                    Task {
                        await shares.start(request, name: name, mode: mode, duration: duration)
                        outcomeID = shares.outcome?.id
                        sharing = false
                    }
                })
        }
    }

    private func close() {
        shares.outcome = nil
        onClose()
    }
}

struct ShareOutcomeSheet: View {
    @Environment(\.dmMetrics) private var m
    let outcome: SessionShareOutcome
    let onStop: (SessionShareRecord) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            switch outcome.result {
            case let .started(record, password, unpublished):
                started(record, password: password, unpublished: unpublished)
            case let .failed(state):
                DMErrorStateView(state: state, startsExpanded: true)
                HStack {
                    Spacer()
                    DMButton("Close", action: onClose).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(m.pt(20))
        .frame(width: m.pt(460))
    }

    @ViewBuilder
    private func started(_ record: SessionShareRecord, password: String?, unpublished: DMErrorState?) -> some View {
        VStack(alignment: .leading, spacing: m.space.xs) {
            Text("Sharing \(record.session)").font(.headline)
            Text("\(record.mode.title) until \(SessionShareText.time(record.expiresAt)).")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
        }
        if let url = record.url {
            DMSectionLabel(text: "Link")
            if let unpublished {
                DMErrorStateView(state: unpublished)
            } else {
                DMCommandBlock(url, wraps: true)
                if !SessionShareInfo.isLoopback(url) {
                    Text("The first visit to a newly published address can take a few seconds while its certificate is issued.")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }
        }
        if let password {
            DMSectionLabel(text: "Password")
            DMCommandBlock(password)
            Text("Send it apart from the link. It is not shown again.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
        }
        HStack {
            DMButton("Stop sharing", variant: .dangerOutline) { onStop(record) }
            Spacer()
            DMButton("Done", action: onClose).keyboardShortcut(.defaultAction)
        }
    }
}

/// Settings → Shares: every share this Mac started, live ones first.
struct SharesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject private var shares = SessionShareStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            HStack {
                Text("Right-click a session in the sidebar and choose Share… to let someone watch it, or type in it, for a while.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                Spacer()
                if shares.records.contains(where: { !$0.isLive(at: Date()) }) {
                    DMButton("Clear ended", variant: .ghost, size: .small) { shares.clearEnded() }
                }
            }
            if shares.records.isEmpty {
                Text("Nothing shared yet.")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmMuted)
                    .padding(.vertical, m.space.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, record in
                        DMTableRow(index: index) { row(record) }
                    }
                }
            }
        }
        .task { await shares.refresh() }
    }

    private var ordered: [SessionShareRecord] {
        let now = Date()
        return shares.records.sorted {
            let live = ($0.isLive(at: now), $1.isLive(at: now))
            if live.0 != live.1 { return live.0 }
            return $0.createdAt > $1.createdAt
        }
    }

    private func row(_ record: SessionShareRecord) -> some View {
        let live = record.isLive(at: Date())
        return HStack(spacing: m.space.md) {
            VStack(alignment: .leading, spacing: m.pt(2)) {
                Text(record.name).font(.dm(12.5)).foregroundStyle(Color.dmRowText)
                Text("\(record.session) · \(record.workspace) · \(SessionShareText.day(record.createdAt))")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
            Spacer(minLength: m.space.md)
            DMPill(text: record.mode.title, color: record.mode == .write ? .orange : Color.dmRowText)
            if live {
                DMPill(text: "Live until \(SessionShareText.time(record.expiresAt))", color: .green)
                if let url = record.url { DMCopyButton(text: url, title: "Copy link") }
                DMButton("Stop", variant: .ghostDanger, size: .small, isLoading: shares.busy.contains(record.id)) {
                    Task { await shares.stop(record) }
                }
            } else {
                Text(SessionShareText.ended(record.endReason))
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
        }
        .padding(.horizontal, m.space.md)
        .padding(.vertical, m.space.sm)
    }
}
