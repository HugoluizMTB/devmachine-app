import XCTest
@testable import DevmachineCore

final class DNSProviderSetupTests: XCTestCase {
    private func answer(_ name: String, zones: [String] = [], error: String? = nil) -> DNSProviderAnswer {
        DNSProviderAnswer(name: name, zones: zones, error: error)
    }

    func testNothingReadIsUnknownAndShowsNoCard() {
        XCTAssertEqual(DNSProviderSetup.evaluate(declared: nil, answers: nil, job: nil), .unknown)
    }

    func testNoProviderDeclaredOrAppliedIsNoneInstalled() {
        XCTAssertEqual(DNSProviderSetup.evaluate(declared: [], answers: [], job: nil), .noneInstalled)
        XCTAssertEqual(DNSProviderSetup.evaluate(declared: [], answers: nil, job: nil), .noneInstalled)
        XCTAssertEqual(DNSProviderSetup.evaluate(declared: nil, answers: [], job: nil), .noneInstalled)
    }

    func testDeclaredButNotInTheAnswerIsNotSynced() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(declared: ["hostinger"], answers: [], job: nil),
            .notSynced(provider: "hostinger", problem: .notApplied))
    }

    func testDeclaredWhileTheMachineCouldNotBeAskedFailsOpen() {
        XCTAssertEqual(DNSProviderSetup.evaluate(declared: ["hostinger"], answers: nil, job: nil), .unknown)
    }

    func testAProviderThatAnswersWithAnErrorStillNeedsItsToken() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(
                declared: ["hostinger"], answers: [answer("hostinger", error: "HOSTINGER_API_TOKEN is not set")],
                job: nil),
            .notSynced(provider: "hostinger", problem: .providerError("HOSTINGER_API_TOKEN is not set")))
    }

    func testAProviderThatSeesNoZoneIsNotReady() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(declared: ["hostinger"], answers: [answer("hostinger")], job: nil),
            .notSynced(provider: "hostinger", problem: .noZones))
    }

    func testAnyProviderWithZonesIsReady() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(
                declared: ["hostinger", "cloudflare"],
                answers: [answer("hostinger", error: "no token"), answer("cloudflare", zones: ["example.com"])],
                job: nil),
            .ready)
    }

    func testAProviderAppliedButNoLongerDeclaredStillCounts() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(declared: [], answers: [answer("cloudflare")], job: nil),
            .notSynced(provider: "cloudflare", problem: .noZones))
    }

    func testARunningJobWinsOverWhatWasRead() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(declared: [], answers: [], job: .running(.sync)),
            .working(.sync))
    }

    func testAFailedJobShowsUntilAProviderAnswersWithZones() {
        let failed = DNSSetupJob.failed(.sync, cause: "exit status 2", details: "fatal")
        XCTAssertEqual(
            DNSProviderSetup.evaluate(declared: ["hostinger"], answers: [], job: failed),
            .failed(.sync, cause: "exit status 2", details: "fatal"))
        XCTAssertEqual(
            DNSProviderSetup.evaluate(
                declared: ["hostinger"], answers: [answer("hostinger", zones: ["example.com"])], job: failed),
            .ready)
    }

    func testAFinishedSyncThatStillSeesNoZonesStaysOnRunSync() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(declared: ["hostinger"], answers: [answer("hostinger")], job: .finished),
            .notSynced(provider: "hostinger", problem: .noZones))
    }

    func testInstallNamesTheMachineAndNeverAsks() {
        XCTAssertEqual(
            DNSProviderSetup.addArguments(package: "hostinger", machine: "main"),
            ["packages", "add", "hostinger", "--machine", "main", "--yes"])
    }

    func testTheSecretIsReadFromStandardInputNeverFromArguments() {
        let arguments = DNSProviderSetup.secretArguments(credential: "hostinger")
        XCTAssertEqual(arguments, ["secrets", "set", "hostinger", "--stdin"])
        XCTAssertEqual(DNSProviderSetup.secretInput("  tok-123 \n"), Data("tok-123\n".utf8))
    }

    func testAnEmptyOrMultiLineSecretIsRefused() {
        XCTAssertNil(DNSProviderSetup.secretInput("   \n"))
        XCTAssertNil(DNSProviderSetup.secretInput("one\ntwo"))
    }

    func testSyncAppliesOnlyTheProviderThenDeliversItsToken() {
        XCTAssertEqual(DNSProviderSetup.syncSteps(package: "hostinger", machine: "main"), [
            ["sync", "--machine", "main", "--tags", "hostinger", "--yes"],
            ["credentials", "push", "--machine", "main", "--yes"],
        ])
    }

    func testTheManualCommandsMatchWhatTheAppRuns() {
        XCTAssertEqual(DNSProviderSetup.manualCommands(package: "cloudflare", machine: "main", declared: false), [
            "devmachine packages add cloudflare --machine main",
            "devmachine secrets set cloudflare",
            "devmachine sync --machine main",
            "devmachine credentials push --machine main",
        ])
        XCTAssertEqual(DNSProviderSetup.manualCommands(package: "cloudflare", machine: "main", declared: true), [
            "devmachine secrets set cloudflare",
            "devmachine sync --machine main",
            "devmachine credentials push --machine main",
        ])
    }

    func testAPackageIsAProviderByItsKindOrCategory() {
        XCTAssertTrue(DNSProviderCatalog.isProvider(kind: "dns", category: nil, summary: nil))
        XCTAssertTrue(DNSProviderCatalog.isProvider(kind: nil, category: "DNS", summary: nil))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: "role", category: "Web", summary: "DNS zones on X."))
    }

    func testWithoutAKindTheSummaryDecides() {
        XCTAssertTrue(DNSProviderCatalog.isProvider(kind: nil, category: nil, summary: "DNS zones on Hostinger."))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: nil, category: nil, summary: "A reverse proxy."))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: nil, category: nil, summary: nil))
    }

    func testOnlyHostingerHasAZonesSetting() {
        XCTAssertEqual(DNSProviderCatalog.zonesSetting(for: "hostinger"), "hostinger.zones")
        XCTAssertNil(DNSProviderCatalog.zonesSetting(for: "cloudflare"))
    }

    func testTheZonesSnippetIsTheMachineSettingInConfigYAML() {
        XCTAssertEqual(
            DNSProviderCatalog.zonesSnippet(package: "hostinger", machine: "main", zones: " example.com, example.net ,"),
            """
            machines:
              - name: main
                settings:
                  hostinger.zones: [example.com, example.net]
            """)
        XCTAssertEqual(
            DNSProviderCatalog.zonesSnippet(package: "hostinger", machine: "main", zones: ""),
            """
            machines:
              - name: main
                settings:
                  hostinger.zones: [example.com]
            """)
        XCTAssertNil(DNSProviderCatalog.zonesSnippet(package: "cloudflare", machine: "main", zones: "example.com"))
    }
}
