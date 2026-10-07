import Foundation

/// The board written when `home.yml` is missing or reset, laid out for the
/// canvas width known at that moment (1280 when none is): every machine in a
/// row at the top, the usage cards side by side under it, and the clock with
/// the summary pill under it on the right edge.
public enum DefaultBoard {
    public static let surface = "home"
    public static let fallbackWidth = 1280
    /// `MachineStatsCard.width`, `MachinesWidgetView.nominalCardHeight` and
    /// `cardSpacing`, which Core cannot import; a test keeps them equal.
    public static let machineCard = CanvasSize(w: 184, h: 132)
    public static let machineCardSpacing = 12
    public static let fallbackMachines = 3
    /// The tallest usage card drawn with a typical snapshot (Claude's three
    /// windows, daily chart and three models) is 591 points at any width.
    public static let usageContentHeight = 600
    public static let usageWidth = 384
    public static let usageMinWidth = 336
    public static let usageMaxWidth = 480
    /// The summary pill drawn with two-digit counts.
    public static let summaryPillWidth = 336
    public static let summaryHeight = 160
    public static let clockMaxWidth = 416
    private static let padding = 24
    private static let gap = 16
    private static let snap = 8
    private static let machineRowsMax = 2

    public static func make(
        harnesses: [String], canvasWidth: Int = fallbackWidth, machines: Int = fallbackMachines
    ) -> Board {
        let width = canvasWidth > 0 ? canvasWidth : fallbackWidth
        let rightEdge = down(width - padding)
        let inner = rightEdge - padding
        let pairWidth = max(0, span(min(harnesses.count, 2), usageWidth, gap))
        let columnWidth = min(clockMaxWidth, max(summaryPillWidth, down(inner - gap - pairWidth)))
        let columnX = rightEdge - columnWidth
        let leftWidth = columnX - gap - padding

        let clock = clockFrame(x: columnX, width: columnWidth)
        let machinesRow = machinesSize(count: machines > 0 ? machines : fallbackMachines, within: leftWidth)
        var board = Board(surface: surface, widgets: [
            BoardWidget(
                id: "machines", type: "devmachine-app/machines",
                frame: BoardFrame(x: padding, y: padding, w: machinesRow.w, h: machinesRow.h),
                size: BoardWidget.customSize, z: 1),
            BoardWidget(id: "clock", type: "devmachine-app/clock", frame: clock, size: BoardWidget.customSize, z: 2),
            BoardWidget(
                id: "summary", type: "devmachine-app/summary",
                frame: BoardFrame(
                    x: rightEdge - summaryPillWidth, y: clock.y + clock.h + gap, w: summaryPillWidth, h: summaryHeight),
                size: BoardWidget.customSize, z: 3),
        ])
        let columns = usageColumns(count: harnesses.count, within: leftWidth)
        let cardWidth = columns > 0 ? min(usageMaxWidth, down((leftWidth - (columns - 1) * gap) / columns)) : 0
        let usageTop = padding + machinesRow.h + gap
        for (index, harness) in harnesses.enumerated() {
            let column = index % columns
            let row = index / columns
            board.widgets.append(BoardWidget(
                id: board.uniqueID(base: "\(harness)-usage"), type: "devmachine-app/usage", with: ["harness": .string(harness)],
                frame: BoardFrame(
                    x: padding + column * (cardWidth + gap), y: usageTop + row * (usageContentHeight + gap),
                    w: cardWidth, h: usageContentHeight),
                size: BoardWidget.customSize, z: 4 + index))
        }
        return board
    }

    /// Tall enough that the clock's font is held back by its width, never
    /// its height (`ClockWidgetSizing` takes the smaller of the two).
    private static func clockFrame(x: Int, width: Int) -> BoardFrame {
        let font = min(150, Int(Double(width) / 2.8))
        return BoardFrame(x: x, y: padding, w: width, h: up(font * 2))
    }

    /// Past one row a second one, and past that the widget's own "+N more".
    private static func machinesSize(count: Int, within width: Int) -> CanvasSize {
        var columns = max(1, min(count, (width + machineCardSpacing) / (machineCard.w + machineCardSpacing)))
        while columns > 1 && up(span(columns, machineCard.w, machineCardSpacing)) > width { columns -= 1 }
        let rows = min(machineRowsMax, (count + columns - 1) / columns)
        return CanvasSize(
            w: up(span(columns, machineCard.w, machineCardSpacing)), h: up(span(rows, machineCard.h, machineCardSpacing)))
    }

