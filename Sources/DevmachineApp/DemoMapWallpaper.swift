#if DEBUG
import SwiftUI
import DevmachineCore

/// Debug builds only. The network map as Home's wallpaper, for
/// `DEVMACHINE_DEMO_WALK=map-wallpaper`: Home over the demo configuration
/// (read through the same stores as outside the walk), over a five-machine
/// fleet, with no machine (the ground alone), and Settings → Appearance with
/// the chip open. `DEVMACHINE_DEMO_WINDOW` checks other window sizes. Nothing runs.
@MainActor
enum DemoMapWallpaper {
    static let screens: [DemoSnapshots.Screen] = [
        .init(id: "map-wallpaper-home", fileName: "180-home-network-map.png", settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-fleet", fileName: "181-home-network-map-fleet.png", settleNanoseconds: 1_500_000_000),
        .init(id: "map-wallpaper-empty", fileName: "182-home-network-map-empty.png", settleNanoseconds: 700_000_000),
        .init(id: "map-wallpaper-appearance", fileName: "183-appearance-network-map.png",
              settleNanoseconds: 1_200_000_000),
    ]

    static func handles(_ id: String) -> Bool { screens.contains { $0.id == id } }

    static func prepare(_ id: String, model: AppModel, settings: SettingsStore, caddy: CaddyStore) async {
        var value = settings.settings ?? DemoData.settings
        value.wallpaper = .networkMap
        settings.settings = value
        model.settings = value

        if id == "map-wallpaper-appearance" {
            DemoSnapshots.setupInitialSection = .appearance
            model.showPage(.setup)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        switch id {
        case "map-wallpaper-fleet":
            seed(DemoMachinesMap.fleet, sites: DemoMachinesMap.sites(for: "map-fleet"), caddy: caddy)
        case "map-wallpaper-empty":
            seed(DemoData.noMachinesSnapshot, sites: [:], caddy: caddy)
        case "map-wallpaper-appearance":
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
