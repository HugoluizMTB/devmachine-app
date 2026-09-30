import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class PaletteRankerTests: XCTestCase {
    private func command(
        _ id: String, _ title: String, _ category: PaletteCategory,
        subtitle: String = "", keywords: [String] = []
    ) -> PaletteCommand {
        PaletteCommand(
            id: id, title: title, subtitle: subtitle, category: category,
            systemImage: "circle", keywords: keywords, action: .goHome)
    }

    private lazy var all: [PaletteCommand] = [
        command("go.home", "Home", .goTo),
        command("go.stats", "Stats", .goTo, keywords: ["ram", "disk"]),
        command("go.subdomains", "Subdomains", .goTo, keywords: ["dns"]),
        command("session.a", "dash", .session, subtitle: "acme"),
        command("session.b", "api", .session, subtitle: "beta"),
        command("action.add-subdomain", "Add subdomain…", .action),
        command("settings.appearance", "Appearance", .settings, subtitle: "Settings"),
    ]

    private func ids(_ sections: [PaletteSection]) -> [String] {
        sections.flatMap(\.commands).map(\.id)
    }

    func testAnEmptyQueryShowsRecentsThenGoToThenSessions() {
        let sections = PaletteRanker.sections(all, query: "", mru: CommandMRU(ids: ["settings.appearance"]))
        XCTAssertEqual(sections.map(\.category), [.recent, .goTo, .session])
        XCTAssertEqual(sections[0].commands.map(\.id), ["settings.appearance"])
        XCTAssertEqual(sections[1].commands.map(\.id), ["go.home", "go.stats", "go.subdomains"])
        XCTAssertEqual(sections[2].commands.map(\.id), ["session.a", "session.b"])
    }

    func testAnEmptyQueryWithoutRecentsStartsWithGoTo() {
        let sections = PaletteRanker.sections(all, query: "", mru: CommandMRU(ids: []))
        XCTAssertEqual(sections.first?.category, .goTo)
    }

    func testARecentCommandIsNotRepeatedInItsOwnGroup() {
        let sections = PaletteRanker.sections(all, query: "", mru: CommandMRU(ids: ["session.b"]))
        XCTAssertEqual(ids(sections).filter { $0 == "session.b" }.count, 1)
    }

    func testRecentsThatNoLongerExistAreSkipped() {
        let sections = PaletteRanker.sections(all, query: "", mru: CommandMRU(ids: ["gone"]))
        XCTAssertNotEqual(sections.first?.category, .recent)
    }

    func testAQueryDropsWhatDoesNotMatch() {
        let found = ids(PaletteRanker.sections(all, query: "sub", mru: CommandMRU(ids: [])))
        XCTAssertEqual(Set(found), ["go.subdomains", "action.add-subdomain"])
    }

    func testTheGroupWithTheBestMatchComesFirst() {
        let sections = PaletteRanker.sections(all, query: "sub", mru: CommandMRU(ids: []))
        XCTAssertEqual(sections.map(\.category), [.goTo, .action])
    }

    func testRecentUseLiftsACommandAboveABetterTextMatch() {
        let plain = PaletteRanker.sections(all, query: "sub", mru: CommandMRU(ids: []))
        XCTAssertEqual(plain.first?.commands.first?.id, "go.subdomains")
        let boosted = PaletteRanker.sections(
            all, query: "sub", mru: CommandMRU(ids: ["action.add-subdomain"]))
        XCTAssertEqual(boosted.first?.commands.first?.id, "action.add-subdomain")
    }

    func testKeywordsFindACommand() {
        let found = ids(PaletteRanker.sections(all, query: "disk", mru: CommandMRU(ids: [])))
        XCTAssertEqual(found, ["go.stats"])
    }

    func testASessionIsFoundByItsWorkspace() {
        let found = ids(PaletteRanker.sections(all, query: "beta", mru: CommandMRU(ids: [])))
        XCTAssertEqual(found, ["session.b"])
    }

    func testCommandsOfTheCurrentWorkspaceComeFirst() {
        let commands = [
            command("ws.a", "New Claude session", .workspace, subtitle: "acme"),
            command("ws.b", "New Claude session", .workspace, subtitle: "beta"),
        ]
        let sections = PaletteRanker.sections(
            commands, query: "claude", mru: CommandMRU(ids: []), currentWorkspace: "beta")
        XCTAssertEqual(ids(sections), ["ws.b", "ws.a"])
    }
}
