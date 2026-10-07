import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class MenubarRenderTests: XCTestCase {
    private func bitmap<V: View>(_ view: V) throws -> (width: Int, height: Int, data: Data) {
        let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        return (image.width, image.height, data)
    }

    private func number(hideZero: Bool, _ text: String) -> some View {
        var view = WidgetView(kind: "number")
        view.hideZero = hideZero
        return NumberWidgetView(view: view, output: .text(text), density: .full)
            .frame(width: 120, height: 60)
            .background(Color.black)
    }

    func testANumberThatHidesZeroDrawsNothingAtZeroOnly() throws {
        let empty = try bitmap(Color.clear.frame(width: 120, height: 60).background(Color.black))
        XCTAssertEqual(try bitmap(number(hideZero: true, "0")).data, empty.data)
        XCTAssertNotEqual(try bitmap(number(hideZero: false, "0")).data, empty.data)
        XCTAssertNotEqual(try bitmap(number(hideZero: true, "7")).data, empty.data)
    }

    func testATabTitleIsDrawnAsWritten() throws {
        func strip(_ title: String) -> some View {
            DMTabStrip(tabs: [title], selection: .constant(title), title: { $0 }).fixedSize()
        }
        XCTAssertGreaterThan(try bitmap(strip("*Deploy*")).width, try bitmap(strip("Deploy")).width)
    }
}
