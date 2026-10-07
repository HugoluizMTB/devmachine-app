import SwiftUI
import DevmachineCore

enum SourceWidgetLayout {
    static func showsRunButton(every: WidgetEvery, state: SourceWidgetState) -> Bool {
        guard !state.isRunning else { return false }
        switch every {
        case .manual: return true
        case .continuous: return state.ended
        case .interval: return false
        }
    }

    static func listRows(height: CGFloat, rowHeight: CGFloat) -> Int {
        max(1, Int((height / rowHeight).rounded(.down)))
    }

    /// The rows drawn and the count a "+N more" line names; one row that
    /// barely fits leaves no room for that line, so it gets none.
    static func listFit(count: Int, height: CGFloat, rowHeight: CGFloat) -> (rows: Int, more: Int) {
        let fit = listRows(height: height, rowHeight: rowHeight)
        guard count > fit else { return (count, 0) }
        guard fit > 1 else { return (1, 0) }
        return (fit - 1, count - fit + 1)
    }

    static func followsNewestLine(kind: String, every: WidgetEvery, tail: Int?) -> Bool {
        every == .continuous || kind == "terminal" || tail != nil
    }
}

enum SourceErrorPresentation {
    static func state(_ error: SourceError) -> DMErrorState {
        switch error {
        case .needsNewerCLI:
            return DMErrorState(
                title: error.title, cause: "The installed devmachine CLI cannot run widgets on a machine yet.",
                details: error.details, needsCLIUpdate: true)
        default:
            return DMErrorState(title: error.title, message: error.details)
        }
    }

    static func state(title: String, error: any Error) -> DMErrorState {
        DMErrorState(title: title, message: message(error))
    }

    static func message(_ error: any Error) -> String {
        if let error = error as? LocalizedError, let text = error.errorDescription { return text }
        return String(describing: error)
    }

    /// What a compact card shows under the title: the guessed cause, else
    /// the error itself when it says more than the title.
    static func compactDetail(_ state: DMErrorState) -> String? {
        if let cause = state.cause { return cause }
        let details = state.details.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty || details == state.title ? nil : details
    }
}

/// A source widget's body: a one-line header (title, ▶ or progress, an
/// error badge when a later run failed) over the view that fits the frame.
struct SourceWidgetContent: View {
    let title: String
    let source: ResolvedSource
    let state: SourceWidgetState
    let history: [SparklinePoint]
    let size: CGSize
    let onRun: () -> Void
    var onOpenSession: (() -> Void)?
    var webAddress: Result<URL, SourceError>?
    @Environment(\.dmMetrics) private var m

    private var density: WidgetDensity {
        WidgetDensity.of(width: size.width / m.pt(1), height: size.height / m.pt(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            header
            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(m.space.lg)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .dmGlass(radius: DMRadius.card)
    }

    private var header: some View {
        HStack(spacing: m.space.sm) {
            Text(verbatim: title)
                .font(.dm(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: m.space.xs)
            if let error = state.error, state.output != nil || !state.lines.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.dm(10))
                    .foregroundStyle(.orange)
                    .help(Text(verbatim: "\(error.title): \(error.details)"))
                    .accessibilityLabel(Text(verbatim: error.title))
            }
            if state.isRunning, source.every != .continuous {
                ProgressView().controlSize(.small)
            } else if SourceWidgetLayout.showsRunButton(every: source.every, state: state) {
                DMIconButton(systemImage: "play.fill", action: onRun)
                    .help(Text(verbatim: "Run now"))
                    .accessibilityLabel(Text(verbatim: "Run \(title) now"))
            }
        }
        .frame(height: m.control.small)
    }

    @ViewBuilder
    private var bodyView: some View {
        if source.view.kind == "web", case let .url(url) = source.source {
            switch webAddress ?? .failure(.unreadable("\(url.url) is not a web address")) {
            case let .success(address):
                WebWidgetView(address: address.absoluteString, zoom: source.view.zoom, every: url.every.seconds)
            case let .failure(error):
                SourceErrorView(state: SourceErrorPresentation.state(error), density: density)
            }
        } else if source.every == .continuous {
            if state.lines.isEmpty, let error = state.error {
                SourceErrorView(
                    state: SourceErrorPresentation.state(error), density: density, retry: onRun, retryTitle: "Run again")
            } else if state.lines.isEmpty {
                quiet(state.ended ? "The stream ended. Press ▶ to start it again." : "Waiting for the first line…")
            } else {
                TextLinesView(lines: TextTail.lines(of: state.lines.joined(separator: "\n"), tail: source.view.tail),
                              wrap: source.view.wrap, keepsColor: source.view.kind == "terminal", followsNewest: true)
            }
        } else if let output = state.output {
            OutputView(source: source, output: output, history: history, density: density, onOpenSession: onOpenSession)
        } else if let error = state.error {
            SourceErrorView(state: SourceErrorPresentation.state(error), density: density, retry: onRun)
        } else if state.isRunning {
            ProgressView().controlSize(.small)
        } else if source.every == .manual {
            quiet("Press ▶ to run it.")
        } else {
            quiet("Waiting for the first answer…")
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(11))
            .foregroundStyle(Color.dmMuted)
    }
}

/// `DMErrorStateView` needs more height than a compact card has, so a
/// compact card shows the title, the retry and the exact error on hover.
struct SourceErrorView: View {
    let state: DMErrorState
    let density: WidgetDensity
    var retry: (() -> Void)?
    var retryTitle = "Try again"
    @Environment(\.dmOpenCLIUpdate) private var openCLIUpdate
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if density == .full {
            ScrollView(.vertical) {
                DMErrorStateView(state: state, retry: retry, retryTitle: retryTitle)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            compact
        }
    }

