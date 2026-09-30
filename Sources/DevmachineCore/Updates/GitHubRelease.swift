import Foundation

public struct GitHubRelease: Codable, Equatable, Sendable {
    public struct Asset: Codable, Equatable, Sendable {
        public let name: String
        public let downloadURL: URL
        public let size: Int

        public init(name: String, downloadURL: URL, size: Int = 0) {
            self.name = name
            self.downloadURL = downloadURL
            self.size = size
        }

        enum CodingKeys: String, CodingKey {
            case name, size
            case downloadURL = "browser_download_url"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            downloadURL = try c.decode(URL.self, forKey: .downloadURL)
            size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        }
    }

    public let tagName: String
    public let name: String
    public let body: String
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let htmlURL: URL?
    public let assets: [Asset]

    public init(
        tagName: String, name: String = "", body: String = "", isDraft: Bool = false,
        isPrerelease: Bool = false, htmlURL: URL? = nil, assets: [Asset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.htmlURL = htmlURL
        self.assets = assets
    }

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case htmlURL = "html_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        isPrerelease = try c.decodeIfPresent(Bool.self, forKey: .isPrerelease) ?? false
        htmlURL = try c.decodeIfPresent(URL.self, forKey: .htmlURL)
        assets = try c.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    public static func decode(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    public var version: SemanticVersion? { SemanticVersion(tagName) }

    public func asset(named name: String) -> Asset? {
        assets.first { $0.name == name }
    }

    /// `Devmachine-X.Y.Z.dmg`, the asset of record. The stable-named copy is
    /// for download links, never for the updater: its name says nothing about
    /// which version it holds.
    public var appDiskImage: Asset? {
        version.flatMap { asset(named: "Devmachine-\($0).dmg") }
    }

    public var appDiskImageDigest: Asset? {
        appDiskImage.flatMap { asset(named: "\($0.name).sha256") }
    }

    /// The release workflow writes `sha256: <hex>` into the notes of every
    /// release, including those made before the `.sha256` asset existed.
    public var bodyDigest: String? {
        body.split(whereSeparator: \.isNewline)
            .first { $0.lowercased().hasPrefix("sha256:") }
            .flatMap { ReleaseDigest.parse(String($0.dropFirst("sha256:".count))) }
    }

    public var notes: String {
        body.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("sha256:") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
