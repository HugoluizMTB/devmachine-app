#if DEBUG
import SwiftUI
import DevmachineCore

/// Debug builds only. The network map as Home's wallpaper, for
/// `DEVMACHINE_DEMO_WALK=map-wallpaper`: Home with the compact map over the
/// demo configuration (read through the same stores as outside the walk),
/// over a five-machine fleet, with no machine (the ground alone), then the
/// large map over both, and Settings → Appearance's Background picker on
/// the large map, a photo theme and the gradients; last, Home with the
/// sidebar collapsed, where the clock centres in the whole window, with the
/// compact map and with the large one over both configurations.
/// `DEVMACHINE_DEMO_WINDOW` checks other window sizes. Nothing runs.
@MainActor
enum DemoMapWallpaper {
    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "map-wallpaper-home", fileName: "180-home-network-map.png", settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-fleet", fileName: "181-home-network-map-fleet.png", settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-empty", fileName: "182-home-network-map-empty.png", settleNanoseconds: 700_000_000),
        .init(id: "map-wallpaper-appearance", fileName: "183-appearance-network-map.png",
              settleNanoseconds: 1_200_000_000),
        .init(id: "map-wallpaper-large", fileName: "184-home-network-map-large.png", settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-large-fleet", fileName: "185-home-network-map-large-fleet.png",
              settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-appearance-photo", fileName: "186-appearance-photo.png",
              settleNanoseconds: 2_500_000_000),
        .init(id: "map-wallpaper-appearance-gradient", fileName: "187-appearance-gradient.png",
              settleNanoseconds: 1_200_000_000),
        .init(id: "map-wallpaper-sidebar-collapsed", fileName: "188-home-sidebar-collapsed.png",
              settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-large-collapsed", fileName: "189-home-network-map-large-collapsed.png",
              settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-large-fleet-collapsed", fileName: "190-home-network-map-large-fleet-collapsed.png",
              settleNanoseconds: 1_500_000_000),
    ]

    static func choice(for id: String) -> WallpaperChoice {
        switch id {
        case "map-wallpaper-large", "map-wallpaper-large-fleet", "map-wallpaper-appearance",
             "map-wallpaper-large-collapsed", "map-wallpaper-large-fleet-collapsed":
            return .networkMap(.large)
        case "map-wallpaper-appearance-photo": return .bundled
        case "map-wallpaper-appearance-gradient": return .gradient(name: "peaks")
        default: return .networkMap(.compact)
        }
    }

    static func handles(_ id: String) -> Bool { screens.contains { $0.id == id } }

    static func prepare(_ id: String, model: AppModel, settings: SettingsStore, caddy: CaddyStore) async {
        var value = settings.settings ?? DemoData.settings
        value.wallpaper = choice(for: id)
        settings.settings = value
        model.settings = value
        model.sidebarCollapsed = id.hasSuffix("collapsed")

        if id.hasPrefix("map-wallpaper-appearance") {
            DemoSnapshots.setupInitialSection = .appearance
            model.showPage(.setup)
        } else {
            model.goHome()
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        switch id {
        case "map-wallpaper-fleet", "map-wallpaper-large-fleet", "map-wallpaper-large-fleet-collapsed":
            seed(DemoMachinesMap.fleet, sites: DemoMachinesMap.sites(for: "map-fleet"), caddy: caddy)
        case "map-wallpaper-empty":
            seed(DemoData.noMachinesSnapshot, sites: [:], caddy: caddy)
        case "map-wallpaper-appearance", "map-wallpaper-appearance-photo", "map-wallpaper-appearance-gradient":
            seed(DemoData.machinesSnapshot, sites: DemoData.subdomainStates, caddy: caddy)
        default:
            break
        }
    }

    private static func seed(_ snapshot: MachinesSnapshot, sites: [String: MachineSitesState], caddy: CaddyStore) {
        MachinesStore.shared.seedDemo(snapshot)
        caddy.show(
            machines: snapshot.machines.map { CLIMachine(name: $0.name, isSelf: $0.isSelf) }, states: sites,
            selected: snapshot.machines.first { !$0.isSelf }?.name)
    }
}
#endif