    /// Two side by side whenever two fit at the narrowest width, so a second
    /// harness never drops to its own row on a small window.
    private static func usageColumns(count: Int, within width: Int) -> Int {
        guard count > 0 else { return 0 }
        let roomy = (width + gap) / (usageWidth + gap)
        let narrow = min(2, (width + gap) / (usageMinWidth + gap))
        return min(count, max(1, roomy, narrow))
    }

    private static func span(_ count: Int, _ item: Int, _ spacing: Int) -> Int {
        count * item + (count - 1) * spacing
    }

    private static func down(_ value: Int) -> Int { value / snap * snap }
    private static func up(_ value: Int) -> Int { (value + snap - 1) / snap * snap }
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
    private let writeData: @Sendable (Data, URL) throws -> Void

    public init(fileURL: URL) {
        self.init(fileURL: fileURL, writeData: { data, url in try data.write(to: url, options: .atomic) })
    }

    init(fileURL: URL, writeData: @escaping @Sendable (Data, URL) throws -> Void) {
        self.fileURL = fileURL
        self.writeData = writeData
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/widget-placements.json")
    }

    public func load() -> WidgetPlacements {
        (try? read()) ?? WidgetPlacements()
    }

    public var brokenFileURL: URL { fileURL.appendingPathExtension("broken") }

    /// Replaces only `surface`'s set in the file, so Home and each sidebar
    /// never write over one another's placements. A file that cannot be
    /// decoded never blocks a save: it moves to `brokenFileURL`, whose URL is
    /// returned so the caller can log it, and a fresh file starts.
    @discardableResult
    public func save(_ placements: WidgetPlacements, surface: String) throws -> URL? {
        var moved: URL?
        var merged: WidgetPlacements
        if let current = try read() {
            merged = current
        } else {
            moved = try setBrokenFileAside()
            merged = WidgetPlacements()
        }
        merged.reset(surface)
        for widget in placements.placed[surface] ?? [] { merged.insert(widget, on: surface) }
        do {
            try write(merged)
        } catch {
            guard let moved else { throw error }
            throw WidgetPlacementsFileError.cannotWriteAfterSettingAside(
                path: fileURL.path, broken: moved.path, reason: error.localizedDescription)
        }
        return moved
    }

    /// Nil when the file exists but does not decode or has another version.
    private func read() throws -> WidgetPlacements? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return WidgetPlacements() }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw WidgetPlacementsFileError.unreadable(path: fileURL.path, reason: error.localizedDescription)
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == Self.version else { return nil }
        return WidgetPlacements(placed: file.placed.mapValues(Set.init))
    }

    private func setBrokenFileAside() throws -> URL {
        let target = brokenFileURL
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: fileURL, to: target)
        } catch {
            throw WidgetPlacementsFileError.cannotSetAside(path: fileURL.path, reason: error.localizedDescription)
        }
        return target
    }

    private func write(_ placements: WidgetPlacements) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(version: Self.version, placed: placements.placed.mapValues { $0.sorted() }))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeData(data, fileURL)
    }
}

public enum WidgetPlacementsFileError: LocalizedError, Equatable {
    case unreadable(path: String, reason: String)
    case cannotSetAside(path: String, reason: String)
    case cannotWriteAfterSettingAside(path: String, broken: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(path, reason):
            return "Cannot read \(path): \(reason)"
        case let .cannotSetAside(path, reason):
            return "Cannot move the broken \(path) aside: \(reason)"
        case let .cannotWriteAfterSettingAside(path, broken, reason):
            return "Cannot write \(path): \(reason). The broken file it replaced was moved to \(broken)."
        }
    }
}

extension CatalogWidget {
    /// Whether the widget adds itself to `surface` the first time it is seen
    /// there; a stack passes its layout, which the widget must fit too.
    public func placesItself(on surface: String, fitting layout: String? = nil) -> Bool {
        places.contains(surface) && surfaces.contains(surface) && available && (layout.map(fits.contains) ?? true)
    }
}

public struct PlacementResult: Equatable, Sendable {
    public let board: Board
    public let placements: WidgetPlacements
    public let boardChanged: Bool
    public let placementsChanged: Bool
}

