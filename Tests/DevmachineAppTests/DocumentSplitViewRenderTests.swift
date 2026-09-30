import XCTest
import SwiftUI
@testable import DevmachineApp

@MainActor
final class DocumentSplitViewRenderTests: XCTestCase {
    private func render(_ split: DocumentSplitState, showsTrailing: Bool = true, width: CGFloat = 1006) throws -> NSBitmapImageRep {
        let view = DocumentSplitView(split: split, showsTrailing: showsTrailing) {
            Color(red: 1, green: 0, blue: 0)
        } trailing: {
            Color(red: 0, green: 0, blue: 1)
        }
        .frame(width: width, height: 40)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return NSBitmapImageRep(cgImage: image)
    }

    private func isBlue(_ bitmap: NSBitmapImageRep, x: Int) -> Bool {
        let color = bitmap.colorAt(x: x, y: 20)!.usingColorSpace(.sRGB)!
        return color.blueComponent > 0.9 && color.redComponent < 0.1
    }

    private func isRed(_ bitmap: NSBitmapImageRep, x: Int) -> Bool {
        let color = bitmap.colorAt(x: x, y: 20)!.usingColorSpace(.sRGB)!
        return color.redComponent > 0.9 && color.blueComponent < 0.1
    }

    private func split(_ fraction: Double? = nil) -> DocumentSplitState {
        let defaults = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
        if let fraction { defaults.set(fraction, forKey: DocumentSplitState.key) }
        return DocumentSplitState(defaults: defaults)
    }

    func testHalfAndHalfSplitsTheWidthAroundTheHandle() throws {
        let bitmap = try render(split())
        XCTAssertTrue(isRed(bitmap, x: 495))
        XCTAssertTrue(isBlue(bitmap, x: 510))
    }

    func testAWideShareLeavesTheTerminalItsMinimum() throws {
        let bitmap = try render(split(0.9), width: 2006)
        XCTAssertTrue(isRed(bitmap, x: 300))
        XCTAssertTrue(isBlue(bitmap, x: 330))
    }

    func testAMaximizedPaneCoversTheWholeWidth() throws {
        let state = split()
        state.toggleMaximized()
        let bitmap = try render(state)
        XCTAssertTrue(isBlue(bitmap, x: 5))
        XCTAssertTrue(isBlue(bitmap, x: 1000))
    }

    func testWithoutThePaneTheTerminalTakesEverything() throws {
        let bitmap = try render(split(), showsTrailing: false)
        XCTAssertTrue(isRed(bitmap, x: 5))
        XCTAssertTrue(isRed(bitmap, x: 1000))
    }
}
