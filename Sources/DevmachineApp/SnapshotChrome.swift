import AppKit

/// Frames a captured window for the website the way a macOS window
/// screenshot looks: rounded corners, a hairline edge, the traffic lights on
/// a full window, all on a black backdrop. A bitmap capture of the content
/// view carries none of that, since the window server draws it.
enum SnapshotChrome {
    enum Kind: Equatable {
        /// The main window: traffic lights top left.
        case window
        /// A menubar pane or a sheet: rounded, no traffic lights.
        case panel
    }

    /// Points of backdrop around the window on every side.
    static let margin: CGFloat = 40
    static let cornerRadius: CGFloat = 10
    static let trafficLightDiameter: CGFloat = 12
    /// Centers in points from the window's top-left corner: where macOS put
    /// them on the captured window (`measure`), which a toolbar moves.
    @MainActor static var trafficLightCenters: [CGPoint] = [
        CGPoint(x: 14, y: 14), CGPoint(x: 34, y: 14), CGPoint(x: 54, y: 14),
    ]

    /// Reads where the window draws its buttons. The capture shows them grey
    /// (the window is never key), so they are painted again in color there.
    @MainActor static func measure(_ window: NSWindow) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let centers = buttons.compactMap { type -> CGPoint? in
            guard let button = window.standardWindowButton(type), let frameView = window.contentView?.superview
            else { return nil }
            let rect = button.convert(button.bounds, to: frameView)
            let y = frameView.isFlipped ? rect.midY : frameView.bounds.height - rect.midY
            return CGPoint(x: rect.midX, y: y)
        }
        if centers.count == 3 { trafficLightCenters = centers }
    }

    /// The window's whole frame view: the content and, above it, the toolbar.
    @MainActor static func capturedView(_ window: NSWindow) -> NSView {
        window.contentView?.superview ?? window.contentView ?? NSView()
    }
    private static let trafficLightColors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1),
    ]

    @MainActor static func framed(_ rep: NSBitmapImageRep, scale: CGFloat, kind: Kind) -> NSBitmapImageRep {
        let inset = margin * scale
        let windowSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let width = rep.pixelsWide + Int(inset) * 2
        let height = rep.pixelsHigh + Int(inset) * 2
        guard let framed = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: framed)
        else { return rep }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let windowRect = NSRect(origin: NSPoint(x: inset, y: inset), size: windowSize)
        let radius = cornerRadius * scale
        let outline = NSBezierPath(roundedRect: windowRect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let image = NSImage(size: windowSize)
        image.addRepresentation(rep)
        image.draw(in: windowRect)
        NSGraphicsContext.restoreGraphicsState()

        let edge = NSBezierPath(
            roundedRect: windowRect.insetBy(dx: scale / 2, dy: scale / 2),
            xRadius: radius - scale / 2, yRadius: radius - scale / 2)
        edge.lineWidth = scale
        NSColor.white.withAlphaComponent(0.16).setStroke()
        edge.stroke()

        if kind == .window {
            drawTrafficLights(in: windowRect, scale: scale)
        }
        NSGraphicsContext.restoreGraphicsState()
        return framed
    }

    @MainActor private static func drawTrafficLights(in windowRect: NSRect, scale: CGFloat) {
        let diameter = trafficLightDiameter * scale
        for (center, color) in zip(trafficLightCenters, trafficLightColors) {
            let x = windowRect.minX + center.x * scale - diameter / 2
            let y = windowRect.maxY - center.y * scale - diameter / 2
            let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter))
            color.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            dot.lineWidth = scale / 2
            dot.stroke()
        }
    }
}
