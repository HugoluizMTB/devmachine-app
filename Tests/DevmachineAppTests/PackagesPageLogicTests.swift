import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class PackagesPageLogicTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)
    private let backup = PackageTarget.machine("backup", isSelf: false)
    private let acme = PackageTarget.workspace("acme", machine: "main")

    private func entry(_ name: String, scope: String = "machine") -> PackageEntry {
        PackageEntry(name: name, scope: scope, source: "release", summary: "", category: nil,
                     platforms: [], needs: [], credentialNames: [], installedOn: [])
    }

    func testEachStatusHasItsPill() {
        XCTAssertEqual(PackageRow.pillText(PackagePlacement(target: main, status: .applied)), "main")
        XCTAssertEqual(PackageRow.pillText(PackagePlacement(target: main, status: .pendingInstall)), "main · pending install")
        XCTAssertEqual(PackageRow.pillText(PackagePlacement(target: main, status: .pendingRemove)), "main · pending removal")
        XCTAssertEqual(PackageRow.pillText(PackagePlacement(target: main, status: .appliedAsDependency(of: "gh"))),
                       "main · via gh")
        XCTAssertEqual(PackageRow.color(for: .applied), .green)
        XCTAssertEqual(PackageRow.color(for: .pendingInstall), .orange)
        XCTAssertEqual(PackageRow.color(for: .appliedAsDependency(of: "gh")), .dmMuted)
    }

    func testPlacementsListOnlyTargetsThatHaveThePackageOrWaitForIt() {
        let placements = PackagePlacement.list(
            for: entry("docker"), targets: [main, backup],
            statuses: [main: ["docker": .applied], backup: [:]])
        XCTAssertEqual(placements, [PackagePlacement(target: main, status: .applied)])
    }

    func testOneDropdownAloneNarrowsTheListToItsKind() {
        XCTAssertNil(PackagesPageState().scope)
        XCTAssertEqual(PackagesPageState(machine: "main").scope, "machine")
        XCTAssertEqual(PackagesPageState(workspace: "acme").scope, "workspace")
        XCTAssertNil(PackagesPageState(machine: "main", workspace: "acme").scope)
        XCTAssertEqual(PackagesPageState(machine: "main", workspace: "acme").focus(in: [main, backup, acme]), [main, acme])
    }

    func testClickingARowOpensItAndAgainClosesIt() {
        var page = PackagesPageState()
        page.toggleExpanded("docker")
        page.rowDestinations = [main]
        XCTAssertEqual(page.expanded, "docker")
        page.toggleExpanded("redis")
        XCTAssertEqual(page.expanded, "redis")
        XCTAssertTrue(page.rowDestinations.isEmpty)
        page.toggleExpanded("redis")
        XCTAssertNil(page.expanded)
    }

    func testAReloadLetsGoOfWhatIsGone() {
        var page = PackagesPageState(machine: "backup", workspace: "acme")
        page.bulkDestinations = [backup, acme]
        page.keep(targets: [main, acme])
        XCTAssertNil(page.machine)
        XCTAssertEqual(page.workspace, "acme")
        XCTAssertEqual(page.bulkDestinations, [acme])
    }

    func testInstalledTargetsHaveEveryPackage() {
        let statuses: [PackageTarget: [String: PackageStatus]] = [
            main: ["docker": .applied, "redis": .applied], backup: ["docker": .applied],
        ]
        XCTAssertEqual(PackagesSettingsView.installedTargets(of: ["docker", "redis"], among: [main, backup], statuses: statuses),
                       [main])
    }

    func testTheButtonsSayHowManyPlaces() {
        let one = PackageBatch(edits: [(main, PackageChanges(adds: ["docker"], removes: []))])
        XCTAssertEqual(PackagesSettingsView.buttonTitle(.install, batch: one), "Install on 1 place")
        XCTAssertEqual(PackagesSettingsView.buttonTitle(.remove, batch: PackageBatch(edits: [])), "Remove")
    }

    func testTheConfirmListsEachPlaceWhatIsLeftOutAndThatRemovingDoesNotUninstall() {
        let batch = PackageBatch(
            edits: [(main, PackageChanges(adds: [], removes: ["redis"]))],
            skips: [PackageSkip(package: "redis", target: backup, reason: "Not there.")])
        XCTAssertEqual(
            PackagesSettingsView.confirmMessage(batch, action: .remove),
            "main: redis\n\nLeft out:\nredis on backup — Not there.\n\n\(PackageRow.removalHint)")
    }

    func testNewPackageOpensClaudeOrCodexWithTheAskAndAnyOtherPlain() {
        XCTAssertEqual(
            PackagesSettingsView.newPackageStartup(.harness(.claude), command: "claude"),
            .command("claude 'I want to create a new devmachine-cli package'"))
        XCTAssertEqual(
            PackagesSettingsView.newPackageStartup(.harness(HarnessID(rawValue: "kimi")), command: "kimi"),
            .program(.harness(HarnessID(rawValue: "kimi"))))
        XCTAssertEqual(PackagesSettingsView.newPackageStartup(.terminal, command: nil), .program(.terminal))
    }

    func testALocalPackageFolderIsUnderTheConfiguration() {
        XCTAssertEqual(
            PackagesSettingsView.localFolder(configDirectory: "/Users/alice/.config/devmachine", name: "acme-tools"),
            "/Users/alice/.config/devmachine/packages/acme-tools")
        XCTAssertNil(PackagesSettingsView.localFolder(configDirectory: nil, name: "acme-tools"))
    }
}
