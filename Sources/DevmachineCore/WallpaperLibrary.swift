import Foundation

public struct WallpaperPhoto: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let user: String
    public let name: String
    public let cdn: String
    public let bundled: Bool

    public init(id: String, user: String, name: String, cdn: String, bundled: Bool = false) {
        self.id = id
        self.user = user
        self.name = name
        self.cdn = cdn
        self.bundled = bundled
    }

    private enum CodingKeys: String, CodingKey {
        case id, user, name, cdn, bundled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        user = try values.decode(String.self, forKey: .user)
        name = try values.decode(String.self, forKey: .name)
        cdn = try values.decode(String.self, forKey: .cdn)
        bundled = try values.decodeIfPresent(Bool.self, forKey: .bundled) ?? false
    }

    /// The Unsplash license asks for this line next to the photo, with links.
    public var credit: String { "Photo by \(name) on Unsplash" }
}

public struct WallpaperTheme: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let photos: [WallpaperPhoto]

    public init(id: String, title: String, photos: [WallpaperPhoto]) {
        self.id = id
        self.title = title
        self.photos = photos
    }
}

public struct WallpaperLibrary: Codable, Equatable, Sendable {
    public let themes: [WallpaperTheme]

    public init(themes: [WallpaperTheme]) {
        self.themes = themes
    }

    public static let empty = WallpaperLibrary(themes: [])

    public static func load(from data: Data) throws -> WallpaperLibrary {
        try JSONDecoder().decode(WallpaperLibrary.self, from: data)
    }

    public static let host = "images.unsplash.com"
    public static let fullWidth = 1920
    public static let thumbnailWidth = 320

    public var photos: [WallpaperPhoto] { themes.flatMap(\.photos) }

    public var bundledPhoto: WallpaperPhoto? { photos.first { $0.bundled } }

    public func photo(id: String) -> WallpaperPhoto? { photos.first { $0.id == id } }

    public func theme(id: String) -> WallpaperTheme? { themes.first { $0.id == id } }

    public func theme(ofPhoto id: String) -> WallpaperTheme? {
        themes.first { theme in theme.photos.contains { $0.id == id } }
    }

    public func imageURL(_ photo: WallpaperPhoto, width: Int = WallpaperLibrary.fullWidth) -> URL? {
        cdnURL(photo, width: width, quality: 80)
    }

    public func thumbnailURL(_ photo: WallpaperPhoto) -> URL? {
        cdnURL(photo, width: Self.thumbnailWidth, quality: 60)
    }

    public func pageURL(_ photo: WallpaperPhoto) -> URL? {
        URL(string: "https://unsplash.com/photos/\(photo.id)")
    }

    public func profileURL(_ photo: WallpaperPhoto) -> URL? {
        URL(string: "https://unsplash.com/@\(photo.user)")
    }

    private func cdnURL(_ photo: WallpaperPhoto, width: Int, quality: Int) -> URL? {
        URL(string: "https://\(Self.host)/\(photo.cdn)?w=\(width)&q=\(quality)&fm=jpg&fit=max")
    }
}

public enum WallpaperChoice: Codable, Equatable, Hashable, Sendable {
    case bundled
    case unsplash(id: String)
    case gradient(name: String)

    private enum CodingKeys: String, CodingKey {
        case kind, id, name
    }

    private enum Kind: String {
        case bundled, unsplash, gradient
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A kind written by a newer build falls back instead of failing the whole
        // settings decode, which would reset every other field to the first run.
        switch try values.decodeIfPresent(String.self, forKey: .kind) {
        case Kind.unsplash.rawValue:
            self = .unsplash(id: try values.decode(String.self, forKey: .id))
        case Kind.gradient.rawValue:
            self = .gradient(name: try values.decode(String.self, forKey: .name))
        default:
            self = .bundled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bundled:
            try values.encode(Kind.bundled.rawValue, forKey: .kind)
        case .unsplash(let id):
            try values.encode(Kind.unsplash.rawValue, forKey: .kind)
            try values.encode(id, forKey: .id)
        case .gradient(let name):
            try values.encode(Kind.gradient.rawValue, forKey: .kind)
            try values.encode(name, forKey: .name)
        }
    }
}
