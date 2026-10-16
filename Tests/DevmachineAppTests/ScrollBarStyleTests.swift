import XCTest
@testable import DevmachineApp

final class ScrollBarStyleTests: XCTestCase {
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    override func tearDown() {
        UserDefaults.standard.setVolatileDomain(saved, forName: UserDefaults.argumentDomain)
        super.tearDown()
    }

    func testTheAppAsksForScrollBarsThatShowOnlyWhileScrolling() {
        let defaults = UserDefaults(suiteName: "ScrollBarStyleTests")!
        ScrollBarStyle.apply(to: defaults, environment: [:])
        XCTAssertEqual(defaults.string(forKey: "AppleShowScrollBars"), "WhenScrolling")
    }

    func testItWinsOverASettingOfAlways() {
        let defaults = UserDefaults(suiteName: "ScrollBarStyleTests")!
        ScrollBarStyle.apply(to: defaults, environment: ["DEVMACHINE_DEMO_SCROLL_BARS": "Always"])
        XCTAssertEqual(defaults.string(forKey: "AppleShowScrollBars"), "WhenScrolling")
    }

    func testItKeepsTheOtherLaunchArguments() {
        let defaults = UserDefaults(suiteName: "ScrollBarStyleTests")!
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["ScrollBarStyleTestsMarker"] = "kept"
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        ScrollBarStyle.apply(to: defaults, environment: [:])
        XCTAssertEqual(defaults.string(forKey: "ScrollBarStyleTestsMarker"), "kept")
    }
}
