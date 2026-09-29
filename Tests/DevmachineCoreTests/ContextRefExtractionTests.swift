import XCTest
@testable import DevmachineCore

final class ContextRefExtractionTests: XCTestCase {
    private func blob(_ text: String, ts: String = "2026-01-01T00:00:00Z") -> ContextRefBlob {
        ContextRefBlob(text: text, timestamp: ts)
    }

    func testExtractsGitHubPullRequestURL() {
        let refs = contextExtractRefs(
            blobs: [blob("see https://github.com/acme/dash/pull/42 for details")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertEqual(refs.github.count, 1)
        let ref = refs.github["acme/dash#42"]
        XCTAssertEqual(ref?.host, "github.com")
        XCTAssertEqual(ref?.repo, "acme/dash")
        XCTAssertEqual(ref?.num, 42)
        XCTAssertEqual(ref?.count, 1)
    }

    func testExtractsEnterpriseHostPullRequestURL() {
        let refs = contextExtractRefs(
            blobs: [blob("https://github.example.net/acme/dash/pull/7")],
            defaultRepo: nil, githubHosts: ["github.com", "github.example.net"]
        )
        XCTAssertEqual(refs.github["acme/dash#7"]?.host, "github.example.net")
    }

    func testGhCommandWithRepoFlagIsExtracted() {
        let refs = contextExtractRefs(
            blobs: [blob("run: gh pr view 12 -R acme/dash --json state")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertEqual(refs.github["acme/dash#12"]?.num, 12)
    }

    func testGhCommandWithoutRepoFallsBackToDefault() {
        let refs = contextExtractRefs(
            blobs: [blob("gh pr checks 9")],
            defaultRepo: "acme/dash", githubHosts: ["github.com"]
        )
        XCTAssertEqual(refs.github["acme/dash#9"]?.num, 9)
    }

    func testGhCommandWithoutRepoAndNoDefaultIsSkipped() {
        let refs = contextExtractRefs(
            blobs: [blob("gh pr checks 9")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertTrue(refs.github.isEmpty)
    }

    func testGhListCommandNamesNoPullRequest() {
        let refs = contextExtractRefs(
            blobs: [blob("gh pr list --limit 15")],
            defaultRepo: "acme/dash", githubHosts: ["github.com"]
        )
        XCTAssertTrue(refs.github.isEmpty)
    }

    func testGhCommandDoesNotMistakeAFlagValueForTheNumber() {
        let refs = contextExtractRefs(
            blobs: [blob("gh pr view --interval 15")],
            defaultRepo: "acme/dash", githubHosts: ["github.com"]
        )
        XCTAssertTrue(refs.github.isEmpty)
    }

    func testGenericLinkIsCaptured() {
        let refs = contextExtractRefs(
            blobs: [blob("see https://linear.app/acme/issue/ABC-123")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertEqual(refs.links.count, 1)
        XCTAssertNotNil(refs.links["https://linear.app/acme/issue/ABC-123"])
    }

    func testNoiseExtensionLinksAreSkipped() {
        let refs = contextExtractRefs(
            blobs: [blob("https://example.com/logo.svg")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertTrue(refs.links.isEmpty)
    }

    func testNoiseHostPrefixLinksAreSkipped() {
        let refs = contextExtractRefs(
            blobs: [blob("https://cdn.example.com/thing")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertTrue(refs.links.isEmpty)
    }

    func testTemplateStringLinkIsSkipped() {
        let refs = contextExtractRefs(
            blobs: [blob("https://example.com/{id}/path")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        XCTAssertTrue(refs.links.isEmpty)
    }

    func testMergeCombinesCountsAndKeepsLatestTimestamp() {
        var a = contextExtractRefs(
            blobs: [blob("https://github.com/acme/dash/pull/1", ts: "2026-01-01T00:00:00Z")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        let b = contextExtractRefs(
            blobs: [blob("https://github.com/acme/dash/pull/1", ts: "2026-01-02T00:00:00Z")],
            defaultRepo: nil, githubHosts: ["github.com"]
        )
        a.merge(b)
        XCTAssertEqual(a.github["acme/dash#1"]?.count, 2)
        XCTAssertEqual(a.github["acme/dash#1"]?.lastTimestamp, "2026-01-02T00:00:00Z")
    }

    func testMapLinksDeduplicatesByIssueKey() {
        let links = contextMapLinks([
            (url: "https://linear.app/acme/issue/ABC-123/title-a", count: 1, lastTimestamp: ""),
            (url: "https://linear.app/acme/issue/ABC-123", count: 1, lastTimestamp: ""),
        ])
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.label, "ABC-123")
        XCTAssertEqual(links.first?.kind, "linear")
    }

    func testServiceOfNamesTheDomainsSecondToLastLabel() {
        XCTAssertEqual(contextServiceOf("https://gist.githubusercontent.com/acme/x"), "github")
        XCTAssertEqual(contextServiceOf("https://linear.app/acme/issue/ABC-1"), "linear")
    }
}
