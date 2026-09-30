import XCTest
import SwiftUI
import AppKit
import DevmachineCore
@testable import DevmachineApp

final class PRStateStyleTests: XCTestCase {
    func testEachStateHasTheGitHubGlyph() {
        XCTAssertEqual(PRStateKind.open.symbol, "arrow.triangle.pull")
        XCTAssertEqual(PRStateKind.draft.symbol, "arrow.triangle.pull")
        XCTAssertEqual(PRStateKind.merged.symbol, "arrow.triangle.merge")
        XCTAssertEqual(PRStateKind.closed.symbol, "xmark.octagon")
    }

    func testEverySymbolExistsOnThisSystem() {
        for state in PRStateKind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil), state.symbol)
        }
    }

    func testEachStateHasTheGitHubColour() {
        XCTAssertEqual(PRStateKind.open.colorHex, 0x3FB950)
        XCTAssertEqual(PRStateKind.draft.colorHex, 0x8B949E)
        XCTAssertEqual(PRStateKind.merged.colorHex, 0xA371F7)
        XCTAssertEqual(PRStateKind.closed.colorHex, 0xF85149)
    }

    func testNoTwoStatesLookTheSame() {
        let looks = PRStateKind.allCases.map { "\($0.symbol)|\($0.colorHex)" }
        XCTAssertEqual(Set(looks).count, PRStateKind.allCases.count)
    }
}

@MainActor
final class DMKindLabelTests: XCTestCase {
    func testTheTextReadsAtFourAndAHalfToOneOnBothPanels() {
        for panel in [Color.dmSidebarBgHex, Color.dmContentBgHex] {
            let fill = Contrast.white(opacity: DMKindLabel.fillOpacity, over: panel)
            XCTAssertGreaterThanOrEqual(Contrast.ratio(DMKindLabel.textHex, fill), 4.5)
            XCTAssertLessThan(Contrast.ratio(DMKindLabel.textHex, fill), 5.5)
        }
    }

    func testEveryKindIsDrawnTheSame() throws {
        let fills = try ["ISSUE", "DOC", "PR", "LINEAR"].map { try fillPixel(DMKindLabel(text: $0)) }
        XCTAssertEqual(Set(fills).count, 1)
    }

    private func fillPixel(_ label: DMKindLabel) throws -> String {
        let renderer = ImageRenderer(content: label.background(Color.dmSidebarBg))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let color = try XCTUnwrap(bitmap.colorAt(x: 4, y: bitmap.pixelsHigh / 2))
        return String(format: "%.3f %.3f %.3f", color.redComponent, color.greenComponent, color.blueComponent)
    }
}
