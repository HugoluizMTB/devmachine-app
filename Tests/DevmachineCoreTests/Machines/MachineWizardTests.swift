import XCTest
@testable import DevmachineCore

final class MachineWizardTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "C", count: 43)

    private func filledServer() -> MachineWizard {
        var wizard = MachineWizard(existingMachines: [], limaFound: true)
        wizard.choose(.server)
        wizard.draft.name = "main"
        wizard.draft.address = "203.0.113.10"
        wizard.draft.fingerprint = fingerprint
        wizard.draft.keyFile = "~/.ssh/id_ed25519"
        return wizard
    }

    func testItStartsByAskingWhatKindOfMachine() {
        let wizard = MachineWizard(existingMachines: [], limaFound: true)
        XCTAssertEqual(wizard.stage, .kind)
        XCTAssertFalse(wizard.canGoBack)
    }

    func testChoosingAKindMovesOnToItsDetails() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true)
        wizard.choose(.localVM)
        XCTAssertEqual(wizard.stage, .details)
        XCTAssertEqual(wizard.draft.kind, .localVM)
    }

    func testALocalMachineCannotBeChosenWithoutLima() {
        var wizard = MachineWizard(existingMachines: [], limaFound: false)
        XCTAssertFalse(wizard.canChoose(.localVM))
        wizard.choose(.localVM)
        XCTAssertEqual(wizard.stage, .kind)
        XCTAssertTrue(wizard.canChoose(.server))
    }

    func testDetailsWithAProblemDoNotMoveOn() {
        var wizard = filledServer()
        wizard.draft.address = ""
        XCTAssertFalse(wizard.canAdvance)
        wizard.next()
        XCTAssertEqual(wizard.stage, .details)
    }

    func testTheStepsGoDetailsPackagesReviewThenRun() {
        var wizard = filledServer()
        wizard.next()
        XCTAssertEqual(wizard.stage, .packages)
        wizard.next()
        XCTAssertEqual(wizard.stage, .review)
        wizard.next()
        XCTAssertEqual(wizard.stage, .run)
        XCTAssertFalse(wizard.canAdvance)
        wizard.next()
        XCTAssertEqual(wizard.stage, .run)
    }

    func testBackKeepsTheAnswers() {
        var wizard = filledServer()
        wizard.next()
        wizard.togglePackage("docker")
        wizard.back()
        wizard.back()
        XCTAssertEqual(wizard.stage, .kind)
        XCTAssertEqual(wizard.draft.name, "main")
        XCTAssertEqual(wizard.draft.packages, ["docker"])
    }

    func testThereIsNoBackFromARunThatStarted() {
        var wizard = filledServer()
        wizard.next()
        wizard.next()
        wizard.next()
        XCTAssertFalse(wizard.canGoBack)
        wizard.back()
        XCTAssertEqual(wizard.stage, .run)
    }

    func testARebuiltWizardReturnsToAStepButNeverIntoARun() {
        var wizard = filledServer()
        wizard.restore(.packages)
        XCTAssertEqual(wizard.stage, .packages)
        wizard.restore(.run)
        XCTAssertEqual(wizard.stage, .packages)
    }

    func testARebuiltWizardStopsAtTheFirstStepThatNowNeedsAnAnswer() {
        var legacy = MachineWizard(existingMachines: [], limaFound: true)
        legacy.choose(.server)
        legacy.draft.name = "main"
        legacy.draft.address = "203.0.113.10"
        legacy.draft.login = .password
        XCTAssertTrue(legacy.problems.isEmpty, "an older CLI asks for the password in its terminal")

        var unattended = MachineWizard(existingMachines: [], limaFound: true, unattended: true)
        unattended.draft = legacy.draft
        unattended.restore(.review)

        XCTAssertEqual(unattended.stage, .details)
        XCTAssertTrue(unattended.problems.contains { $0.field == .password })
    }

    func testARebuiltWizardWithoutLimaGoesBackToTheKind() {
        var wizard = MachineWizard(existingMachines: [], limaFound: false)
        wizard.draft.kind = .localVM
        wizard.draft.name = "lab"
        wizard.restore(.review)
        XCTAssertEqual(wizard.stage, .kind)
    }

    func testAFailedRunCanGoBackToItsDetailsWithEveryAnswer() {
        var wizard = filledServer()
        wizard.next()
        wizard.togglePackage("docker")
        wizard.next()
        wizard.next()

        wizard.editAnswers()

        XCTAssertEqual(wizard.stage, .details)
        XCTAssertEqual(wizard.draft.name, "main")
        XCTAssertEqual(wizard.draft.packages, ["docker"])
    }

    func testOnlyARunGoesBackToEditItsAnswers() {
        var wizard = filledServer()
        wizard.next()
        wizard.editAnswers()
        XCTAssertEqual(wizard.stage, .packages)
    }

    func testTheFirstRunAsksTheSameQuestionsAndEndsWithThisAppsPackageAndASync() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, firstRun: true)
        XCTAssertEqual(wizard.stage, .kind)
        wizard.choose(.server)
        wizard.draft.name = "main"
        wizard.draft.address = "203.0.113.10"
        wizard.draft.keySource = .agent
        wizard.draft.agentKey = fingerprint
        wizard.draft.fingerprint = fingerprint
        wizard.draft.sync = false
        wizard.draft.packages = ["docker"]
        wizard.next()
        XCTAssertEqual(wizard.stage, .packages)

        XCTAssertEqual(wizard.plan.map(\.arguments), [
            ["machines", "add", "--name", "main", "--address", "203.0.113.10", "--fingerprint", fingerprint,
             "--key", "agent:\(fingerprint)", "--yes"],
            ["packages", "add", "docker", "--machine", "main", "--yes"],
            ["packages", "add", "devmachine-app", "--machine", "main", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
    }

    func testTheFirstRunCanMakeAMachineOnThisMacAndInstallsLimaFirstWhenMissing() {
        var wizard = MachineWizard(existingMachines: [], limaFound: false, unattended: true, firstRun: true)
        XCTAssertTrue(wizard.canChoose(.localVM))
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        XCTAssertEqual(wizard.plan.map(\.kind), [
            .installLima, .createLocal, .addPackage(MachinePackageCatalog.appPackage), .sync,
        ])
        XCTAssertEqual(wizard.plan.first?.id, MachinePlanStep.installLimaID)
        XCTAssertFalse(wizard.plan.first?.isCommand ?? true)
        XCTAssertEqual(wizard.plan[1].arguments, ["machines", "create-local", "lab", "--add"])
    }

    func testLimaThatIsThereIsNotInstalledAgain() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        XCTAssertEqual(wizard.plan.map(\.kind), [.createLocal, .sync])
    }

    func testTheSkillsAreInstalledOnceForEveryHarnessChosenAfterTheSync() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, firstRun: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        wizard.draft.skillAgents = ["claude", "opencode"]
        XCTAssertEqual(Array(wizard.plan.suffix(2).map(\.arguments)), [
            ["sync", "--machine", "lab", "--yes"],
            ["skills", "add", "--agent", "claude", "--agent", "opencode", "--yes"],
        ])
        XCTAssertEqual(wizard.plan.last?.kind, .skills)
        XCTAssertFalse(wizard.plan.last?.blocksSetup ?? true)
    }

    func testNoHarnessChosenMeansNoSkillsStep() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, firstRun: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        XCTAssertFalse(wizard.plan.contains { $0.kind == .skills })
    }

    func testOnlyTheFirstRunInstallsSkills() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        wizard.draft.skillAgents = ["claude"]
        XCTAssertFalse(wizard.plan.contains { $0.kind == .skills })
    }

    func testAHarnessIsChosenOrLeftOutByToggling() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, firstRun: true)
        wizard.toggleSkillAgent("claude")
        wizard.toggleSkillAgent("codex")
        wizard.toggleSkillAgent("claude")
        XCTAssertEqual(wizard.draft.skillAgents, ["codex"])
    }

    func testTheSkillHarnessesAreTheCLIsFourInItsOrder() {
        XCTAssertEqual(SkillAgent.all.map(\.id), ["claude", "codex", "pi", "opencode"])
        XCTAssertEqual(SkillAgent.all.map(\.name), ["Claude Code", "Codex", "Pi", "OpenCode"])
        XCTAssertEqual(SkillAgent.ordered(["opencode", "claude", "unknown"]), ["claude", "opencode"])
    }

    func testAFirstRunWizardIsRebuiltAtItsKindLikeAnyOther() {
        var wizard = MachineWizard(existingMachines: [], limaFound: false, unattended: true, firstRun: true)
        wizard.restore(.review)
        XCTAssertEqual(wizard.stage, .details)
    }

    func testAPackageIsToggledInTheOrderItWasChosen() {
        var wizard = filledServer()
        wizard.togglePackage("tailscale")
        wizard.togglePackage("docker")
        XCTAssertEqual(wizard.draft.packages, ["tailscale", "docker"])
        wizard.togglePackage("tailscale")
        XCTAssertEqual(wizard.draft.packages, ["docker"])
    }

    func testEssentialsIsAlwaysInstalledAndCannotBeTurnedOff() {
        var wizard = filledServer()
        XCTAssertTrue(wizard.isSelected(MachinePackageCatalog.essentials))
        wizard.togglePackage(MachinePackageCatalog.essentials)
        XCTAssertTrue(wizard.draft.essentials)
        XCTAssertEqual(wizard.draft.packages, [])
        XCTAssertTrue(wizard.isSelected(MachinePackageCatalog.essentials))
    }

    func testTheProblemsShownAreTheCurrentDetailsProblems() {
        var wizard = MachineWizard(existingMachines: ["main"], limaFound: true)
        wizard.choose(.server)
        wizard.draft.name = "main"
        XCTAssertTrue(wizard.problems.contains { $0.field == .name })
    }
}

