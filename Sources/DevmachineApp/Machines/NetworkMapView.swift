import SwiftUI
import DevmachineCore

/// The network map: every machine as an isometric tile on a faint ground
/// grid, grouped by location, with the links the configuration proves.
/// Drawn natively after the website's hero (hairline's plates, creases and
/// coins). `.interactive` is Settings → Machines' map, where a click on a
/// machine selects it in the list below; `.decorative` is Home's wallpaper,
/// which fills its container, takes no click and fades in once data arrives.
struct NetworkMapView: View {
    let map: NetworkMap
    let presentation: NetworkMapPresentation
    var selected: String?
    var select: (String) -> Void = { _ in }
    var minimumMargin = NetworkMapBackdrop.minimumMargin

    init(map: NetworkMap, selected: String?, select: @escaping (String) -> Void) {
        self.map = map
        presentation = .interactive
        self.selected = selected
        self.select = select
    }

    init(decorative map: NetworkMap, minimumMargin: Double = NetworkMapBackdrop.minimumMargin) {
        self.map = map
        presentation = .decorative
        self.minimumMargin = minimumMargin
    }

    var body: some View {
        if presentation.isInteractive {
            InteractiveNetworkMap(map: map, selected: selected, select: select)
        } else {
            DecorativeNetworkMap(map: map, presentation: presentation, minimumMargin: minimumMargin)
        }
    }
}

private struct InteractiveNetworkMap: View {
    @Environment(\.dmMetrics) private var m
    let map: NetworkMap
    let selected: String?
    let select: (String) -> Void
    @State private var width = 900.0
    @State private var hovered: String?

    var body: some View {
        let geometry = NetworkMapGeometry(map: map, width: width)
        Canvas { context, size in
            NetworkMapPainter(
                geometry: geometry, presentation: .interactive, selected: selected, hovered: hovered,
                fontScale: m.scale
            ).draw(in: &context, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(height: geometry.height)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
            if let machine = geometry.machine(at: point) { select(machine) }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(point):
                let machine = geometry.machine(at: point)
                if machine != hovered { hovered = machine }
            case .ended:
                hovered = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: NetworkMapPainter.summary(map)))
    }
}

/// The map as a background: the ground always, the machines over it once
/// there are any. Two canvases so the machines can fade in over a ground
/// that is already there, and each is `Equatable` so a Home redraw (a stats
/// tick, a usage refresh) does not repaint them.
private struct DecorativeNetworkMap: View {
    @Environment(\.dmMetrics) private var m
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let map: NetworkMap
    let presentation: NetworkMapPresentation
    let minimumMargin: Double

