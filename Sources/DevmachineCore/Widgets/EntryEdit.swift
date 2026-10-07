import Foundation

/// One edit of one board entry, whatever the area. The chooser and the
/// editor build it, the board's controller applies it inside one store
/// update, so every other entry is written back as it was read.
public enum EntryEdit: Equatable, Sendable {
    /// nil removes the key, so the input falls back to its default.
    case input(name: String, value: BoardScalar?)
    case typed(title: String?, with: [String: BoardScalar], every: String?)
    case inline(InlineWidget)

    @discardableResult
    public func apply(to widget: inout BoardWidget) -> Bool {
        var next = widget
        switch self {
        case let .input(name, value):
            guard !next.isInline else { return false }
            next.with[name] = value
        case let .typed(title, with, every):
            guard !next.isInline else { return false }
            next.titleOverride = title
            next.with = with
            next.everyOverride = every
        case let .inline(inline):
            guard next.isInline else { return false }
            next.inline = inline
        }
        guard next != widget else { return false }
        widget = next
        return true
    }

    @discardableResult
    public func apply(to entry: inout StackEntry) -> Bool {
        var widget = entry.boardWidget
        guard apply(to: &widget) else { return false }
        entry.with = widget.with
        entry.titleOverride = widget.titleOverride
        entry.everyOverride = widget.everyOverride
        entry.inline = widget.inline
        return true
    }
}

/// What the editor reads of an entry, the same on a canvas and in a list.
public struct EditableEntry: Equatable, Sendable {
    public let id: String
    public let type: String
    public let with: [String: BoardScalar]
    public let titleOverride: String?
    public let everyOverride: String?
    public let inline: InlineWidget?

    public init(_ widget: BoardWidget) {
        id = widget.id
        type = widget.type
        with = widget.with
        titleOverride = widget.titleOverride
        everyOverride = widget.everyOverride
        inline = widget.inline
    }

    public init(_ entry: StackEntry) {
        self.init(entry.boardWidget)
    }
}

/// Where a new inline widget lands on a canvas: the first free spot at its
/// preset, as a widget from the gallery lands.
public enum InlineEntryPlacement {
    public static func canvasWidget(
        id: String, inline: InlineWidget, preset: String, on board: Board, canvasWidth: Int,
        contract: WidgetContract = .current
    ) -> BoardWidget {
        let size = CanvasLayout.presetSize(preset, contract: contract) ?? CanvasSize(w: 320, h: 160)
        let spot = CanvasLayout.firstFreeSpot(for: size, avoiding: board.widgets.map(\.frame), bandWidth: canvasWidth)
        return BoardWidget(
            id: id, type: "", frame: spot, size: CanvasLayout.presetSize(preset, contract: contract) == nil ? BoardWidget.customSize : preset,
            z: board.topZ + 1, inline: inline)
    }
}
