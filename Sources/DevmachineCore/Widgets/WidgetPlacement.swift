import Foundation

/// The board written when `home.yml` is missing or reset: the Home the app
/// drew before widgets, laid out at a 1280 x 800 reference in board points.
public enum DefaultBoard {
    public static let surface = "home"
    public static let reference = (width: 1280, height: 800)
    public static let usageCell = CanvasSize(w: 384, h: 288)
    private static let padding = 24
    private static let gap = 16
    private static let usageTop = 360
    private static let clockSize = CanvasSize(w: 320, h: 160)

    public static func make(harnesses: [String]) -> Board {
        let columns = harnesses.count >= 2 ? 2 : 1
        let cardsMaxX = padding + columns * usageCell.w + (columns - 1) * gap
        let left = cardsMaxX + padding
        let free = reference.width - padding - left
        let clockX = (left + (free - clockSize.w) / 2) / 8 * 8
        var board = Board(surface: surface, widgets: [
            BoardWidget(
                id: "machines", type: "devmachine-app/machines",
                frame: BoardFrame(x: padding, y: padding, w: usageCell.w, h: 320), size: BoardWidget.customSize, z: 1),
            BoardWidget(
                id: "clock", type: "devmachine-app/clock",
                frame: BoardFrame(x: clockX, y: 320, w: clockSize.w, h: clockSize.h), size: "medium", z: 2),
            BoardWidget(
                id: "summary", type: "devmachine-app/summary",
                frame: BoardFrame(
                    x: reference.width - padding - clockSize.w, y: reference.height - padding - clockSize.h,
                    w: clockSize.w, h: clockSize.h),
                size: "medium", z: 3),
        ])
        for (index, harness) in harnesses.enumerated() {
            let column = index % columns
            let row = index / columns
            board.widgets.append(BoardWidget(
                id: board.uniqueID(base: "\(harness)-usage"), type: "devmachine-app/usage", with: ["harness": .string(harness)],
                frame: BoardFrame(
                    x: padding + column * (usageCell.w + gap), y: usageTop + row * (usageCell.h + gap),
                    w: usageCell.w, h: usageCell.h),
                size: BoardWidget.customSize, z: 4 + index))
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
