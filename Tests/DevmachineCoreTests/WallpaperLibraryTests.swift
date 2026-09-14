import XCTest
@testable import DevmachineCore

private let fixture = Data("""
{
  "themes": [
    {
      "id": "ocean",
      "title": "Ocean",
      "photos": [
        { "id": "aaa111", "user": "alice", "name": "Alice Stone", "cdn": "photo-1", "bundled": true },
        { "id": "bbb222", "user": "bob", "name": "Bob Reed", "cdn": "photo-2" }
      ]
    },
    {
      "id": "space",
      "title": "Space",
      "photos": [
        { "id": "ccc333", "user": "carol", "name": "Carol Vine", "cdn": "photo-3" }
      ]
    }
  ]
}
""".utf8)

private func sample() throws -> WallpaperLibrary {
    try WallpaperLibrary.load(from: fixture)
}

/// The file the app ships, read from the repo so the test covers the real data.
private func shipped() throws -> WallpaperLibrary {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/wallpapers.json"))
    return try WallpaperLibrary.load(from: data)
}

final class WallpaperLibraryTests: XCTestCase {
    func testLoadReadsThemesInOrder() throws {
        let library = try sample()
        XCTAssertEqual(library.themes.map(\.id), ["ocean", "space"])
        XCTAssertEqual(library.themes.map(\.title), ["Ocean", "Space"])
        XCTAssertEqual(library.themes.first?.photos.count, 2)
    }

    func testPhotosFlattensEveryTheme() throws {
        XCTAssertEqual(try sample().photos.map(\.id), ["aaa111", "bbb222", "ccc333"])
    }

    func testMissingBundledFlagMeansFalse() throws {
        let library = try sample()
        XCTAssertEqual(library.photo(id: "aaa111")?.bundled, true)
        XCTAssertEqual(library.photo(id: "bbb222")?.bundled, false)
    }

    func testBundledPhotoIsTheFlaggedOne() throws {
        XCTAssertEqual(try sample().bundledPhoto?.id, "aaa111")
    }

    func testPhotoLookupAnswersNilForAnUnknownID() throws {
        XCTAssertNil(try sample().photo(id: "nope"))
    }

    func testThemeLookupByID() throws {
        XCTAssertEqual(try sample().theme(id: "space")?.photos.count, 1)
        XCTAssertNil(try sample().theme(id: "forest"))
    }

    func testThemeOfPhotoFindsTheOwningTheme() throws {
        XCTAssertEqual(try sample().theme(ofPhoto: "ccc333")?.id, "space")
        XCTAssertNil(try sample().theme(ofPhoto: "nope"))
    }

    func testImageURLAsksTheCDNForTheFullWidth() throws {
        let library = try sample()
        let photo = try XCTUnwrap(library.photo(id: "bbb222"))
        XCTAssertEqual(
            library.imageURL(photo)?.absoluteString,
            "https://images.unsplash.com/photo-2?w=1920&q=80&fm=jpg&fit=max"
        )
    }

    func testImageURLTakesACustomWidth() throws {
        let library = try sample()
        let photo = try XCTUnwrap(library.photo(id: "bbb222"))
        XCTAssertEqual(
            library.imageURL(photo, width: 640)?.absoluteString,
            "https://images.unsplash.com/photo-2?w=640&q=80&fm=jpg&fit=max"
        )
    }

    func testThumbnailURLIsSmallerAndCheaper() throws {
        let library = try sample()
        let photo = try XCTUnwrap(library.photo(id: "bbb222"))
        XCTAssertEqual(
            library.thumbnailURL(photo)?.absoluteString,
            "https://images.unsplash.com/photo-2?w=320&q=60&fm=jpg&fit=max"
        )
    }

    func testPageAndProfileURLsPointAtUnsplash() throws {
        let library = try sample()
        let photo = try XCTUnwrap(library.photo(id: "ccc333"))
        XCTAssertEqual(library.pageURL(photo)?.absoluteString, "https://unsplash.com/photos/ccc333")
        XCTAssertEqual(library.profileURL(photo)?.absoluteString, "https://unsplash.com/@carol")
    }

    func testCreditNamesThePhotographer() throws {
        let photo = try XCTUnwrap(try sample().photo(id: "ccc333"))
        XCTAssertEqual(photo.credit, "Photo by Carol Vine on Unsplash")
    }

    func testLoadRejectsBrokenJSON() {
        XCTAssertThrowsError(try WallpaperLibrary.load(from: Data("{}".utf8)))
    }

    func testEmptyLibraryHasNoPhotos() {
        XCTAssertTrue(WallpaperLibrary.empty.photos.isEmpty)
        XCTAssertNil(WallpaperLibrary.empty.bundledPhoto)
    }

    func testShippedLibraryHasSixThemesAndUniquePhotos() throws {
        let library = try shipped()
        XCTAssertEqual(
            library.themes.map(\.id),
            ["surfing", "city", "mountains", "ocean", "space", "abstract"]
        )
        XCTAssertEqual(library.photos.count, 31)
        XCTAssertEqual(Set(library.photos.map(\.id)).count, 31)
        XCTAssertTrue(library.photos.allSatisfy { !$0.cdn.isEmpty && !$0.user.isEmpty && !$0.name.isEmpty })
    }

    func testShippedLibraryMarksExactlyOnePhotoAsBundled() throws {
        XCTAssertEqual(try shipped().photos.filter(\.bundled).count, 1)
    }
}

final class WallpaperChoiceTests: XCTestCase {
    private func roundTrip(_ choice: WallpaperChoice) throws -> WallpaperChoice {
        let data = try JSONEncoder().encode(choice)
        return try JSONDecoder().decode(WallpaperChoice.self, from: data)
    }

    func testEveryCaseSurvivesARoundTrip() throws {
        for choice: WallpaperChoice in [.bundled, .unsplash(id: "aaa111"), .gradient(name: "midnight")] {
            XCTAssertEqual(try roundTrip(choice), choice)
        }
    }

    func testEncodingKeepsAStableShape() throws {
        let data = try JSONEncoder().encode(WallpaperChoice.unsplash(id: "aaa111"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["kind": "unsplash", "id": "aaa111"])
    }

    func testDecodesTheDocumentedShape() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(WallpaperChoice.self, from: Data(#"{"kind":"bundled"}"#.utf8)),
            .bundled
        )
        XCTAssertEqual(
            try decoder.decode(WallpaperChoice.self, from: Data(#"{"kind":"gradient","name":"ember"}"#.utf8)),
            .gradient(name: "ember")
        )
    }

    func testUnknownKindFallsBackToBundled() throws {
        let data = Data(#"{"kind":"video","url":"x"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WallpaperChoice.self, from: data), .bundled)
    }
}
