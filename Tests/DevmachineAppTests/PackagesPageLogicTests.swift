import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class PackagesPageLogicTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)
    private let acme = PackageTarget.workspace("acme", machine: "main")

    private func entry(_ name: String, scope: String = "machine") -> PackageEntry {
        PackageEntry(name: name, scope: scope, source: "release", summary: "", category: nil,
                     platforms: [], needs: [], credentialNames: [], installedOn: [])
    }

    func testEachStatusHasItsPill() {
        XCTAssertEqual(PackageRow.pill(for: .applied)?.text, "Installed")
        XCTAssertEqual(PackageRow.pill(for: .applied)?.color, .green)
        XCTAssertEqual(PackageRow.pill(for: .appliedAsDependency(of: "gh"))?.text, "Via gh")
        XCTAssertEqual(PackageRow.pill(for: .appliedAsDependency(of: "gh"))?.color, .dmMuted)
        XCTAssertEqual(PackageRow.pill(for: .pendingInstall)?.text, "Pending install")
        XCTAssertEqual(PackageRow.pill(for: .pendingInstall)?.color, .orange)
        XCTAssertEqual(PackageRow.pill(for: .pendingRemove)?.text, "Pending removal")
        XCTAssertEqual(PackageRow.pill(for: .pendingRemove)?.color, .orange)
        XCTAssertNil(PackageRow.pill(for: .available))
    }

    func testOnlyAnInstalledRowTickedForRemovalSaysTheSoftwareStays() {
        XCTAssertEqual(PackageRow.removalNote(status: .applied, isSelected: true), PackageRow.removalHint)
        XCTAssertNil(PackageRow.removalNote(status: .applied, isSelected: false))
        XCTAssertNil(PackageRow.removalNote(status: .available, isSelected: true))
        XCTAssertNil(PackageRow.removalNote(status: .pendingInstall, isSelected: true))
        XCTAssertNil(PackageRow.removalNote(status: nil, isSelected: true))
    }

    func testTheShortLabelDropsTheKindPrefix() {
        XCTAssertEqual(PackageRow.shortLabel("machine main"), "main")
        XCTAssertEqual(PackageRow.shortLabel("workspace acme"), "acme")
        XCTAssertEqual(PackageRow.shortLabel("dev"), "dev")
    }

    func testTheConfirmMessageWarnsOnlyWhenSomethingIsRemoved() {
        let adds = PackagesSettingsView.confirmMessage(PackageChanges(adds: ["docker", "gh"], removes: []))
        XCTAssertEqual(adds, "Install: docker, gh")
        XCTAssertFalse(adds.contains(PackagesSettingsView.removalNote))

        let both = PackagesSettingsView.confirmMessage(PackageChanges(adds: ["docker"], removes: ["node"]))
        XCTAssertEqual(both, "Install: docker\nRemove: node\n\(PackagesSettingsView.removalNote)")
    }

    func testTheCheckboxShowsWhatTheTargetHasOnceApplied() {
        let declared: [PackageStatus] = [.applied, .pendingInstall, .appliedAsDependency(of: "gh")]
        for status in declared {
            XCTAssertTrue(PackageRow.isChecked(status: status, isSelected: false), "\(status)")
            XCTAssertFalse(PackageRow.isChecked(status: status, isSelected: true), "\(status)")
        }
        for status: PackageStatus in [.available, .pendingRemove] {
            XCTAssertFalse(PackageRow.isChecked(status: status, isSelected: false), "\(status)")
            XCTAssertTrue(PackageRow.isChecked(status: status, isSelected: true), "\(status)")
        }
        XCTAssertFalse(PackageRow.isChecked(status: nil, isSelected: false))
    }

    func testTheCheckboxIsOffWithoutATargetOrWithABlock() {
        XCTAssertTrue(PackageRow.isDisabled(target: nil, block: nil))
        XCTAssertTrue(PackageRow.isDisabled(target: main, block: .essentials))
        XCTAssertFalse(PackageRow.isDisabled(target: main, block: nil))

        XCTAssertNil(PackageRow.block(entry: entry("docker"), status: .available, target: nil))
        XCTAssertNil(PackageRow.block(entry: entry("docker"), status: .available, target: main))
        XCTAssertEqual(PackageRow.block(entry: entry("gh", scope: "workspace"), status: nil, target: main),
                       .wrongScope("workspace"))
    }

    func testWithoutATargetTheRowHasNoCheckboxAndThePageSaysWhatToPick() {
        XCTAssertFalse(PackageRow.showsCheckbox(target: nil))
        XCTAssertTrue(PackageRow.showsCheckbox(target: main))
        XCTAssertEqual(PackagesSettingsView.pickTargetHint, "Choose a machine or workspace above to add or remove packages.")
    }

    func testChoosingAnotherTargetEmptiesTheSelection() {
        var page = PackagesPageState(target: main)
        page.selection.toggle("docker")
        page.choose(main)
        XCTAssertEqual(page.selection.names, ["docker"])

        page.choose(acme)
        XCTAssertEqual(page.target, acme)
        XCTAssertTrue(page.selection.names.isEmpty)

        page.selection.toggle("gh")
        page.choose(nil)
        XCTAssertNil(page.target)
        XCTAssertTrue(page.selection.names.isEmpty)
    }

    func testAReloadWithoutTheTargetGoesBackToEveryMachine() {
        var page = PackagesPageState(target: acme)
        page.selection.toggle("gh")
        page.keep(targets: [main, acme])
        XCTAssertEqual(page.target, acme)
        XCTAssertEqual(page.selection.names, ["gh"])

        page.keep(targets: [main])
        XCTAssertNil(page.target)
        XCTAssertTrue(page.selection.names.isEmpty)
    }
}