final class MachinePackageCatalogTests: XCTestCase {
    func testOnlyMachinePackagesAreOfferedWithEssentialsFirst() {
        let cards = MachinePackageCatalog.cards(from: [
            PackageInfo(name: "zsh", scope: "workspace", summary: "A shell.", source: "release"),
            PackageInfo(name: "tailscale", scope: "machine", summary: "Joins a tailnet.", source: "release"),
            PackageInfo(name: "docker", scope: "machine", summary: "Docker Engine.", source: "release"),
            PackageInfo(name: "essentials", scope: "machine", summary: "What almost every machine wants.", source: "release"),
            PackageInfo(name: "caddy-sites", scope: "machine", summary: "", source: "local"),
        ])
        XCTAssertEqual(cards.map(\.name), ["essentials", "caddy-sites", "docker", "tailscale"])
        XCTAssertEqual(cards.first?.isRecommended, true)
        XCTAssertEqual(cards.first { $0.name == "caddy-sites" }?.isYours, true)
        XCTAssertEqual(cards.first { $0.name == "docker" }?.isYours, false)
    }

    func testWhatEssentialsContainsIsNotOfferedAgainOnItsOwn() {
        let cards = MachinePackageCatalog.cards(from: [
            PackageInfo(name: "essentials", scope: "machine", summary: "Base.", source: "release",
                        needs: ["base", "caddy", "devmachine-app"]),
            PackageInfo(name: "caddy", scope: "machine", summary: "Sites.", source: "release"),
            PackageInfo(name: "devmachine-app", scope: "machine", summary: "App.", source: "release"),
            PackageInfo(name: "docker", scope: "machine", summary: "Docker Engine.", source: "release"),
        ])
        XCTAssertEqual(cards.map(\.name), ["essentials", "docker"])
        XCTAssertEqual(cards[0].contains, ["base", "caddy", "devmachine-app"])
        XCTAssertTrue(cards[0].isLocked)
        XCTAssertFalse(cards[1].isLocked)
    }

