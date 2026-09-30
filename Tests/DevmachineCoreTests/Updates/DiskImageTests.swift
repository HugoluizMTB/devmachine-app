import XCTest
@testable import DevmachineCore

final class DiskImageTests: XCTestCase {
    func testAttachIsReadOnlyHiddenAndMachineReadable() {
        let args = DiskImage.attachArguments(
            image: URL(fileURLWithPath: "/tmp/u/Devmachine-0.1.3.dmg"), mountRoot: URL(fileURLWithPath: "/tmp/u/mnt"))
        XCTAssertEqual(args, [
            "attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify",
            "-mountroot", "/tmp/u/mnt", "-plist", "/tmp/u/Devmachine-0.1.3.dmg",
        ])
    }

    func testReadsTheMountPointFromThePlist() throws {
        let plist: [String: Any] = ["system-entities": [
            ["dev-entry": "/dev/disk9"],
            ["dev-entry": "/dev/disk9s1", "mount-point": "/tmp/u/mnt/Devmachine"],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertEqual(DiskImage.mountPoint(fromAttachOutput: data), URL(fileURLWithPath: "/tmp/u/mnt/Devmachine"))
    }

    func testNoMountPointIsNil() {
        XCTAssertNil(DiskImage.mountPoint(fromAttachOutput: Data("nope".utf8)))
    }

    func testDetach() {
        XCTAssertEqual(
            DiskImage.detachArguments(mountPoint: URL(fileURLWithPath: "/tmp/u/mnt/Devmachine")),
            ["detach", "/tmp/u/mnt/Devmachine", "-force"])
    }
}
