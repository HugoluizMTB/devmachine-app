import XCTest
@testable import DevmachineCore

final class ProcessListTests: XCTestCase {
    private let sample = """
     17270 17269 -zsh
     34661 17270 claude
     19171 19170 -zsh
     41877 61839 claude bg-pty-host
     55555 19171 /opt/homebrew/bin/node
    """

    func testParsesPidParentAndProgram() {
        let entries = ProcessTree.parse(sample)
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.first?.pid, 17270)
        XCTAssertEqual(entries.first?.parent, 17269)
        XCTAssertEqual(entries.first?.program, "zsh")
        XCTAssertEqual(entries[1].program, "claude")
        XCTAssertEqual(entries[3].program, "claude")
        XCTAssertEqual(entries.last?.program, "node")
    }

    func testFindsTheSessionThatRunsClaude() {
        let roots = ProcessTree.rootsRunning(
            "claude", roots: [17270, 19171], in: ProcessTree.parse(sample))
        XCTAssertEqual(roots, [17270])
    }

    func testClaudeDeeperInTheTreeStillCounts() {
        let entries = ProcessTree.parse("""
         100 1 -zsh
         200 100 npm
         300 200 claude
        """)
        XCTAssertEqual(ProcessTree.rootsRunning("claude", roots: [100], in: entries), [100])
    }

    func testARootThatIsItselfTheProgramDoesNotCount() {
        let entries = ProcessTree.parse("100 1 claude")
        XCTAssertTrue(ProcessTree.rootsRunning("claude", roots: [100], in: entries).isEmpty)
    }

    func testGarbageLinesAreSkipped() {
        XCTAssertTrue(ProcessTree.parse("nonsense\n\n").isEmpty)
    }
}
