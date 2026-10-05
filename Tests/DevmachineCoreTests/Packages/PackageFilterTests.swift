import XCTest
@testable import DevmachineCore

final class PackageFilterTests: XCTestCase {
    private func entry(_ name: String, source: String = "release", category: String? = nil,
                       scope: String = "machine", summary: String = "", on: [String] = []) -> PackageEntry {
        PackageEntry(name: name, scope: scope, source: source, summary: summary, category: category,
                     platforms: [], needs: [], credentialNames: [], installedOn: on)
    }

    private lazy var entries = [
        entry("docker", category: "Containers", summary: "Docker engine"),
        entry("mine", source: "local", category: "Developer tools"),
        entry("node", category: "Developer tools", scope: "workspace", on: ["workspace acme"]),
        entry("odd"),
    ]

    func testCatalogIsReleaseOnly() {
        XCTAssertEqual(PackageFilter().apply(entries, statuses: nil).map(\.name), ["docker", "node", "odd"])
    }

    func testLocalTab() {
        XCTAssertEqual(PackageFilter(tab: .local).apply(entries, statuses: nil).map(\.name), ["mine"])
    }

    func testInstalledWithoutTargetUsesInstalledOn() {
        XCTAssertEqual(PackageFilter(tab: .installed).apply(entries, statuses: nil).map(\.name), ["node"])
    }

    func testInstalledWithTargetUsesStatuses() {
        let statuses: [String: PackageStatus] = ["docker": .pendingRemove, "node": .available]
        XCTAssertEqual(PackageFilter(tab: .installed).apply(entries, statuses: statuses).map(\.name), ["docker"])
    }

    func testQueryMatchesNameAndSummaryCaseInsensitive() {
        XCTAssertEqual(PackageFilter(query: "ENGINE").apply(entries, statuses: nil).map(\.name), ["docker"])
    }

    func testCategoryAndScope() {
        XCTAssertEqual(PackageFilter(categories: ["Developer tools"]).apply(entries, statuses: nil).map(\.name), ["node"])
        XCTAssertEqual(PackageFilter(categories: ["Other"]).apply(entries, statuses: nil).map(\.name), ["odd"])
        XCTAssertEqual(PackageFilter(scope: "machine").apply(entries, statuses: nil).map(\.name), ["docker", "odd"])
    }

    func testCategoriesSortedOtherLast() {
        XCTAssertEqual(PackageFilter.categories(in: entries), ["Containers", "Developer tools", "Other"])
    }
}
