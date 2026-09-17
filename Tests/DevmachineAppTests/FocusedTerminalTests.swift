import XCTest
import DevmachineCore
@testable import DevmachineApp

final class FocusedTerminalTests: XCTestCase {
    func testARemotePaneIsTaggedByItsWorkspaceAndSession() {
        XCTAssertEqual(
            FocusedTerminal.tag(for: .remote(alias: "acme-devmachine", session: "dash")),
            "term:acme-devmachine/dash")
    }

    func testALocalPaneIsTaggedUnderTheLocalWorkspace() {
        XCTAssertEqual(
            FocusedTerminal.tag(for: .local(session: "acme", path: "/dev/acme")),
            "term:\(Workspace.local.alias)/acme")
    }

    /// The tag has to read back as the reference the grid works with, or
    /// "maximize" cannot tell which cell has the keyboard.
    func testEveryTagReadsBackAsItsReference() {
        for kind in [TerminalKind.remote(alias: "acme-devmachine", session: "dash"),
                     .local(session: "acme", path: "/dev/acme")] {
            let tag = FocusedTerminal.tag(for: kind)
            let body = tag.dropFirst(FocusedTerminal.prefix.count)
            let slash = try! XCTUnwrap(body.firstIndex(of: "/"))
            let ref = SessionRef(
                alias: String(body[..<slash]), name: String(body[body.index(after: slash)...]))
            switch kind {
            case let .remote(alias, session):
                XCTAssertEqual(ref, SessionRef(alias: alias, name: session))
            case let .local(session, _):
                XCTAssertEqual(ref, SessionRef(alias: Workspace.local.alias, name: session))
            }
        }
    }
}
