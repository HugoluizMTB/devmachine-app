import XCTest
@testable import DevmachineCore

final class WorkspaceNameTests: XCTestCase {
    func testANameIsALinuxAccountName() {
        for valid in ["acme", "acme-lab", "acme_2", "_tools"] {
            XCTAssertNil(WorkspaceName.problem(valid, existing: []), valid)
        }
        for invalid in ["Acme", "2acme", "-acme", "acme.lab", "acme lab", String(repeating: "a", count: 33)] {
            XCTAssertNotNil(WorkspaceName.problem(invalid, existing: []), invalid)
        }
    }

    func testANameCannotBeASystemAccountTheAdminLoginOrATakenWorkspace() {
        XCTAssertEqual(
            WorkspaceName.problem("root", existing: []),
            "root is already an account on the machine. Pick another, like acme.")
        XCTAssertNotNil(WorkspaceName.problem("deploy", adminUser: "deploy", existing: []))
        XCTAssertNil(WorkspaceName.problem("deploy", existing: []))
        XCTAssertEqual(WorkspaceName.problem("beta", existing: ["acme", "beta"]), "A workspace named beta already exists.")
    }

    func testAnEmptyNameAsksForOne() {
        XCTAssertEqual(WorkspaceName.problem("  ", existing: []), "Give the workspace a name, like acme.")
    }
}

