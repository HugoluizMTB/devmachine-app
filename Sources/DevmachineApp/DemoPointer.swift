#if DEBUG
import AppKit

/// Debug builds only. The pointer the site walk draws on its frames: the
/// system arrow, moved along an eased path, and a soft circle at its tip
/// that shrinks and fades on a click.
enum DemoPointer {
    static let moveFrames = 15
    static let moveFrameSeconds = 0.033
    static let clickFrameSeconds = 0.083

    /// Ring radius and opacity in points, one per click frame.
    struct Ring: Equatable {
        let radius: CGFloat
        let opacity: CGFloat
    }

    static let rings = [Ring(radius: 15, opacity: 0.5), Ring(radius: 11, opacity: 0.35), Ring(radius: 7, opacity: 0.18)]

    static var moveSeconds: Double { Double(moveFrames) * moveFrameSeconds }

    static var clickSeconds: Double { moveSeconds + Double(rings.count) * clickFrameSeconds }

    /// Where a label sits, in window points from the top left: its leading
    /// edge at a point, or its trailing edge there.
    enum LabelPlace: Equatable {
        case leading(CGPoint)
        case trailing(CGPoint)
    }

    /// A copy of `base` with a small dark pill of white text.
    @MainActor
    static func drawLabel(_ text: String, on base: NSBitmapImageRep, place: LabelPlace, scale: CGFloat) -> NSBitmapImageRep {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15 * scale, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let padding = NSSize(width: 14 * scale, height: 7 * scale)
        let size = NSSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        let anchor: CGPoint
        let left: CGFloat
        switch place {
        case let .leading(point):
            anchor = point
            left = point.x * scale
        case let .trailing(point):
            anchor = point
            left = point.x * scale - size.width
        }
        let height = CGFloat(base.pixelsHigh)
        let rect = NSRect(
            x: max(8 * scale, left), y: height - anchor.y * scale - size.height / 2,
            width: size.width, height: size.height)
        return drawn(on: base) {
            let pill = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 12 * scale
            shadow.set()
            NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.94).setFill()
            pill.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.22).setStroke()
            pill.lineWidth = scale
            pill.stroke()
            string.draw(at: NSPoint(x: rect.minX + padding.width, y: rect.minY + padding.height))
        }
    }

    @MainActor
    private static func drawn(on base: NSBitmapImageRep, _ draw: () -> Void) -> NSBitmapImageRep {
        let width = base.pixelsWide
        let height = base.pixelsHigh
        guard let copy = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: copy)
        else { return base }
        let size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let backdrop = NSImage(size: size)
        backdrop.addRepresentation(base)
        backdrop.draw(in: NSRect(origin: .zero, size: size))
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return copy
    }

    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    /// The positions after the start, ending on the target.
    static func path(from start: CGPoint, to end: CGPoint, frames: Int = moveFrames) -> [CGPoint] {
        (1...frames).map { index in
            let t = easeInOut(Double(index) / Double(frames))
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    /// A copy of `base` with the arrow's hot spot at `point` (window points
    /// from the top left) and, on a click, the ring under it.
    @MainActor
    static func draw(on base: NSBitmapImageRep, at point: CGPoint, ring: Ring?, scale: CGFloat) -> NSBitmapImageRep {
        let width = base.pixelsWide
        let height = base.pixelsHigh
        guard let copy = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: copy)
        else { return base }
        let size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let backdrop = NSImage(size: size)
        backdrop.addRepresentation(base)
        backdrop.draw(in: NSRect(origin: .zero, size: size))

        let tip = NSPoint(x: point.x * scale, y: CGFloat(height) - point.y * scale)
        if let ring {
            let radius = ring.radius * scale
            let circle = NSBezierPath(ovalIn: NSRect(
                x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
            NSColor.white.withAlphaComponent(ring.opacity).setFill()
            circle.fill()
            NSColor.white.withAlphaComponent(min(1, ring.opacity + 0.25)).setStroke()
            circle.lineWidth = scale
            circle.stroke()
        }

        let cursor = NSCursor.arrow
        let image = cursor.image
        let hotSpot = cursor.hotSpot
        let rect = NSRect(
            x: tip.x - hotSpot.x * scale,
            y: tip.y - (image.size.height - hotSpot.y) * scale,
            width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return copy
    }
}
#endif
