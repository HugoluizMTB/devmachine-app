import Foundation

public enum StackCellSize: String, Codable, Sendable, CaseIterable {
    case auto, half, full

    public var next: StackCellSize {
        switch self {
        case .auto: return .half
        case .half: return .full
        case .full: return .auto
        }
    }
}

public struct StackCellRect: Equatable, Sendable {
    public let index: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public enum StackGrid {
    public static func dims(_ n: Int) -> (cols: Int, rows: Int) {
        let cols = max(1, Int(ceil(Double(n).squareRoot())))
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        return (cols, rows)
    }

    public static func layout(_ sizes: [StackCellSize]) -> [StackCellRect] {
        guard !sizes.isEmpty else { return [] }
        let epsilon = 1e-6
        let cols = dims(sizes.count).cols

        let rows = packRows(sizes, cols: cols, epsilon: epsilon)
        let rowCount = rows.count
        let rowHeight = 1.0 / Double(rowCount)

        var rects: [StackCellRect] = []
        for (rowIndex, row) in rows.enumerated() {
            let widths = stretchedWidths(for: row, epsilon: epsilon)
            let y = Double(rowIndex) * rowHeight
            var x = 0.0
            for (item, width) in zip(row, widths) {
                rects.append(StackCellRect(index: item.index, x: x, y: y, width: width, height: rowHeight))
                x += width
            }
        }
        return rects
    }

    private struct Item {
        let index: Int
        let size: StackCellSize
        let width: Double
    }

    private static func desiredWidth(_ size: StackCellSize, cols: Int) -> Double {
        switch size {
        case .auto: return 1.0 / Double(cols)
        case .half: return 0.5
        case .full: return 1.0
        }
    }

    private static func packRows(_ sizes: [StackCellSize], cols: Int, epsilon: Double) -> [[Item]] {
        var rows: [[Item]] = []
        var currentRow: [Item] = []
        var currentWidth = 0.0

        for (index, size) in sizes.enumerated() {
            let item = Item(index: index, size: size, width: desiredWidth(size, cols: cols))

            if size == .full {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                    currentWidth = 0.0
                }
                rows.append([item])
                continue
            }

            if !currentRow.isEmpty && currentWidth + item.width > 1.0 + epsilon {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0.0
            }
            currentRow.append(item)
            currentWidth += item.width
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }

    private static func stretchedWidths(for row: [Item], epsilon: Double) -> [Double] {
        var widths = row.map(\.width)
        let totalWidth = widths.reduce(0, +)
        let autoIndices = row.indices.filter { row[$0].size == .auto }
        guard totalWidth < 1.0 - epsilon, !autoIndices.isEmpty else { return widths }

        let bonus = (1.0 - totalWidth) / Double(autoIndices.count)
        for i in autoIndices {
            widths[i] += bonus
        }
        return widths
    }
}
