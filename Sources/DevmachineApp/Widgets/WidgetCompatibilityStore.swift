import Foundation
import DevmachineCore

struct WidgetCompatibilityDependencies: Sendable {
    var cliVersion: @Sendable () async -> String?
    var packagesOutdated: @Sendable () async -> PackagesOutdated?
    var updater: any CLIUpdating
    var manifest = WidgetAppManifest.current

    static func live() -> WidgetCompatibilityDependencies {
        WidgetCompatibilityDependencies(
            cliVersion: { try? DevmachineCLI.resolve().version() },
            packagesOutdated: {
                (try? DevmachineCLI.resolve().packagesOutdated()).flatMap { try? PackagesOutdated.parse($0) }
            },
            updater: ProcessCLIUpdater())
    }

    static let demo = WidgetCompatibilityDependencies(
        cliVersion: { nil }, packagesOutdated: { nil }, updater: UnavailableCLIUpdater())
}

/// Whether this app's widgets can work with the installed CLI and the
/// pinned packages release. Only an explicit click runs the update.
@MainActor
final class WidgetCompatibilityStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case failed(DMErrorState)
    }

    static let shared = WidgetCompatibilityStore(dependencies: DemoMode.isActive ? .demo : .live())

    @Published private(set) var status: CompatibilityStatus = .unknown
    @Published private(set) var phase: Phase = .idle
    var onUpdated: (@MainActor () -> Void)?

    private let dependencies: WidgetCompatibilityDependencies

    init(dependencies: WidgetCompatibilityDependencies) {
        self.dependencies = dependencies
    }

    var gap: CompatibilityGap? {
        guard case let .behind(gap) = status else { return nil }
        return gap
    }

    var manifest: WidgetAppManifest { dependencies.manifest }

    func check() async {
        let dependencies = self.dependencies
        async let version = dependencies.cliVersion()
        async let outdated = dependencies.packagesOutdated()
        let next = CompatibilityCheck.evaluate(
            manifest: dependencies.manifest, cliVersionOutput: await version, packages: await outdated)
        if next != status { status = next }
        if gap == nil, case .failed = phase { phase = .idle }
    }

    func runUpdate() async {
        guard let gap, phase != .running else { return }
        phase = .running
        let sink = ProcessOutputSink { _ in }
        do {
            _ = try await dependencies.updater.run(gap.command, output: sink.receive)
            phase = .idle
            await check()
            onUpdated?()
        } catch {
            let lines = sink.snapshot.suffix(40).joined(separator: "\n")
            phase = .failed(DMErrorState(
                title: "The update did not finish", message: lines.isEmpty ? error.localizedDescription : lines))
        }
    }
}
