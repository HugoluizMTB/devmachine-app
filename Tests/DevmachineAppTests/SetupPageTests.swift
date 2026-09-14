import XCTest
import DevmachineCore
@testable import DevmachineApp

private let shipped = WallpaperPhoto(
    id: "aaa111", user: "alice", name: "Alice Stone", cdn: "photo-1", bundled: true
)
private let remote = WallpaperPhoto(id: "ccc333", user: "carol", name: "Carol Vine", cdn: "photo-3")

private let library = WallpaperLibrary(themes: [
    WallpaperTheme(id: "ocean", title: "Ocean", photos: [shipped]),
    WallpaperTheme(id: "space", title: "Space", photos: [remote])
])

final class SetupPageWallpaperTests: XCTestCase {
    func testTheShippedPhotoSelectsTheBundledChoice() {
        XCTAssertEqual(SetupPage.choice(for: shipped), .bundled)
    }

    func testAnyOtherPhotoSelectsItsUnsplashID() {
        XCTAssertEqual(SetupPage.choice(for: remote), .unsplash(id: "ccc333"))
    }

    func testAGradientChoiceOpensTheGradientChip() {
        XCTAssertEqual(
            SetupPage.openThemeID(for: .gradient(name: "ember"), in: library),
            SetupPage.gradientTheme
        )
    }

    func testTheBundledChoiceOpensTheThemeOfTheShippedPhoto() {
        XCTAssertEqual(SetupPage.openThemeID(for: .bundled, in: library), "ocean")
    }

    func testAPhotoChoiceOpensItsOwnTheme() {
        XCTAssertEqual(SetupPage.openThemeID(for: .unsplash(id: "ccc333"), in: library), "space")
    }

    func testAnUnknownPhotoOpensTheFirstTheme() {
        XCTAssertEqual(SetupPage.openThemeID(for: .unsplash(id: "zzz999"), in: library), "ocean")
    }

    func testWithoutAnyThemeTheGradientChipOpens() {
        XCTAssertEqual(
            SetupPage.openThemeID(for: .bundled, in: .empty),
            SetupPage.gradientTheme
        )
    }

    @MainActor
    func testTheGradientChipIDIsNotAThemeOfTheShippedLibrary() {
        let library = WallpaperStore.shippedLibrary()
        XCTAssertFalse(library.themes.map(\.id).contains(SetupPage.gradientTheme))
    }
}
