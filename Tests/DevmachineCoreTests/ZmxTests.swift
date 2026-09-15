import XCTest
@testable import DevmachineCore

final class ZmxTests: XCTestCase {
    func testTheSocketDirectoryIsShortAndPerUser() {
        XCTAssertEqual(Zmx.socketDirectory(uid: 501), "/tmp/zmx-501")
    }

    func testASeparatorInTheNameIsReplaced() {
        XCTAssertEqual(
            Zmx.sessionName(from: "dev/acme", socketDirectory: "/tmp/zmx-501"), "dev-acme")
    }

    func testALeadingDotIsDropped() {
        XCTAssertEqual(Zmx.sessionName(from: "..", socketDirectory: "/tmp/zmx-501"), "shell")
        XCTAssertEqual(Zmx.sessionName(from: ".git", socketDirectory: "/tmp/zmx-501"), "git")
    }

    func testALongNameIsCutToFitTheSocketPath() {
        let long = String(repeating: "a", count: 200)
        let name = Zmx.sessionName(from: long, socketDirectory: "/tmp/zmx-501")
        XCTAssertEqual(name.utf8.count, Zmx.nameLimit(socketDirectory: "/tmp/zmx-501"))
        XCTAssertLessThan("/tmp/zmx-501/\(name)".utf8.count, Zmx.socketPathLimit)
    }

    func testTheEnvironmentNamesTheShellAndTheSocketDirectory() {
        let env = Zmx.environment(shell: "/bin/zsh", socketDirectory: "/tmp/zmx-501")
        XCTAssertTrue(env.contains("SHELL=/bin/zsh"))
        XCTAssertTrue(env.contains("ZMX_DIR=/tmp/zmx-501"))
        XCTAssertTrue(env.contains("ZMX_NO_DETACH_KEY=1"))
    }
}

final class ZmxListParserTests: XCTestCase {
    func testReadsNamePidClientsAndDirectory() {
        let line = "  name=acme\tpid=13022\tclients=1\tcreated=1789499412"
            + "\tcwd=file://Mac.local/Users/alice/dev/acme\tclaude=1"
        let sessions = ZmxListParser.parse(line)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.name, "acme")
        XCTAssertEqual(sessions.first?.pid, 13022)
        XCTAssertEqual(sessions.first?.clients, 1)
        XCTAssertEqual(sessions.first?.directory, "/Users/alice/dev/acme")
    }

    func testTheCurrentSessionMarkerIsNotPartOfTheName() {
        let sessions = ZmxListParser.parse("→ name=acme\tpid=1\tclients=0\tcreated=1")
        XCTAssertEqual(sessions.first?.name, "acme")
    }

    func testALineWithoutAPidIsSkipped() {
        let sessions = ZmxListParser.parse("  name=gone\terr=SocketMissing\tstatus=cleaning up")
        XCTAssertTrue(sessions.isEmpty)
    }

    func testASessionWithoutADirectoryStillParses() {
        let sessions = ZmxListParser.parse("  name=acme\tpid=7\tclients=0\tcreated=1")
        XCTAssertNil(sessions.first?.directory)
        XCTAssertEqual(sessions.first?.pid, 7)
    }
}
