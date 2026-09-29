import SwiftUI
import DevmachineCore

/// The doctor checklist, embedded in Settings → Advanced next to Debug
/// logging: what `devmachine doctor` (and, for this Mac, `devmachine machine
/// doctor`) say about every configured machine.
struct HealthCheckView: View {
    @EnvironmentObject var store: HealthCheckStore
    @State private var copiedCheck: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let err = store.commandErrorText {
                DMBanner(message: err) {
                    DMIconButton(systemImage: "arrow.clockwise", tint: nil) { store.run() }
                }
            }
            if store.isRunning && store.results.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Running…")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            } else if store.results.isEmpty {
                Text("Run a health check to see whether every configured machine can be reached.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            } else {
                results
            }
        }
        .onAppear {
            if store.results.isEmpty && !store.isRunning { store.run() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Health check")
                .font(.dm(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if let lastRunAt = store.lastRunAt {
                Text(verbatim: "last run \(Self.timeFormatter.string(from: lastRunAt))")
                    .font(.dm(10))
                    .foregroundStyle(Color.dmMuted)
            }
            if store.isRunning {
                ProgressView().controlSize(.small)
            }
            Button(store.isRunning ? "Running…" : "Run again") { store.run() }
                .buttonStyle(.dmChip)
                .disabled(store.isRunning)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(store.results) { machine in
                VStack(alignment: .leading, spacing: 6) {
                    if store.results.count > 1 {
                        Text(verbatim: machine.isSelf ? "\(machine.machineName) (this Mac)" : machine.machineName)
                            .font(.dm(11, weight: .semibold))
                            .foregroundStyle(Color.dmMuted)
                    }
                    if let errorText = machine.errorText {
                        DMBanner(message: errorText) {}
                    } else if let raw = machine.rawOutput {
                        rawOutputView(raw)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(machine.checks) { check in
                                checkRow(check)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rawOutputView(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11, design: .monospaced))
            .foregroundStyle(Color.dmRowText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .dmSurface(Color.dmSelection, radius: DMRadius.control)
    }

    private func checkRow(_ check: DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: check.status.systemImage)
                .foregroundStyle(check.status.color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: check.name)
                        .font(.dm(12, weight: .medium))
                        .foregroundStyle(Color.dmRowText)
                    DMPill(text: check.status.rawValue.uppercased(), color: check.status.color)
                }
                if !check.detail.isEmpty {
                    detailText(check)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// A `fail`'s detail often reads `"...: run \`the fix command\`"`. Pulled
    /// out and shown in monospace with its own copy button, so the exact
    /// command can be pasted rather than retyped from a sentence.
    @ViewBuilder
    private func detailText(_ check: DoctorCheck) -> some View {
        if let command = Self.fixCommand(in: check.detail) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: check.detail)
                    .font(.dm(10))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(verbatim: command)
                        .font(.dm(10.5, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .textSelection(.enabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .dmSurface(Color.dmSelection, radius: DMRadius.control)
                    Button(copiedCheck == check.id ? "Copied" : "Copy") { copy(command, for: check.id) }
                        .buttonStyle(.dmChip)
                }
            }
        } else {
            Text(verbatim: check.detail)
                .font(.dm(10))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ command: String, for id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCheck = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedCheck == id { copiedCheck = nil }
        }
    }

    /// Pulls the backtick-quoted command out of a detail such as
    /// `"missing: run \`devmachine secrets set gh\`"`. `nil` when the detail
    /// carries no command to copy.
    static func fixCommand(in detail: String) -> String? {
        guard let open = detail.firstIndex(of: "`") else { return nil }
        let afterOpen = detail.index(after: open)
        guard let close = detail[afterOpen...].firstIndex(of: "`") else { return nil }
        let command = String(detail[afterOpen..<close])
        return command.isEmpty ? nil : command
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension DoctorStatus {
    var color: Color {
        switch self {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .skip: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .skip: return "minus.circle.fill"
        }
    }
}
