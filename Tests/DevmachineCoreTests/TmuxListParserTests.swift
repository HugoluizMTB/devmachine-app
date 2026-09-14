import XCTest
@testable import DevmachineCore

final class TmuxListParserTests: XCTestCase {
    func testParseiaSessoesEDetectaClaude() {
        let out = """
        dash-claude|3
        dash-shell|1
        @@PANES@@
        dash-claude|claude
        dash-claude|zsh
        dash-shell|zsh
        """
        let s = TmuxListParser.parse(out)
        XCTAssertEqual(s, [
            TmuxSession(name: "dash-claude", windows: 3, hasClaude: true),
            TmuxSession(name: "dash-shell", windows: 1, hasClaude: false)
        ])
    }

    func testSaidaVaziaSemServidor() {
        XCTAssertEqual(TmuxListParser.parse("@@PANES@@\n"), [])
        XCTAssertEqual(TmuxListParser.parse(""), [])
    }
}
