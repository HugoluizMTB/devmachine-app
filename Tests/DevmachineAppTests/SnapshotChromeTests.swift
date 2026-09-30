import XCTest
import AppKit
@testable import DevmachineApp

@MainActor
final class SnapshotChromeTests: XCTestCase {
    private func solid(width: Int, height: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(NSColor(deviceRed: 0.2, green: 0.2, blue: 0.2, alpha: 1), atX: x, y: y)
            }
        }
        return rep
    }

    func testTheFrameAddsAMarginOnEverySide() {
        let framed = SnapshotChrome.framed(solid(width: 400, height: 300), scale: 1, kind: .window)
        let margin = Int(SnapshotChrome.margin)
        XCTAssertEqual(framed.pixelsWide, 400 + margin * 2)
        XCTAssertEqual(framed.pixelsHigh, 300 + margin * 2)
    }

    func testTheMarginScalesWithTheBackingScale() {
        let framed = SnapshotChrome.framed(solid(width: 800, height: 600), scale: 2, kind: .panel)
        XCTAssertEqual(framed.pixelsWide, 800 + Int(SnapshotChrome.margin) * 4)
    }

    func testTheWindowSitsOnAnOpaqueBlackBackdrop() {
        let framed = SnapshotChrome.framed(solid(width: 400, height: 300), scale: 1, kind: .window)
        let corner = framed.colorAt(x: 0, y: 0)
        XCTAssertEqual(corner?.alphaComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(corner?.brightnessComponent ?? 1, 0, accuracy: 0.02)
    }

    func testTheWindowCornerIsRounded() {
        let framed = SnapshotChrome.framed(solid(width: 400, height: 300), scale: 1, kind: .panel)
        let margin = Int(SnapshotChrome.margin)
        let corner = framed.colorAt(x: margin, y: margin)
        let inside = framed.colorAt(x: margin + 200, y: margin + 150)
        XCTAssertEqual(inside?.alphaComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertNotEqual(corner?.redComponent, inside?.redComponent)
    }

    func testAWindowGetsTrafficLights() {
        let framed = SnapshotChrome.framed(solid(width: 400, height: 300), scale: 1, kind: .window)
        let point = SnapshotChrome.trafficLightCenters.first!
        let margin = Int(SnapshotChrome.margin)
        let red = framed.colorAt(x: margin + Int(point.x), y: margin + Int(point.y))!
        XCTAssertGreaterThan(red.redComponent, 0.8)
        XCTAssertLessThan(red.greenComponent, 0.5)
    }

    func testAPanelHasNoTrafficLights() {
        let framed = SnapshotChrome.framed(solid(width: 400, height: 300), scale: 1, kind: .panel)
        let point = SnapshotChrome.trafficLightCenters.first!
        let margin = Int(SnapshotChrome.margin)
        let pixel = framed.colorAt(x: margin + Int(point.x), y: margin + Int(point.y))!
        XCTAssertEqual(pixel.redComponent, 0.2, accuracy: 0.05)
    }
}
