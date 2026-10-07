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
        var title = entry.titleOverride ?? entry.inline?.title ?? WidgetTitle.make(type: entry.type, in: catalog)
        var header = StackHeaderStyle.standard
        var height = StackRowHeight.fixed(CGFloat(StackLayout.placeholderHeight(contract: contract)))
        var choices: [StackSize] = []
        var size = entry.size
        switch resolution {
        case let .ready(resolved)?:
            let appTitle = StackAppViewKind(viewKind: resolved.viewKind).flatMap { AppStackWidgets.titles[$0.rawValue] }
                ?? AppMenubarWidgets.boardTitles[resolved.viewKind]
            title = entry.titleOverride ?? entry.inline?.title ?? appTitle ?? title
            header = StackHeaderStyle.of(viewKind: resolved.viewKind)
            choices = StackLayout.sizeChoices(for: resolved, contract: contract)
            size = StackLayout.effectiveSize(of: entry, resolved: resolved, contract: contract)
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
            id: entry.id, title: title, header: header, height: height, sizeChoices: choices, size: size,
            canMoveUp: index > 0, canMoveDown: index < count - 1, isCollapsed: entry.collapsed)
    }

    /// An app widget with nothing to show takes no space at rest or on a
    /// plain hover, as before the stack; with ⌥ held over the panel (the
    /// `.bare` rule) it shows its title row, so it can still be collapsed,
    /// moved or removed.
    static func showsEmptyHeader(panelHovered: Bool, optionHeld: Bool, dragging: Bool, canEdit: Bool) -> Bool {
        canEdit && (dragging || (panelHovered && optionHeld))
    }

    /// A row without its own header has nowhere to put the controls but over
    /// its content, where they would cover the first workspace's buttons, so
    /// it shows them only while ⌥ is held over it.
    func showsControls(
        hovering: Bool, optionHeld: Bool, dragging: Bool, canEdit: Bool, inTitleHeader: Bool = false
    ) -> Bool {
        guard canEdit else { return false }
        if dragging || inTitleHeader { return true }
        switch header {
        case .standard: return true
        case .own: return hovering
        case .bare: return hovering && optionHeld
        }
    }
}

/// Where a dropped row goes, named by the neighbour it crossed in the list
/// the drag froze; a board read again meanwhile still lands it there.
enum StackDropTarget {
    static func position(of id: String, to target: Int, in entries: [StackEntry]) -> StackPosition? {
        guard let from = entries.firstIndex(where: { $0.id == id }), entries.indices.contains(target), target != from
        else { return nil }
        let neighbour = entries[target].id
        return target > from ? .after(neighbour) : .before(neighbour)
    }
}

enum StackWidgetMenuText {
    static func label(_ size: StackSize, contract: WidgetContract = .current) -> String {
        guard let name = size.presetName, let rows = contract.presetCells(name)?.rows else { return "Auto" }
        return "\(name.prefix(1).uppercased() + name.dropFirst()) · \(rows) rows"
    }
}
