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

/// The network map laid out as a background: centred in an area of its
/// container (the whole container by default), fitted inside generous
/// margins, never larger than `maximumScale`, and shrunk as a whole when the
/// area is too small. The ground always covers the whole container.
public struct NetworkMapBackdrop: Sendable {
    public static let marginFraction = 0.12
    public static let minimumMargin = 48.0
    /// One machine in a big window would otherwise draw a tile the size of the clock.
    public static let maximumScale = 2.0
    /// Below this a tile is a smudge and its name unreadable: the ground alone looks better.
    public static let minimumLegibleScale = 0.5
    /// The background draws no host beside a site, so its lanes sit close.
    public static let siteRow = 6.0

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
    private let availableWidth: Double

    /// `minimumMargin` is smaller for a thumbnail, where 48 points would leave no room.
    public init(
        map: NetworkMap, size: CGSize, area: CGRect? = nil,
        minimumMargin: Double = NetworkMapBackdrop.minimumMargin
    ) {
        self.map = map
        let area = area ?? CGRect(origin: .zero, size: size)
        let margins = CGSize(
            width: max(minimumMargin, area.width * Self.marginFraction),
            height: max(minimumMargin, area.height * Self.marginFraction))
        self.margins = margins
        let available = CGSize(
            width: max(1, area.width - 2 * margins.width), height: max(1, area.height - 2 * margins.height))
        let geometry = NetworkMapGeometry(
            map: map, width: available.width, maximumScale: Self.maximumScale, siteRow: Self.siteRow)
        self.geometry = geometry

        let zoom = map.nodes.isEmpty
            ? 1
            : min(1, available.width / max(geometry.contentWidth, 1), available.height / max(geometry.height, 1))
        self.zoom = zoom
        let origin = CGPoint(
            x: area.midX - available.width / 2 * zoom, y: area.midY - geometry.height / 2 * zoom)
        self.origin = origin
        ground = CGRect(
            x: -origin.x / zoom, y: -origin.y / zoom, width: size.width / zoom, height: size.height / zoom)
        availableWidth = available.width
    }

    /// The drawn map in the container's points: its tiles, lanes and labels.
    public var mapFrame: CGRect {
        CGRect(
            x: origin.x + (availableWidth - geometry.contentWidth) / 2 * zoom, y: origin.y,
            width: geometry.contentWidth * zoom, height: geometry.height * zoom)
    }

    /// Whether the machines are drawn at all, or only the ground.
    public var showsMap: Bool {
        !map.nodes.isEmpty && geometry.scale * zoom >= Self.minimumLegibleScale
    }
}

/// Where Home has room for the network map wallpaper: right of the cards
/// column and under the clock when they sit side by side, under everything
/// when Home is stacked; always above the stats pill. Nil when what is left
/// is too small to hold a map.
public enum HomeMapArea {
    public enum Layout: Equatable, Sendable {
        case sideBySide(cardsMaxX: Double, clockMaxY: Double)
        case stacked(contentMaxY: Double)
    }

    public static let minimumSide = 80.0

    public static func rect(size: CGSize, padding: Double, gap: Double, pillMinY: Double, layout: Layout) -> CGRect? {
        let bottom = pillMinY - gap
        let left: Double, top: Double, right = size.width - padding
        switch layout {
        case let .sideBySide(cardsMaxX, clockMaxY):
            left = cardsMaxX + gap
            top = clockMaxY + gap
        case let .stacked(contentMaxY):
            left = padding
            top = contentMaxY + gap
        }
        // Checked before building the rect: CGRect reports a negative size as positive.
        guard right - left >= minimumSide, bottom - top >= minimumSide else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
