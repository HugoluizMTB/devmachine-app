import XCTest
@testable import DevmachineCore

final class SemanticVersionTests: XCTestCase {
    func testParsesATagWithOrWithoutTheLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion(" 0.1.2\n"), SemanticVersion(major: 0, minor: 1, patch: 2))
    }

    func testATwoPartVersionHasPatchZero() {
        XCTAssertEqual(SemanticVersion("2.4"), SemanticVersion(major: 2, minor: 4, patch: 0))
    }

    func testRefusesWhatIsNotAVersion() {
        XCTAssertNil(SemanticVersion("dev"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("1"))
        XCTAssertNil(SemanticVersion("1.x.3"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
    }

    func testComparesNumericallyNotAsText() {
        XCTAssertLessThan(SemanticVersion("0.1.9")!, SemanticVersion("0.1.10")!)
        XCTAssertLessThan(SemanticVersion("0.9.0")!, SemanticVersion("1.0.0")!)
        XCTAssertLessThan(SemanticVersion("1.2.3")!, SemanticVersion("1.3.0")!)
        XCTAssertFalse(SemanticVersion("1.2.3")! < SemanticVersion("1.2.3")!)
    }

    func testAPrereleaseComesBeforeItsRelease() {
        let beta = SemanticVersion("1.2.3-beta.1")!
        XCTAssertTrue(beta.isPrerelease)
        XCTAssertLessThan(beta, SemanticVersion("1.2.3")!)
        XCTAssertLessThan(SemanticVersion("1.2.3-beta.2")!, SemanticVersion("1.2.3-beta.10")!)
        XCTAssertLessThan(SemanticVersion("1.2.3-alpha")!, SemanticVersion("1.2.3-beta")!)
    }

    func testBuildMetadataIsIgnored() {
        XCTAssertEqual(SemanticVersion("1.2.3+sha.abc"), SemanticVersion("1.2.3"))
    }

    func testFindsTheVersionInsideAWholeLine() {
        XCTAssertEqual(SemanticVersion.first(in: "devmachine version v0.7.1 (abc123)"), SemanticVersion("0.7.1"))
        XCTAssertEqual(SemanticVersion.first(in: "0.7.1\n"), SemanticVersion("0.7.1"))
        XCTAssertNil(SemanticVersion.first(in: "dev"))
    }

    func testDescriptionHasNoLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3")!.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("1.2.3-rc.1")!.description, "1.2.3-rc.1")
    }
}
