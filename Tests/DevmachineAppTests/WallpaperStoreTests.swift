import AppKit
import XCTest
import DevmachineCore
@testable import DevmachineApp

private let photo = WallpaperPhoto(id: "aaa111", user: "alice", name: "Alice Stone", cdn: "photo-1")
private let other = WallpaperPhoto(id: "bbb222", user: "bob", name: "Bob Reed", cdn: "photo-2")

private let library = WallpaperLibrary(themes: [
    WallpaperTheme(id: "ocean", title: "Ocean", photos: [photo, other])
])

private final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var body = Data()
    private var calls = 0

    func set(status: Int, body: Data) {
        lock.lock()
        self.status = status
        self.body = body
        calls = 0
        lock.unlock()
    }

    func take() -> (status: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return (status, body)
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private final class StubURLProtocol: URLProtocol {
    fileprivate static let state = StubState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let reply = Self.state.take()
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class WallpaperStoreTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!
    private var jpeg: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wallpaper-tests-" + UUID().uuidString, isDirectory: true)
        jpeg = try Self.jpeg()
        StubURLProtocol.state.set(status: 200, body: jpeg)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private static func jpeg() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
    }

    private func makeStore(settings: SettingsStore? = nil) -> WallpaperStore {
        WallpaperStore(library: library, settings: settings, directory: directory, session: session)
    }

    private func wait(for condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the store published nothing")
    }

    func testStartsOnTheBundledChoiceWithNothingLoaded() {
        let store = makeStore()
        XCTAssertEqual(store.choice, .bundled)
        XCTAssertTrue(store.images.isEmpty)
        XCTAssertTrue(store.thumbnails.isEmpty)
        XCTAssertNil(store.selectedPhoto)
    }

    func testCacheURLNamesTheFileAfterThePhoto() {
        let store = makeStore()
        XCTAssertEqual(store.cacheURL(photo).lastPathComponent, "aaa111.jpg")
        XCTAssertEqual(store.cacheURL(photo, thumbnail: true).lastPathComponent, "aaa111-thumb640.jpg", "a cell now draws 150 points tall, so the old 320 px file is not reused")
    }

    func testDefaultDirectoryLivesUnderApplicationSupport() {
        XCTAssertTrue(WallpaperStore.defaultDirectory.path.hasSuffix("/Devmachine/wallpapers"))
    }

    func testEnsurePublishesThePhotoAndWritesTheCacheFile() async throws {
        let store = makeStore()
        store.ensure(photo)
        try await wait { store.images["aaa111"] != nil }

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.cacheURL(photo).path))
        XCTAssertEqual(StubURLProtocol.state.callCount, 1)
    }

    func testEnsureThumbnailKeepsItsOwnFileAndDictionary() async throws {
        let store = makeStore()
        store.ensureThumbnail(photo)
        try await wait { store.thumbnails["aaa111"] != nil }

        XCTAssertNil(store.images["aaa111"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.cacheURL(photo, thumbnail: true).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cacheURL(photo).path))
    }

    func testAPhotoAlreadyOnDiskSkipsTheDownload() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = makeStore()
        try jpeg.write(to: store.cacheURL(photo))

        store.ensure(photo)
        try await wait { store.images["aaa111"] != nil }
        XCTAssertEqual(StubURLProtocol.state.callCount, 0)
    }

    func testTwoCallsShareOneDownload() async throws {
        let store = makeStore()
        store.ensure(photo)
        store.ensure(photo)
        store.ensure(photo)
        try await wait { store.images["aaa111"] != nil }

        store.ensure(photo)
        XCTAssertEqual(StubURLProtocol.state.callCount, 1)
    }

    func testEachPhotoIsFetchedOnItsOwn() async throws {
        let store = makeStore()
        store.ensure(photo)
        store.ensure(other)
        try await wait { store.images.count == 2 }
        XCTAssertEqual(StubURLProtocol.state.callCount, 2)
    }

    func testAFailedDownloadLeavesNoImageAndDoesNotRepeatItself() async throws {
        StubURLProtocol.state.set(status: 404, body: Data())
        let store = makeStore()

        store.ensure(photo)
        try await wait { StubURLProtocol.state.callCount == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(store.images["aaa111"])

        store.ensure(photo)
        store.ensure(photo)
        XCTAssertEqual(StubURLProtocol.state.callCount, 1)
    }

    func testAForcedCallRetriesAfterAFailure() async throws {
        StubURLProtocol.state.set(status: 500, body: Data())
        let store = makeStore()
        store.ensure(photo)
        try await wait { StubURLProtocol.state.callCount == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)

        store.ensure(photo, force: true)
        try await wait { StubURLProtocol.state.callCount == 2 }
    }

    func testTheSavedChoiceDrivesTheStoreAndDownloadsThePhoto() async throws {
        let suite = "dev.devmachine.app.wallpaper.tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        let store = makeStore(settings: settings)
        XCTAssertEqual(store.choice, .bundled)

        settings.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "myhost",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            wallpaper: .unsplash(id: "aaa111")
        )

        XCTAssertEqual(store.choice, .unsplash(id: "aaa111"))
        XCTAssertEqual(store.selectedPhoto, photo)
        try await wait { store.images["aaa111"] != nil }
    }

    func testAGradientChoiceDownloadsNothing() async throws {
        let suite = "dev.devmachine.app.wallpaper.gradient.tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        let store = makeStore(settings: settings)
        settings.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "myhost",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            wallpaper: .gradient(name: "ember")
        )

        XCTAssertEqual(store.choice, .gradient(name: "ember"))
        XCTAssertNil(store.selectedPhoto)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(StubURLProtocol.state.callCount, 0)
    }

    func testTheNetworkMapChoiceDownloadsNothing() async throws {
        let suite = "dev.devmachine.app.wallpaper.map.tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        let store = makeStore(settings: settings)
        settings.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "myhost",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            wallpaper: .networkMap(.compact)
        )

        XCTAssertEqual(store.choice, .networkMap(.compact))
        XCTAssertNil(store.selectedPhoto)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(StubURLProtocol.state.callCount, 0)
    }

    func testAnUnknownPhotoIDNeverBecomesADownload() async throws {
        let suite = "dev.devmachine.app.wallpaper.unknown.tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        let store = makeStore(settings: settings)
        settings.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "myhost",
            publicIP: "203.0.113.10",
            baseDomain: "example.com",
            wallpaper: .unsplash(id: "zzz999")
        )

        XCTAssertNil(store.selectedPhoto)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(StubURLProtocol.state.callCount, 0)
    }
}

