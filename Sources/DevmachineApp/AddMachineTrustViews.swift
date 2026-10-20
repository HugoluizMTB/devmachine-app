import SwiftUI
import DevmachineCore

/// The server's host key, read with `machines scan` once the address is
/// typed: one quiet line. The add trusts only that key, so a fake server
/// never gets the password. Checking it against the provider's console is
/// there for whoever wants it, folded away.
struct AddMachineScanView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel
    @State private var showsDetails = false
    @State private var checksConsole = false

    private var draft: MachineDraft { state.wizard.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            line
            if let scan = draft.currentScan {
                DisclosureGroup(isExpanded: $checksConsole) {
                    consoleCheck(scan)
                        .padding(.top, m.space.sm)
                } label: {
                    Text(verbatim: "Check it against the provider console (optional)")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }
            if draft.consoleDisagreesWithScan {
                AddMachineWarning(text: "The console printed a different key than the server presented. "
                    + "Do not add this server: something between you and it may not be the server.")
            }
        }
        .task(id: state.scanTarget) { await state.scanAfterPause() }
    }

    @ViewBuilder
    private var line: some View {
        if let scan = draft.currentScan {
            HStack(spacing: m.space.sm) {
                Image(systemName: "key")
                    .foregroundStyle(Color.dmMuted)
                Text(verbatim: "Server key: \(scan.keyTypeName) \(scan.fingerprint)")
                    .font(.dm(11, design: .monospaced))
                    .foregroundStyle(Color.dmMuted)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else if state.scanning {
            HStack(spacing: m.space.sm) {
                ProgressView().controlSize(.small)
                Text(verbatim: "Reading the server's key…")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
        } else if let failure = state.currentScanFailure {
            VStack(alignment: .leading, spacing: m.space.xs) {
                AddMachineWarning(text: failure.message)
                HStack(spacing: m.space.sm) {
                    DMButton("Try again", variant: .ghost, size: .small) { Task { await state.scan() } }
                    DMButton(DMErrorStateView.disclosureTitle(expanded: showsDetails), variant: .ghost,
                             size: .small) { showsDetails.toggle() }
                }
                if showsDetails {
                    Text(verbatim: failure.details)
                        .font(.dm(10.5, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(m.space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dmSurface(Color.dmBand, radius: DMRadius.panel)
                }
            }
        }
    }

    private func consoleCheck(_ scan: MachineScan) -> some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Text(verbatim: "Run this in the provider's web console and paste what it prints.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            DMCommandBlock(scan.verify ?? AddMachineContent.verifyCommand, wraps: true)
            TextField("Paste what the console printed", text: $state.wizard.draft.fingerprint, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: m.pt(11.5), design: .monospaced))
                .dmField()
            if draft.consoleConfirmsScan {
                Label {
                    Text(verbatim: "The console shows the same key.")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .font(.dm(11))
                .foregroundStyle(Color.green)
            }
        }
    }
}

/// The keys the SSH agent holds (the socket the app hands the CLI), one to
/// choose: `machines add --key agent:<fingerprint>` then offers only it.
struct AddMachineAgentKeysView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            if let keys = state.agentKeys {
                if keys.isEmpty {
                    AddMachineWarning(text: state.agentKeysError.map { "The SSH agent did not answer: \($0)" }
                        ?? "The SSH agent holds no key. Unlock your password manager, or add a key with ssh-add.")
                }
                ForEach(keys) { key in
                    DMChoiceCard(
                        title: key.comment.isEmpty ? key.type : key.comment,
                        detail: key.fingerprint, badge: key.comment.isEmpty ? nil : key.type,
                        selected: state.wizard.draft.agentKey == key.fingerprint
                    ) { state.wizard.draft.agentKey = key.fingerprint }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            HStack(spacing: m.space.sm) {
                DMButton("Read the agent again", variant: .ghost, size: .small) {
                    Task { await state.loadAgentKeys() }
                }
                Text(verbatim: "Keys in the SSH agent, 1Password included.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }
        }
        .task { await state.loadAgentKeys() }
    }
}

struct AddMachineFieldLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.dm(11, weight: .semibold))
            .foregroundStyle(Color.dmRowText.opacity(0.8))
    }
}

struct AddMachineWarning: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.dm(11))
            .foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
