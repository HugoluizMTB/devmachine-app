import CoreGraphics
import Foundation

/// How the network map is drawn: as Settings → Machines' map, which answers
/// clicks and shows a selection, or as Home's wallpaper, which never takes a
/// click and stays quiet under the clock and the cards.
public struct NetworkMapPresentation: Equatable, Sendable {
    public let isInteractive: Bool
    /// The tiles, links and labels.
    public let inkOpacity: Double
    /// The grid the tiles stand on.
    public let groundOpacity: Double
    /// Each site's host beside its marker. Behind Home they run under the
    /// clock's digits; the markers and lanes still show where sites are.
    public let showsSiteLabels: Bool
    /// "+N more on the Subdomains page" points at another page, which only
    /// means something where the map can be read closely.
    public let showsHiddenSiteCount: Bool

    public static let interactive = NetworkMapPresentation(
        isInteractive: true, inkOpacity: 1, groundOpacity: 1, showsSiteLabels: true, showsHiddenSiteCount: true)
    public static let decorative = NetworkMapPresentation(
        isInteractive: false, inkOpacity: 0.45, groundOpacity: 0.9, showsSiteLabels: false,
        showsHiddenSiteCount: false)

    public var allowsHitTesting: Bool { isInteractive }

    /// The machine drawn lit: the selection or the hover, never in the background.
    public func highlighted(_ id: String?) -> String? {
        isInteractive ? id : nil
    }
}

/// The network map laid out as a background: centred in its container, fitted
/// inside generous margins, never larger than `maximumScale`, and shrunk as a
/// whole when the container is too short for it.
public struct NetworkMapBackdrop: Sendable {
    public static let marginFraction = 0.12
    public static let minimumMargin = 48.0
    /// One machine in a big window would otherwise draw a tile the size of the clock.
    public static let maximumScale = 2.0

    public let map: NetworkMap
    /// Laid out for the width inside the margins, in the map's own points.
    public let geometry: NetworkMapGeometry
    public let margins: CGSize
    /// Applied to the whole drawing, at most 1.
    public let zoom: Double
    /// Where the map's (0, 0) lands in the container.
    public let origin: CGPoint
    /// The whole container in the map's points, for the ground grid.
    public let ground: CGRect

    /// `minimumMargin` is smaller for a thumbnail, where 48 points would leave no room.
    public init(map: NetworkMap, size: CGSize, minimumMargin: Double = NetworkMapBackdrop.minimumMargin) {
        self.map = map
        let margins = CGSize(
            width: max(minimumMargin, size.width * Self.marginFraction),
            height: max(minimumMargin, size.height * Self.marginFraction))
        self.margins = margins
        let available = CGSize(
            width: max(1, size.width - 2 * margins.width), height: max(1, size.height - 2 * margins.height))
        let geometry = NetworkMapGeometry(map: map, width: available.width, maximumScale: Self.maximumScale)
        self.geometry = geometry

        let zoom = map.nodes.isEmpty
            ? 1
            : min(1, available.width / max(geometry.contentWidth, 1), available.height / max(geometry.height, 1))
        self.zoom = zoom
        let origin = CGPoint(
            x: size.width / 2 - available.width / 2 * zoom, y: size.height / 2 - geometry.height / 2 * zoom)
        self.origin = origin
        ground = CGRect(
            x: -origin.x / zoom, y: -origin.y / zoom, width: size.width / zoom, height: size.height / zoom)
        availableWidth = available.width
    }

    private let availableWidth: Double

    /// The drawn map in the container's points: its tiles, lanes and labels.
    public var mapFrame: CGRect {
        CGRect(
            x: origin.x + (availableWidth - geometry.contentWidth) / 2 * zoom, y: origin.y,
            width: geometry.contentWidth * zoom, height: geometry.height * zoom)
    }
}
