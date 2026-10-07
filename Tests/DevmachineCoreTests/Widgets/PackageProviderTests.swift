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
                     "{{inputs.p}}/load", "acme/load; rm -rf ~", "acme /load", "", "0acme/load", "acme.tools/load",
                     "acme/load.sh", "acme/9load"] {
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
        XCTAssertThrowsError(try index.spec(for: "acme-tools/nope")) {
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.message,
                           "source.name acme-tools/nope: acme-tools has no provider nope; its providers: load")
        }
    }

    func testACatalogIsCompleteOnlyWhenItReadAReleaseAndListsProviders() {
        let spec = PackageProviderSpec(returns: [:], minEvery: "10s")
        let listed = [CatalogProvider(name: "acme-tools/load", spec: spec)]
        XCTAssertTrue(WidgetCatalog(engine: "1.3", packagesRelease: "v41", widgets: [], providers: listed)
            .packageProviderIndex.isComplete)
        let noRelease = WidgetCatalog(engine: "1.3", packagesRelease: "", widgets: [], providers: listed).packageProviderIndex
        XCTAssertFalse(noRelease.isComplete)
        XCTAssertEqual(noRelease.packages, ["acme-tools"])
        let older = WidgetCatalog(engine: "1.2", packagesRelease: "v41", widgets: [], providers: nil).packageProviderIndex
        XCTAssertFalse(older.isComplete)
        XCTAssertEqual(older.packages, [])
    }

    func testACompleteIndexNamesWhatIsMissing() {
        let index = PackageProviderIndex(
            providers: ["acme-tools/load": PackageProviderSpec(returns: [:], minEvery: "10s")],
            packages: ["acme-tools", "mine"], isComplete: true)
        XCTAssertThrowsError(try index.spec(for: "ghost/load")) {
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.message,
                           "source.name ghost/load: no package ghost in the release or your own packages")
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.path, ["name"])
        }
        XCTAssertThrowsError(try index.spec(for: "acme-tools/nope")) {
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.message,
                           "source.name acme-tools/nope: acme-tools has no provider nope; its providers: load")
        }
        XCTAssertThrowsError(try index.spec(for: "mine/load")) {
            XCTAssertEqual(($0 as? WidgetSpecProblem)?.message, "source.name mine/load: mine has no provider load; its providers: none")
        }
    }
}
