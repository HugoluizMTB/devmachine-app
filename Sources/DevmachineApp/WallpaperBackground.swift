import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import DevmachineCore

enum WallpaperStyle {
    /// The photo as-is (Home).
    case photo
    /// The photo reduced to soft color washes: heavy blur, darker, a little more
    /// saturated — a backdrop for translucent terminals that stays readable.
    case ambient

    // The asset ships at 1920px. Both variants are baked once, in bitmap pixels:
    // the photo gets a whisper of blur so the low-res source never reads as
    // pixelated on a 5K pane; ambient is a 512px wash (25px ≈ 5% of its width,
    // the same softness the old live blur(70) had on a ~1400pt pane).
    var bakeWidth: CGFloat { self == .photo ? 1920 : 512 }
    var bakeBlur: CGFloat { self == .photo ? 2 : 25 }
    var bakeKey: String { self == .photo ? "photo" : "ambient" }
}

struct WallpaperBackground: View {
    var style: WallpaperStyle = .photo
    /// Overrides the saved choice, so Setup can preview its draft live.
    var choice: WallpaperChoice?

    @EnvironmentObject private var wallpapers: WallpaperStore

    private var active: WallpaperChoice { choice ?? wallpapers.choice }

    var body: some View {
        // Base on Color.clear (zero intrinsic size, shrinks freely) and paint the
        // image as an overlay clipped to it, so this view never imposes the
        // image's native width on its parent (as a ZStack child or a background).
        Color.clear
            .overlay { wallpaper }
            .overlay(
                LinearGradient(
                    colors: Self.dimming(style: style, choice: active).map { .black.opacity($0) },
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipped()
            // .clipped() trims the drawing but NOT hit-testing: scaledToFill
            // overflows the container (3:2 photo in a narrower pane) and the
            // overflow leaked over the sidebar's right edge, swallowing clicks.
            .allowsHitTesting(false)
    }

    /// The black laid over the wallpaper, top and bottom, so Home's text
    /// reads on any photo. The map is already dark and quiet; it needs only
    /// the bottom darkened, under the stats pill.
    static func dimming(style: WallpaperStyle, choice: WallpaperChoice) -> [Double] {
        switch (style, choice) {
        case (.photo, .networkMap): return [0, 0.35]
        case (.photo, _): return [0.25, 0.55]
        case (.ambient, _): return [0.5, 0.8]
        }
    }

    @ViewBuilder
    private var wallpaper: some View {
        if active == .networkMap {
            switch style {
            case .photo: NetworkMapWallpaper()
            case .ambient: NetworkMapGround()
            }
        } else if let image = baked {
            let filled = Image(nsImage: image).resizable().scaledToFill()
            switch style {
            case .photo:
                filled
            case .ambient:
                filled.saturation(1.25).brightness(-0.25)
            }
        } else {
            fallback
        }
    }

    private var baked: NSImage? {
        switch active {
        case .bundled:
            return bundled
        case .unsplash(let id):
            // The plain gradient while the chosen photo is read from disk, not
            // the bundled one: showing another photo for an instant reads as the
            // app flashing a wallpaper the owner did not pick.
            guard let image = wallpapers.images[id] else { return nil }
            return WallpaperBaker.image(key: "unsplash:" + id, style: style) { image }
        case .gradient(let name):
            let gradient = WallpaperGradient.named(name)
            return WallpaperBaker.image(key: "gradient:" + gradient.name, style: style) {
                gradient.isLandscape ? gradient.bitmap(width: 1920, height: 1200) : gradient.bitmap()
            }
        case .networkMap:
            return nil
        }
    }

    private var bundled: NSImage? {
        WallpaperBaker.image(key: "bundled", style: style) { WallpaperAsset.bundledImage() }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [Color(hex: 0x1B2733), Color(hex: 0x0E1217)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

struct WallpaperGradient: Identifiable, Equatable {
    let name: String
    let title: String
    let top: Color
    let bottom: Color
    /// Drawn as layered mountain ridges under the sky gradient: a landscape
    /// made in code, so it carries no photo rights and shows no one.
    var isLandscape = false

    var id: String { name }

    static let all: [WallpaperGradient] = [
        WallpaperGradient(name: "midnight", title: "Midnight", top: Color(hex: 0x16294A), bottom: Color(hex: 0x04060A)),
        WallpaperGradient(name: "ember", title: "Ember", top: Color(hex: 0x451316), bottom: Color(hex: 0x0A0405)),
        WallpaperGradient(name: "forest", title: "Forest", top: Color(hex: 0x123524), bottom: Color(hex: 0x040806)),
        WallpaperGradient(name: "graphite", title: "Graphite", top: Color(hex: 0x2E333A), bottom: Color(hex: 0x090A0C)),
        WallpaperGradient(
            name: "peaks", title: "Peaks", top: Color(hex: 0x1C2840), bottom: Color(hex: 0x7A4A52), isLandscape: true)
    ]

    static func named(_ name: String) -> WallpaperGradient {
        all.first { $0.name == name } ?? all[0]
    }

    var swatch: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// `lockFocus` draws into the current graphics context, which is main-thread only.
    @MainActor
    func bitmap(width: CGFloat = 1024, height: CGFloat = 640) -> NSImage? {
        let size = NSSize(width: width, height: height)
        if isLandscape { return PeaksPainter.image(size: size, sky: NSColor(top), horizon: NSColor(bottom)) }
        guard let gradient = NSGradient(starting: NSColor(top), ending: NSColor(bottom)) else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        gradient.draw(in: NSRect(origin: .zero, size: size), angle: 285)
        image.unlockFocus()
        return image
    }
}

/// Paints the "Peaks" landscape: a dusk sky and four mountain ridges, far to
/// near, each darker and lower. The ridges come from a seeded midpoint
/// displacement, so every launch draws the same picture.
enum PeaksPainter {
    private struct Ridge {
        let base: CGFloat
        let height: CGFloat
        let roughness: CGFloat
        let color: NSColor
        let seed: UInt64
    }

    private static let ridges: [Ridge] = [
        Ridge(base: 0.50, height: 0.22, roughness: 0.55, color: NSColor(srgbRed: 0.34, green: 0.25, blue: 0.32, alpha: 1), seed: 11),
        Ridge(base: 0.38, height: 0.20, roughness: 0.52, color: NSColor(srgbRed: 0.24, green: 0.17, blue: 0.23, alpha: 1), seed: 23),
        Ridge(base: 0.24, height: 0.16, roughness: 0.50, color: NSColor(srgbRed: 0.10, green: 0.09, blue: 0.13, alpha: 1), seed: 37),
        Ridge(base: 0.10, height: 0.12, roughness: 0.45, color: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1), seed: 53)
    ]

    @MainActor
    static func image(size: NSSize, sky: NSColor, horizon: NSColor) -> NSImage? {
        guard let skyGradient = NSGradient(colors: [horizon, sky, sky.blended(withFraction: 0.4, of: .black) ?? sky]) else {
            return nil
        }
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = NSRect(origin: .zero, size: size)
        skyGradient.draw(in: bounds, angle: 90)
        for (index, ridge) in ridges.enumerated() {
            ridge.color.setFill()
            path(for: ridge, in: size).fill()
            if index < ridges.count - 1 { haze(below: ridge, in: size) }
        }
        image.unlockFocus()
        return image
    }

    private static func path(for ridge: Ridge, in size: NSSize) -> NSBezierPath {
        let heights = profile(points: 129, roughness: ridge.roughness, seed: ridge.seed)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        for (index, value) in heights.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(heights.count - 1)
            path.line(to: NSPoint(x: x, y: size.height * (ridge.base + ridge.height * value)))
        }
        path.line(to: NSPoint(x: size.width, y: 0))
        path.close()
        return path
    }

    private static func haze(below ridge: Ridge, in size: NSSize) {
        let band = NSRect(x: 0, y: 0, width: size.width, height: size.height * ridge.base)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.035)])?
            .draw(in: band, angle: 90)
    }