final class WallpaperGradientTests: XCTestCase {
    func testGradientsWithStableNames() {
        XCTAssertEqual(WallpaperGradient.all.map(\.name), ["midnight", "ember", "forest", "graphite", "peaks"])
    }

    func testOnlyPeaksIsALandscape() {
        XCTAssertEqual(WallpaperGradient.all.filter { $0.isLandscape }.map(\.name), ["peaks"])
    }

    @MainActor
    func testPeaksDrawsDarkRidgesUnderALighterSky() throws {
        let image = try XCTUnwrap(WallpaperGradient.named("peaks").bitmap(width: 320, height: 200))
        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: image.tiffRepresentation!))
        let sky = try XCTUnwrap(rep.colorAt(x: 160, y: rep.pixelsHigh / 4)).brightnessComponent
        let ground = try XCTUnwrap(rep.colorAt(x: 160, y: rep.pixelsHigh - 2)).brightnessComponent
        XCTAssertGreaterThan(sky, ground)
        let row = rep.pixelsHigh * 11 / 20
        let across = Set((0..<16).map { i in
            Int(((rep.colorAt(x: i * rep.pixelsWide / 16, y: row)?.brightnessComponent ?? 0) * 50).rounded())
        })
        XCTAssertGreaterThan(across.count, 1, "a ridge line, not a flat vertical gradient")
    }

    func testLookupByName() {
        XCTAssertEqual(WallpaperGradient.named("forest").title, "Forest")
    }

    func testAnUnknownNameFallsBackToTheFirstGradient() {
        XCTAssertEqual(WallpaperGradient.named("beige").name, "midnight")
    }

    @MainActor
    func testBitmapDrawsAtTheAskedSize() throws {
        let image = try XCTUnwrap(WallpaperGradient.named("ember").bitmap(width: 64, height: 40))
        XCTAssertEqual(image.size, NSSize(width: 64, height: 40))
    }
}

