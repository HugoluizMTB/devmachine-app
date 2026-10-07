import Foundation

/// A stream's last `capacity` lines; older ones fall off.
public struct LineRing: Equatable, Sendable {
    public let capacity: Int
    public private(set) var lines: [String] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(contentsOf more: [String]) {
        lines.append(contentsOf: more)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }
}

/// Bytes as they arrive into whole lines, holding back a partial line (and
/// a split UTF-8 character) until the rest comes.
public struct LineAssembler: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer[buffer.startIndex..<newline]
            if line.last == 0x0D { line = line.dropLast() }
            lines.append(String(decoding: line, as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    public mutating func flush() -> [String] {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
    }
}