    /// Heights in 0...1 from midpoint displacement, `points` = 2^n + 1.
    private static func profile(points: Int, roughness: CGFloat, seed: UInt64) -> [CGFloat] {
        var random = SeededRandom(seed: seed)
        var values = [CGFloat](repeating: 0, count: points)
        values[0] = random.unit()
        values[points - 1] = random.unit()
        var step = points - 1
        var spread: CGFloat = 1
        while step > 1 {
            let half = step / 2
            for start in stride(from: 0, to: points - 1, by: step) {
                let middle = (values[start] + values[start + step]) / 2
                values[start + half] = middle + (random.unit() - 0.5) * spread
            }
            spread *= roughness
            step = half
        }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        return values.map { high > low ? ($0 - low) / (high - low) : 0 }
    }

    private struct SeededRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

        mutating func unit() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }
    }
}

enum WallpaperAsset {
    static func bundledImage() -> NSImage? {
        guard let url = url(resource: "wallpaper", extension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func libraryData() -> Data? {
        guard let url = url(resource: "wallpapers", extension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Walks up from `start` to the checkout that holds it, so an unbundled
    /// binary finds the assets of the tree it was built from.
    static func checkoutRoot(from start: URL) -> URL? {
        var directory = start
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    // Unbundled (a plain `swift build` binary) there is no resource folder, so
    // fall back to the checkout — its root holds the photo, Resources/ the list.
    private static func url(resource: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: resource, withExtension: ext) { return url }

        let roots = [
            checkoutRoot(from: Bundle.main.bundleURL),
            URL(fileURLWithPath: NSHomeDirectory() + "/dev/devmachine-app")
        ]
        for root in roots.compactMap({ $0 }) {
            for candidate in [
                root.appendingPathComponent("\(resource).\(ext)"),
                root.appendingPathComponent("Resources/\(resource).\(ext)")
            ] where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// One bake per (source, style). The key names the source, so an Unsplash choice
/// that is still downloading shares the bundled bake instead of making its own.
@MainActor
enum WallpaperBaker {
    /// A 1920px bake is around 10MB, and browsing Setup walks through 31 photos.
    static let cap = 6

    private static var cache: [String: NSImage] = [:]
    private static var usedAt: [String: Date] = [:]

    static func image(key: String, style: WallpaperStyle, source: () -> NSImage?) -> NSImage? {
        let id = key + "#" + style.bakeKey
        usedAt[id] = Date()

        if let hit = cache[id] { return hit }
        guard let baked = bake(source(), width: style.bakeWidth, blur: style.bakeBlur) else {
            usedAt[id] = nil
            return nil
        }

        cache[id] = baked
        for stale in LRUEviction.keysToEvict(detachedAt: usedAt, cap: cap) {
            cache[stale] = nil
            usedAt[stale] = nil
        }
        return baked
    }

    private static func bake(_ image: NSImage?, width: CGFloat, blur: CGFloat) -> NSImage? {
        guard let image,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              source.width > 0
        else { return nil }

        let scale = min(1, width / CGFloat(source.width))
        let target = CGRect(
            x: 0, y: 0,
            width: (CGFloat(source.width) * scale).rounded(),
            height: (CGFloat(source.height) * scale).rounded()
        )
        // Clamp to an infinite extent before resizing and blurring, then crop back:
        // both filters sample outside the source extent, and the transparent pixels
        // they find there fade the edges, which reveals the pane background.
        let resize = CIFilter.lanczosScaleTransform()
        resize.inputImage = CIImage(cgImage: source).clampedToExtent()
        resize.scale = Float(scale)
        guard let small = resize.outputImage else { return nil }

        let soften = CIFilter.gaussianBlur()
        soften.inputImage = small
        soften.radius = Float(blur)
        guard let blurred = soften.outputImage,
              let baked = CIContext().createCGImage(blurred, from: target)
        else { return nil }

        return NSImage(cgImage: baked, size: NSSize(width: baked.width, height: baked.height))
    }
}
