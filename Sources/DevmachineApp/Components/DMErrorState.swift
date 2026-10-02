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
    /// Only a newer devmachine CLI fixes it, so the state offers the update.
    var needsCLIUpdate = false

    init(
        systemImage: String = "exclamationmark.triangle", title: String, cause: String?, details: String,
        needsCLIUpdate: Bool = false
    ) {
        self.systemImage = systemImage
        self.title = title
        self.cause = cause
        self.details = details
        self.needsCLIUpdate = needsCLIUpdate
    }

    init(title: String, message: String) {
        let cause = FailureCause(message: message)
        self.init(
            title: title, cause: cause?.summary, details: message, needsCLIUpdate: cause?.needsCLIUpdate ?? false)
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
    @Environment(\.dmOpenCLIUpdate) private var openCLIUpdate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dmMetrics) private var m

    static func disclosureTitle(expanded: Bool) -> String { expanded ? "Hide details" : "Show details" }
    static func disclosureValue(expanded: Bool) -> String { expanded ? "Expanded" : "Collapsed" }

    private static let longDetailsLines = 8
    private static let longDetailsCharacters = 600

    var body: some View {
        VStack(spacing: m.space.lg) {
            VStack(spacing: m.pt(5)) {
                Image(systemName: state.systemImage)
                    .font(.dm(DMIconSize.lg, weight: .light))
                    .foregroundStyle(Color.dmMuted)
                    .padding(.bottom, m.pt(3))
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
                HStack(spacing: m.space.sm) { actions }
                VStack(spacing: m.space.xs) { actions }
            }

            if expanded {
                details
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: m.card.errorState)
    }

    static let updateCLITitle = "Update the CLI"

    @ViewBuilder
    private var actions: some View {
        if state.needsCLIUpdate, let openCLIUpdate {
            DMButton(Self.updateCLITitle, systemImage: "arrow.down.circle", size: .small, action: openCLIUpdate)
        }
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
            .padding(m.pt(10))
            .padding(.trailing, m.pt(26))
        Group {
            if isLong {
                ScrollView { text }
                    .frame(height: m.pt(150))
            } else {
                text
            }
        }
        .background(Color.dmBand, in: RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
        .overlay(alignment: .topTrailing) {
            DMButton(icon: copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy error",
                     size: .small, action: copy)
                .padding(m.space.xs)
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

private struct DMOpenCLIUpdateKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    /// Where an error that only a newer CLI fixes sends the person: Settings
    /// → About, which updates the CLI. Nil hides the button.
    var dmOpenCLIUpdate: (@MainActor () -> Void)? {
        get { self[DMOpenCLIUpdateKey.self] }
        set { self[DMOpenCLIUpdateKey.self] = newValue }
    }
}
