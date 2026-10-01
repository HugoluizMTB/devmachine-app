import XCTest
import SwiftUI
@testable import DevmachineApp

/// Draws a view offscreen at one text size, with an empty margin around it,
/// and counts the solid pixels that land in the margin: text or a control
/// drawn past the view's own frame. A soft shadow stays under the threshold.
@MainActor
enum DMFitCheck {
    static let scales: [Double] = [0.8, 1, 1.3, 1.6]
    private static let margin: CGFloat = 40
    private static let pixelScale: CGFloat = 2
    private static let solidAlpha: UInt8 = 150

    struct Result {
        let size: CGSize
        let spilledPixels: Int
    }

    /// `width` is points at 100%, scaled with everything else. The view is
    /// built after the text size is set, the way the app rebuilds its tree.
    static func render(width: CGFloat? = nil, scale: Double, _ view: () -> some View) -> Result {
        let m = DMMetrics(scale: scale)
        let saved = DMFont.scale
        DMFont.scale = scale
        defer { DMFont.scale = saved }

        let root = view()
            .frame(width: width.map(m.pt), alignment: .leading)
            .fixedSize(horizontal: width == nil, vertical: true)
            .padding(margin)
            .environment(\.dmMetrics, m)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: root)
        renderer.scale = pixelScale
        guard let image = renderer.cgImage else { return Result(size: .zero, spilledPixels: -1) }

        let size = CGSize(
            width: CGFloat(image.width) / pixelScale - margin * 2,
            height: CGFloat(image.height) / pixelScale - margin * 2)
        return Result(size: size, spilledPixels: spilled(image))
    }

    /// Fails when the view spills out of its frame at any text size, or does
    /// not grow with the text. `proportionalWidth` is false for a view whose
    /// width is set from outside.
    static func assertFits(
        _ name: String, width: CGFloat? = nil, proportionalWidth: Bool = true,
        file: StaticString = #filePath, line: UInt = #line, _ view: () -> some View
    ) {
        let base = render(width: width, scale: 1, view)
        for scale in scales {
            let result = render(width: width, scale: scale, view)
            XCTAssertGreaterThan(result.size.width, 0, "\(name) at \(scale)", file: file, line: line)
            XCTAssertEqual(result.spilledPixels, 0, "\(name) spills out of its frame at \(scale)",
                           file: file, line: line)
            let expectedHeight = base.size.height * scale
            XCTAssertEqual(result.size.height, expectedHeight, accuracy: max(3, expectedHeight * 0.12),
                           "\(name) height at \(scale)", file: file, line: line)
            if proportionalWidth && width == nil {
                let expectedWidth = base.size.width * scale
                XCTAssertEqual(result.size.width, expectedWidth, accuracy: max(3, expectedWidth * 0.12),
                               "\(name) width at \(scale)", file: file, line: line)
            }
        }
    }

    private static func spilled(_ image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        let inset = Int(margin * pixelScale) - 2
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let inside = x >= inset && x < width - inset && y >= inset && y < height - inset
                if !inside && pixels[(y * width + x) * 4 + 3] > solidAlpha { count += 1 }
            }
        }
        return count
    }
}
