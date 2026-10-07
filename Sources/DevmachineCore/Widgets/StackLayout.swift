import Foundation

/// A stack widget's height: as tall as its content, or a fixed number of points.
public enum StackHeight: Equatable, Sendable {
    case auto
    case points(Int)
}

/// Heights in a stack are preset rows of `stack_row` points (at 100% text
/// size); width is always the panel's.
public enum StackLayout {
    public static let approvalRows = 5

    public static func height(of entry: StackEntry, resolved: ResolvedWidget, contract: WidgetContract = .current) -> StackHeight {
        switch effectiveSize(of: entry, resolved: resolved, contract: contract) {
        case let .preset(name): return .points(rows(name, contract: contract) * contract.stackRow)
        case .auto: return .auto
        }
    }

    /// The size an entry draws at, written or not, so the Size menu ticks
    /// what the person sees.
    public static func effectiveSize(of entry: StackEntry, resolved: ResolvedWidget, contract: WidgetContract = .current) -> StackSize {
        if let size = entry.size { return size }
        return contract.viewGrows(resolved.viewKind) ? .auto : .preset(defaultPreset(resolved))
    }

    public static func placeholderHeight(contract: WidgetContract = .current) -> Int { 2 * contract.stackRow }

    public static func sizeChoices(for resolved: ResolvedWidget, contract: WidgetContract = .current) -> [StackSize] {
        let presets = WidgetContract.presetOrder.filter(resolved.widget.sizes.contains).map(StackSize.preset)
        return (contract.viewGrows(resolved.viewKind) ? [.auto] : []) + presets
    }

    private static func defaultPreset(_ resolved: ResolvedWidget) -> String {
        if !resolved.widget.defaultSize.isEmpty { return resolved.widget.defaultSize }
        return resolved.widget.sizes.first ?? "medium"
    }

    private static func rows(_ preset: String, contract: WidgetContract) -> Int {
        contract.presetCells(preset)?.rows ?? 2
    }
}

/// Where a dragged header row lands. Rows move past a neighbour once the
/// drag crosses that neighbour's middle.
public enum StackDragMath {
    public static func targetIndex(from index: Int, translation: Double, heights: [Double]) -> Int {
        guard heights.indices.contains(index) else { return index }
        let step = translation >= 0 ? 1 : -1
        var target = index
        var left = abs(translation)
        var next = index + step
        while heights.indices.contains(next), left > heights[next] / 2 {
            left -= heights[next]
            target = next
            next += step
        }
        return target
    }

    public static func indicatorY(from index: Int, to target: Int, heights: [Double]) -> Double {
        let end = target > index ? target + 1 : target
        return heights.prefix(max(0, min(end, heights.count))).reduce(0, +)
    }
}

public struct StackPlacementResult: Equatable, Sendable {
    public let board: StackBoard
    public let placements: WidgetPlacements
    public let boardChanged: Bool
    public let placementsChanged: Bool
}

/// A widget whose `places` names a stack joins its end once; one the person
/// removed stays removed, because its placement is remembered.
public enum StackPlacer {
    public static func place(on board: StackBoard, catalog: WidgetCatalog?, placements: WidgetPlacements) -> StackPlacementResult {
        var board = board
        var placements = placements
        var boardChanged = false
        var placementsChanged = false
        let surface = board.surface
        for widget in StackCatalog.merged(catalog).widgets
            where widget.placesItself(on: surface, fitting: "stack") && !placements.contains(widget.name, on: surface) {
            if !board.entries.contains(where: { $0.type == widget.name }) {
                board.insert(newEntry(of: widget, on: board), at: .end)
                boardChanged = true
            }
            placements.insert(widget.name, on: surface)
            placementsChanged = true
        }
        return StackPlacementResult(
            board: board, placements: placements, boardChanged: boardChanged, placementsChanged: placementsChanged)
    }

    public static func newEntry(of widget: CatalogWidget, on board: StackBoard) -> StackEntry {
        let size: StackSize? = WidgetContract.current.viewGrows(widget.viewKind) ? .auto : nil
        return StackEntry(id: board.uniqueID(base: widget.widget), type: widget.name, size: size)
    }
}
