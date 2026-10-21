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

    func testAProviderThatAnswersWinsOverARunningJob() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(
                declared: ["cloudflare"], answers: [answer("cloudflare", zones: ["example.com"])],
                job: .running(.sync)),
            .ready)
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
        XCTAssertEqual(
            DNSProviderSetup.manualCommands(package: "cloudflare", credential: "cf-token", machine: "main", declared: false),
            [
                "devmachine packages add cloudflare --machine main",
                "devmachine secrets set cf-token",
                "devmachine sync --machine main",
                "devmachine credentials push --machine main",
            ])
        XCTAssertEqual(
            DNSProviderSetup.manualCommands(package: "cloudflare", credential: "cloudflare", machine: "main", declared: true),
            [
                "devmachine secrets set cloudflare",
                "devmachine sync --machine main",
                "devmachine credentials push --machine main",
            ])
    }

    func testANewCLIDecidesByKindAlone() {
        XCTAssertTrue(DNSProviderCatalog.isProvider(kind: "dns", summary: nil, listReportsKinds: true))
        XCTAssertTrue(DNSProviderCatalog.isProvider(kind: "DNS", summary: nil, listReportsKinds: true))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: nil, summary: "DNS zones on X.", listReportsKinds: true))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: "role", summary: "DNS zones on X.", listReportsKinds: true))
    }

    func testAnOlderCLIFallsBackToTheSummary() {
        XCTAssertTrue(DNSProviderCatalog.isProvider(kind: nil, summary: "DNS zones on Hostinger.", listReportsKinds: false))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: nil, summary: "A reverse proxy.", listReportsKinds: false))
        XCTAssertFalse(DNSProviderCatalog.isProvider(kind: nil, summary: nil, listReportsKinds: false))
    }

    func testTheSecretNameComesFromTheDeclaredCredential() {
        let declared = [
            PackageCredential(name: "cf-login", kind: "login"),
            PackageCredential(name: "cf-token", kind: "secret", scope: "machine", env: "CLOUDFLARE_API_TOKEN"),
        ]
        XCTAssertEqual(DNSProviderCatalog.secretName(package: "cloudflare", credentials: declared), "cf-token")
        XCTAssertEqual(
            DNSProviderCatalog.secretName(package: "cloudflare", credentials: [PackageCredential(name: "x", kind: "file")]),
            "x")
        XCTAssertEqual(DNSProviderCatalog.secretName(package: "cloudflare", credentials: []), "cloudflare")
        XCTAssertEqual(DNSProviderCatalog.secretName(package: "cloudflare", credentials: nil), "cloudflare")
    }

    func testZonesAreReadFromACommaListAndRefuseAnythingButAName() {
        XCTAssertEqual(DNSProviderCatalog.zones(from: " example.com, example.net ,"), ["example.com", "example.net"])
        XCTAssertEqual(DNSProviderCatalog.zones(from: "  "), [])
        XCTAssertNil(DNSProviderCatalog.zones(from: "example.com]: x"))
        XCTAssertNil(DNSProviderCatalog.zones(from: "a b.com"))
    }

    func testZonesAreSetThroughMachinesEditAsAYAMLList() {
        XCTAssertEqual(
            DNSProviderSetup.zonesArguments(setting: "hostinger.zones", machine: "main", zones: ["example.com", "example.net"]),
            ["machines", "edit", "main", "--set", "hostinger.zones=[example.com, example.net]", "--yes"])
    }

    func testOnlyACLIWithMachinesEditSetsTheZones() {
        XCTAssertFalse(DNSProviderSetup.canEditMachineSettings(cliVersion: nil))
        XCTAssertFalse(DNSProviderSetup.canEditMachineSettings(cliVersion: SemanticVersion("0.7.26")))
        XCTAssertTrue(DNSProviderSetup.canEditMachineSettings(cliVersion: SemanticVersion("0.7.27")))
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

    func testEveryPackageStateFromOneMachine() {
        let answers = [
            answer("cloudflare", zones: ["example.com"]),
            answer("hostinger", error: "HOSTINGER_API_TOKEN is not set"),
            answer("godaddy"),
        ]
        let declared = ["cloudflare", "hostinger", "godaddy", "route53"]
        XCTAssertEqual(DNSProviderSetup.evaluate(package: "cloudflare", declared: declared, answers: answers, job: nil), .ready)
        XCTAssertEqual(
            DNSProviderSetup.evaluate(package: "hostinger", declared: declared, answers: answers, job: nil),
            .tokenMissing(error: "HOSTINGER_API_TOKEN is not set"))
        XCTAssertEqual(DNSProviderSetup.evaluate(package: "godaddy", declared: declared, answers: answers, job: nil), .noZones)
        XCTAssertEqual(DNSProviderSetup.evaluate(package: "route53", declared: declared, answers: answers, job: nil), .notSynced)
        XCTAssertEqual(DNSProviderSetup.evaluate(package: "desec", declared: declared, answers: answers, job: nil), .notInstalled)
    }

    func testAJobWinsOverTheAnswer() {
        XCTAssertEqual(
            DNSProviderSetup.evaluate(package: "godaddy", declared: ["godaddy"], answers: [], job: .running(.remove)),
            .working(.remove))
        XCTAssertEqual(
            DNSProviderSetup.evaluate(
                package: "godaddy", declared: [], answers: [], job: .failed(.install, cause: "x", details: "y")),
            .failed(.install, cause: "x", details: "y"))
    }

    func testStateLabelsAreShort() {
        XCTAssertEqual(DNSProviderState.notInstalled.label, "Not installed")
        XCTAssertEqual(DNSProviderState.tokenMissing(error: "e").label, "Token missing")
        XCTAssertEqual(DNSProviderState.ready.label, "Ready")
        XCTAssertEqual(DNSProviderState.working(.sync).label, "Working…")
    }

    func testRemoveNamesTheMachineThenSyncsEverythingThenForgetsTheSecret() {
        XCTAssertEqual(
            DNSProviderSetup.removeArguments(package: "godaddy", machine: "main"),
            ["packages", "rm", "godaddy", "--machine", "main", "--yes"])
        XCTAssertEqual(DNSProviderSetup.fullSyncSteps(machine: "main"), [["sync", "--machine", "main", "--yes"]])
        XCTAssertEqual(DNSProviderSetup.secretRemoveArguments(credential: "godaddy"), ["secrets", "rm", "godaddy"])
    }
}
