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
