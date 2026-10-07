import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

private final class SilentRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
final class MenuBarLabelTests: XCTestCase {
    func testLabelGrowsWhenThereAreOpenPRs() throws {
        let store = PRStore(client: GHClient(runner: SilentRunner()))

        store.openCount = 0
        let bare = try XCTUnwrap(ImageRenderer(content: MenuBarLabel(prStore: store)).nsImage)

        store.openCount = 7
        let counted = try XCTUnwrap(ImageRenderer(content: MenuBarLabel(prStore: store)).nsImage)

        XCTAssertGreaterThan(counted.size.width, bare.size.width)
    }
}

private struct TodaysMenuBarLabel: View {
    let openCount: Int

    var body: some View {
        let mark = Text(verbatim: "❯_").font(.dm(13, weight: .bold, design: .monospaced))
        if openCount > 0 {
            HStack(spacing: 3) {
                mark
                Text(verbatim: "\(openCount)")
            }
        } else {
            mark
        }
    }
}

@MainActor
final class MenuBarLabelDefaultTests: XCTestCase {
    private func bitmap<V: View>(_ view: V) throws -> (width: Int, height: Int, data: Data) {
        let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        return (image.width, image.height, data)
    }

    func testTheDefaultBoardDrawsExactlyTodaysLabel() throws {
        let store = PRStore(client: GHClient(runner: SilentRunner()))
        for count in [0, 7, 42] {
            store.openCount = count
            let drawn = try bitmap(MenuBarLabel(prStore: store))
            let today = try bitmap(TodaysMenuBarLabel(openCount: count))
            XCTAssertEqual(drawn.width, today.width, "\(count)")
            XCTAssertEqual(drawn.height, today.height, "\(count)")
            XCTAssertEqual(drawn.data, today.data, "\(count)")
        }
    }

    func testEverySlotItemDrawsSomething() throws {
        let mark = try bitmap(MenuBarLabel(items: [.brand]))
        for items: [MenubarSlotItem] in [[.text("0.42")], [.status(.warn, "slow")], [.waiting], [.brand, .status(.ok, "up"), .text("3")]] {
            let drawn = try bitmap(MenuBarLabel(items: items))
            XCTAssertGreaterThan(drawn.width, 0, "\(items)")
            XCTAssertGreaterThan(drawn.height, 0, "\(items)")
        }
        XCTAssertGreaterThan(try bitmap(MenuBarLabel(items: [.brand, .text("3")])).width, mark.width)
    }
}