final class WorkspacePlanTests: XCTestCase {
    func testANewWorkspaceIsDeclaredWithItsPackagesThenSynced() {
        let steps = WorkspacePlan.newSteps(name: "acme", machine: "main", packages: ["dev", "zsh"], sync: true)
        XCTAssertEqual(steps.map(\.arguments), [
            ["workspaces", "new", "acme", "--machine", "main", "--packages", "dev,zsh", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
        XCTAssertEqual(steps.map(\.kind), [.newWorkspace, .sync])
        XCTAssertEqual(steps[0].displayLine, "devmachine workspaces new acme --machine main --packages dev,zsh --yes")
    }

    func testNoPackageChosenStillPassesAnEmptyListAndNoSyncLeavesItInTheConfiguration() {
        let steps = WorkspacePlan.newSteps(name: "acme", machine: "main", packages: [], sync: false)
        XCTAssertEqual(steps.map(\.arguments), [
            ["workspaces", "new", "acme", "--machine", "main", "--packages=", "--yes"],
        ])
    }

    func testAnEditAddsRemovesSetsAndUnsetsThenSyncsTheWorkspacesMachine() {
        let changes = WorkspaceChanges(
            add: ["pi", "glab"], remove: ["mise"],
            set: [WorkspaceSetting(key: "zsh.theme", value: "robbyrussell")], unset: ["dev.node"])
        let steps = WorkspacePlan.editSteps(name: "acme", machine: "main", changes: changes, sync: true)
        XCTAssertEqual(steps.map(\.arguments), [
            ["workspaces", "edit", "acme", "--add", "pi", "--add", "glab", "--rm", "mise",
             "--set", "zsh.theme=robbyrussell", "--unset", "dev.node", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
        XCTAssertEqual(steps[0].kind, .editWorkspace)
    }

    func testForgetOnlyTakesTheWorkspaceOutOfTheConfiguration() {
        let steps = WorkspacePlan.forgetSteps(name: "acme")
        XCTAssertEqual(steps.map(\.arguments), [["workspaces", "rm", "acme", "--yes"]])
        XCTAssertEqual(steps.map(\.kind), [.forgetWorkspace])
    }

    func testDestroyConfirmsWithTheNameAndKeepsDNSOnlyWhenAsked() {
        XCTAssertEqual(
            WorkspacePlan.destroySteps(name: "acme", keepDNS: false).map(\.arguments),
            [["workspaces", "destroy", "acme", "--confirm", "acme"]])
        XCTAssertEqual(
            WorkspacePlan.destroySteps(name: "acme", keepDNS: true).map(\.arguments),
            [["workspaces", "destroy", "acme", "--confirm", "acme", "--keep-dns"]])
        XCTAssertEqual(WorkspacePlan.destroySteps(name: "acme", keepDNS: false).map(\.kind), [.destroyWorkspace])
    }

    func testChangesCompareTheChosenPackagesAndSettingsWithTheCurrentOnes() {
        let changes = WorkspaceChanges.between(
            packages: ["dev", "zsh", "mise"], settings: ["zsh.theme": "clean", "dev.node": "22"],
            chosenPackages: ["dev", "zsh", "pi"],
            chosenSettings: [
                WorkspaceSetting(key: "zsh.theme", value: "clean"),
                WorkspaceSetting(key: "pi.model", value: "fast"),
            ])
        XCTAssertEqual(changes.add, ["pi"])
        XCTAssertEqual(changes.remove, ["mise"])
        XCTAssertEqual(changes.set, [WorkspaceSetting(key: "pi.model", value: "fast")])
        XCTAssertEqual(changes.unset, ["dev.node"])
        XCTAssertFalse(changes.isEmpty)
        XCTAssertTrue(WorkspaceChanges.between(
            packages: ["dev"], settings: [:], chosenPackages: ["dev"], chosenSettings: []).isEmpty)
    }

    func testAChangedValueIsSetAgain() {
        let changes = WorkspaceChanges.between(
            packages: ["zsh"], settings: ["zsh.theme": "clean"], chosenPackages: ["zsh"],
            chosenSettings: [WorkspaceSetting(key: "zsh.theme", value: "agnoster")])
        XCTAssertEqual(changes.set, [WorkspaceSetting(key: "zsh.theme", value: "agnoster")])
        XCTAssertEqual(changes.unset, [])
    }
}

final class WorkspaceSettingTests: XCTestCase {
    func testAKeyNamesAPackageTheWorkspaceInstalls() {
        XCTAssertNil(WorkspaceSetting(key: "zsh.theme", value: "clean").problem(packages: ["zsh"]))
        XCTAssertEqual(
            WorkspaceSetting(key: "theme", value: "clean").problem(packages: ["zsh"]),
            "Write the setting as <package>.<name>, like zsh.theme.")
        XCTAssertEqual(
            WorkspaceSetting(key: "pi.model", value: "fast").problem(packages: ["zsh"]),
            "pi is not one of this workspace's packages, so the CLI refuses its setting.")
        XCTAssertEqual(
            WorkspaceSetting(key: "zsh.theme", value: " ").problem(packages: ["zsh"]),
            "Type a value, or remove the setting.")
    }

    func testAValueReadFromTheCLIIsWrittenBackAsYAMLText() throws {
        let json = Data(#"{"a":"text","b":3,"c":true,"d":["x","y"],"e":{"k":1},"f":2.5}"#.utf8)
        let values = try JSONDecoder().decode([String: SettingValue].self, from: json)
        XCTAssertEqual(values["a"]?.text, "text")
        XCTAssertEqual(values["b"]?.text, "3")
        XCTAssertEqual(values["c"]?.text, "true")
        XCTAssertEqual(values["d"]?.text, #"["x","y"]"#)
        XCTAssertEqual(values["e"]?.text, #"{"k":1}"#)
        XCTAssertEqual(values["f"]?.text, "2.5")
    }
}

final class WorkspaceSyncTests: XCTestCase {
    private let lock = PackagesLock(machines: [:], workspaces: [
        "acme": [.init(name: "workspace"), .init(name: "dev"), .init(name: "zsh")],
        "beta": [.init(name: "workspace")],
    ])

    func testEveryDeclaredPackageInTheLockIsApplied() {
        XCTAssertEqual(WorkspaceSync.state(workspace: "acme", packages: ["dev", "zsh"], lock: lock), .applied)
    }

    func testADeclaredPackageMissingFromTheLockWaitsForASync() {
        XCTAssertEqual(
            WorkspaceSync.state(workspace: "beta", packages: ["dev", "pi"], lock: lock), .pending(["dev", "pi"]))
    }

    func testAWorkspaceTheLockDoesNotNameWasNeverSynced() {
        XCTAssertEqual(WorkspaceSync.state(workspace: "gamma", packages: [], lock: lock), .neverSynced)
    }

    func testNoLockToReadSaysNothing() {
        XCTAssertEqual(WorkspaceSync.state(workspace: "acme", packages: ["dev"], lock: nil), .unknown)
    }

    func testTheLockReadsItsWorkspaces() throws {
        let parsed = try XCTUnwrap(PackagesLock.parse("""
            applied_at: "2026-09-18T12:00:00Z"
            machines:
                main:
                    - name: base
                      source: release
            workspaces:
                acme:
                    - name: workspace
                      source: release
                    - name: zsh
                      source: release
                      version: v27
                beta: []
            """))
        XCTAssertEqual(parsed.workspaces["acme"]?.map(\.name), ["workspace", "zsh"])
        XCTAssertEqual(parsed.workspaces["beta"], [])
        XCTAssertEqual(parsed.machines["main"]?.map(\.name), ["base"])
        XCTAssertNil(parsed.machines["acme"])
    }
}

final class WorkspacePackageCatalogTests: XCTestCase {
    private let packages = [
        PackageInfo(name: "workspace", scope: "workspace", summary: "The Linux account.", source: "release",
                    category: "Foundation"),
        PackageInfo(name: "zsh", scope: "workspace", summary: "zsh.", source: "release", needs: ["workspace"],
                    category: "Foundation"),
        PackageInfo(name: "claude-code", scope: "workspace", summary: "Claude Code.", source: "release",
                    category: "Coding agents"),
        PackageInfo(name: "dev", scope: "workspace", summary: "gh, bun, node.", source: "release",
                    category: "Foundation"),
        PackageInfo(name: "docker", scope: "machine", summary: "Docker.", source: "release"),
        PackageInfo(name: "mac-only", scope: "workspace", summary: "", source: "local", platforms: ["macos"]),
        PackageInfo(name: "acme-tools", scope: "workspace", summary: "", source: "local"),
    ]

    func testCardsAreWorkspacePackagesForLinuxWithTheAccountFirstAndLocked() {
        let cards = WorkspacePackageCatalog.cards(from: packages)
        XCTAssertEqual(cards.map(\.name), ["workspace", "dev", "zsh", "claude-code", "acme-tools"])
        XCTAssertTrue(cards[0].isLocked)
        XCTAssertFalse(cards[1].isLocked)
        XCTAssertEqual(cards.last?.summary, "No description.")
        XCTAssertTrue(cards.last?.isYours ?? false)
    }

    func testCardsGroupByCategoryInTheCatalogsOrder() {
        let groups = WorkspacePackageCatalog.groups(WorkspacePackageCatalog.cards(from: packages))
        XCTAssertEqual(groups.map(\.title), ["Foundation", "Coding agents", "Other"])
        XCTAssertEqual(groups[0].cards.map(\.name), ["workspace", "dev", "zsh"])
    }

    func testThePreselectionIsTheCLIsSetupDefaultThatTheListHas() {
        let cards = WorkspacePackageCatalog.cards(from: packages)
        XCTAssertEqual(WorkspacePackageCatalog.preselected(from: cards), ["dev", "zsh"])
    }

    func testAPackageTheWorkspaceHasButTheListLacksStillGetsACard() {
        let cards = WorkspacePackageCatalog.cards(from: packages, keeping: ["zsh", "old-tool"])
        XCTAssertTrue(cards.contains { $0.name == "old-tool" })
    }
}

final class WorkspaceFlowTests: XCTestCase {
    private let machines = [
        WorkspaceMachineChoice(name: "main", adminUser: "root"),
        WorkspaceMachineChoice(name: "staging", adminUser: "deploy"),
    ]
    private let acme = WorkspaceSummary(
        name: "acme", machine: "main", user: "acme", packages: ["dev", "zsh"], settings: ["zsh.theme": "clean"])

    private func newFlow() -> WorkspaceFlow {
        WorkspaceFlow.new(machines: machines, existingWorkspaces: ["acme"], packages: ["dev", "zsh"])
    }

    func testNewStartsOnTheFormWithTheOnlyOrFirstMachineAndThePreselection() {
        let flow = newFlow()
        XCTAssertEqual(flow.stage, .form)
        XCTAssertEqual(flow.draft.machine, "main")
        XCTAssertEqual(flow.draft.packages, ["dev", "zsh"])
        XCTAssertFalse(flow.canAdvance)
    }

    func testNewNeedsAValidFreeNameAndAMachine() {
        var flow = newFlow()
        flow.draft.name = "acme"
        XCTAssertEqual(flow.nameProblem, "A workspace named acme already exists.")
        flow.draft.name = "deploy"
        flow.draft.machine = "staging"
        XCTAssertNotNil(flow.nameProblem)
        flow.draft.name = "beta"
        XCTAssertTrue(flow.canAdvance)
        flow.draft.machine = ""
        XCTAssertFalse(flow.canAdvance)
    }

    func testNewGoesFormReviewRunAndBackKeepsTheAnswers() {
        var flow = newFlow()
        flow.draft.name = "beta"
        flow.next()
        XCTAssertEqual(flow.stage, .review)
        XCTAssertEqual(flow.plan.map(\.displayLine), [
            "devmachine workspaces new beta --machine main --packages dev,zsh --yes",
            "devmachine sync --machine main --yes",
        ])
        flow.back()
        XCTAssertEqual(flow.stage, .form)
        XCTAssertEqual(flow.draft.name, "beta")
        flow.next()
        flow.next()
        XCTAssertEqual(flow.stage, .run)
        XCTAssertFalse(flow.canGoBack)
        flow.editAnswers()
        XCTAssertEqual(flow.stage, .form)
    }

    func testTogglingAPackageNeverDropsTheAccount() {
        var flow = newFlow()
        flow.togglePackage("zsh")
        flow.togglePackage("pi")
        flow.togglePackage(WorkspacePackageCatalog.account)
        XCTAssertEqual(flow.draft.packages, ["dev", "pi"])
        XCTAssertTrue(flow.isSelected(WorkspacePackageCatalog.account))
    }

    func testEditNeedsAChangeAndSyncsTheWorkspacesOwnMachine() {
        var flow = WorkspaceFlow.edit(acme)
        XCTAssertEqual(flow.packages, ["dev", "zsh"])
        XCTAssertEqual(flow.settings, [WorkspaceSetting(key: "zsh.theme", value: "clean")])
        XCTAssertFalse(flow.canAdvance)
        flow.setSetting("zsh.theme", "agnoster")
        XCTAssertTrue(flow.canAdvance)
        flow.next()
        XCTAssertEqual(flow.plan.map(\.arguments), [
            ["workspaces", "edit", "acme", "--set", "zsh.theme=agnoster", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
    }

    func testEditStartsFromTheAutoConnectChoiceAndTheSwitchAloneRunsNoCommand() {
        var flow = WorkspaceFlow.edit(acme, autoConnect: true)
        XCTAssertTrue(flow.autoConnect)
        XCTAssertFalse(flow.autoConnectChanged)
        XCTAssertFalse(flow.canAdvance)
        flow.autoConnect = false
        XCTAssertTrue(flow.autoConnectChanged)
        XCTAssertTrue(flow.canAdvance)
        XCTAssertEqual(flow.plan, [], "the switch lives on this Mac, never in the CLI")
        flow.setSetting("zsh.theme", "agnoster")
        XCTAssertEqual(flow.plan.map(\.arguments), [
            ["workspaces", "edit", "acme", "--set", "zsh.theme=agnoster", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
    }

    func testEditNeverChangesPackagesWhichLiveInSettingsPackages() {
        var flow = WorkspaceFlow.edit(acme)
        flow.togglePackage("pi")
        flow.togglePackage("zsh")
        XCTAssertEqual(flow.packages, ["dev", "zsh"])
        XCTAssertFalse(flow.canAdvance)
        flow.setSetting("zsh.theme", "agnoster")
        XCTAssertEqual(flow.changes.add, [])
        XCTAssertEqual(flow.changes.remove, [])
        XCTAssertFalse(flow.plan[0].arguments.contains("--add"))
        XCTAssertFalse(flow.plan[0].arguments.contains("--rm"))
    }

    func testEditRefusesASettingForAPackageTheWorkspaceDoesNotHave() {
        var flow = WorkspaceFlow.edit(acme)
        flow.setSetting("pi.model", "fast")
        XCTAssertEqual(flow.settingProblems.first, "pi is not one of this workspace's packages, so the CLI refuses its setting.")
        XCTAssertFalse(flow.canAdvance)
        flow.setSetting("pi.model", "")
        flow.removeSetting(at: 0)
        XCTAssertTrue(flow.canAdvance)
        XCTAssertEqual(flow.changes.unset, ["zsh.theme"])
    }

    func testEditAddsASetting() {
        var flow = WorkspaceFlow.edit(acme)
        flow.addSetting()
        XCTAssertFalse(flow.canAdvance)
        flow.settings[1] = WorkspaceSetting(key: "dev.node", value: "22")
        XCTAssertTrue(flow.canAdvance)
        XCTAssertEqual(flow.changes.set, [WorkspaceSetting(key: "dev.node", value: "22")])
    }

    func testForgetRunsStraightFromItsScreen() {
        var flow = WorkspaceFlow.forget(acme)
        XCTAssertTrue(flow.canAdvance)
        XCTAssertEqual(flow.plan.map(\.arguments), [["workspaces", "rm", "acme", "--yes"]])
        flow.next()
        XCTAssertEqual(flow.stage, .run)
    }

    func testDestroyWaitsForTheNameTypedExactly() {
        var flow = WorkspaceFlow.destroy(acme)
        XCTAssertFalse(flow.canAdvance)
        flow.typedName = "Acme"
        XCTAssertFalse(flow.canAdvance)
        flow.typedName = "acme"
        XCTAssertTrue(flow.canAdvance)
        flow.keepDNS = true
        XCTAssertEqual(flow.plan.map(\.arguments), [["workspaces", "destroy", "acme", "--confirm", "acme", "--keep-dns"]])
        flow.next()
        XCTAssertEqual(flow.stage, .run)
    }

    func testTheMachineASyncRunsOn() {
        var flow = newFlow()
        flow.draft.machine = "staging"
        XCTAssertEqual(flow.machine, "staging")
        XCTAssertEqual(WorkspaceFlow.edit(acme).machine, "main")
    }
}

final class CodingAgentPackagesTests: XCTestCase {
    private let harnesses: [(HarnessID, String?)] = [
        (.claude, "claude-code"), (.codex, nil), (.pi, "pi"), (.kimi, "kimi-code"),
    ]

    func testOnlyAHarnessWithAPackageInTheReleaseCanBeTurnedOn() {
        XCTAssertEqual(
            CodingAgentPackages.activatable(harnesses: harnesses, available: ["claude-code", "pi", "zsh"]),
            [.claude, .pi])
    }

    func testAListNotReadYetTrustsTheDeclaredPackage() {
        XCTAssertEqual(CodingAgentPackages.activatable(harnesses: harnesses, available: nil), [.claude, .pi, .kimi])
    }

    func testOnlyTheHarnessesTurnedOnAreOfferedAndTheOthersAreHidden() {
        let choice = CodingAgentPackages.choose(
            harnesses: harnesses, enabled: [.claude, .codex], available: ["claude-code", "pi", "kimi-code"])
        XCTAssertEqual(choice.offered, ["claude-code"])
        XCTAssertEqual(choice.hidden, ["pi", "kimi-code"])
    }

    func testNoHarnessOnOffersNone() {
        let choice = CodingAgentPackages.choose(harnesses: harnesses, enabled: [], available: nil)
        XCTAssertEqual(choice.offered, [])
        XCTAssertEqual(choice.hidden, ["claude-code", "pi", "kimi-code"])
    }

    func testHiddenAgentsAndWhatNeedsThemLeaveTheCardsUnlessTheWorkspaceHasThem() {
        let packages = [
            PackageInfo(name: "claude-code", scope: "workspace", summary: "", source: "release", category: "Coding agents"),
            PackageInfo(name: "claude-plugins", scope: "workspace", summary: "", source: "release",
                        needs: ["claude-code"], category: "Coding agents"),
            PackageInfo(name: "pi", scope: "workspace", summary: "", source: "release", category: "Coding agents"),
            PackageInfo(name: "devmachine-skills", scope: "workspace", summary: "", source: "release",
                        category: "Coding agents"),
            PackageInfo(name: "zsh", scope: "workspace", summary: "", source: "release", category: "Foundation"),
        ]
        XCTAssertEqual(
            WorkspacePackageCatalog.cards(from: packages, hiding: ["claude-code"]).map(\.name),
            ["zsh", "devmachine-skills", "pi"])
        XCTAssertEqual(
            WorkspacePackageCatalog.cards(from: packages, keeping: ["claude-code"], hiding: ["claude-code"]).map(\.name),
            ["zsh", "claude-code", "claude-plugins", "devmachine-skills", "pi"])
    }
}
