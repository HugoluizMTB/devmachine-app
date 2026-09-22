import XCTest
@testable import DevmachineCore

final class PRCoreTests: XCTestCase {
    private func pr(_ n: Int, repo: String, head: String, base: String,
                     draft: Bool = false, review: String = "", ci: CIState = .none) -> PullRequest {
        PullRequest(number: n, title: "PR \(n)", repo: repo, url: "u", isDraft: draft,
                    reviewDecision: review, headRefName: head, baseRefName: base, ci: ci)
    }

    // MARK: - rollupState

    func testRollupEmptyIsNone() {
        XCTAssertEqual(rollupState(from: []), .none)
    }

    func testRollupSingleSuccess() {
        XCTAssertEqual(rollupState(from: [
            CheckContext(status: "COMPLETED", conclusion: "SUCCESS", state: nil)
        ]), .success)
    }

    func testRollupAnyFailureWins() {
        XCTAssertEqual(rollupState(from: [
            CheckContext(status: "COMPLETED", conclusion: "SUCCESS", state: nil),
            CheckContext(status: "COMPLETED", conclusion: "FAILURE", state: nil),
        ]), .failure)
    }

    func testRollupRunningWithNoFailureIsPending() {
        XCTAssertEqual(rollupState(from: [
            CheckContext(status: "COMPLETED", conclusion: "SUCCESS", state: nil),
            CheckContext(status: "IN_PROGRESS", conclusion: nil, state: nil),
        ]), .pending)
    }

    func testRollupLegacyPendingState() {
        XCTAssertEqual(rollupState(from: [CheckContext(status: nil, conclusion: nil, state: "PENDING")]), .pending)
    }

    func testRollupLegacyErrorState() {
        XCTAssertEqual(rollupState(from: [CheckContext(status: nil, conclusion: nil, state: "ERROR")]), .failure)
    }

    func testRollupTimedOutIsFailure() {
        XCTAssertEqual(rollupState(from: [CheckContext(status: "COMPLETED", conclusion: "TIMED_OUT", state: nil)]), .failure)
    }

    func testRollupCancelledIsFailure() {
        XCTAssertEqual(rollupState(from: [CheckContext(status: "COMPLETED", conclusion: "CANCELLED", state: nil)]), .failure)
    }

    func testRollupOnlySkippedIsNone() {
        XCTAssertEqual(rollupState(from: [CheckContext(status: "COMPLETED", conclusion: "SKIPPED", state: nil)]), .none)
    }

    // MARK: - rowState

    func testDraftWins() {
        XCTAssertEqual(pr(1, repo: "a/b", head: "h", base: "main", draft: true).rowState, .draft)
    }

    func testApproved() {
        XCTAssertEqual(pr(1, repo: "a/b", head: "h", base: "main", review: "APPROVED").rowState, .approved)
    }

    func testChangesRequested() {
        XCTAssertEqual(pr(1, repo: "a/b", head: "h", base: "main", review: "CHANGES_REQUESTED").rowState, .changesRequested)
    }

    func testDefaultOpen() {
        XCTAssertEqual(pr(1, repo: "a/b", head: "h", base: "main").rowState, .open)
    }

    func testDraftBeatsApproved() {
        XCTAssertEqual(pr(1, repo: "a/b", head: "h", base: "main", draft: true, review: "APPROVED").rowState, .draft)
    }

    // MARK: - lifecycle rowState

    func testMergedBeatsReview() {
        XCTAssertEqual(rowState(lifecycle: .merged, review: .approved), .merged)
        XCTAssertEqual(rowState(lifecycle: .merged, review: .changesRequested), .merged)
    }

    func testClosedBeatsReview() {
        XCTAssertEqual(rowState(lifecycle: .closed, review: .approved), .closed)
    }

    func testDraftBeatsReviewInLifecycle() {
        XCTAssertEqual(rowState(lifecycle: .draft, review: .approved), .draft)
    }

    func testOpenTakesTheReview() {
        XCTAssertEqual(rowState(lifecycle: .open, review: .approved), .approved)
        XCTAssertEqual(rowState(lifecycle: .open, review: .changesRequested), .changesRequested)
        XCTAssertEqual(rowState(lifecycle: .open, review: .required), .open)
        XCTAssertEqual(rowState(lifecycle: .open, review: .none), .open)
    }

    func testUnknownLifecycleStillReadsTheReview() {
        XCTAssertEqual(rowState(lifecycle: .unknown, review: .approved), .approved)
    }

