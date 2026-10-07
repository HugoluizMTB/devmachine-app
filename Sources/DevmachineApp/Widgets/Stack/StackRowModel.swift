import CoreGraphics
import DevmachineCore

enum StackHeaderStyle: Equatable {
    case own
    case bare
    case standard

    static func of(viewKind: String) -> StackHeaderStyle {
        switch StackAppViewKind(viewKind: viewKind) {
        case .shortcuts?, .monitors?, .shells?, .subAgents?, .todo?, .pullRequests?, .links?: return .own
        case .workspaces?, .publishPort?: return .bare
        case nil: return .standard
        }
    }
}

/// The app's own sidebar views. The raw value is the widget's name; the
/// catalog calls the view `app.<name>`.
enum StackAppViewKind: String, CaseIterable {
    case workspaces, shortcuts, monitors, shells, todo, links
    case publishPort = "publish-port"
    case subAgents = "sub-agents"
    case pullRequests = "pull-requests"

    private static let prefix = "app."

    init?(viewKind: String) {
        guard viewKind.hasPrefix(Self.prefix) else { return nil }
        self.init(rawValue: String(viewKind.dropFirst(Self.prefix.count)))
    }

    var viewKind: String { Self.prefix + rawValue }
}

enum StackRowHeight: Equatable {
    case content
    case fixed(CGFloat)
}

/// What a stack row needs to draw its chrome, decided without SwiftUI.
struct StackRowModel: Equatable {
    let id: String
    let title: String
    let header: StackHeaderStyle
    let height: StackRowHeight
    let sizeChoices: [StackSize]
    let size: StackSize?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isCollapsed: Bool

    static func make(
        entry: StackEntry, index: Int, count: Int, resolution: WidgetResolution?, approval: ApprovalState?,
        catalog: WidgetCatalog?, contract: WidgetContract = .current
    ) -> StackRowModel {
        var title = entry.inline?.title ?? WidgetTitle.make(type: entry.type, in: catalog)
        var header = StackHeaderStyle.standard
        var height = StackRowHeight.fixed(CGFloat(StackLayout.placeholderHeight(contract: contract)))
        var choices: [StackSize] = []
        switch resolution {
        case let .ready(resolved)?:
            let appTitle = StackAppViewKind(viewKind: resolved.viewKind).flatMap { AppStackWidgets.titles[$0.rawValue] }
            title = entry.inline?.title ?? appTitle ?? title
            header = StackHeaderStyle.of(viewKind: resolved.viewKind)
            choices = StackLayout.sizeChoices(for: resolved, contract: contract)
            switch StackLayout.height(of: entry, resolved: resolved, contract: contract) {
            case .auto: height = .content
            case let .points(points): height = .fixed(CGFloat(points))
            }
            if resolved.source != nil, let approval, !approval.canRun {
                let least = CGFloat(StackLayout.approvalRows * contract.stackRow)
                if case let .fixed(points) = height { height = .fixed(max(points, least)) } else { height = .fixed(least) }
            }
        case let .some(other):
            title = WidgetResolutionCopy.title(other)
        case nil:
            break
        }
        return StackRowModel(
            id: entry.id, title: title, header: header, height: height, sizeChoices: choices, size: entry.size,
            canMoveUp: index > 0, canMoveDown: index < count - 1, isCollapsed: entry.collapsed)
    }
}

enum StackWidgetMenuText {
    static func label(_ size: StackSize, contract: WidgetContract = .current) -> String {
        guard let name = size.presetName, let rows = contract.presetCells(name)?.rows else { return "Auto" }
        return "\(name.prefix(1).uppercased() + name.dropFirst()) · \(rows) rows"
    }
}
