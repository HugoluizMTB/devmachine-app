import XCTest
import CoreGraphics
@testable import DevmachineCore

final class MainWindowSizingTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let desktop = CGRect(x: 0, y: 25, width: 2560, height: 1415)

    func testAFirstOpenTakesEightyPercentOfTheVisibleScreen() {
        let frame = MainWindowSizing.defaultFrame(visible: desktop)
        XCTAssertEqual(frame.width, 2048, accuracy: 0.5)
        XCTAssertEqual(frame.height, 1132, accuracy: 0.5)
    }

    func testTheDefaultFrameIsCenteredOnTheVisibleScreen() {
        let frame = MainWindowSizing.defaultFrame(visible: desktop)
        XCTAssertEqual(frame.midX, desktop.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, desktop.midY, accuracy: 0.5)
    }

    func testASmallScreenStillGetsTheMinimumSize() {
        let small = CGRect(x: 0, y: 0, width: 1024, height: 640)
        let frame = MainWindowSizing.defaultFrame(visible: small)
        XCTAssertEqual(frame.size, MainWindowSizing.minimum)
    }

    func testTheMinimumNeverOutgrowsTheScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 500)
        let frame = MainWindowSizing.defaultFrame(visible: tiny)
        XCTAssertEqual(frame, tiny)
    }

    func testALaptopScreenGetsALargeWindowNotTheMinimum() {
        let frame = MainWindowSizing.defaultFrame(visible: laptop)
        XCTAssertGreaterThan(frame.width, MainWindowSizing.minimum.width + 200)
        XCTAssertGreaterThan(frame.height, MainWindowSizing.minimum.height + 150)
    }

    func testAFrameTheUserSavedIsLeftAlone() {
        XCTAssertNil(MainWindowSizing.initialFrame(savedFrame: "0 0 1000 700 0 0 2560 1415 ", visible: desktop))
    }

    func testNoSavedFrameGetsTheDefault() {
        XCTAssertEqual(
            MainWindowSizing.initialFrame(savedFrame: nil, visible: desktop),
            MainWindowSizing.defaultFrame(visible: desktop))
        XCTAssertEqual(
            MainWindowSizing.initialFrame(savedFrame: "", visible: desktop),
            MainWindowSizing.defaultFrame(visible: desktop))
    }
}
