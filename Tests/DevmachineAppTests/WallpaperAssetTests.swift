import XCTest
@testable import DevmachineApp

final class WallpaperAssetTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("checkout-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".build/arm64-apple-macosx/release"),
            withIntermediateDirectories: true
        )
        try Data("// swift-tools-version: 6.0".utf8).write(to: root.appendingPathComponent("Package.swift"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testFindsTheCheckoutFromABuildFolder() {
        let binary = root.appendingPathComponent(".build/arm64-apple-macosx/release")
        XCTAssertEqual(WallpaperAsset.checkoutRoot(from: binary)?.path, root.path)
    }

    func testFindsTheCheckoutFromItsOwnRoot() {
        XCTAssertEqual(WallpaperAsset.checkoutRoot(from: root)?.path, root.path)
    }

    func testAnswersNilOutsideAnyCheckout() {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nowhere-" + UUID().uuidString, isDirectory: true)
        XCTAssertNil(WallpaperAsset.checkoutRoot(from: outside))
    }
}
