import SwiftUI
import DevmachineCore

/// Home's network map wallpaper: Settings → Machines' map, drawn quiet and
/// centred, from the same stores. It reads nothing of its own: the
/// configuration comes from `MachinesStore` (read once if nobody has yet; the
/// config folder watcher reloads it), the sites from `CaddyStore`'s cache,
/// asked again only past their TTL and never for DNS. Before any data, and
/// with no machine at all, only the ground shows.
struct NetworkMapWallpaper: View {
    var placement = NetworkMapPlacement.whole
    var minimumMargin = NetworkMapBackdrop.minimumMargin
    @ObservedObject private var machines = MachinesStore.shared
    @EnvironmentObject private var caddy: CaddyStore

    var body: some View {
        NetworkMapView(
            decorative: NetworkMap.build(
                NetworkMapSource.input(machines: machines.machines, sites: caddy.sitesByMachine)),
            placement: placement, minimumMargin: minimumMargin)
            .background(NetworkMapGround())
            .task {
                if machines.snapshot == nil { await machines.load() }
                caddy.appearForMap()
            }
    }
}

/// What the map stands on: the map's own dark plate, a little lighter in the
/// middle. Also the terminals' ambient backdrop when the map is the
/// wallpaper, where tiles and text behind a translucent pane would be noise.
struct NetworkMapGround: View {
    var body: some View {
        RadialGradient(
            colors: [Color(hex: 0x161B22), Color(hex: 0x07090C)],
            center: .center, startRadius: 0, endRadius: 900)
            .allowsHitTesting(false)
    }
}
