import SwiftUI
import AppKit
import DevmachineCore
import HarnessUsageKit

/// A failed read, told calmly: a title, one line of likely cause when the
/// error lets us guess it, and the exact error kept for whoever wants it.
struct DMErrorState: Equatable {
    var systemImage = "exclamationmark.triangle"
    let title: String
    let cause: String?
    let details: String

    init(systemImage: String = "exclamationmark.triangle", title: String, cause: String?, details: String) {
        self.systemImage = systemImage
        self.title = title
        self.cause = cause
        self.details = details
    }

    init(title: String, message: String) {
        self.init(title: title, cause: FailureCause(message: message)?.summary, details: message)
    }

    init(_ usage: HarnessUsageErrorPresentation) {
        self.init(
            systemImage: usage.kind.systemImage, title: usage.title, cause: usage.cause,
            details: usage.details)
    }
}

struct DMErrorStateView: View {
    let state: DMErrorState
    var retry: (() -> Void)?
    var retryTitle: String
    @State private var expanded: Bool

    init(
        state: DMErrorState, retry: (() -> Void)? = nil, retryTitle: String = "Try again",
        startsExpanded: Bool = false
    ) {
        self.state = state
        self.retry = retry
        self.retryTitle = retryTitle
        _expanded = State(initialValue: startsExpanded)
    }

    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func disclosureTitle(expanded: Bool) -> String { expanded ? "Hide details" : "Show details" }
    static func disclosureValue(expanded: Bool) -> String { expanded ? "Expanded" : "Collapsed" }

    private static let longDetailsLines = 8
    private static let longDetailsCharacters = 600

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 5) {
                Image(systemName: state.systemImage)
                    .font(.dm(20, weight: .light))
                    .foregroundStyle(Color.dmMuted)
                    .padding(.bottom, 3)
                    .accessibilityHidden(true)
                Text(verbatim: state.title)
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                if let cause = state.cause {
                    Text(verbatim: cause)
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { actions }
                VStack(spacing: 4) { actions }
            }

            if expanded {
                details
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 440)
    }

    @ViewBuilder
    private var actions: some View {
        if let retry {
            DMButton(retryTitle, systemImage: "arrow.clockwise", variant: .outline, size: .small,
                     action: retry)
        }
        DMButton(
            Self.disclosureTitle(expanded: expanded),
            systemImage: expanded ? "chevron.up" : "chevron.down",
            variant: .ghost, size: .small
        ) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { expanded.toggle() }
        }
        .accessibilityValue(Text(verbatim: Self.disclosureValue(expanded: expanded)))
        .accessibilityHint(Text(verbatim: "Shows the exact error message"))
    }

    private var isLong: Bool {
        state.details.split(separator: "\n", omittingEmptySubsequences: false).count > Self.longDetailsLines
            || state.details.count > Self.longDetailsCharacters
    }

    @ViewBuilder
    private var details: some View {
        let text = Text(verbatim: state.details)
            .font(.dm(10.5, design: .monospaced))
            .foregroundStyle(Color.dmRowText)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .padding(.trailing, 26)
        Group {
            if isLong {
                ScrollView { text }
                    .frame(height: 150)
            } else {
                text
            }
        }
        .background(Color.dmBand, in: RoundedRectangle(cornerRadius: DMRadius.tile, style: .continuous))
        .overlay(alignment: .topTrailing) {
            DMButton(icon: copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy error",
                     size: .small, action: copy)
                .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Error details"))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.details, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
