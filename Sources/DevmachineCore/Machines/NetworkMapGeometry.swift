import CoreGraphics
import Foundation

/// The 2:1 isometric camera of the website's hero (hairline's `Cam(45, 0.5,
/// S)`): world x runs down to the right, y down to the left, z up.
public struct IsoCamera: Equatable, Sendable {
    public static let elevation = 0.5
    static let cosine = 0.5.squareRoot()
    static let height = (1 - elevation * elevation).squareRoot()

    public var scale: Double
    public var originX: Double
    public var originY: Double

    public init(scale: Double, originX: Double, originY: Double) {
        self.scale = scale
        self.originX = originX
        self.originY = originY
    }

    public func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let across = (x - y) * Self.cosine
        let depth = (x + y) * Self.cosine
        return CGPoint(
            x: originX + scale * across, y: originY + scale * (depth * Self.elevation - z * Self.height))
    }

    /// Whether a ring sample's outward normal faces the camera.
    public func faces(_ sample: IsoShapes.Sample) -> Bool {
        sample.nu * Self.cosine + sample.nv * Self.cosine >= -1e-6
    }
}

/// hairline's rounded solids: a footprint is a ring of samples with their
/// outward normals; a solid is the hull of its bottom and top rings.
public enum IsoShapes {
    public struct Sample: Equatable, Sendable {
        public let u: Double
        public let v: Double
        public let nu: Double
        public let nv: Double
    }

    public static func roundedRect(
        x0: Double, y0: Double, x1: Double, y1: Double, radius: Double, steps: Int = 4
    ) -> [Sample] {
        let r = max(0, min(radius, (x1 - x0) / 2, (y1 - y0) / 2))
        let corners: [(Double, Double, Double)] = [(x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180),
                                                   (x1 - r, y0 + r, 270)]
        return corners.flatMap { cu, cv, start in
            (0...steps).map { k in
                let angle = (start + 90 * Double(k) / Double(steps)) * .pi / 180
                return Sample(u: cu + r * cos(angle), v: cv + r * sin(angle), nu: cos(angle), nv: sin(angle))
            }
        }
    }

    public static func circle(radius: Double, steps: Int = 24) -> [Sample] {
        (0..<steps).map { k in
            let angle = Double(k) / Double(steps) * 2 * .pi
            return Sample(u: radius * cos(angle), v: radius * sin(angle), nu: cos(angle), nv: sin(angle))
        }
    }

