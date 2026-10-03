import XCTest
@testable import DevmachineCore

final class LocalMachineSizeTests: XCTestCase {
    private let gib: UInt64 = 1 << 30
    private let diskGib: Int64 = 1 << 30

    private var mac: LocalMachineSizeLimits {
        LocalMachineSizeLimits(cores: 10, memoryBytes: 32 * gib, freeDiskBytes: 400 * diskGib)
    }

    func testLimitsComeFromThisMacAndLeaveItRoomToRun() {
        XCTAssertEqual(mac.cpus, 1...10)
        XCTAssertEqual(mac.memoryGiB, 2...30)
        XCTAssertEqual(mac.diskGiB, 10...390)
    }

    func testTheDefaultIsAComfortableShareOfThisMac() {
        XCTAssertEqual(mac.defaultSize, LocalMachineSize(cpus: 4, memoryGiB: 8, diskGiB: 40))
        let small = LocalMachineSizeLimits(cores: 4, memoryBytes: 8 * gib, freeDiskBytes: 30 * diskGib)
        XCTAssertEqual(small.defaultSize, LocalMachineSize(cpus: 2, memoryGiB: 4, diskGiB: 20))
        XCTAssertTrue(small.contains(small.defaultSize))
    }

    func testAMacShortOfEverythingStillOffersTheSmallestMachine() {
        let tiny = LocalMachineSizeLimits(cores: 1, memoryBytes: 2 * gib, freeDiskBytes: 5 * diskGib)
        XCTAssertEqual(tiny.cpus, 1...1)
        XCTAssertEqual(tiny.memoryGiB, 2...2)
        XCTAssertEqual(tiny.diskGiB, 10...10)
        XCTAssertEqual(tiny.defaultSize, LocalMachineSize(cpus: 1, memoryGiB: 2, diskGiB: 10))
    }

    func testAnUnknownFreeDiskCapsAtAPlainMaximum() {
        let unknown = LocalMachineSizeLimits(cores: 8, memoryBytes: 16 * gib, freeDiskBytes: nil)
        XCTAssertEqual(unknown.diskGiB, 10...LocalMachineSizeLimits.maximumDiskGiB)
    }

    func testASizeOutOfRangeIsClampedAndReported() {
        let size = LocalMachineSize(cpus: 64, memoryGiB: 1, diskGiB: 2000)
        XCTAssertFalse(mac.contains(size))
        XCTAssertEqual(mac.clamped(size), LocalMachineSize(cpus: 10, memoryGiB: 2, diskGiB: 390))
    }

    func testOnlyACLIThatTakesTheSizeFlagsGetsThem() {
        XCTAssertFalse(LocalMachineSizing.isSupported(cliVersion: nil))
        XCTAssertFalse(LocalMachineSizing.isSupported(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 27)))
        XCTAssertTrue(LocalMachineSizing.isSupported(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 28)))
    }

    func testTheSizeGoesToCreateLocalAsFlags() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, sizeLimits: mac)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        wizard.draft.localSize = LocalMachineSize(cpus: 6, memoryGiB: 12, diskGiB: 60)
        XCTAssertEqual(wizard.plan.first?.arguments, [
            "machines", "create-local", "lab", "--add", "--cpus", "6", "--memory", "12", "--disk", "60",
        ])
        XCTAssertTrue(wizard.problems.isEmpty)

        wizard.draft.localSize = LocalMachineSize(cpus: 64, memoryGiB: 12, diskGiB: 60)
        XCTAssertEqual(wizard.problems.map(\.field), [.size])
    }

    func testAnOlderCLIKeepsItsDefaultSizeAndGetsNoFlags() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true)
        wizard.choose(.localVM)
        wizard.draft.name = "lab"
        wizard.draft.localSize = LocalMachineSize(cpus: 6, memoryGiB: 12, diskGiB: 60)
        XCTAssertEqual(wizard.plan.first?.arguments, ["machines", "create-local", "lab", "--add"])
        XCTAssertTrue(wizard.problems.isEmpty)
    }

    func testAServerIsNeverSized() {
        var wizard = MachineWizard(existingMachines: [], limaFound: true, unattended: true, sizeLimits: mac)
        wizard.choose(.server)
        wizard.draft.localSize = LocalMachineSize(cpus: 64, memoryGiB: 1, diskGiB: 1)
        XCTAssertFalse(wizard.problems.contains { $0.field == .size })
    }

    func testTheSizeReadsAsOneLine() {
        XCTAssertEqual(
            LocalMachineSize(cpus: 1, memoryGiB: 8, diskGiB: 40).summary, "1 CPU, 8 GiB of memory, a 40 GiB disk")
        XCTAssertEqual(
            LocalMachineSize(cpus: 4, memoryGiB: 8, diskGiB: 40).summary, "4 CPUs, 8 GiB of memory, a 40 GiB disk")
    }
}
