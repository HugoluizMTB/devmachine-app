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
        try Self.write(Self.svg(fill: "currentColor"), as: "both.svg", in: folder)
        try Self.write(Self.svg(fill: "#D97757"), as: "both-color.svg", in: folder)
        try Self.write(Self.svg(fill: "currentColor"), as: "mono.svg", in: folder)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private nonisolated static func write(_ text: String, as name: String, in folder: URL) throws {
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private nonisolated static func svg(fill: String) -> String {
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="14" height="14">"#
            + #"<path fill="\#(fill)" d="M2 2 H22 V22 H2 Z"/></svg>"#
    }

    private var checkoutIcons: URL {
        HarnessIconLibrary.directory(inCheckout: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    func testColorStylePicksTheColorFile() throws {
        let library = HarnessIconLibrary(directory: folder)
        let icon = try XCTUnwrap(library.icon(for: HarnessID(rawValue: "both"), style: .color))
        XCTAssertFalse(icon.isTemplate)
        XCTAssertGreaterThan(icon.image.size.width, 0)
    }

    func testColorStyleFallsBackToTheMonochromeFile() throws {
        let library = HarnessIconLibrary(directory: folder)
        let icon = try XCTUnwrap(library.icon(for: HarnessID(rawValue: "mono"), style: .color))
        XCTAssertTrue(icon.isTemplate)
        XCTAssertTrue(icon.image.isTemplate)
    }

    func testMonochromeStyleNeverLoadsTheColorFile() throws {
        let library = HarnessIconLibrary(directory: folder)
        XCTAssertTrue(try XCTUnwrap(library.icon(for: HarnessID(rawValue: "both"), style: .monochrome)).isTemplate)
        XCTAssertFalse(try XCTUnwrap(library.icon(for: HarnessID(rawValue: "both"), style: .color)).isTemplate)
    }

    func testAColorFileAloneIsNoIcon() throws {
        try Self.write(Self.svg(fill: "#D97757"), as: "lone-color.svg", in: folder)
        let library = HarnessIconLibrary(directory: folder)
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "lone"), style: .color))
        XCTAssertFalse(library.hasIcon(for: HarnessID(rawValue: "lone")))
    }

    func testAColorVariantCannotBeAskedForAsAHarness() {
        let library = HarnessIconLibrary(directory: folder)
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "both-color"), style: .monochrome))
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "both-color"), style: .color))
    }

    func testAHarnessWithoutAFileHasNoIcon() {
        let library = HarnessIconLibrary(directory: folder)
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "missing"), style: .color))
        XCTAssertFalse(library.hasIcon(for: HarnessID(rawValue: "missing")))
        XCTAssertTrue(library.hasIcon(for: HarnessID(rawValue: "both")))
    }

    func testAnIdThatIsNotAPlainNameIsNeverReadFromDisk() {
        let library = HarnessIconLibrary(directory: folder.appendingPathComponent("sub"))
        try? FileManager.default.createDirectory(
            at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        XCTAssertNil(library.icon(for: HarnessID(rawValue: "../both"), style: .color))
    }

    func testNoFolderMeansNoIcons() {
        XCTAssertNil(HarnessIconLibrary(directory: nil).icon(for: .claude, style: .color))
    }

    func testEveryBuiltInHarnessShipsAMonochromeIconInCurrentColorOnly() throws {
        for id in HarnessRegistry.builtIn.adapters.map(\.id) {
            let file = checkoutIcons.appendingPathComponent("\(id.rawValue).svg")
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(text.contains("currentColor"), id.rawValue)
            XCTAssertNil(text.range(of: #"(fill|stroke)="(#|url|rgb|white|black)"#, options: .regularExpression), id.rawValue)
            let library = HarnessIconLibrary(directory: checkoutIcons)
            XCTAssertTrue(try XCTUnwrap(library.icon(for: id, style: .monochrome)).isTemplate, id.rawValue)
        }
    }

    func testTheCheckoutShipsTheBrandColorsItHas() throws {
        let library = HarnessIconLibrary(directory: checkoutIcons)
        for id in [HarnessID.claude, .codex, .antigravity, .kimi] {
            XCTAssertFalse(try XCTUnwrap(library.icon(for: id, style: .color)).isTemplate, id.rawValue)
        }
        for id in [HarnessID.pi, .opencode, .cline] {
            XCTAssertTrue(try XCTUnwrap(library.icon(for: id, style: .color)).isTemplate, id.rawValue)
        }
        for license in ["LICENSE-orca.txt", "LICENSE-lobe-icons.txt"] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: checkoutIcons.appendingPathComponent(license).path), license)
        }
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
