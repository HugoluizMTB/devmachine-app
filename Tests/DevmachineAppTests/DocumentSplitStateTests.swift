import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DocumentSplitStateTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!
    }

    func testANewWindowSplitsInHalf() {
        XCTAssertEqual(DocumentSplitState(defaults: defaults).fraction, 0.5)
    }

    func testTheSavedSplitComesBack() {
        defaults.set(0.72, forKey: DocumentSplitState.key)
        XCTAssertEqual(DocumentSplitState(defaults: defaults).fraction, 0.72)
    }

    func testABrokenSavedSplitIsIgnored() {
        defaults.set(3.0, forKey: DocumentSplitState.key)
        XCTAssertEqual(DocumentSplitState(defaults: defaults).fraction, 0.5)
    }

    func testEndingADragSavesTheSplit() {
        let split = DocumentSplitState(defaults: defaults)

        split.commit(0.8)

        XCTAssertEqual(split.fraction, 0.8)
        XCTAssertEqual(defaults.double(forKey: DocumentSplitState.key), 0.8)
    }

    func testNothingIsSavedUntilADragEnds() {
        let split = DocumentSplitState(defaults: defaults)
        var live = split.fraction
        for step in 1...50 {
            live = DocumentSplit.dragged(from: split.fraction, by: -Double(step), available: 1600)
        }

        XCTAssertNil(defaults.object(forKey: DocumentSplitState.key))
        split.commit(live)
        XCTAssertEqual(defaults.double(forKey: DocumentSplitState.key), live)
    }

    func testCommittingTheSameSplitWritesNothing() {
        let split = DocumentSplitState(defaults: defaults)

        split.commit(0.5)

        XCTAssertNil(defaults.object(forKey: DocumentSplitState.key))
    }

    func testResetGoesBackToHalfAndHalf() {
        let split = DocumentSplitState(defaults: defaults)
        split.commit(0.8)

        split.reset()

        XCTAssertEqual(split.fraction, 0.5)
        XCTAssertEqual(defaults.double(forKey: DocumentSplitState.key), 0.5)
    }

    func testMaximizeTogglesAndIsNotSaved() {
        let split = DocumentSplitState(defaults: defaults)

        split.toggleMaximized()
        XCTAssertTrue(split.isMaximized)
        XCTAssertNil(defaults.object(forKey: DocumentSplitState.key))

        split.toggleMaximized()
        XCTAssertFalse(split.isMaximized)
    }

    func testClosingThePaneRestoresTheTerminal() {
        let split = DocumentSplitState(defaults: defaults)
        split.toggleMaximized()

        split.paneClosed()

        XCTAssertFalse(split.isMaximized)
    }

    func testTheMaximizeShortcutActsOnAFocusedPreview() {
        let split = DocumentSplitState(defaults: defaults)

        XCTAssertFalse(split.handleMaximizeShortcut(previewFocused: false, paneVisible: true))
        XCTAssertFalse(split.isMaximized)
        XCTAssertFalse(split.handleMaximizeShortcut(previewFocused: true, paneVisible: false))
        XCTAssertTrue(split.handleMaximizeShortcut(previewFocused: true, paneVisible: true))
        XCTAssertTrue(split.isMaximized)
    }

    func testTheMaximizeShortcutRestoresAMaximizedPaneWhateverHasFocus() {
        let split = DocumentSplitState(defaults: defaults)
        split.toggleMaximized()

        XCTAssertTrue(split.handleMaximizeShortcut(previewFocused: false, paneVisible: true))
        XCTAssertFalse(split.isMaximized)
    }
}

final class PreviewUserAgentTests: XCTestCase {
    func testTheInAppBrowserSaysItIsSafari() throws {
        let agent = PreviewUserAgent.current
        XCTAssertTrue(agent.hasPrefix("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"))
        XCTAssertTrue(agent.hasSuffix(" Safari/605.1.15"))
        let version = try XCTUnwrap(agent.range(of: #"Version/\d+(\.\d+)*"#, options: .regularExpression))
        XCTAssertFalse(agent[version].isEmpty)
    }
}
