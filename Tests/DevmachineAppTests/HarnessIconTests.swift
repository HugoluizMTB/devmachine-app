import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class HarnessIconLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-icons-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.svg(fill: "#D97757").write(
            to: folder.appendingPathComponent("brand.svg"), atomically: true, encoding: .utf8)
        try Self.svg(fill: "currentColor").write(
            to: folder.appendingPathComponent("mono.svg"), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private static func svg(fill: String) -> String {
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="14" height="14">"#
            + #"<path fill="\#(fill)" d="M2 2 H22 V22 H2 Z"/></svg>"#
    }

    func testAFileNamedAfterTheHarnessIsItsIcon() throws {
        let library = HarnessIconLibrary(directory: folder)
        let brand = try XCTUnwrap(library.icon(for: HarnessID(rawValue: "brand")))
        XCTAssertFalse(brand.isTemplate)
        XCTAssertGreaterThan(brand.image.size.width, 0)
    }

    func testAnIconDrawnInCurrentColorFollowsTheTint() throws {
        let library = HarnessIconLibrary(directory: folder)
        let mono = try XCTUnwrap(library.icon(for: HarnessID(rawValue: "mono")))
        XCTAssertTrue(mono.isTemplate)
        XCTAssertTrue(mono.image.isTemplate)
    }

    func testAHarnessWithoutAFileHasNoIcon() {
        let library = HarnessIconLibrary(directory: folder)
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "missing")))
        XCTAssertFalse(library.hasIcon(for: HarnessID(rawValue: "missing")))
        XCTAssertTrue(library.hasIcon(for: HarnessID(rawValue: "brand")))
    }

    func testAnIdThatIsNotAPlainNameIsNeverReadFromDisk() {
        let library = HarnessIconLibrary(directory: folder.appendingPathComponent("sub"))
        try? FileManager.default.createDirectory(
            at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "../brand")))
    }

    func testNoFolderMeansNoIcons() {
        XCTAssertNil(HarnessIconLibrary(directory: nil).icon(for: .claude))
    }

    func testTheCheckoutShipsAnIconForEveryKnownHarness() throws {
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let library = HarnessIconLibrary(directory: HarnessIconLibrary.directory(inCheckout: checkout))
        let known = HarnessRegistry.builtIn.adapters.map(\.id) + [.pi]
        for id in known {
            XCTAssertNotNil(library.icon(for: id), id.rawValue)
        }
        XCTAssertFalse(try XCTUnwrap(library.icon(for: .claude)).isTemplate)
        XCTAssertTrue(try XCTUnwrap(library.icon(for: .codex)).isTemplate)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: checkout.appendingPathComponent("Resources/HarnessIcons/LICENSE-orca.txt").path))
    }
}

final class SessionRowGlyphTests: XCTestCase {
    private let facade = SessionHarnessFacade(registry: .builtIn)

    func testOffKeepsTheRowAsItWas() {
        let badges = facade.badges(for: [.claude])
        let glyph = SessionRowGlyph(showsHarnessIcons: false, badges: badges, hasIcon: { _ in true })
        XCTAssertNil(glyph.icon)
        XCTAssertFalse(glyph.reservesLeadingSlot)
        XCTAssertEqual(glyph.hoverBadges.map(\.id), [.claude])
    }

    func testOnShowsTheIconOfAKnownHarnessInsteadOfItsDot() {
        let badges = facade.badges(for: [.claude])
        let glyph = SessionRowGlyph(showsHarnessIcons: true, badges: badges, hasIcon: { _ in true })
        XCTAssertEqual(glyph.icon, .claude)
        XCTAssertTrue(glyph.reservesLeadingSlot)
        XCTAssertTrue(glyph.hoverBadges.isEmpty)
    }

    func testOnPicksTheFirstHarnessInRegistryOrderAndKeepsTheOthersDots() {
        let badges = facade.badges(for: [.codex, .claude])
        let glyph = SessionRowGlyph(showsHarnessIcons: true, badges: badges, hasIcon: { _ in true })
        XCTAssertEqual(glyph.icon, .claude)
        XCTAssertEqual(glyph.hoverBadges.map(\.id), [.codex])
    }

    func testAHarnessWithoutAnIconKeepsItsDot() {
        let badges = facade.badges(for: [.codex])
        let glyph = SessionRowGlyph(showsHarnessIcons: true, badges: badges, hasIcon: { $0 != .codex })
        XCTAssertNil(glyph.icon)
        XCTAssertTrue(glyph.reservesLeadingSlot)
        XCTAssertEqual(glyph.hoverBadges.map(\.id), [.codex])
    }

    func testATerminalSessionKeepsItsPlaceSoNamesStayAligned() {
        let glyph = SessionRowGlyph(showsHarnessIcons: true, badges: [], hasIcon: { _ in true })
        XCTAssertNil(glyph.icon)
        XCTAssertTrue(glyph.reservesLeadingSlot)
        XCTAssertTrue(glyph.hoverBadges.isEmpty)
    }
}
