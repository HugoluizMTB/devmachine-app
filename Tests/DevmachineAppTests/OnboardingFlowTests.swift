import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private func detection(
    cliFound: Bool = true, adminMachine: String? = nil, missingPackageMachines: [String] = [],
    cliVersion: SemanticVersion? = MachineUnattendedAdd.minimumCLIVersion
) -> OnboardingDetection {
    OnboardingDetection(
        cliFound: cliFound, adminMachine: adminMachine, missingPackageMachines: missingPackageMachines,
        cliVersion: cliFound ? cliVersion : nil)
}

private let freshMac = detection(cliFound: false)
private let cliOnly = detection()
private let ready = detection(adminMachine: "acme")

final class OnboardingFlowTests: XCTestCase {
    func testNothingCanStartBeforeTheFirstDetection() {
        var flow = OnboardingFlow()
        XCTAssertNil(flow.start())
        XCTAssertEqual(flow.screen, .start)
    }

    func testAFreshMacInstallsTheCLIThenOpensTheWizardThenCompletes() {
        var flow = OnboardingFlow()
        XCTAssertNil(flow.receive(freshMac))

        XCTAssertEqual(flow.start(), .run([.installCLI]))
        XCTAssertEqual(flow.screen, .preparing)

        XCTAssertEqual(flow.runFinished(succeeded: true), .refreshDetection)
        XCTAssertEqual(flow.receive(cliOnly), .openWizard)
        XCTAssertEqual(flow.screen, .wizard)

        XCTAssertEqual(flow.wizardFinished(), .refreshDetection)
        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.screen, .complete)
    }

    func testAFailedRunWaitsOnScreenForRetryOrBack() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()

        XCTAssertNil(flow.runFinished(succeeded: false))
        XCTAssertEqual(flow.screen, .preparing)
        XCTAssertEqual(flow.plan, [.installCLI])

        XCTAssertEqual(flow.back(), .stop)
        XCTAssertEqual(flow.screen, .start)
        XCTAssertEqual(flow.plan, [])
    }

    func testAnInstallThatLeavesTheCLIMissingIsAFailureNotALoop() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        _ = flow.runFinished(succeeded: true)

        XCTAssertNil(flow.receive(freshMac))
        XCTAssertEqual(flow.screen, .preparing)
        XCTAssertNotNil(flow.unresolved)

        XCTAssertEqual(flow.checkAgain(), .refreshDetection)
        XCTAssertNil(flow.unresolved)
        XCTAssertEqual(flow.receive(cliOnly), .openWizard)
    }

    func testAMacAlreadyConnectedOnlyGetsThisAppsPackageOnEachMachine() {
        var flow = OnboardingFlow()
        _ = flow.receive(detection(adminMachine: "acme", missingPackageMachines: ["acme"]))
        XCTAssertEqual(flow.start(), .run(OnboardingPlan.prepareSteps(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme"]))))
        XCTAssertEqual(flow.plan.map(\.kind), [.addPackage(MachinePackageCatalog.appPackage), .sync])

        _ = flow.runFinished(succeeded: true)
        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.screen, .complete)
    }

    func testAnOlderCLIIsSaidToBeTooOldAndCanBeReplaced() {
        var flow = OnboardingFlow()
        _ = flow.receive(detection(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 20)))

        XCTAssertNil(flow.start())
        XCTAssertEqual(flow.screen, .cliTooOld)
        XCTAssertEqual(flow.updateCLI(), .run([.installCLI]))
        _ = flow.runFinished(succeeded: true)
        XCTAssertEqual(flow.receive(cliOnly), .openWizard)
    }

    func testCheckingAgainAfterUpdatingTheCLIElsewhereOpensTheWizard() {
        var flow = OnboardingFlow()
        _ = flow.receive(detection(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 20)))
        _ = flow.start()

        XCTAssertEqual(flow.checkAgain(), .refreshDetection)
        XCTAssertEqual(flow.receive(cliOnly), .openWizard)
    }

    func testAWizardRunTheCLIDoesNotReportIsAFailureWithCheckAgain() {
        var flow = OnboardingFlow()
        _ = flow.receive(cliOnly)
        _ = flow.start()
        _ = flow.wizardFinished()

        XCTAssertNil(flow.receive(cliOnly))
        XCTAssertEqual(flow.screen, .wizard)
        XCTAssertNotNil(flow.unresolved)
    }

    func testAMacAlreadySetUpIsCompleteAtOnce() {
        var flow = OnboardingFlow()
        XCTAssertNil(flow.receive(ready))
        XCTAssertEqual(flow.screen, .complete)
    }

    func testAReadWhileARunGoesOnChangesNothing() {
        var flow = OnboardingFlow()
        _ = flow.receive(freshMac)
        _ = flow.start()
        XCTAssertNil(flow.receive(cliOnly))
        XCTAssertEqual(flow.screen, .preparing)
    }

    func testAFinishedRunOnAnotherScreenIsIgnored() {
        var flow = OnboardingFlow()
        _ = flow.receive(cliOnly)
        XCTAssertNil(flow.runFinished(succeeded: true))
        XCTAssertNil(flow.wizardFinished())
    }
}
