import XCTest
import DevmachineCore
@testable import DevmachineApp

final class WidgetGalleryNewWidgetsTests: XCTestCase {
    func testHomeOffersEveryTemplateAsItsOwnRow() {
        let offer = WidgetGalleryNewWidgets.home(canEdit: true, sharedReason: nil)
        XCTAssertEqual(offer?.templates, [.command, .urlStatus, .webPage, .prompt, .session])
        XCTAssertEqual(offer?.enabled, true)
    }

    func testHomeStillShowsTheTemplatesWhileTheBoardCannotChange() {
        let offer = WidgetGalleryNewWidgets.home(canEdit: false, sharedReason: nil)
        XCTAssertEqual(offer?.templates.count, 5)
        XCTAssertEqual(offer?.enabled, false)
    }

    func testASharedReasonDisablesTheTemplates() {
        let offer = WidgetGalleryNewWidgets.of(templates: [.command], canMake: true, sharedReason: "home.yml is broken")
        XCTAssertEqual(offer?.enabled, false)
    }

    func testTheMenuBarOffersOnlyOneLineTemplates() {
        let offer = WidgetGalleryNewWidgets.of(
            templates: InlineWidgetTemplate.offered(on: "slot"), canMake: true, sharedReason: nil)
        XCTAssertEqual(offer?.templates, [.command, .urlStatus])
    }

    func testNoTemplatesMeansNoNewWidgetSection() {
        XCTAssertNil(WidgetGalleryNewWidgets.of(templates: [], canMake: true, sharedReason: nil))
    }
}