@MainActor
final class WallpaperBakerTests: XCTestCase {
    private var calls = 0

    private func source() -> NSImage? {
        calls += 1
        return WallpaperGradient.named("ember").bitmap(width: 16, height: 16)
    }

    private func bake(_ key: String, style: WallpaperStyle = .ambient) -> NSImage? {
        WallpaperBaker.image(key: key, style: style) { source() }
    }

    func testASecondAskReusesTheBake() {
        let key = UUID().uuidString
        XCTAssertNotNil(bake(key))
        XCTAssertNotNil(bake(key))
        XCTAssertEqual(calls, 1)
    }

    func testEveryStyleGetsItsOwnBake() {
        let key = UUID().uuidString
        XCTAssertNotNil(bake(key, style: .photo))
        XCTAssertNotNil(bake(key, style: .ambient))
        XCTAssertEqual(calls, 2)
    }

    func testTheOldestBakeGoesWhenTheCacheIsFull() {
        let keys = (0...WallpaperBaker.cap).map { _ in UUID().uuidString }
        for key in keys {
            XCTAssertNotNil(bake(key))
        }
        XCTAssertEqual(calls, keys.count)

        XCTAssertNotNil(bake(keys[0]))
        XCTAssertEqual(calls, keys.count + 1)
        XCTAssertNotNil(bake(keys[keys.count - 1]))
        XCTAssertEqual(calls, keys.count + 1)
    }

    func testASourceThatGivesNothingBakesNothing() {
        XCTAssertNil(WallpaperBaker.image(key: UUID().uuidString, style: .photo) { nil })
    }
}

final class WallpaperStyleTests: XCTestCase {
    func testPhotoBakesBigAndSharp() {
        XCTAssertEqual(WallpaperStyle.photo.bakeWidth, 1920)
        XCTAssertEqual(WallpaperStyle.photo.bakeBlur, 2)
    }

    func testAmbientBakesSmallAndSoft() {
        XCTAssertEqual(WallpaperStyle.ambient.bakeWidth, 512)
        XCTAssertEqual(WallpaperStyle.ambient.bakeBlur, 25)
    }

    func testEveryStyleHasItsOwnCacheKey() {
        XCTAssertNotEqual(WallpaperStyle.photo.bakeKey, WallpaperStyle.ambient.bakeKey)
    }
}

final class WallpaperDimmingTests: XCTestCase {
    func testAPhotoIsDimmedTopAndBottomForHomesText() {
        XCTAssertEqual(WallpaperBackground.dimming(style: .photo, choice: .bundled), [0.25, 0.55])
        XCTAssertEqual(WallpaperBackground.dimming(style: .photo, choice: .gradient(name: "peaks")), [0.25, 0.55])
    }

    func testTheMapIsAlreadyQuietSoOnlyItsBottomIsDarkened() {
        for size in NetworkMapSize.allCases {
            let map = WallpaperBackground.dimming(style: .photo, choice: .networkMap(size))
            XCTAssertLessThan(map[0], 0.25)
            XCTAssertGreaterThan(map[1], map[0])
        }
    }

    func testTheTerminalsBackdropDimsEveryChoiceTheSame() {
        for choice: WallpaperChoice in [.bundled, .gradient(name: "ember"), .networkMap(.compact), .networkMap(.large)] {
            XCTAssertEqual(WallpaperBackground.dimming(style: .ambient, choice: choice), [0.5, 0.8])
        }
    }
}
