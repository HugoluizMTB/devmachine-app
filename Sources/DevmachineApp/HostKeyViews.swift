import SwiftUI
import DevmachineCore

/// The host key review's words, kept apart from the views so they are tested.
enum HostKeyContent {
    static func sidebarLine(machine: String) -> String { "\(machine)'s SSH identity changed" }
    static let reviewTitle = "Review"

    static func title(machine: String, status: HostKeyReport.Status?) -> String {
        switch status {
        case .missing: return "\(machine)'s SSH identity isn't trusted yet"
        default: return "\(machine) answered with a different SSH identity"
        }
    }

    static let explanation = "ssh stopped before logging in because the machine's host key is not the one "
        + "this Mac trusts. That is what a rebuilt machine looks like — and a Lima VM writes new keys on "
        + "every restart — but it is also what someone in the middle looks like. Check the new key on the "
        + "machine itself before trusting it."

    static let verifyStep = "1. Run this on the machine's own console: the provider's web console, or "
        + "limactl shell on the Mac that runs a Lima VM. Not over SSH to this machine — an attacker in the "
        + "middle would answer that with the fingerprint you expect."

    /// Every host key type at once, for a CLI that named no single file.
    static let verifyAllCommand = "for f in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf \"$f\"; done"

    static let pasteStep = "2. Paste what it printed."
    static let pastePlaceholder = "256 SHA256:… root@host (ECDSA)"
    static let matches = "Matches the key the machine presents."
    static let doesNotMatch = "This doesn't contain the presented fingerprint. Don't trust the key until it does."

    static func trustTitle(status: HostKeyReport.Status) -> String {
        status == .changed ? "Replace host key" : "Trust host key"
    }

    static func trustedTitle(machine: String) -> String { "\(machine)'s host key is trusted" }
    static let trustedBody = "Its workspaces are connecting again."
    static func matchingTitle(machine: String) -> String { "\(machine)'s host key already matches" }
    static let matchingBody = "The key it presents is the one this Mac trusts, so ssh failed for another reason, "
        + "or the key was fixed in a terminal. Try connecting again."

    static let olderCLIBody = "Your devmachine CLI can't read a changed key from here yet (it needs "
        + "\(HostKeyTrust.minimumCLIVersion) or newer). Update the CLI first, or run this in a terminal to see "
        + "both fingerprints, then compare the new one on the machine's console before replacing it:"

    /// An older CLI reports a changed key only with `--replace` beside
    /// `--check`; it still writes nothing.
    static func olderCLICommand(machine: String) -> String {
        "devmachine machines trust \(machine) --check --replace"
    }
    static let updateCLITitle = "Update the CLI first"
}

