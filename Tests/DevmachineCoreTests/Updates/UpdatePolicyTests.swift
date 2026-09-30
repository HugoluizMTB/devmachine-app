import XCTest
@testable import DevmachineCore

final class UpdatePolicyTests: XCTestCase {
    private let current = SemanticVersion("0.1.2")!

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, isDraft: draft, isPrerelease: prerelease)
    }

    func testANewerReleaseIsAvailable() {
        let newer = release("v0.1.3")
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: newer, skippedVersion: nil), .available(newer))
    }

    func testTheSameOrAnOlderReleaseIsUpToDate() {
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: release("v0.1.2"), skippedVersion: nil), .upToDate)
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: release("v0.1.1"), skippedVersion: nil), .upToDate)
    }

    func testDraftsAndPrereleasesAreIgnored() {
        XCTAssertEqual(
            UpdatePolicy.evaluate(current: current, release: release("v0.2.0", draft: true), skippedVersion: nil),
            .upToDate)
        XCTAssertEqual(
            UpdatePolicy.evaluate(current: current, release: release("v0.2.0", prerelease: true), skippedVersion: nil),
            .upToDate)
        XCTAssertEqual(
            UpdatePolicy.evaluate(current: current, release: release("v0.2.0-beta.1"), skippedVersion: nil),
            .upToDate)
    }

    func testATagThatIsNotAVersionIsIgnored() {
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: release("nightly"), skippedVersion: nil), .upToDate)
    }

    func testASkippedVersionIsReportedAsSkipped() {
        let newer = release("v0.1.3")
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: newer, skippedVersion: "0.1.3"), .skipped(newer))
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: newer, skippedVersion: "v0.1.3"), .skipped(newer))
    }

    func testSkippingAnOlderVersionDoesNotHideANewerOne() {
        let newer = release("v0.1.4")
        XCTAssertEqual(UpdatePolicy.evaluate(current: current, release: newer, skippedVersion: "0.1.3"), .available(newer))
    }
}
