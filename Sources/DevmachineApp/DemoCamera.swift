#if DEBUG
import AppKit

/// Debug builds only. The site walk's camera: it eases into a part of the
/// window and back out, by cropping and scaling the real frames. A scene
/// that zooms is captured at a higher scale, so the zoomed text stays sharp.
enum DemoCamera {
    static let captureScale: CGFloat = 4
    /// How much of the window the zoomed view shows, as a share of its width.
    static let zoom: CGFloat = 1.8
    static let frames = 24
    static let frameSeconds = 0.8 / Double(frames)
    static var seconds: Double { Double(frames) * frameSeconds }

    /// `DemoSiteWalk.windowSize`, the window every scene is captured in.
    static let window = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    /// A rect of the window's shape around a control, kept inside the window.
    static func rect(around control: CGRect, left: CGFloat? = nil) -> CGRect {
        DemoSnapshots.zoomRect(around: control, in: window.size, zoom: zoom, left: left)
    }

    /// The camera rect for a frame's `zoom` target, from the frames the walk
    /// recorded.
    @MainActor
    static func rect(for target: String) -> CGRect? {
        let frames = DemoClickTargets.frames
        guard let control = frames[target] else { return nil }
        return rect(around: control, left: DemoSnapshots.zoomLeftEdge(for: target, frames: frames))
    }

    /// The rects in between, eased, ending on the target; nil is the whole
    /// window.
    static func path(from start: CGRect?, to end: CGRect?) -> [CGRect] {
        let a = start ?? window
        let b = end ?? window
        return (1...frames).map { index in
            let t = CGFloat(DemoPointer.easeInOut(Double(index) / Double(frames)))
            return CGRect(
                x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
        }
    }

    /// The part of the frame inside `rect` (window points from the top left),
    /// scaled back up to the whole frame's size.
    @MainActor
    static func crop(_ base: NSBitmapImageRep, to rect: CGRect, scale: CGFloat) -> NSBitmapImageRep {
        let width = base.pixelsWide
        let height = base.pixelsHigh
        guard let copy = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: copy)
        else { return base }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(base)
        let source = NSRect(
            x: rect.minX * scale, y: CGFloat(height) - rect.maxY * scale,
            width: rect.width * scale, height: rect.height * scale)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: source, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return copy
    }
}
#endif
