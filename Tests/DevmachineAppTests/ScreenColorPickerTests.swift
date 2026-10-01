import XCTest
import AppKit
@testable import DevmachineApp

@MainActor
final class ScreenColorPickerTests: XCTestCase {
    func testAnSRGBColorKeepsItsHex() {
        let color = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        XCTAssertEqual(ScreenColorPicker.hex(of: color), "#1A334D")
    }

    func testADisplayP3ColorIsConvertedToSRGBFirst() {
        let color = NSColor(displayP3Red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        XCTAssertEqual(ScreenColorPicker.hex(of: color), "#808080")
        let red = NSColor(displayP3Red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        XCTAssertNotEqual(ScreenColorPicker.hex(of: red), "#CC3333")
    }

    func testAGrayColorIsConverted() {
        XCTAssertEqual(ScreenColorPicker.hex(of: NSColor(white: 1, alpha: 1)), "#FFFFFF")
    }
}
