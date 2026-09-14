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
                    colors: style == .photo
                        ? [.black.opacity(0.25), .black.opacity(0.55)]
                        : [.black.opacity(0.5), .black.opacity(0.8)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipped()
            // .clipped() trims the drawing but NOT hit-testing: scaledToFill
            // overflows the container (3:2 photo in a narrower pane) and the
            // overflow leaked over the sidebar's right edge, swallowing clicks.
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var wallpaper: some View {
        if let image = baked {
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
            guard let image = wallpapers.images[id] else { return bundled }
            return WallpaperBaker.image(key: "unsplash:" + id, style: style) { image }
        case .gradient(let name):
            let gradient = WallpaperGradient.named(name)
            return WallpaperBaker.image(key: "gradient:" + gradient.name, style: style) { gradient.bitmap() }
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

    var id: String { name }

    static let all: [WallpaperGradient] = [
        WallpaperGradient(name: "midnight", title: "Midnight", top: Color(hex: 0x16294A), bottom: Color(hex: 0x04060A)),
        WallpaperGradient(name: "ember", title: "Ember", top: Color(hex: 0x451316), bottom: Color(hex: 0x0A0405)),
        WallpaperGradient(name: "forest", title: "Forest", top: Color(hex: 0x123524), bottom: Color(hex: 0x040806)),
        WallpaperGradient(name: "graphite", title: "Graphite", top: Color(hex: 0x2E333A), bottom: Color(hex: 0x090A0C))
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
        guard let gradient = NSGradient(starting: NSColor(top), ending: NSColor(bottom)) else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        gradient.draw(in: NSRect(origin: .zero, size: size), angle: 285)
        image.unlockFocus()
        return image
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
