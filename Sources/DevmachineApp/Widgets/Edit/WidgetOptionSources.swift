import SwiftUI
import DevmachineCore
import HarnessUsageKit

/// The one place that knows where each `option_sources` key's options live.
/// Every chooser reads it; tests hand it closures.
@MainActor
struct WidgetOptionSources {
    var machines: () -> [ChoiceOption]
    var workspaces: () -> [ChoiceOption]
    var harnesses: () -> [ChoiceOption]

    static let none = WidgetOptionSources(machines: { [] }, workspaces: { [] }, harnesses: { [] })

    func options(_ source: WidgetOptionSource) -> [ChoiceOption] {
        switch source {
        case .machines: return machines()
        case .workspaces: return workspaces()
        case .harnesses: return harnesses()
        }
    }

    static func harnessOptions(states: [HarnessUsageState], title: (String) -> String?) -> [ChoiceOption] {
        states.map { ChoiceOption(id: $0.harnessID, label: title($0.harnessID) ?? $0.harnessID) }
    }

    static func live(
        stats: StatsStore, model: AppModel, usage: HarnessUsageStore, facade: HarnessSettingsFacade
    ) -> WidgetOptionSources {
        WidgetOptionSources(
            machines: { stats.machines.map { ChoiceOption(id: $0.name, label: $0.name) } },
            workspaces: { model.visibleWorkspaces.map { ChoiceOption(id: $0.name, label: $0.name) } },
            harnesses: {
                harnessOptions(states: usage.states) { facade.descriptor(for: HarnessID(rawValue: $0))?.shortTitle }
            })
    }
}

private struct WidgetOptionSourcesKey: EnvironmentKey {
    static var defaultValue: WidgetOptionSources { MainActor.assumeIsolated { .none } }
}

extension EnvironmentValues {
    var widgetOptionSources: WidgetOptionSources {
        get { self[WidgetOptionSourcesKey.self] }
        set { self[WidgetOptionSourcesKey.self] = newValue }
    }
}
