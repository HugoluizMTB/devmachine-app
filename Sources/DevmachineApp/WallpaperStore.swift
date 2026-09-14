import AppKit
import Combine
import Foundation
import DevmachineCore

@MainActor
final class WallpaperStore: ObservableObject {
    @Published private(set) var choice: WallpaperChoice = .bundled
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    let library: WallpaperLibrary

    private let directory: URL
    private let session: URLSession
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var settingsObserver: AnyCancellable?

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/wallpapers", isDirectory: true)
    }

    init(
        library: WallpaperLibrary = WallpaperStore.shippedLibrary(),
        settings: SettingsStore? = .shared,
        directory: URL = WallpaperStore.defaultDirectory,
        session: URLSession = .shared
    ) {
        self.library = library
        self.directory = directory
        self.session = session

        guard let settings else { return }
        apply(settings.settings?.wallpaper ?? .bundled)
        settingsObserver = settings.$settings.sink { [weak self] value in
            self?.apply(value?.wallpaper ?? .bundled)
        }
    }

    static func shippedLibrary() -> WallpaperLibrary {
        guard let data = WallpaperAsset.libraryData(),
              let library = try? WallpaperLibrary.load(from: data)
        else { return .empty }
        return library
    }

    var themes: [WallpaperTheme] { library.themes }

    var selectedPhoto: WallpaperPhoto? { photo(of: choice) }

    func photo(of choice: WallpaperChoice) -> WallpaperPhoto? {
        guard case .unsplash(let id) = choice else { return nil }
        return library.photo(id: id)
    }

    /// `force` is the one retry: a click on the same photo asks again after a
    /// failure, so a dead network never turns into a download loop.
    func ensure(_ photo: WallpaperPhoto, force: Bool = false) {
        download(photo, thumbnail: false, force: force)
    }

    func ensureThumbnail(_ photo: WallpaperPhoto, force: Bool = false) {
        download(photo, thumbnail: true, force: force)
    }

    func cacheURL(_ photo: WallpaperPhoto, thumbnail: Bool = false) -> URL {
        directory.appendingPathComponent(fileName(photo, thumbnail: thumbnail))
    }

    private func fileName(_ photo: WallpaperPhoto, thumbnail: Bool) -> String {
        (thumbnail ? photo.id + "-thumb" : photo.id) + ".jpg"
    }

    private func apply(_ value: WallpaperChoice) {
        guard choice != value else { return }
        choice = value
        if let photo = photo(of: value) {
            ensure(photo, force: true)
        }
    }

    private func download(_ photo: WallpaperPhoto, thumbnail: Bool, force: Bool) {
        let key = fileName(photo, thumbnail: thumbnail)
        if (thumbnail ? thumbnails[photo.id] : images[photo.id]) != nil { return }
        if inFlight.contains(key) { return }
        if failed.contains(key), !force { return }
        guard let url = thumbnail ? library.thumbnailURL(photo) : library.imageURL(photo) else { return }

        inFlight.insert(key)
        failed.remove(key)
        let file = directory.appendingPathComponent(key)
        let session = self.session
        Task { [weak self] in
            let data = await Self.fetch(url: url, file: file, session: session)
            self?.publish(key: key, id: photo.id, thumbnail: thumbnail, data: data)
        }
    }

    private func publish(key: String, id: String, thumbnail: Bool, data: Data?) {
        inFlight.remove(key)
        guard let data, let image = NSImage(data: data) else {
            failed.insert(key)
            return
        }
        if thumbnail {
            thumbnails[id] = image
        } else {
            images[id] = image
        }
    }

    /// `nonisolated` on purpose: disk read, download and disk write all run off
    /// the main actor, and only the bytes come back to it.
    private nonisolated static func fetch(url: URL, file: URL, session: URLSession) async -> Data? {
        if let cached = try? Data(contentsOf: file), !cached.isEmpty { return cached }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty
        else { return nil }

        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file)
        return data
    }
}
