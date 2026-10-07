import XCTest
@testable import DevmachineCore

final class PackageProviderTests: XCTestCase {
    func testANameIsAPackageAndOneOfItsCommands() throws {
        let parts = try XCTUnwrap(PackageProviderName.parts("acme-tools/load"))
        XCTAssertEqual(parts.package, "acme-tools")
        XCTAssertEqual(parts.command, "load")
        XCTAssertEqual(PackageProviderName.parts("devmachine-app/stats")?.command, "stats")
    }

    func testTheAppPrefixAndOddNamesAreNotPackageProviders() {
        for name in ["app/clock", "acme", "acme/load/x", "-x/load", "acme/-rf", "Acme/load", "acme/", "/load",
                     "{{inputs.p}}/load", "acme/load; rm -rf ~", "acme /load", ""] {
            XCTAssertNil(PackageProviderName.parts(name), name)
        }
    }

    func testRequiredFieldsAreTheOnesWithoutAQuestionMark() {
        let spec = PackageProviderSpec(returns: ["load": "number", "note": "string?", "cpu": "number"], minEvery: "10s")
        XCTAssertEqual(spec.requiredFields, ["cpu", "load"])
    }

    func testTheSpecDecodesFromTheCatalog() throws {
        let spec = try JSONDecoder().decode(
            PackageProviderSpec.self, from: Data(#"{"returns": {"load": "number"}, "min_every": "10s"}"#.utf8))
        XCTAssertEqual(spec, PackageProviderSpec(returns: ["load": "number"], minEvery: "10s"))
    }

    func testAnIncompleteIndexLeavesAnUnknownNameToTheCLI() throws {
        let spec = PackageProviderSpec(returns: [:], minEvery: "10s")
        let index = PackageProviderIndex(providers: ["acme-tools/load": spec], packages: ["acme-tools"], isComplete: false)
        XCTAssertEqual(try index.spec(for: "acme-tools/load"), spec)
        XCTAssertNil(try index.spec(for: "ghost/load"))
        XCTAssertNil(try PackageProviderIndex.unknown.spec(for: "acme-tools/load"))
    }

    func testACompleteIndexNamesWhatIsMissing() {
        let index = PackageProviderIndex(
            providers: ["acme-tools/load": PackageProviderSpec(returns: [:], minEvery: "10s")],
            packages: ["acme-tools"], isComplete: true)
        XCTAssertThrowsError(try index.spec(for: "ghost/load")) {
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.message, "no package ghost")
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.path, ["name"])
        }
        XCTAssertThrowsError(try index.spec(for: "acme-tools/nope")) {
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.message, "acme-tools has no provider nope")
        }
    }
}