    var body: some View {
        let shows = !map.nodes.isEmpty
        ZStack {
            DecorativeLayer(map: map, layer: .ground, fontScale: m.scale, minimumMargin: minimumMargin)
                .equatable()
                .opacity(presentation.groundOpacity)
            DecorativeLayer(map: map, layer: .ink, fontScale: m.scale, minimumMargin: minimumMargin)
                .equatable()
                .opacity(shows ? presentation.inkOpacity : 0)
                .animation(reduceMotion ? nil : .easeIn(duration: 0.9), value: shows)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DecorativeLayer: View, Equatable {
    let map: NetworkMap
    let layer: NetworkMapPainter.Layer
    let fontScale: CGFloat
    let minimumMargin: Double

    var body: some View {
        Canvas { context, size in
            let backdrop = NetworkMapBackdrop(map: map, size: size, minimumMargin: minimumMargin)
            context.translateBy(x: backdrop.origin.x, y: backdrop.origin.y)
            context.scaleBy(x: backdrop.zoom, y: backdrop.zoom)
            NetworkMapPainter(
                geometry: backdrop.geometry, presentation: .decorative, selected: nil, hovered: nil,
                fontScale: fontScale, layers: [layer], ground: backdrop.ground
            ).draw(in: &context, size: backdrop.ground.size)
        }
    }
}

/// The map's own palette: hairline's dark theme, set against the app's
/// content background.
enum MapInk {
    static let plate = Color(hex: 0x0B0E12)
    static let hi = Color(hex: 0xF5F5F2)
    static let edge = Color(hex: 0x8C9099)
    static let mid = Color(hex: 0x4A4D55)
    static let lo = Color(hex: 0x2A2E35)
    static let trace = Color(hex: 0x4A4F58)
    static let grid = Color.white.opacity(0.07)
    static let coin = Color(hex: 0xE9EAE6)
    static let mark = Color(hex: 0x050505)
    static let brand = Color(hex: 0x28C840)
    static let tag = Color(hex: 0x8A8D94)
}

struct NetworkMapPainter {
    enum Layer: Hashable {
        /// The grid the tiles stand on.
        case ground
        /// Everything on it: zones, links, tiles, labels.
        case ink
    }

    let geometry: NetworkMapGeometry
    let presentation: NetworkMapPresentation
    let selected: String?
    let hovered: String?
    let fontScale: CGFloat
    var layers: Set<Layer> = [.ground, .ink]
    /// The area the ground covers, in the map's points; the canvas when nil.
    var ground: CGRect?

    init(
        geometry: NetworkMapGeometry, presentation: NetworkMapPresentation, selected: String?, hovered: String?,
        fontScale: CGFloat, layers: Set<Layer> = [.ground, .ink], ground: CGRect? = nil
    ) {
        self.geometry = geometry
        self.presentation = presentation
        self.selected = presentation.highlighted(selected)
        self.hovered = presentation.highlighted(hovered)
        self.fontScale = fontScale
        self.layers = layers
        self.ground = ground
    }

    private var map: NetworkMap { geometry.map }
    private var scale: Double { geometry.scale }
    private var stroke: CGFloat { 0.9 }

    static func summary(_ map: NetworkMap) -> String {
        let zones = map.zones.map { "\($0.name): \($0.machines.joined(separator: ", "))" }
        return "Network map. " + zones.joined(separator: ". ")
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        if layers.contains(.ground) { drawGrid(in: &context, bounds: ground ?? CGRect(origin: .zero, size: size)) }
        guard layers.contains(.ink) else { return }
        for zone in map.zones { drawZone(zone, in: &context) }
        for link in map.links { drawLink(link, in: &context) }
        drawTags(in: &context)
        for node in map.nodes { drawTile(node, in: &context) }
        for site in map.sites { drawSite(site, in: &context) }
        for node in map.nodes { drawLabel(node, in: &context) }
        if map.hiddenSites > 0, presentation.showsHiddenSiteCount { drawHiddenSites(in: &context) }
    }

    // MARK: - Ground

    /// The world's ground grid, so every tile stands on it; it fades out
    /// toward the edges like the hero's. With no machine yet it is centred
    /// in `bounds`, the ground a background shows before its data.
    private func drawGrid(in context: inout GraphicsContext, bounds: CGRect) {
        let anchor = map.machineNodes.first
        let camera = anchor.map { geometry.camera(for: $0.id) }
            ?? IsoCamera(scale: geometry.scale, originX: bounds.midX, originY: bounds.midY)
        let step = NetworkMapGeometry.tileHalf
        let reach = ground == nil
            ? Double(Int(bounds.width / max(step * geometry.scale, 1)) + 20)
            : Self.gridReach(camera: camera, bounds: bounds, step: step * geometry.scale)
        let center = CGPoint(x: bounds.midX, y: anchor == nil ? bounds.midY : geometry.machineRowY)
        context.drawLayer { layer in
            var path = Path()
            for k in stride(from: -reach, through: reach, by: 1) {
                let offset = k * step
                path.move(to: camera.project(offset, -reach * step, 0))
                path.addLine(to: camera.project(offset, reach * step, 0))
                path.move(to: camera.project(-reach * step, offset, 0))
                path.addLine(to: camera.project(reach * step, offset, 0))
            }
            layer.stroke(path, with: .color(MapInk.grid), lineWidth: 0.6)
            layer.blendMode = .destinationIn
            layer.fill(
                Path(bounds),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .black, location: 0), .init(color: .black.opacity(0.4), location: 0.6),
                        .init(color: .clear, location: 1),
                    ]),
                    center: center,
                    startRadius: 0, endRadius: max(bounds.width * 0.55, geometry.height)))
        }
    }

    /// Lines each way from the anchor for a background's ground, which can
    /// be far taller than its map and reach the anchor's far side in any
    /// direction; the page's map is a strip, where its width decides.
    static func gridReach(camera: IsoCamera, bounds: CGRect, step: Double) -> Double {
        let farthest = max(abs(camera.originX - bounds.minX), abs(bounds.maxX - camera.originX),
                           abs(camera.originY - bounds.minY), abs(bounds.maxY - camera.originY))
        return Double(Int(2 * farthest / max(step, 1)) + 4)
    }

    private func drawZone(_ zone: NetworkMap.Zone, in context: inout GraphicsContext) {
        let frame = geometry.frame(ofZone: zone)
        let radius = 10.0
        let shape = Path(roundedRect: frame, cornerSize: CGSize(width: radius, height: radius))
        context.fill(shape, with: .color(Color.white.opacity(0.018)))
        context.stroke(shape, with: .color(MapInk.mid), style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 3.5]))
        let text = Text(verbatim: zone.name.uppercased())
            .font(.system(size: 9 * fontScale, weight: .medium, design: .monospaced))
            .kerning(1.2)
            .foregroundColor(MapInk.tag)
        context.draw(text, at: CGPoint(x: frame.minX + 10, y: frame.maxY - 5), anchor: .bottomLeading)
    }

    // MARK: - Links

    private func drawLink(_ link: NetworkMap.Link, in context: inout GraphicsContext) {
        let points = geometry.route(of: link)
        var path = Path()
        path.addLines(points)
        let highlighted = [link.from, link.to].contains { $0 == selected || $0 == hovered }
        let color = highlighted ? MapInk.edge : MapInk.trace
        switch link.kind {
        case .tailnet:
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round, dash: [3, 3]))
        default:
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
        }
    }

    /// One small label per kind of link, on its lane near where it starts.
    private func drawTags(in context: inout GraphicsContext) {
        for (kind, word) in [(NetworkMap.LinkKind.https, "https"), (.ssh, "ssh"), (.tailnet, "tailnet")] {
            guard let link = map.links.first(where: { $0.kind == kind }) else { continue }
            let points = geometry.route(of: link)
            guard points.count >= 3 else { continue }
            let start = points[1], end = points[2]
            let x = end.x >= start.x ? start.x + 8 : start.x - 8
            let text = Text(verbatim: word)
                .font(.system(size: 8.5 * fontScale, design: .monospaced))
                .kerning(1)
                .foregroundColor(MapInk.tag)
            context.draw(
                text, at: CGPoint(x: x, y: start.y - 2), anchor: end.x >= start.x ? .bottomLeading : .bottomTrailing)
        }
    }

    // MARK: - Sites

    private func drawSite(_ site: NetworkMap.Site, in context: inout GraphicsContext) {
        let point = geometry.marker(of: site)
        let dot = Path(ellipseIn: CGRect(x: point.x - 2.6, y: point.y - 2.6, width: 5.2, height: 5.2))
        context.fill(dot, with: .color(site.door == selected || site.target == selected ? MapInk.hi : MapInk.edge))
        guard presentation.showsSiteLabels else { return }
        let label = site.workspace.map { "\(site.host) → \($0)" } ?? site.host
        let text = Text(verbatim: label)
            .font(.system(size: 9.5 * fontScale, design: .monospaced))
            .foregroundColor(Color.dmRowText.opacity(0.85))
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: 600, height: 40))
        let doorX = geometry.center(of: site.door).x
        let leftward = site.door != site.target && doorX < point.x
            && point.x - size.width - 8 > 0
        let origin = CGPoint(x: leftward ? point.x - 6 - size.width : point.x + 6, y: point.y - size.height - 1)
        backdrop(CGRect(origin: origin, size: size), in: &context)
        context.draw(resolved, at: origin, anchor: .topLeading)
    }

    private func drawHiddenSites(in context: inout GraphicsContext) {
        let text = Text(verbatim: "+\(map.hiddenSites) more on the Subdomains page")
            .font(.system(size: 9 * fontScale, design: .monospaced))
            .foregroundColor(MapInk.tag)
        let y = geometry.siteLane(row: map.sites.count) - 2
        context.draw(text, at: CGPoint(x: geometry.frame(of: map.nodes[0].id).minX, y: y), anchor: .bottomLeading)
    }

    private func backdrop(_ rect: CGRect, in context: inout GraphicsContext) {
        let padded = rect.insetBy(dx: -3, dy: -1)
        context.fill(
            Path(roundedRect: padded, cornerRadius: 3), with: .color(Color.dmContentBg.opacity(0.92)))
    }

    // MARK: - Tiles

    private func drawTile(_ node: NetworkMap.Node, in context: inout GraphicsContext) {
        let camera = geometry.camera(for: node.id)
        let s = geometry.tileHalf(of: node.id)
        let k = s / 15
        let base = NetworkMapGeometry.baseHeight, tier = NetworkMapGeometry.tierHeight
        let lit = node.id == selected || node.id == hovered

        drawSolid(camera: camera, half: s, radius: 6 * k, inset: 1.6, z0: 0, z1: base, highlight: false,
                  in: &context)
        drawSolid(camera: camera, half: s - 4, radius: 4.5 * k, inset: 1.4, z0: base, z1: base + tier,
                  highlight: lit, in: &context)

        let top = base + tier
        let workspaces = Array(node.workspaces.prefix(3))
        let coinCenter = workspaces.isEmpty ? (0.0, 0.0) : (2.6 * k, 2.6 * k)
        let coinRadius = (workspaces.isEmpty ? 8.2 : 5.6) * k
        let coin = polygon(IsoShapes.circle(radius: coinRadius, steps: 28).map {
            camera.project(coinCenter.0 + $0.u, coinCenter.1 + $0.v, top + 0.2)
        })
        context.fill(coin, with: .color(MapInk.coin))
        context.stroke(coin, with: .color(MapInk.coin), lineWidth: stroke)
        let markScale = 0.95 * k * coinRadius / (8.2 * k)
        var mark = Path()
        for line in Self.mark(for: node) {
            mark.addLines(line.map { camera.project(coinCenter.0 + $0.0 * markScale, coinCenter.1 + $0.1 * markScale, top + 0.3) })
        }
        let brand = node.id == selected || node.kind == .thisMac && selected == nil
        context.stroke(
            mark, with: .color(brand ? MapInk.brand : MapInk.mark),
            style: StrokeStyle(lineWidth: brand ? 1.4 : 1.1, lineCap: .round, lineJoin: .round))

        let spots: [(Double, Double)] = [(-6.2, -6.2), (-6.2, 0.4), (0.4, -6.2)]
        for (index, _) in workspaces.enumerated() {
            let (u, v) = spots[index]
            drawSolid(camera: camera, center: (u * k, v * k), half: 2.4 * k, radius: 0.9 * k, inset: 0.5,
                      z0: top, z1: top + 2.8, highlight: lit, in: &context)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func drawSolid(
        camera: IsoCamera, center: (Double, Double) = (0, 0), half: Double, radius: Double, inset: Double,
        z0: Double, z1: Double, highlight: Bool, in context: inout GraphicsContext
    ) {
        let (cx, cy) = center
        let ring = IsoShapes.roundedRect(x0: cx - half, y0: cy - half, x1: cx + half, y1: cy + half, radius: radius)
        let inner = IsoShapes.roundedRect(
            x0: cx - half + inset, y0: cy - half + inset, x1: cx + half - inset, y1: cy + half - inset,
            radius: max(0.3, radius - inset))
        let points = ring.map { camera.project($0.u, $0.v, z1) } + ring.map { camera.project($0.u, $0.v, z0) }
        let silhouette = polygon(IsoShapes.hull(points))
        context.fill(silhouette, with: .color(MapInk.plate))
        context.stroke(
            silhouette, with: .color(highlight ? MapInk.hi : MapInk.edge),
            style: StrokeStyle(lineWidth: stroke, lineJoin: .round))
        var crease = Path()
        crease.addLines(IsoShapes.run(inner, keep: camera.faces).map { camera.project($0.u, $0.v, z1) })
        context.stroke(crease, with: .color(MapInk.mid), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    // MARK: - Labels

    private func drawLabel(_ node: NetworkMap.Node, in context: inout GraphicsContext) {
        let center = geometry.center(of: node.id)
        if node.kind == .internet {
            let text = Text(verbatim: "internet")
                .font(.system(size: 10 * fontScale, weight: .medium, design: .monospaced))
                .foregroundColor(MapInk.tag)
            let frame = geometry.frame(of: node.id)
            context.draw(text, at: CGPoint(x: frame.maxX + 6, y: center.y), anchor: .leading)
            return
        }
        let below = center.y + NetworkMapGeometry.bottom(geometry.tileHalf(of: node.id)) * scale + 6
        let name = Text(verbatim: node.kind == .thisMac && node.id == NetworkMap.thisMacID ? "this Mac" : node.id)
            .font(.system(size: 11 * fontScale, weight: .semibold))
            .foregroundColor(node.id == selected ? MapInk.hi : Color.dmRowText)
        let resolvedName = context.resolve(name)
        let nameSize = resolvedName.measure(in: CGSize(width: 400, height: 40))
        let detail = Text(verbatim: Self.detail(for: node))
            .font(.system(size: 9.5 * fontScale, design: .monospaced))
            .foregroundColor(MapInk.tag)
        let resolvedDetail = context.resolve(detail)
        let detailSize = resolvedDetail.measure(in: CGSize(width: 400, height: 40))
        context.draw(resolvedName, at: CGPoint(x: center.x, y: below), anchor: .top)
        context.draw(resolvedDetail, at: CGPoint(x: center.x, y: below + nameSize.height + 1), anchor: .top)
        _ = detailSize
    }

    static func detail(for node: NetworkMap.Node) -> String {
        var parts: [String] = []
        switch node.kind {
        case .thisMac: parts.append(node.id == NetworkMap.thisMacID ? "where the app runs" : "this Mac")
        case .localVM: parts.append("Lima VM")
        case .server, .internet: break
        }
        if node.isDoor { parts.append("caddy") }
        if !node.workspaces.isEmpty {
            let shown = node.workspaces.prefix(2).joined(separator: ", ")
            let more = node.workspaces.count > 2 ? " +\(node.workspaces.count - 2)" : ""
            parts.append(shown + more)
        }
        return parts.isEmpty ? "server" : parts.joined(separator: " · ")
    }

    // MARK: - Marks

    /// The glyph on each coin, in ground units around the coin's centre,
    /// after the hero's marks.
    static func mark(for node: NetworkMap.Node) -> [[(Double, Double)]] {
        switch node.kind {
        case .internet:
            let circle = IsoShapes.circle(radius: 5, steps: 16).map { ($0.u, $0.v) }
            return [circle + [circle[0]], circle.map { ($0.0 * 0.42, $0.1) } + [(circle[0].0 * 0.42, circle[0].1)],
                    [(-5, 0), (5, 0)]]
        case .thisMac:
            let screen = IsoShapes.roundedRect(x0: -5, y0: -4, x1: 5, y1: 2, radius: 1, steps: 2).map { ($0.u, $0.v) }
            return [screen + [screen[0]], [(-6.5, 4), (6.5, 4)]]
        case .localVM:
            let window = IsoShapes.roundedRect(x0: -6, y0: -4.5, x1: 6, y1: 4.5, radius: 1.2, steps: 2).map { ($0.u, $0.v) }
            return [window + [window[0]], [(-6, -1.8), (6, -1.8)], [(-4, 1.2), (2, 1.2)]]
        case .server where node.isDoor:
            let door = IsoShapes.roundedRect(x0: -3.6, y0: -5.5, x1: 3.6, y1: 5.5, radius: 1.6, steps: 3).map { ($0.u, $0.v) }
            return [door + [door[0]], [(1.6, 0.4), (1.6, 0.5)], [(-5.5, 5.5), (5.5, 5.5)]]
        case .server:
            return [[(-4.5, -5), (0.5, 0), (-4.5, 5)], [(2.5, 4), (7.5, 4)]]
        }
    }
}

/// The map's input from what the app already read: the configuration's
/// machines and each Caddy machine's published sites.
enum NetworkMapSource {
    static func input(machines: [ConfiguredMachine], sites: [String: MachineSitesState]) -> NetworkMapInput {
        NetworkMapInput(
            machines: machines.map { machine in
                NetworkMapInput.Machine(
                    name: machine.name, location: machine.location, hosts: machine.hosts, isSelf: machine.isSelf,
                    isLocalVM: machine.isLocalVM,
                    hasCaddy: CaddyDetection.hasCaddy(installedPackageNames: Set(machine.packages)),
                    workspaces: machine.workspaces)
            },
            sites: machines.flatMap { machine in
                (sites[machine.name]?.rows ?? []).map { row in
                    NetworkMapInput.Site(
                        host: row.site.host, servingMachine: machine.name,
                        workspace: row.site.workspace ?? row.resolvedWorkspace)
                }
            })
    }
}
