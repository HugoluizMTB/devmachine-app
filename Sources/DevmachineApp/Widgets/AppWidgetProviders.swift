import Foundation
import DevmachineCore
import HarnessUsageKit

/// Where each `app/*` provider's data comes from. Stats keep their own
/// app-wide schedule (one ssh per machine, with backoff), so a widget only
/// makes sure it runs; usage refreshes on the widget's interval.
@MainActor
struct AppWidgetProviders {
    let usage: HarnessUsageStore
    let stats: StatsStore

    func refresh(_ key: WidgetRefreshKey, force: Bool) {
        switch key.provider {
        case "app/harness-usage":
            usage.refresh(harnessID: key.args["harness"] ?? "", force: true)
        case "app/machines":
            if force { stats.refresh() } else { stats.start() }
        default:
            break
        }
    }
}

enum AppWidgetJobs {
    static let appProviderPrefix = "app/"
    static let minimumAppInterval: TimeInterval = 5

    /// A minimized widget and one scrolled out of sight ask for no refresh.
    static func job(for instance: BoardWidget, resolved: ResolvedWidget, isOnScreen: Bool) -> WidgetJob {
        let every = resolved.provider.hasPrefix(appProviderPrefix)
            ? max(minimumAppInterval, resolved.every) : resolved.every
        return WidgetJob(
            instanceID: instance.id,
            key: WidgetRefreshKey(provider: resolved.provider, args: resolved.arguments),
            every: every,
            isActive: isOnScreen && !instance.minimized)
    }
}

@MainActor
final class WidgetRuntimeDriver {
    var providers: AppWidgetProviders?
    private var runtime = WidgetRuntime()
    private var timer: Timer?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func setJobs(_ jobs: [WidgetJob]) {
        runtime.replaceJobs(jobs)
        tick()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow(_ key: WidgetRefreshKey) {
        providers?.refresh(key, force: true)
        runtime.markRan([key], at: now())
    }

    private func tick() {
        guard timer != nil, let providers else { return }
        let date = now()
        let due = runtime.due(now: date)
        for key in due { providers.refresh(key, force: false) }
        runtime.markRan(due, at: date)
    }
}
