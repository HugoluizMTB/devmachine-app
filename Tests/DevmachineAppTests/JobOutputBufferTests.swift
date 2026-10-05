import XCTest
@testable import DevmachineApp

@MainActor
final class JobOutputBufferTests: XCTestCase {
    func testDeliversEveryLineInOrderInFewBatches() async {
        var received: [String] = []
        var batches = 0
        let buffer = JobOutputBuffer { lines in
            received.append(contentsOf: lines)
            batches += 1
        }
        DispatchQueue.concurrentPerform(iterations: 1) { _ in
            for i in 0..<10_000 { buffer.receive(String(i)) }
        }
        for _ in 0..<200 where received.count < 10_000 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(received, (0..<10_000).map(String.init))
        XCTAssertLessThan(batches, 10_000)
    }
}
