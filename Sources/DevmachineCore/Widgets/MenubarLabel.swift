import Foundation

/// One slot of the menu bar title. macOS templates the title, so a slot is
/// text, or one SF Symbol and text, never colour or an image.
public enum MenubarSlotItem: Equatable, Sendable {
    case brand
    case text(String)
    case status(WidgetLevel, String)
    case waiting
}

/// Everything one slot needs, gathered by the app, so the label model stays
/// a pure function a test can call without sources or stores.
public struct MenubarSlotInput: Equatable, Sendable {
    public var viewKind: String
    public var view: WidgetView?
    public var output: SourceOutput?
    public var approval: ApprovalState

    public init(viewKind: String, view: WidgetView? = nil, output: SourceOutput? = nil, approval: ApprovalState = .notNeeded) {
        self.viewKind = viewKind
        self.view = view
        self.output = output
        self.approval = approval
    }
}

/// What the title draws. With nothing to draw it keeps the brand mark, so
/// the menu bar item never vanishes and can always be clicked.
public enum MenubarLabelModel {
    public static func items(_ inputs: [MenubarSlotInput], contract: WidgetContract = .current) -> [MenubarSlotItem] {
        let drawn = inputs.compactMap { item($0, contract: contract) }
        return drawn.isEmpty ? [.brand] : drawn
    }

    public static func item(_ input: MenubarSlotInput, contract: WidgetContract = .current) -> MenubarSlotItem? {
        switch input.approval {
        case .waiting: return .waiting
        case .denied: return nil
        case .notNeeded, .allowed: break
        }
        if input.viewKind == "app.brand" { return .brand }
        guard let output = input.output else { return nil }
        let view = input.view ?? WidgetView(kind: input.viewKind)
        let limit = contract.slotEntry.textMax
        switch input.viewKind {
        case "number":
            guard let number = try? ValueExtraction.number(from: output, view: view) else { return nil }
            if view.hideZero, number == 0 { return nil }
            return text(NumberText.format(number, format: view.format, unit: view.unit), limit: limit)
        case "status":
            guard let model = try? StatusModel.make(output: output, view: view) else { return nil }
            return .status(model.level, cut(model.label, limit: limit))
        case "text":
            return text(plainText(output), limit: limit)
        default:
            return nil
        }
    }

    /// The first line with something on it, trimmed, at most `limit`
    /// characters counting the "…".
    public static func cut(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard line.count > limit else { return line }
        return String(line.prefix(max(0, limit - 1))) + "…"
    }

    public static func symbol(_ level: WidgetLevel) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        case .neutral: return "circle.fill"
        }
    }

    /// A source widget's view is already read; an app provider widget's is
    /// read from its catalog entry against that provider.
    public static func view(of resolved: ResolvedWidget, contract: WidgetContract = .current) -> WidgetView? {
        if let source = resolved.source { return source.view }
        let source = WidgetSource.provider(
            ProviderSource(name: resolved.provider, with: resolved.arguments, every: resolved.widget.source.every))
        return try? WidgetViewReader.read(
            resolved.widget.view, source: source, sourceWritesParse: false,
            scope: .package(inputs: Set(resolved.widget.inputs.keys), contextKeys: []), contract: contract)
    }

    private static func text(_ value: String, limit: Int) -> MenubarSlotItem? {
        let shown = cut(value, limit: limit)
        return shown.isEmpty ? nil : .text(shown)
    }

    private static func plainText(_ output: SourceOutput) -> String {
        switch output {
        case let .text(text): return text
        case let .ansi(text): return ANSIText.lines(text).map { $0.map(\.text).joined() }.joined(separator: "\n")
        case let .lines(lines): return lines.joined(separator: "\n")
        case let .number(number): return NumberText.plain(number)
        case let .json(value): return value.text
        case let .status(code, _): return String(code)
        }
    }
}

/// The slot board as label inputs. The app passes its live sources and
/// pull request count; a test or a first draw passes none.
public enum MenubarLabelInputs {
    public static func make(
        board: StackBoard, resolve: (StackEntry) -> WidgetResolution?, openCount: Int,
        output: (String) -> SourceOutput?, approval: (String, ResolvedSource) -> ApprovalState,
        contract: WidgetContract = .current
    ) -> [MenubarSlotInput] {
        board.entries.compactMap { entry in
            guard case let .ready(resolved)? = resolve(entry) else { return nil }
            if let source = resolved.source {
                return MenubarSlotInput(
                    viewKind: resolved.viewKind, view: source.view, output: output(entry.id),
                    approval: approval(entry.id, source))
            }
            return MenubarSlotInput(
                viewKind: resolved.viewKind, view: MenubarLabelModel.view(of: resolved, contract: contract),
                output: appOutput(resolved.provider, openCount: openCount))
        }
    }

    private static func appOutput(_ provider: String, openCount: Int) -> SourceOutput? {
        provider == "app/open-pull-requests" ? .number(Double(openCount)) : nil
    }
}