    func testLifecycleFromInferStrings() {
        XCTAssertEqual(PRLifecycle(inferState: "merged"), .merged)
        XCTAssertEqual(PRLifecycle(inferState: "OPEN"), .open)
        XCTAssertEqual(PRLifecycle(inferState: "closed"), .closed)
        XCTAssertEqual(PRLifecycle(inferState: "draft"), .draft)
        XCTAssertEqual(PRLifecycle(inferState: "nonsense"), .unknown)
    }

    func testReviewFromInferStrings() {
        XCTAssertEqual(ReviewState(inferReview: "approved"), .approved)
        XCTAssertEqual(ReviewState(inferReview: "changes"), .changesRequested)
        XCTAssertEqual(ReviewState(inferReview: "required"), .required)
        XCTAssertEqual(ReviewState(inferReview: "none"), .none)
    }

    func testCIFromInferStrings() {
        XCTAssertEqual(CIState(inferCI: "pass"), .success)
        XCTAssertEqual(CIState(inferCI: "fail"), .failure)
        XCTAssertEqual(CIState(inferCI: "pending"), .pending)
        XCTAssertEqual(CIState(inferCI: "none"), .none)
        XCTAssertEqual(CIState(inferCI: ""), .none)
    }

    func testRowStateLabels() {
        XCTAssertEqual(RowState.merged.label, "Merged")
        XCTAssertEqual(RowState.closed.label, "Closed")
    }

    // MARK: - buildStackForest

    func testStackForestChainOrderedRootToTop() {
        let prs = [
            pr(12, repo: "acme/web", head: "c", base: "b"),
            pr(10, repo: "acme/web", head: "a", base: "main"),
            pr(11, repo: "acme/web", head: "b", base: "a"),
            pr(5, repo: "solo/x", head: "fix", base: "main"),
        ]
        let forest = buildStackForest(prs)
        let acme = forest.filter { $0.pr.repo == "acme/web" }
        XCTAssertEqual(acme.map { $0.pr.number }, [10, 11, 12])
        XCTAssertEqual(acme.map { $0.depth }, [0, 1, 2])

        let solo = forest.filter { $0.pr.repo == "solo/x" }
        XCTAssertEqual(solo.count, 1)
        XCTAssertEqual(solo[0].depth, 0)
    }

    func testStackForestCycleDoesNotHangOrDrop() {
        let cyclic = [
            pr(1, repo: "r/r", head: "x", base: "y"),
            pr(2, repo: "r/r", head: "y", base: "x"),
        ]
        XCTAssertEqual(buildStackForest(cyclic).count, 2)
    }

    // MARK: - mergeOwners

    func testMergeOwnersAllPinnedFirstAndDeduped() {
        let owners = mergeOwners(orgs: ["Zorg", "acme"], resultOwners: ["9Gamma", "acme"], myLogin: "alice")
        XCTAssertEqual(owners.first, allOwnersSentinel)
        XCTAssertTrue(owners.contains("9Gamma"))
        XCTAssertTrue(owners.contains("alice"))
        XCTAssertEqual(Set(owners).count, owners.count)
        XCTAssertEqual(owners, [allOwnersSentinel] + ["9Gamma", "acme", "alice", "Zorg"])
    }

    func testMergeOwnersEmptiesDropped() {
        XCTAssertEqual(mergeOwners(orgs: [], resultOwners: [""], myLogin: nil), [allOwnersSentinel])
    }

    // MARK: - orderOwners

    func testOrderOwnersFavoritesFirstInListOrder() {
        let owners = [allOwnersSentinel, "acme", "beta", "gamma", "zeta"]
        let ordered = orderOwners(owners, favorites: ["gamma", "zeta"])
        XCTAssertEqual(ordered.first, allOwnersSentinel)
        XCTAssertEqual(Array(ordered.dropFirst(1).prefix(2)), ["gamma", "zeta"])
        XCTAssertEqual(Array(ordered.suffix(2)), ["acme", "beta"])
        XCTAssertEqual(Set(ordered), Set(owners))
    }

    func testOrderOwnersMissingFavoriteStillSurfaced() {
        let ordered = orderOwners([allOwnersSentinel, "acme"], favorites: ["ghost"])
        XCTAssertTrue(ordered.contains("ghost"))
    }

    func testOrderOwnersNoFavoritesUnchanged() {
        let owners = [allOwnersSentinel, "acme", "beta", "gamma", "zeta"]
        XCTAssertEqual(orderOwners(owners, favorites: []), owners)
    }

    func testOrderOwnersAllNeverDuplicated() {
        let owners = [allOwnersSentinel, "acme", "beta", "gamma", "zeta"]
        XCTAssertFalse(orderOwners(owners, favorites: [allOwnersSentinel]).dropFirst().contains(allOwnersSentinel))
    }

    // MARK: - RefreshCoordinator