public enum WidgetPlacer {
    /// Entries of an older packages release that already show one option of a
    /// choice widget, keyed `<type>#<option>`.
    private static let legacyTypes: [String: String] = [
        "devmachine-app/usage#claude": "claude-code/usage",
        "devmachine-app/usage#codex": "codex/usage",
    ]

    /// `options` maps an option source (such as `harnesses`) to its values.
    /// A widget that places itself and takes one choice from a source is placed
    /// once per option. A placing widget whose choice cannot be decided is
    /// never placed, so no copy without its choice reaches the board.
    public static func place(
        on board: Board, catalog: WidgetCatalog, placements: WidgetPlacements, canvasWidth: Int,
        contract: WidgetContract = .current, options: [String: [String]] = [:],
        isShown: (CatalogWidget) -> Bool = { _ in false }, isEligible: (CatalogWidget) -> Bool
    ) -> PlacementResult {
        var board = board
        var placements = placements
        var boardChanged = false
        var placementsChanged = false
        let surface = board.surface
        for widget in catalog.widgets where widget.placesItself(on: surface) {
            if let choice = oneChoice(of: widget) {
                let values = contract.allowed(options[choice.source] ?? [], from: choice.source)
                for option in values {
                    let key = "\(widget.name)#\(option)"
                    guard !placements.contains(key, on: surface) else { continue }
                    let isFirst = option == values.first
                    if !showsOption(board, widget: widget, input: choice.input, option: option, key: key, isFirst: isFirst) {
                        var copy = newInstance(
                            of: widget, on: board, canvasWidth: canvasWidth, contract: contract, idBase: "\(option)-usage")
                        copy.with = [choice.input: .string(option)]
                        board.widgets.append(copy)
                        boardChanged = true
                    }
                    placements.insert(key, on: surface)
                    placementsChanged = true
                }
                continue
            }
            if widget.inputs.values.contains(where: { $0.type == "choice" && $0.defaultValue == nil }) { continue }
            guard !placements.contains(widget.name, on: surface), isEligible(widget) else { continue }
            if !board.widgets.contains(where: { $0.type == widget.name }) && !isShown(widget) {
                board.widgets.append(newInstance(of: widget, on: board, canvasWidth: canvasWidth, contract: contract))
                boardChanged = true
            }
            placements.insert(widget.name, on: surface)
            placementsChanged = true
        }
        return PlacementResult(
            board: board, placements: placements, boardChanged: boardChanged, placementsChanged: placementsChanged)
    }

    private static func oneChoice(of widget: CatalogWidget) -> (input: String, source: String)? {
        let choices = widget.inputs.filter { $0.value.type == "choice" }
        guard choices.count == 1, let entry = choices.first, !entry.value.many, let source = entry.value.from else { return nil }
        return (entry.key, source)
    }

    /// An entry with no value for a one-choice input shows its first option.
    private static func showsOption(
        _ board: Board, widget: CatalogWidget, input: String, option: String, key: String, isFirst: Bool
    ) -> Bool {
        board.widgets.contains { entry in
            guard entry.type == widget.name else { return entry.type == legacyTypes[key] }
            return entry.with[input] == .string(option) || (isFirst && entry.with[input] == nil)
        }
    }

    public static func newInstance(
        of widget: CatalogWidget, on board: Board, canvasWidth: Int, contract: WidgetContract = .current, idBase: String? = nil
    ) -> BoardWidget {
        let preset = CanvasLayout.presetSize(widget.defaultSize, contract: contract)
        let size = preset ?? CanvasLayout.minimumSize(sizes: widget.sizes, contract: contract)
        let spot = CanvasLayout.firstFreeSpot(for: size, avoiding: board.widgets.map(\.frame), bandWidth: canvasWidth)
        return BoardWidget(
            id: board.uniqueID(base: idBase ?? widget.name.replacingOccurrences(of: "/", with: "-")), type: widget.name,
            frame: spot, size: preset == nil ? BoardWidget.customSize : widget.defaultSize, z: board.topZ + 1)
    }

    public static func harness(of widget: CatalogWidget) -> String? {
        guard widget.source.name == "app/harness-usage" else { return nil }
        return WidgetTemplate.arguments(of: widget, values: [:])["harness"]
    }
}
