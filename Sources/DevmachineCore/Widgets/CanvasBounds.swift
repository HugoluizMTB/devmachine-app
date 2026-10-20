import CoreGraphics
import Foundation

/// Keeps every widget on Home where it can be seen and grabbed. Clamping
/// moves only the drawing: the board file changes when the person moves or
/// resizes a widget, so a window that shrinks and grows back finds the
/// layout as it was saved.
public enum CanvasBounds {
    /// The top strip of a widget that must stay on the canvas to drag it by.
    public static let grab = CanvasSize(w: 120, h: 44)
    /// The smallest box a widget is drawn or resized to, so a widget whose
    /// content failed or is empty can still be seen, grabbed and fixed.
    public static let floor = CanvasSize(w: 160, h: 80)

    /// A growing view is as tall as its content (a one-line pill is valid),
    /// so its height floor is only the grab strip.
    public static func minimum(declared: CanvasSize?, grows: Bool) -> CanvasSize {
        let declared = declared ?? CanvasSize(w: 0, h: 0)
        return CanvasSize(w: max(declared.w, floor.w), h: max(declared.h, grows ? grab.h : floor.h))
    }

    /// Fully inside the canvas when it fits; a widget wider or taller than the
    /// canvas is pinned to that edge's start, so its top strip shows.
    public static func onCanvas(_ frame: BoardFrame, in canvas: CGSize) -> BoardFrame {
        let w = max(1, frame.w), h = max(1, frame.h)
        let width = max(0, Int(canvas.width.rounded(.down))), height = max(0, Int(canvas.height.rounded(.down)))
        return BoardFrame(x: clamp(frame.x, 0, width - w), y: clamp(frame.y, 0, height - h), w: w, h: h)
    }

    /// A resized frame stops at the canvas edge, never under `minimum`; when
    /// the minimum does not fit where it is, the widget moves in.
    public static func fitted(
        _ frame: BoardFrame, minimum: CanvasSize, in canvas: CGSize, capsHeight: Bool = true
    ) -> BoardFrame {
        let roomW = Int(canvas.width.rounded(.down)) - frame.x, roomH = Int(canvas.height.rounded(.down)) - frame.y
        let w = max(minimum.w, min(frame.w, roomW))
        let h = capsHeight ? max(minimum.h, min(frame.h, roomH)) : max(minimum.h, frame.h)
        return onCanvas(BoardFrame(x: frame.x, y: frame.y, w: w, h: h), in: canvas)
    }

    /// Push-down (display only) may move a widget under the bottom edge; it
    /// stops where the widget's grab strip is still on the canvas. The held
    /// widget is drawn where the pointer has it. `order` breaks ties between
    /// widgets at the same place, as the board's order does.
    public static func settled(
        _ frames: [String: BoardFrame], order: [String]? = nil, in canvas: CGSize, holding held: String?
    ) -> [String: BoardFrame] {
        let pushed = CanvasLayout.pushedDown((order ?? frames.keys.sorted()).compactMap { id in
            frames[id].map { CanvasPlacement(id: id, x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
        })
        var shown = frames
        for (id, y) in pushed where id != held {
            guard var frame = shown[id] else { continue }
            let lowest = max(frame.y, Int(canvas.height.rounded(.down)) - min(frame.h, grab.h))
            frame.y = min(y, max(0, lowest))
            shown[id] = frame
        }
        return shown
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        max(low, min(value, max(low, high)))
    }
}