    func testRefreshCoordinatorSoleGenerationMayApply() {
        var coordinator = RefreshCoordinator()
        let gen = coordinator.begin()
        XCTAssertTrue(coordinator.mayApply(gen))
    }

    func testRefreshCoordinatorSupersededGenerationBlocked() {
        var coordinator = RefreshCoordinator()
        let first = coordinator.begin()
        _ = coordinator.begin()
        XCTAssertFalse(coordinator.mayApply(first))
    }

    func testRefreshCoordinatorLatestGenerationWins() {
        var coordinator = RefreshCoordinator()
        _ = coordinator.begin()
        let latest = coordinator.begin()
        XCTAssertTrue(coordinator.mayApply(latest))
    }

    // MARK: - decode smoke

    func testDecodeSearchPRsParsesGhFields() throws {
        let json = """
        [
          {"number": 42, "title": "Add feature", "isDraft": true,
           "repository": {"nameWithOwner": "acme/repo"}}
        ]
        """
        let results = try decodeSearchPRs(Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].number, 42)
        XCTAssertEqual(results[0].title, "Add feature")
        XCTAssertTrue(results[0].isDraft)
        XCTAssertEqual(results[0].repository.nameWithOwner, "acme/repo")
    }

    func testDecodePRDetailParsesGhFields() throws {
        let json = """
        {"number": 7, "title": "Fix bug", "url": "https://github.com/acme/repo/pull/7",
         "isDraft": false, "reviewDecision": "APPROVED",
         "headRefName": "fix-bug", "baseRefName": "main",
         "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "SUCCESS", "state": null}]}
        """
        let detail = try decodePRDetail(Data(json.utf8))
        XCTAssertEqual(detail.number, 7)
        XCTAssertEqual(detail.title, "Fix bug")
        XCTAssertEqual(detail.url, "https://github.com/acme/repo/pull/7")
        XCTAssertFalse(detail.isDraft)
        XCTAssertEqual(detail.reviewDecision, "APPROVED")
        XCTAssertEqual(detail.headRefName, "fix-bug")
        XCTAssertEqual(detail.baseRefName, "main")
        XCTAssertEqual(detail.statusCheckRollup?.count, 1)
        XCTAssertEqual(detail.statusCheckRollup?.first?.conclusion, "SUCCESS")
    }
}

final class SessionRecencyTests: XCTestCase {
    private struct Ref: SessionMentioned, Equatable {
        let number: Int
        let repo: String
        let lastSeen: String?
    }

    private func ref(_ number: Int, _ lastSeen: String?, repo: String = "acme/dash") -> Ref {
        Ref(number: number, repo: repo, lastSeen: lastSeen)
    }

    func testNewestMentionComesFirst() {
        let rows = [ref(1, "2026-01-01T00:00:00Z"),
                    ref(2, "2026-01-03T00:00:00Z"),
                    ref(3, "2026-01-02T00:00:00Z")]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [2, 3, 1])
    }

    func testFractionalSecondsCompareWithWholeOnes() {
        let rows = [ref(1, "2026-01-01T00:00:00Z"),
                    ref(2, "2026-01-01T00:00:00.500Z")]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [2, 1])
    }

    func testOffsetsAreComparedAsInstants() {
        let rows = [ref(1, "2026-01-01T00:00:00Z"),
                    ref(2, "2026-01-01T00:30:00+02:00")]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [1, 2])
    }

    func testRowsWithoutAMentionSinkBelowTheDatedOnes() {
        let rows = [ref(1, nil), ref(2, "2026-01-01T00:00:00Z"), ref(3, nil)]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [2, 3, 1])
    }

    func testUndatedRowsFallBackToTheHigherNumber() {
        let rows = [ref(7, nil), ref(41, nil), ref(12, nil)]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [41, 12, 7])
    }

    func testUnparsableDatesCountAsNoMention() {
        let rows = [ref(1, "yesterday"), ref(2, "2026-01-01T00:00:00Z")]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [2, 1])
    }

    func testSameMentionKeepsTheHigherNumberOnTop() {
        let rows = [ref(3, "2026-01-01T00:00:00Z", repo: "acme/api"),
                    ref(9, "2026-01-01T00:00:00Z")]
        XCTAssertEqual(orderByLastMention(rows).map(\.number), [9, 3])
    }

    func testTheSameRowTwiceKeepsTheGivenOrder() {
        let rows = [ref(4, "2026-01-01T00:00:00Z", repo: "acme/api"),
                    ref(4, "2026-01-01T00:00:00Z", repo: "acme/dash")]
        XCTAssertEqual(orderByLastMention(rows).map(\.repo), ["acme/api", "acme/dash"])
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(orderByLastMention([Ref]()), [])
    }
}
