import Foundation
import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

private final class FakeSiteExposer: SiteExposing, @unchecked Sendable {
    struct Call: Equatable {
        let workspace: String
        let port: Int
        let host: String
    }

    private let lock = NSLock()
    private var storedCalls: [Call] = []

    func expose(workspace: String, port: Int, host: String) throws {
        lock.lock()
        storedCalls.append(Call(workspace: workspace, port: port, host: host))
        lock.unlock()
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

@MainActor
final class AddSubdomainRunnerTests: XCTestCase {
    func testRunnerDelegatesExactlyOnceToCLI() async {
        let fake = FakeSiteExposer()
        let runner = AddSubdomainRunner(exposer: fake)
        let request = SubdomainRequest(host: "app.example.com", port: 8080, managedDNS: true)

        let result = await runner.run(workspace: "alice", request) { _, _ in }

        if case .failure(let error) = result {
            XCTFail("unexpected failure: \(error)")
        }
        XCTAssertEqual(fake.calls, [.init(workspace: "alice", port: 8080, host: "app.example.com")])
    }
}
