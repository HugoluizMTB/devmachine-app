import SwiftUI
import DevmachineCore

/// The server's host key, read with `machines scan` before anything trusts
/// it: what it presents beside the command that prints the same key on its
/// own console. The add trusts it only once the person says they match, or
/// the console output pasted here holds it.
struct AddMachineScanView: View {
    @Environment(\.dmMetrics) private var m
    @ObservedObject var state: AddMachineModel

    private var draft: MachineDraft { state.wizard.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            AddMachineFieldLabel(text: "Server fingerprint")
            Text(verbatim: "devmachine reads the key the server presents, without logging in. Check it against "
                + "your provider's console (not SSH) before anything trusts it.")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            DMButton(
                draft.currentScan == nil ? "Read the fingerprint" : "Read it again", systemImage: "key.viewfinder",
                variant: .outline, size: .small, isLoading: state.scanning
            ) { Task { await state.scan() } }
            .disabled(draft.address.trimmingCharacters(in: .whitespaces).isEmpty)
            if let error = state.scanError {
                AddMachineWarning(text: "Could not read the fingerprint: \(error)")
            }
            if let scan = draft.currentScan {
                presented(scan)
            }
            consoleField
            outcome
        }
    }

    private func presented(_ scan: MachineScan) -> some View {
        HStack(alignment: .top, spacing: m.space.lg) {
            VStack(alignment: .leading, spacing: m.space.xs) {
                AddMachineFieldLabel(text: "The server presents")
                Text(verbatim: scan.keyType)
                    .font(.dm(10.5))
                    .foregroundStyle(Color.dmMuted)
                Text(verbatim: scan.fingerprint)
                    .font(.dm(11.5, design: .monospaced))
                    .foregroundStyle(Color.dmRowText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(m.space.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .dmSurface(Color.dmBand, radius: DMRadius.panel)
            VStack(alignment: .leading, spacing: m.space.xs) {
                AddMachineFieldLabel(text: "On its console, run")
                DMCommandBlock(scan.verify ?? AddMachineContent.verifyCommand, wraps: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var consoleField: some View {
        TextField(
            "Optional: paste what the console printed", text: $state.wizard.draft.fingerprint, axis: .vertical)
            .lineLimit(1...3)
            .font(.system(size: m.pt(11.5), design: .monospaced))
            .dmField()
    }

    @ViewBuilder
    private var outcome: some View {
        if draft.consoleDisagreesWithScan {
            AddMachineWarning(text: "The console printed a different key than the server presented. "
                + "Do not add this server: something between you and it may not be the server.")
        } else if draft.consoleConfirmsScan || (draft.currentScan == nil && draft.expectedFingerprint != nil) {
            Label {
                Text(verbatim: draft.consoleConfirmsScan
                    ? "The console shows the same key." : "devmachine trusts \(draft.expectedFingerprint ?? "").")
            } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
            .font(.dm(11))
            .foregroundStyle(Color.green)
        } else if draft.currentScan != nil {
            Toggle(isOn: $state.wizard.draft.scanConfirmed) {
                Text(verbatim: "The console shows this same fingerprint")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmRowText)
            }
            .toggleStyle(.checkbox)
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
                Text(verbatim: "The key the server already takes. Only it is offered from then on.")
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
