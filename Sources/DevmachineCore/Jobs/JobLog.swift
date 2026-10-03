import Foundation

/// A job's output, keeping only the newest lines: a first sync prints tens
/// of thousands, and every one of them would be drawn.
public struct JobLog: Equatable, Sendable {
    public static let defaultCap = 5000

    public private(set) var lines: [String] = []
    public private(set) var dropped = 0
    private let cap: Int

    public init(cap: Int = JobLog.defaultCap) {
        self.cap = cap
    }

    public mutating func append(contentsOf more: [String]) {
        lines.append(contentsOf: more)
        let over = lines.count - cap
        guard over > 0 else { return }
        lines.removeFirst(over)
        dropped += over
    }

    public var shown: [String] {
        dropped == 0 ? lines : ["… \(dropped) earlier lines not kept"] + lines
    }
}