/// One line in the sidebar under a machine whose host key ssh refused, with
/// the way into the review page. The sidebar is too narrow for fingerprints.
struct HostKeySidebarCard: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    let machine: String

    var body: some View {
        HStack(spacing: m.space.sm) {
            Image(systemName: "key.slash").foregroundStyle(.orange)
            Text(verbatim: HostKeyContent.sidebarLine(machine: machine))
                .font(.dm(11.5, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            DMButton(HostKeyContent.reviewTitle, variant: .outline, size: .small) {
                model.showPage(.hostKey(machine))
            }
        }
        .padding(m.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The central page that reviews one machine's host key: both fingerprints,
/// the console command that proves the new one, and a trust button that
/// stays off until the pasted output holds the exact presented fingerprint.
struct HostKeyPage: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: HostKeyStore
    let machine: String
    @State private var pasted: String

    init(store: HostKeyStore, machine: String, pasted: String = "") {
        self.store = store
        self.machine = machine
        _pasted = State(initialValue: pasted)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: m.space.lg) {
                content
            }
            .padding(m.space.xxl)
            .frame(maxWidth: m.pt(720), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .task(id: machine) { await store.check(machine) }
        .onChange(of: machine) { _, _ in pasted = "" }
        .onDisappear { store.dismiss(machine) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase(for: machine) {
        case .checking, nil:
            header(HostKeyContent.title(machine: machine, status: nil))
            DMStatusView(kind: .loading("Reading the key \(machine) presents…"), fillsHeight: false)
        case let .review(report):
            review(report, isTrusting: false)
        case let .trusting(report):
            review(report, isTrusting: true)
        case .trusted:
            header(HostKeyContent.trustedTitle(machine: machine), systemImage: "checkmark.circle.fill", tint: .green)
            paragraph(HostKeyContent.trustedBody)
            DMButton("Done", size: .small) { close() }
        case .matching:
            header(HostKeyContent.matchingTitle(machine: machine), systemImage: "checkmark.circle", tint: .green)
            paragraph(HostKeyContent.matchingBody)
            HStack(spacing: m.space.sm) {
                DMButton("Connect again", size: .small) {
                    model.hostKeyResolved(onMachine: machine)
                    close()
                }
                DMButton("Check again", variant: .outline, size: .small) { Task { await store.check(machine) } }
            }
        case .needsNewerCLI:
            header(HostKeyContent.title(machine: machine, status: .changed))
            paragraph(HostKeyContent.explanation)
            paragraph(HostKeyContent.olderCLIBody)
            DMCommandBlock([HostKeyContent.olderCLICommand(machine: machine)], wraps: true)
            DMButton(HostKeyContent.updateCLITitle, variant: .link, size: .small) { model.openSettings(.about) }
        case let .failed(error):
            DMErrorStateView(state: error, retry: { Task { await store.check(machine) } })
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func review(_ report: HostKeyReport, isTrusting: Bool) -> some View {
        header(HostKeyContent.title(machine: machine, status: report.status))
        paragraph(HostKeyContent.explanation)
        fingerprints(report)
        paragraph(HostKeyContent.verifyStep)
        DMCommandBlock([report.verify ?? HostKeyContent.verifyAllCommand], wraps: true)
        paragraph(HostKeyContent.pasteStep)
        TextField(HostKeyContent.pastePlaceholder, text: $pasted, axis: .vertical)
            .lineLimit(2...6)
            .font(.system(size: m.pt(11.5), design: .monospaced))
            .dmField()
            .disabled(isTrusting)
        if !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let ok = HostKeyTrust.confirms(pasted, report: report)
            Label {
                Text(verbatim: ok ? HostKeyContent.matches : HostKeyContent.doesNotMatch)
            } icon: {
                Image(systemName: ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
            }
            .font(.dm(11.5))
            .foregroundStyle(ok ? Color.green : Color.orange)
        }
        HStack(spacing: m.space.sm) {
            DMButton(
                HostKeyContent.trustTitle(status: report.status), systemImage: "key",
                variant: report.status == .changed ? .danger : .primary, size: .small, isLoading: isTrusting
            ) {
                Task { await store.trust(machine, report: report, pasted: pasted) }
            }
            .disabled(!HostKeyTrust.confirms(pasted, report: report) || isTrusting)
            DMButton("Check again", variant: .outline, size: .small) {
                pasted = ""
                Task { await store.check(machine) }
            }
            .disabled(isTrusting)
            DMButton("Cancel", variant: .ghost, size: .small) { close() }
                .disabled(isTrusting)
        }
    }

    private func fingerprints(_ report: HostKeyReport) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: m.space.lg, verticalSpacing: m.space.sm) {
            row("Address", report.address)
            if let current = report.currentFingerprint {
                row("Trusted key", [report.currentKeyType, current].compactMap { $0 }.joined(separator: "  "))
            }
            // Not selectable: copying it from here into the field below would
            // skip the console check it stands for.
            row("Presented key", "\(report.keyType)  \(report.presentedFingerprint)", selectable: false)
        }
        .padding(m.space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    private func row(_ label: String, _ value: String, selectable: Bool = true) -> some View {
        GridRow {
            Text(verbatim: label)
                .font(.dm(11.5))
                .foregroundStyle(Color.dmMuted)
            let text = Text(verbatim: value)
                .font(.system(size: m.pt(11.5), design: .monospaced))
                .foregroundStyle(Color.dmRowText)
                .fixedSize(horizontal: false, vertical: true)
            if selectable {
                text.textSelection(.enabled)
            } else {
                text.textSelection(.disabled)
            }
        }
    }

    private func header(_ text: String, systemImage: String = "key.slash", tint: Color = .orange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(verbatim: text)
                .font(.dm(15, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func close() {
        store.dismiss(machine)
        if model.activePage == .hostKey(machine) { model.activePage = nil }
    }
}