    func testDockerIsSuggestedWhenItIsOffered() {
        let docker = MachinePackageCard(name: "docker", summary: "", isRecommended: false, isYours: false)
        let tailscale = MachinePackageCard(name: "tailscale", summary: "", isRecommended: false, isYours: false)
        XCTAssertEqual(MachinePackageCatalog.suggested(from: [tailscale, docker]), ["docker"])
        XCTAssertEqual(MachinePackageCatalog.suggested(from: [tailscale]), [])
    }

    func testAPackageWithNoSummarySaysSo() {
        let card = MachinePackageCatalog.cards(from: [
            PackageInfo(name: "caddy-sites", scope: "machine", summary: "  ", source: "local"),
        ])[0]
        XCTAssertEqual(card.summary, "No description.")
    }
}

final class AddMachinePromptTests: XCTestCase {
    func testTheSidebarOffersAMachineOnlyOnceItKnowsThereIsNone() {
        XCTAssertFalse(AddMachinePrompt.shows(remoteMachines: nil))
        XCTAssertTrue(AddMachinePrompt.shows(remoteMachines: []))
        XCTAssertFalse(AddMachinePrompt.shows(remoteMachines: ["main"]))
    }
}

final class LimaToolTests: XCTestCase {
    func testLimaIsFoundWhereHomebrewPutsIt() {
        XCTAssertEqual(LimaTool.find(exists: { $0 == "/usr/local/bin/limactl" }), "/usr/local/bin/limactl")
        XCTAssertNil(LimaTool.find(exists: { _ in false }))
    }

    func testTheInstallAdviceIsHomebrews() {
        XCTAssertEqual(LimaTool.installCommand, "brew install lima")
    }
}
