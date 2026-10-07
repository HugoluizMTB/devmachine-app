import Foundation

public struct UsageHarness: Equatable, Sendable {
    public let harness: String
    public let package: String

    public init(harness: String, package: String) {
        self.harness = harness
        self.package = package
    }
}

/// The board written when `home.yml` is missing or reset: today's Home.
public enum DefaultBoard {
    public static let surface = "home"

    public static func make(usage: [UsageHarness]) -> Board {
        var board = Board(surface: surface, widgets: [
            BoardWidget(
                id: "clock", type: "devmachine-app/clock",
                frame: BoardFrame(x: 368, y: 24, w: 320, h: 160), size: "medium", z: 1),
            BoardWidget(
                id: "summary", type: "devmachine-app/summary",
                frame: BoardFrame(x: 368, y: 200, w: 640, h: 160), size: "wide", z: 2),
            BoardWidget(
                id: "machines", type: "devmachine-app/machines",
                frame: BoardFrame(x: 24, y: 24, w: 320, h: 320), size: "large", z: 3),
        ])
        for (index, entry) in usage.enumerated() {
            board.widgets.append(BoardWidget(
                id: board.uniqueID(base: "\(entry.harness)-usage"), type: "\(entry.package)/usage",
                with: ["harness": .string(entry.harness)],
                frame: BoardFrame(x: 24, y: 360 + index * 176, w: 320, h: 160), size: "medium", z: 4 + index))
        }
        return board
    }
}

/// Which widgets each surface already received through `places`, so one
/// the person removed is not added again.
public struct WidgetPlacements: Equatable, Sendable {
    public private(set) var placed: [String: Set<String>]

    public init(placed: [String: Set<String>] = [:]) {
        self.placed = placed
    }

    public func contains(_ widget: String, on surface: String) -> Bool {
        placed[surface]?.contains(widget) ?? false
    }

    public mutating func insert(_ widget: String, on surface: String) {
        placed[surface, default: []].insert(widget)
    }

    public mutating func reset(_ surface: String) {
        placed[surface] = nil
    }
}

public struct WidgetPlacementsFile: Sendable {
    private struct File: Codable {
        let version: Int
        let placed: [String: [String]]
    }

    private static let version = 1

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/widget-placements.json")
    }

    public func load() -> WidgetPlacements {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == Self.version
        else { return WidgetPlacements() }
        return WidgetPlacements(placed: file.placed.mapValues(Set.init))
    }

    public func save(_ placements: WidgetPlacements) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(version: Self.version, placed: placements.placed.mapValues { $0.sorted() }))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

public struct PlacementResult: Equatable, Sendable {
    public let board: Board
    public let placements: WidgetPlacements
    public let boardChanged: Bool
    public let placementsChanged: Bool
}

public enum WidgetPlacer {
    public static func place(
        on board: Board, catalog: WidgetCatalog, placements: WidgetPlacements, canvasWidth: Int,
        contract: WidgetContract = .current, isEligible: (CatalogWidget) -> Bool
    ) -> PlacementResult {
        var board = board
        var placements = placements
        var boardChanged = false
        var placementsChanged = false
        let surface = board.surface
        for widget in catalog.widgets where widget.places.contains(surface)
            && widget.surfaces.contains(surface) && widget.available
            && !placements.contains(widget.name, on: surface) && isEligible(widget) {
            if !board.widgets.contains(where: { $0.type == widget.name }) {
                board.widgets.append(newInstance(of: widget, on: board, canvasWidth: canvasWidth, contract: contract))
                boardChanged = true
            }
            placements.insert(widget.name, on: surface)
            placementsChanged = true
        }
        return PlacementResult(
            board: board, placements: placements, boardChanged: boardChanged, placementsChanged: placementsChanged)
    }

    public static func newInstance(
        of widget: CatalogWidget, on board: Board, canvasWidth: Int, contract: WidgetContract = .current
    ) -> BoardWidget {
        let preset = CanvasLayout.presetSize(widget.defaultSize, contract: contract)
        let size = preset ?? CanvasLayout.minimumSize(sizes: widget.sizes, contract: contract)
        let spot = CanvasLayout.firstFreeSpot(for: size, avoiding: board.widgets.map(\.frame), bandWidth: canvasWidth)
        return BoardWidget(
            id: board.uniqueID(base: widget.name.replacingOccurrences(of: "/", with: "-")), type: widget.name,
            frame: spot, size: preset == nil ? BoardWidget.customSize : widget.defaultSize, z: board.topZ + 1)
    }

    public static func harness(of widget: CatalogWidget) -> String? {
        guard widget.source.name == "app/harness-usage" else { return nil }
        return WidgetTemplate.arguments(of: widget, values: [:])["harness"]
    }
}
