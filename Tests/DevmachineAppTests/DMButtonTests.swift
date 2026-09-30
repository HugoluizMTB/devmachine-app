import XCTest
import SwiftUI
@testable import DevmachineApp

final class DMButtonTests: XCTestCase {
    private func look(
        _ variant: DMButtonVariant, enabled: Bool = true, pressed: Bool = false, hovered: Bool = false
    ) -> DMButtonAppearance {
        DMButtonAppearance(variant: variant, isEnabled: enabled, isPressed: pressed, isHovered: hovered)
    }

    func testPrimaryIsFilledWithTheAccent() {
        XCTAssertEqual(look(.primary).fill, .accentColor)
        XCTAssertEqual(look(.primary).foreground, .white)
        XCTAssertNil(look(.primary).stroke)
    }

    func testOutlineIsASolidSecondaryButtonThatReadsAsClickable() {
        XCTAssertEqual(look(.outline).fill, DMButtonPalette.outlineFill)
        XCTAssertEqual(look(.outline).stroke, DMButtonPalette.outlineStroke)
        XCTAssertEqual(look(.outline).foreground, .white)
        XCTAssertEqual(look(.outline, hovered: true).fill, DMButtonPalette.outlineHoverFill)
    }

    func testDangerIsRedFilledAndDangerOutlineIsRedEdged() {
        XCTAssertEqual(look(.danger).fill, DMButtonPalette.danger)
        XCTAssertEqual(look(.dangerOutline).fill, .clear)
        XCTAssertEqual(look(.dangerOutline).stroke, DMButtonPalette.danger.opacity(0.7))
        XCTAssertEqual(look(.dangerOutline).foreground, DMButtonPalette.dangerText)
    }

    func testGhostShowsNothingUntilHovered() {
        XCTAssertEqual(look(.ghost).fill, .clear)
        XCTAssertNil(look(.ghost).stroke)
        XCTAssertEqual(look(.ghost, hovered: true).fill, .dmSelection)
    }

    func testGhostDangerIsQuietUntilHoveredThenRed() {
        XCTAssertEqual(look(.ghostDanger).fill, .clear)
        XCTAssertEqual(look(.ghostDanger).foreground, .dmMuted)
        XCTAssertEqual(look(.ghostDanger, hovered: true).fill, DMButtonPalette.danger.opacity(0.14))
        XCTAssertEqual(look(.ghostDanger, hovered: true).foreground, DMButtonPalette.dangerText)
    }

    func testLinkIsBareAccentText() {
        XCTAssertTrue(look(.link).isBare)
        XCTAssertEqual(look(.link).foreground, .accentColor)
        XCTAssertTrue(look(.link, hovered: true).underline)
        XCTAssertFalse(look(.primary).isBare)
    }

    func testDisabledDimsAndIgnoresHoverAndPress() {
        for variant in DMButtonVariant.allCases {
            let disabled = look(variant, enabled: false, pressed: true, hovered: true)
            XCTAssertEqual(disabled.opacity, 0.4, "\(variant)")
            XCTAssertEqual(disabled.fill, look(variant, enabled: false).fill, "\(variant)")
            XCTAssertFalse(disabled.underline, "\(variant)")
        }
    }

    func testPressedReadsDarkerThanResting() {
        for variant in DMButtonVariant.allCases {
            XCTAssertLessThan(look(variant, pressed: true).opacity, look(variant).opacity, "\(variant)")
        }
    }

    func testSizesGrowFromSmallToLarge() {
        let heights = DMButtonSize.allCases.map(\.metrics.height)
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(Set(heights).count, heights.count)
        let fonts = DMButtonSize.allCases.map(\.metrics.fontSize)
        XCTAssertEqual(fonts, fonts.sorted())
    }

    func testLoadingIsNeverInteractive() {
        XCTAssertTrue(DMButtonStyle.isInteractive(isEnabled: true, isLoading: false))
        XCTAssertFalse(DMButtonStyle.isInteractive(isEnabled: true, isLoading: true))
        XCTAssertFalse(DMButtonStyle.isInteractive(isEnabled: false, isLoading: false))
    }

    func testAnIconOnlyButtonCarriesItsAccessibilityLabel() {
        let button = DMButton(icon: "arrow.clockwise", label: "Refresh") {}
        XCTAssertEqual(button.accessibilityText, "Refresh")
        XCTAssertTrue(button.isIconOnly)
        XCTAssertEqual(button.style.variant, .ghost)
    }

    func testATitledButtonIsReadByItsTitle() {
        let button = DMButton("Save", variant: .primary, isLoading: true) {}
        XCTAssertEqual(button.accessibilityText, "Save")
        XCTAssertFalse(button.isIconOnly)
        XCTAssertTrue(button.style.isLoading)
    }
}