    private var compact: some View {
        HStack(alignment: .top, spacing: m.space.sm) {
            Image(systemName: state.systemImage)
                .font(.dm(12))
                .foregroundStyle(Color.dmMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: state.title)
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                    .lineLimit(2)
                if let detail = SourceErrorPresentation.compactDetail(state) {
                    Text(verbatim: detail)
                        .font(.dm(10))
                        .foregroundStyle(Color.dmMuted)
                        .lineLimit(2)
                }
            }
            .help(Text(verbatim: state.details))
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if state.needsCLIUpdate, let openCLIUpdate {
                DMIconButton(systemImage: "arrow.down.circle", action: openCLIUpdate)
                    .help(Text(verbatim: DMErrorStateView.updateCLITitle))
                    .accessibilityLabel(Text(verbatim: DMErrorStateView.updateCLITitle))
            }
            if let retry {
                DMIconButton(systemImage: "arrow.clockwise", action: retry)
                    .help(Text(verbatim: retryTitle))
                    .accessibilityLabel(Text(verbatim: retryTitle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One drawn output; a value the view cannot use is an error in place.
private struct OutputView: View {
    let source: ResolvedSource
    let output: SourceOutput
    let history: [SparklinePoint]
    let density: WidgetDensity
    let onOpenSession: (() -> Void)?

    var body: some View {
        let view = source.view
        switch view.kind {
        case "number":
            NumberWidgetView(view: view, output: output, density: density)
        case "gauge":
            GaugeWidgetView(view: view, output: output, density: density)
        case "status":
            StatusWidgetView(view: view, output: output, density: density)
        case "sparkline":
            SparklineWidgetView(view: view, output: output, history: history, density: density)
        case "list":
            ListWidgetView(template: view.item, output: output, density: density)
        case "markdown":
            MarkdownWidgetView(text: plainText(output))
        case "terminal":
            TerminalWidgetView(text: plainText(output), tail: view.tail, onOpen: onOpenSession)
        default:
            TextLinesView(
                lines: TextTail.lines(of: plainText(output), tail: view.tail), wrap: view.wrap, keepsColor: false,
                followsNewest: SourceWidgetLayout.followsNewestLine(kind: view.kind, every: source.every, tail: view.tail))
        }
    }

    private func plainText(_ output: SourceOutput) -> String {
        switch output {
        case let .text(text), let .ansi(text): return text
        case let .lines(lines): return lines.joined(separator: "\n")
        case let .number(number): return NumberText.format(number, format: .plain, unit: nil)
        case let .json(value): return value.canonicalJSON
        case let .status(code, _): return String(code)
        }
    }
}
