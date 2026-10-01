import XCTest
@testable import DevmachineCore

final class PublishProgressTests: XCTestCase {
    private let host = "app.example.com"

    private func published(_ json: String, stderr: String = "", exit: Int32 = 0) -> PublishProgress {
        .finished(.publish, host: host, output: CLIOutput(stdout: json, stderr: stderr, exitCode: exit))
    }

    func testARunningPublishNamesTheHostAndWaitsOnEachStep() {
        let progress = PublishProgress.running(.publish, host: host)

        XCTAssertEqual(progress.headline, "Publishing app.example.com…")
        XCTAssertEqual(progress.steps.map(\.id), [.dns, .caddy])
        XCTAssertEqual(progress.steps.map(\.state), [.running, .waiting])
        XCTAssertEqual(progress.outcome, .running)
        XCTAssertFalse(progress.isFinished)
    }

    func testAnAppliedRouteIsLive() {
        let progress = published(
            #"{"host":"app.example.com","port":8080,"workspace":"alice","applied":true,"status":"published"}"#,
            stderr: "published: https://app.example.com -> alice:8080 on box.\n")

        XCTAssertEqual(progress.outcome, .live(URL(string: "https://app.example.com")!))
        XCTAssertEqual(progress.headline, "Live: https://app.example.com")
        XCTAssertEqual(progress.steps.map(\.state), [.done, .done])
        XCTAssertEqual(progress.step(.caddy)?.title, "Caddy route applied")
        XCTAssertTrue(progress.isFinished)
        XCTAssertTrue(progress.changedTheMachine)
    }

    func testAPendingRouteIsSavedWithTheReason() {
        let progress = published(
            #"{"host":"app.example.com","port":8080,"workspace":"alice","applied":false,"status":"pending","note":"box could not be reached"}"#)

        XCTAssertEqual(progress.outcome, .saved(reason: "box could not be reached"))
        XCTAssertEqual(progress.headline, "Saved; will apply on next sync")
        XCTAssertEqual(progress.step(.caddy)?.state, .attention)
        XCTAssertEqual(progress.step(.caddy)?.detail, "box could not be reached")
    }

    func testARecordToCreateByHandAsksForAttention() {
        let stderr = """
        No installed provider holds example.com. Create this record by hand:

          app\tA\t203.0.113.10

        Check it with `devmachine dns status app.example.com`.
        """
        let progress = published(
            #"{"host":"app.example.com","port":8080,"workspace":"alice","applied":true,"status":"published"}"#,
            stderr: stderr)

        XCTAssertEqual(progress.step(.dns)?.state, .attention)
        XCTAssertEqual(progress.step(.dns)?.title, "Create the DNS record by hand")
        XCTAssertEqual(progress.step(.dns)?.detail, "app A 203.0.113.10")
        XCTAssertEqual(progress.outcome, .live(URL(string: "https://app.example.com")!))
    }

    func testARefusedRouteFailsWithTheExactStderr() {
        let stderr = "caddy refused the new /etc/caddy/sites.d/alice.caddy, so the old one stays:\nbad port\nhttps://app.example.com is recorded in the configuration and pending: fix it and run `devmachine sync`\n"
        let progress = published(
            #"{"host":"app.example.com","port":8080,"workspace":"alice","applied":false,"status":"pending","note":"caddy refused"}"#,
            stderr: stderr, exit: 1)

        XCTAssertEqual(progress.outcome, .failed(details: stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(progress.headline, "Couldn't publish app.example.com")
        XCTAssertEqual(progress.step(.dns)?.state, .done)
        XCTAssertEqual(progress.step(.caddy)?.state, .failed)
        XCTAssertTrue(progress.changedTheMachine)
    }

    func testAFailureBeforeAnythingWasRecordedSkipsEveryStep() {
        let stderr = "caddy is not on box: add it with `devmachine packages add caddy --machine box` and run `devmachine sync`"
        let progress = published("", stderr: stderr, exit: 1)

        XCTAssertEqual(progress.outcome, .failed(details: stderr))
        XCTAssertEqual(progress.steps.map(\.state), [.skipped, .skipped])
        XCTAssertFalse(progress.changedTheMachine)
    }

    func testAnOlderCLIWithoutJSONIsSavedButSaysItCannotTell() {
        let progress = published("recorded https://app.example.com -> alice:8080 in the configuration.\n")

        guard case .saved(let reason) = progress.outcome else {
            return XCTFail("expected saved, got \(progress.outcome)")
        }
        XCTAssertTrue(reason.contains("0.7.21"))
        XCTAssertTrue(progress.changedTheMachine)
    }

    func testAnEmptyFailureStillSaysSomething() {
        let progress = published("", stderr: "", exit: 2)
        XCTAssertEqual(progress.outcome, .failed(details: "Devmachine CLI failed."))
    }

    func testACLIThatCouldNotStartFails() {
        let progress = PublishProgress.couldNotStart(.publish, host: host, message: "Devmachine CLI was not found")
        XCTAssertEqual(progress.outcome, .failed(details: "Devmachine CLI was not found"))
        XCTAssertTrue(progress.isFinished)
    }

    func testARemovalThatCaddyAppliedIsRemoved() {
        let progress = PublishProgress.finished(.remove, host: host, output: CLIOutput(
            stdout: #"{"host":"app.example.com","workspace":"alice","applied":true,"status":"removed"}"#,
            stderr: "", exitCode: 0))

        XCTAssertEqual(progress.outcome, .removed)
        XCTAssertEqual(progress.headline, "Removed app.example.com")
        XCTAssertEqual(progress.steps.map(\.id), [.config, .caddy])
        XCTAssertEqual(progress.steps.map(\.state), [.done, .done])
    }

    func testAPendingRemovalIsSavedWithTheReason() {
        let progress = PublishProgress.finished(.remove, host: host, output: CLIOutput(
            stdout: #"{"host":"app.example.com","workspace":"alice","applied":false,"status":"pending","note":"box could not be reached (timeout)"}"#,
            stderr: "", exitCode: 0))

        XCTAssertEqual(progress.outcome, .saved(reason: "box could not be reached (timeout)"))
        XCTAssertEqual(progress.headline, "Removed from the configuration; Caddy drops it on next sync")
    }

    func testARunningRemovalSaysSo() {
        let progress = PublishProgress.running(.remove, host: host)
        XCTAssertEqual(progress.headline, "Removing app.example.com…")
        XCTAssertEqual(progress.steps.map(\.state), [.running, .waiting])
    }
}
