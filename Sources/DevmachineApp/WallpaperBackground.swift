import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum WallpaperStyle {
    /// The photo as-is (Home).
    case photo
    /// The photo reduced to soft color washes: heavy blur, darker, a little more
    /// saturated — a backdrop for translucent terminals that stays readable.
    case ambient
}

struct WallpaperBackground: View {
    var style: WallpaperStyle = .photo

    // The asset ships at 1920px. Both variants are baked once, in bitmap pixels:
    // the photo gets a whisper of blur so the low-res source never reads as
    // pixelated on a 5K pane; ambient is a 512px wash (25px ≈ 5% of its width,
    // the same softness the old live blur(70) had on a ~1400pt pane).
    private static let source: NSImage? = loadWallpaper()
    private static let photoWallpaper: NSImage? = bake(source, width: 1920, blur: 2)
    private static let ambientWallpaper: NSImage? = bake(source, width: 512, blur: 25)

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
        switch style {
        case .photo:
            if let img = Self.photoWallpaper {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        case .ambient:
            if let img = Self.ambientWallpaper {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .saturation(1.25)
                    .brightness(-0.25)
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [Color(hex: 0x1B2733), Color(hex: 0x0E1217)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private static func loadWallpaper() -> NSImage? {
        if let url = Bundle.main.url(forResource: "wallpaper", withExtension: "jpg"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let devPath = NSHomeDirectory() + "/dev/devmachine-app/wallpaper.jpg"
        return NSImage(contentsOfFile: devPath)
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