    /// The convex hull, counter-clockwise (Andrew's monotone chain).
    public static func hull(_ input: [CGPoint]) -> [CGPoint] {
        let points = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard points.count > 2 else { return points }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for point in points {
            while lower.count > 1, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        var upper: [CGPoint] = []
        for point in points.reversed() {
            while upper.count > 1, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// The one cyclic run of samples that pass `keep`: the front of a crease.
    public static func run(_ ring: [Sample], keep: (Sample) -> Bool) -> [Sample] {
        let n = ring.count
        guard let start = (0..<n).first(where: { keep(ring[$0]) && !keep(ring[($0 + n - 1) % n]) }) else {
            return ring.first.map(keep) == true ? ring : []
        }
        var out: [Sample] = []
        for k in 0..<n {
            let sample = ring[(start + k) % n]
            guard keep(sample) else { break }
            out.append(sample)
        }
        return out
    }
}

/// Where everything on the network map goes for one width, in points. Tiles
/// sit in one row; above them run horizontal lanes (the internet, each site,
/// ssh, the tailnet), and every link drops from its node to its lane along an
/// isometric axis, the way the website's hero routes its traces.
public struct NetworkMapGeometry: Sendable {
    public static let minimumScale = 0.9
    public static let maximumScale = 3.0
    /// A tile's half side, its base and tier heights, in world units.
    public static let tileHalf = 15.0
    public static let internetHalf = 12.0
    public static let baseHeight = 8.0
    public static let tierHeight = 6.0
    /// Columns apart, in world units along the screen's width.
    static let pitch = 46.0
    static let labelHeight = 40.0
    /// Under the labels: the zone's name.
    public static let zoneFooter = 20.0
    /// Between the last lane and the tiles' tops: a zone's outline.
    static let zoneHeadroom = 24.0
    static let laneGap = 16.0
    static let edge = 18.0
    public static let siteRow = 17.0
    static let bottomEdge = 30.0

    public let map: NetworkMap
    public let scale: Double
    public let contentWidth: Double
    public let height: Double
    public let machineRowY: Double
    let left: Double
    let minColumn: Double
    let internetY: Double
    let lanes: [NetworkMap.LinkKind: Double]
    let siteLaneTop: Double
    /// Between two site lanes: room for a host's label, or less when none is drawn.
    let siteRow: Double
    /// Set only by `spread`: the distance between two columns, and where the
    /// internet tile goes across. Nil keeps the page's own layout.
    let columnStep: Double?
    let internetX: Double?
    /// Set only by `spread`: columns past `skipAfter` move right by `skipBy`,
    /// over the clock's band, so no machine stands under it.
    let skipAfter: Double?
    let skipBy: Double

    public init(
        map: NetworkMap, width: Double, maximumScale: Double = NetworkMapGeometry.maximumScale,
        siteRow: Double = NetworkMapGeometry.siteRow
    ) {
        self.map = map
        self.siteRow = siteRow
        let columns = map.nodes.map(\.column)
        let minColumn = columns.min() ?? 0
        let span = (columns.max() ?? 0) - minColumn
        let half = Self.halfWidth(Self.tileHalf)
        let unitsWide = span * Self.pitch * IsoCamera.cosine * 2 + 2 * (half + Self.edge)
        let scale = min(maximumScale, max(Self.minimumScale, width / unitsWide))
        self.scale = scale
        self.minColumn = minColumn
        contentWidth = unitsWide * scale
        left = (width - contentWidth) / 2 + (half + Self.edge) * scale

        var y = Self.edge
        let hasInternet = map.nodes.contains { $0.kind == .internet }
        var lanes: [NetworkMap.LinkKind: Double] = [:]
        if hasInternet {
            y += Self.top(Self.internetHalf) * scale
            internetY = y
            y += Self.bottom(Self.internetHalf) * scale + Self.laneGap
            lanes[.https] = y
            y += Self.laneGap
        } else {
            internetY = y
        }
        siteLaneTop = y
        y += Double(map.sites.count + (map.hiddenSites > 0 ? 1 : 0)) * siteRow + Self.laneGap
        let kinds = Set(map.links.map(\.kind))
        for kind in [NetworkMap.LinkKind.ssh, .tailnet] where kinds.contains(kind) {
            lanes[kind] = y
            y += Self.laneGap
        }
        self.lanes = lanes
        y += Self.zoneHeadroom + Self.top(Self.tileHalf) * scale
        machineRowY = y
        // The internet tile's top sits `edge` under the map's top, but its
        // tier draws a little lower; the zones' outlines end flush, so the
        // bottom gets the difference back to look as open as the top.
        height = y + Self.bottom(Self.tileHalf) * scale + Self.labelHeight + Self.zoneFooter + Self.bottomEdge
        columnStep = nil
        internetX = nil
        skipAfter = nil
        skipBy = 0
    }

    private init(
        map: NetworkMap, scale: Double, size: CGSize, left: Double, minColumn: Double, columnStep: Double,
        skipAfter: Double?, skipBy: Double, internetX: Double?, internetY: Double, lanes: [NetworkMap.LinkKind: Double], siteLaneTop: Double,
        siteRow: Double, machineRowY: Double
    ) {
        self.map = map
        self.scale = scale
        contentWidth = size.width
        height = size.height
        self.left = left
        self.minColumn = minColumn
        self.columnStep = columnStep
        self.skipAfter = skipAfter
        self.skipBy = skipBy
        self.internetX = internetX
        self.internetY = internetY
        self.lanes = lanes
        self.siteLaneTop = siteLaneTop
        self.siteRow = siteRow
        self.machineRowY = machineRowY
    }

    static func halfWidth(_ half: Double) -> Double { 2 * half * IsoCamera.cosine }
    static func top(_ half: Double) -> Double {
        half * 2 * IsoCamera.cosine * IsoCamera.elevation + (baseHeight + tierHeight) * IsoCamera.height
    }

    public static func bottom(_ half: Double) -> Double { half * 2 * IsoCamera.cosine * IsoCamera.elevation }

    /// The camera that draws one node's tile, centred on its ground point.
    public func camera(for id: String) -> IsoCamera {
        let center = self.center(of: id)
        return IsoCamera(scale: scale, originX: center.x, originY: center.y)
    }

    /// A node's centre on the ground.
    public func center(of id: String) -> CGPoint {
        guard let node = map.node(id) else { return .zero }
        if let columnStep {
            let x = node.kind == .internet ? internetX ?? spreadX(node.column, step: columnStep)
                : spreadX(node.column, step: columnStep)
            return CGPoint(x: x, y: node.kind == .internet ? internetY : machineRowY)
        }
        let x = left + (node.column - minColumn) * Self.pitch * IsoCamera.cosine * 2 * scale
        return CGPoint(x: x, y: node.kind == .internet ? internetY : machineRowY)
    }

    private func spreadX(_ column: Double, step: Double) -> Double {
        let x = left + (column - minColumn) * step
        guard let skipAfter, x > skipAfter + 1e-9 else { return x }
        return x + skipBy
    }

    public func tileHalf(of id: String) -> Double {
        map.node(id)?.kind == .internet ? Self.internetHalf : Self.tileHalf
    }

    /// The tile and, for a machine, its two label lines under it.
    public func frame(of id: String) -> CGRect {
        let center = self.center(of: id)
        let half = tileHalf(of: id)
        let width = Self.halfWidth(half) * scale
        let top = Self.top(half) * scale
        let label = map.node(id)?.kind == .internet ? 0 : Self.labelHeight
        return CGRect(x: center.x - width, y: center.y - top, width: width * 2,
                      height: top + Self.bottom(half) * scale + label)
    }

    /// The configured machine whose tile or label is under `point`.
    public func machine(at point: CGPoint) -> String? {
        map.nodes.last { $0.selectable && frame(of: $0.id).contains(point) }?.id
    }

    /// A zone's outline: around its tiles, their labels and its own name.
    public func frame(ofZone zone: NetworkMap.Zone) -> CGRect {
        guard let first = zone.machines.first, let last = zone.machines.last else { return .zero }
        let pad = 8.0
        let left = frame(of: first).minX - pad, right = frame(of: last).maxX + pad
        let top = machineRowY - Self.top(Self.tileHalf) * scale - Self.zoneHeadroom * 0.6
        let bottom = machineRowY + Self.bottom(Self.tileHalf) * scale + Self.labelHeight + Self.zoneFooter
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The lane a site in `row` would take: the one under the last site
    /// shown carries the count of the hidden ones.
    public func siteLane(row: Int) -> Double {
        siteLaneTop + Double(row) * siteRow
    }

    public func lane(of link: NetworkMap.Link) -> Double {
        if link.kind == .site, let row = link.row { return siteLane(row: row) }
        return lanes[link.kind] ?? siteLaneTop
    }

    /// The polyline a link is drawn along: straight up from each end (the
    /// world's z axis) to its lane, and along the lane between them, so
    /// lines lie in the air above the tiles and never cross on the ground.
    public func route(of link: NetworkMap.Link) -> [CGPoint] {
        let from = center(of: link.from), to = center(of: link.to)
        let lane = lane(of: link)
        guard link.from != link.to else { return [from, CGPoint(x: from.x, y: lane)] }
        return Self.route(from: from, to: to, lane: lane)
    }

    static func route(from: CGPoint, to: CGPoint, lane: Double) -> [CGPoint] {
        [from, CGPoint(x: from.x, y: lane), CGPoint(x: to.x, y: lane), to]
    }

    /// Where a site's marker sits: on its lane, over the machine that runs it.
    public func marker(of site: NetworkMap.Site) -> CGPoint {
        let link = NetworkMap.Link(kind: .site, from: site.door, to: site.target, row: site.row)
        let points = route(of: link)
        return site.door == site.target ? points[points.count - 1] : points[points.count - 2]
    }
}

extension NetworkMapGeometry {
    /// Between the clock's band and anything drawn near it.
    public static let clearGap = 14.0
    /// Room beside a machine's tile for its name and the line under it.
    static let labelHalfWidth = 64.0
    /// Room above a lane for its tag ("https", "ssh").
    static let tagHeight = 12.0

    /// The map spread over `size` around a band it must leave empty
    /// (`keepClear`, the clock and its date): the internet high, the
    /// machines low and across the whole width, the lanes above the band
    /// when no machine stands under it, else between the band and the
    /// machines with the internet moved beside the band, so no line runs
    /// through it. Nil when the band leaves no room; the caller then draws
    /// the ordinary layout. Same inputs, same layout.
    public static func spread(
        map: NetworkMap, size: CGSize, keepClear: CGRect, maximumScale: Double, siteRow: Double
    ) -> NetworkMapGeometry? {
        guard !map.nodes.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let machineColumns = map.machineNodes.map(\.column)
        let minColumn = machineColumns.min() ?? 0
        let span = (machineColumns.max() ?? 0) - minColumn
        let hasInternet = map.nodes.contains { $0.kind == .internet }
        let kinds = Set(map.links.map(\.kind))
        let otherLanes = [NetworkMap.LinkKind.ssh, .tailnet].filter { kinds.contains($0) }
        let laneBlock = (hasInternet ? laneGap : 0)
            + Double(map.sites.count + (map.hiddenSites > 0 ? 1 : 0)) * siteRow + laneGap
            + Double(otherLanes.count) * laneGap
        let above = keepClear.minY - clearGap
        let below = keepClear.maxY + clearGap

        func layout(scale: Double, allowCrossing: Bool, requireSides: Bool) -> NetworkMapGeometry? {
            let side = max(edge + halfWidth(tileHalf) * scale, labelHalfWidth)
            let usable = size.width - 2 * side
            guard usable >= 0 else { return nil }
            let minimumStep = 2 * halfWidth(tileHalf) * scale + laneGap
            // The machines take the two sides of the band, so their lines
            // never rise through it; too little room there, and they take
            // the whole width.
            let leftRun = max(0, keepClear.minX - clearGap - side)
            let rightStart = max(side, keepClear.maxX + clearGap)
            let rightRun = max(0, size.width - side - rightStart)
            let sidesStep = span > 0 ? (leftRun + rightRun) / span : 0
            let skips = span > 0 && sidesStep >= minimumStep
            if requireSides, span > 0, !skips { return nil }
            let step = skips ? sidesStep : (span > 0 ? usable / span : 0)
            if span > 0, step < minimumStep { return nil }
            let left = span > 0 ? side : size.width / 2
            let skipAfter = skips ? side + leftRun : nil
            let skipBy = skips ? rightStart - (side + leftRun) : 0
            let columnX = { (column: Double) -> Double in
                let x = left + (column - minColumn) * step
                guard let skipAfter, x > skipAfter + 1e-9 else { return x }
                return x + skipBy
            }

            let internetY = edge + top(internetHalf) * scale
            let internetBottom = hasInternet ? internetY + bottom(internetHalf) * scale : edge
            let machineRowY = size.height - (bottom(tileHalf) * scale + labelHeight + zoneFooter + bottomEdge)
            let zoneTop = machineRowY - top(tileHalf) * scale - zoneHeadroom * 0.6
            guard zoneTop >= below, internetBottom <= above || !hasInternet else { return nil }

            let crossesBand = map.machineNodes.contains { node in
                let x = columnX(node.column)
                return x >= keepClear.minX - clearGap && x <= keepClear.maxX + clearGap
            }
            let lanesAbove = internetBottom + laneGap + laneBlock <= above
            let lanesBelow = below + tagHeight + laneBlock <= zoneTop
            let laneStart: Double
            var internetX: Double?
            let movedInternet = hasInternet
                ? besideBand(columnX(map.node(NetworkMap.internetID)?.column ?? minColumn), scale: scale) : nil
            if lanesAbove, !crossesBand {
                laneStart = internetBottom + laneGap
            } else if lanesBelow, allowCrossing || movedInternet?.isClear != false {
                laneStart = below + tagHeight
                internetX = movedInternet?.x
            } else if lanesAbove, allowCrossing {
                laneStart = internetBottom + laneGap
            } else {
                return nil
            }

            var y = laneStart
            var lanes: [NetworkMap.LinkKind: Double] = [:]
            if hasInternet {
                lanes[.https] = y
                y += laneGap
            }
            let siteLaneTop = y
            y += Double(map.sites.count + (map.hiddenSites > 0 ? 1 : 0)) * siteRow + laneGap
            for kind in otherLanes {
                lanes[kind] = y
                y += laneGap
            }
            return NetworkMapGeometry(
                map: map, scale: scale, size: size, left: left, minColumn: minColumn, columnStep: step,
                skipAfter: skipAfter, skipBy: skipBy, internetX: internetX, internetY: internetY, lanes: lanes, siteLaneTop: siteLaneTop,
                siteRow: siteRow, machineRowY: machineRowY)
        }

        /// The internet's x moved off the band, to the nearer side that has
        /// room for its tile and its "internet" label; where neither side has
        /// room, its line has to cross.
        func besideBand(_ x: Double, scale: Double) -> (x: Double, isClear: Bool) {
            let reach = halfWidth(internetHalf) * scale
            let label = labelHalfWidth
            guard x + reach + label > keepClear.minX - clearGap, x - reach < keepClear.maxX + clearGap else {
                return (x, true)
            }
            let leftX = keepClear.minX - clearGap - reach - label
            let rightX = keepClear.maxX + clearGap + reach
            let leftFits = leftX - reach >= edge
            let rightFits = rightX + reach + label <= size.width - edge
            switch (leftFits, rightFits) {
            case (true, true): return (x - leftX <= rightX - x ? leftX : rightX, true)
            case (true, false): return (leftX, true)
            case (false, true): return (rightX, true)
            case (false, false): return (x, false)
            }
        }

        // A smaller map with the machines beside the band and nothing through
        // it beats a bigger one with a machine under it or a line across it.
        for (requireSides, allowCrossing) in [(true, false), (false, false), (false, true)] {
            var scale = maximumScale
            while scale >= minimumScale {
                if let geometry = layout(scale: scale, allowCrossing: allowCrossing, requireSides: requireSides) {
                    return geometry
                }
                scale -= 0.05
            }
        }
        return nil
    }
}
