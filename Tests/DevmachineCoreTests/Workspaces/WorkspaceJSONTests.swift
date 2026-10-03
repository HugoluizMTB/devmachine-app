import XCTest
@testable import DevmachineCore

final class WorkspaceJSONTests: XCTestCase {
    func testDefaultsVariablesAndSharingComeFromCLI0729() {
        XCTAssertFalse(WorkspaceJSON.isSupported(cliVersion: nil))
        XCTAssertFalse(WorkspaceJSON.isSupported(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 28)))
        XCTAssertTrue(WorkspaceJSON.isSupported(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 29)))
    }

    func testAVariableDecodesWithANullDefaultAndNoType() throws {
        let json = Data(#"""
            [{"name":"theme","summary":"The prompt.","default":"clean","type":"string"},
             {"name":"zones","summary":"Zones.","default":[],"type":"list"},
             {"name":"token_path","summary":"Where it is.","default":null}]
            """#.utf8)
        let variables = try JSONDecoder().decode([PackageVariable].self, from: json)
        XCTAssertEqual(variables[0], PackageVariable(name: "theme", summary: "The prompt.", default: .string("clean"), type: .string))
        XCTAssertEqual(variables[1].type, .list)
        XCTAssertEqual(variables[1].default?.text, "[]")
        XCTAssertNil(variables[2].default)
        XCTAssertNil(variables[2].type)
    }

    func testAVariableEncodesBackForTheCache() throws {
        let variable = PackageVariable(name: "ports", summary: "", default: .array([.int(3000)]), type: .list)
        let decoded = try JSONDecoder().decode(PackageVariable.self, from: JSONEncoder().encode(variable))
        XCTAssertEqual(decoded, variable)
    }

    func testANumberMustReadAsOne() {
        let number = PackageVariable(name: "port", summary: "", default: .int(3000), type: .number)
        XCTAssertNil(number.problem("8080"))
        XCTAssertNil(number.problem("2.5"))
        XCTAssertEqual(number.problem("eighty"), "port takes a number.")
        XCTAssertNil(PackageVariable(name: "theme", summary: "", default: nil, type: nil).problem("anything"))
    }

    func testTheDefaultReadsAsText() {
        XCTAssertEqual(PackageVariable(name: "a", summary: "", default: .bool(true), type: .boolean).defaultText, "true")
        XCTAssertEqual(PackageVariable(name: "a", summary: "", default: nil, type: nil).defaultText, "none")
    }
}

final class WorkspaceSharingTests: XCTestCase {
    private let acme = WorkspaceSummary(
        name: "acme", machine: "main", user: "acme", packages: ["claude-code", "glab"],
        credentials: ["claude": "own"])

    func testALoginFollowsTheWorkspaceThenTheConfigurationThenThePackage() {
        let logins = WorkspaceLogin.logins(
            packages: ["claude-code", "glab", "zsh"],
            declared: [
                "claude-code": [PackageCredential(name: "claude", kind: "file", scope: "machine")],
                "glab": [PackageCredential(name: "glab", kind: "secret", scope: "workspace")],
                "dev": [PackageCredential(name: "gh", kind: "secret", scope: "machine")],
            ],
            configuration: ["glab": "machine"])
        XCTAssertEqual(logins, [
            WorkspaceLogin(name: "claude", package: "claude-code", inherited: "machine"),
            WorkspaceLogin(name: "glab", package: "glab", inherited: "machine"),
        ])
    }

    func testEditWritesOnlyTheAnswersThatChanged() {
        var flow = WorkspaceFlow.edit(acme)
        XCTAssertEqual(flow.sharing, ["claude": "own"])
        XCTAssertFalse(flow.canAdvance)
        flow.setSharing("glab", "own")
        flow.setSharing("claude", nil)
        XCTAssertEqual(flow.changes.share, [WorkspaceShare(name: "claude", value: ""), WorkspaceShare(name: "glab", value: "own")])
        XCTAssertTrue(flow.canAdvance)
        flow.next()
        XCTAssertEqual(flow.plan[0].arguments, [
            "workspaces", "edit", "acme", "--share", "claude=", "--share", "glab=own", "--yes",
        ])
    }

    func testATypedSettingIsSetAndAnEmptyOneTakenOut() {
        var flow = WorkspaceFlow.edit(WorkspaceSummary(
            name: "acme", machine: "main", user: "acme", packages: ["zsh"], settings: ["zsh.theme": "clean"]))
        XCTAssertEqual(flow.settingValue("zsh.theme"), "clean")
        XCTAssertEqual(flow.settingValue("zsh.plugins"), "")
        flow.setSetting("zsh.plugins", "[git]")
        flow.setSetting("zsh.theme", "")
        XCTAssertEqual(flow.changes.set, [WorkspaceSetting(key: "zsh.plugins", value: "[git]")])
        XCTAssertEqual(flow.changes.unset, ["zsh.theme"])
    }

    func testTheRealDefaultsArePreselectedAndBadged() {
        let packages = ["zsh", "dev", "mise", "glab"].map {
            PackageInfo(name: $0, scope: "workspace", summary: "", source: "release")
        }
        let cards = WorkspacePackageCatalog.cards(from: packages, defaults: ["zsh", "glab", "gone"])
        XCTAssertEqual(cards.filter(\.isRecommended).map(\.name), ["glab", "zsh"])
        XCTAssertEqual(WorkspacePackageCatalog.preselected(from: cards, defaults: ["zsh", "glab", "gone"]), ["zsh", "glab"])
    }
}
