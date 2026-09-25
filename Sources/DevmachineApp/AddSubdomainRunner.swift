import Foundation
import DevmachineCore

protocol SiteExposing: Sendable {
    func expose(workspace: String, port: Int, host: String) throws
}

extension DevmachineCLI: SiteExposing {}

@MainActor
final class AddSubdomainRunner {
    private let exposer: any SiteExposing

    init(exposer: any SiteExposing) {
        self.exposer = exposer
    }

    static let stepCount = 2

    func run(
        workspace: String,
        _ request: SubdomainRequest,
        progress: @escaping (String, Int) -> Void
    ) async -> Result<Void, Error> {
        progress("Publishing…", 1)
        let exposer = self.exposer
        do {
            try await Task.detached {
                try exposer.expose(workspace: workspace, port: request.port, host: request.host)
            }.value
            progress("Published", 2)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
