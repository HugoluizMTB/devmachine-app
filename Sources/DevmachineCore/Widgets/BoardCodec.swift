import Foundation
import Yams

/// Reads a board with a full YAML parser, so any style a person, the CLI or
/// an agent writes is accepted, and writes it in the one fixed shape the
/// spec gives every writer.
public enum BoardCodec {
    private static let topKeys: Set<String> = ["format", "surface", "widgets"]
    private static let widgetKeys: Set<String> = [
        "id", "type", "title", "with", "source", "view", "sizes", "fits", "frame", "size", "minimized", "collapsed", "z",
    ]
    private static let stackLayout = "stack"
    private static let frameKeys = ["x", "y", "w", "h"]
    private static let specialFloats: [String: Double] = [".inf": .infinity, "-.inf": -.infinity, ".nan": .nan]

    public static func decode(_ text: String, contract: WidgetContract = .current) throws -> Board {
        let envelope = try envelope(text, contract: contract)
        var widgets: [BoardWidget] = []
        var seen: Set<String> = []
        for item in envelope.items {
            let widget = try decodeWidget(item, envelope: envelope, contract: contract)
            guard seen.insert(widget.id).inserted else {
                throw BoardProblem(line: line(item), message: "id \"\(widget.id)\" is used twice")
            }
            widgets.append(widget)
        }
        return Board(surface: envelope.surface, widgets: widgets)
    }

    public static func decodeStack(_ text: String, contract: WidgetContract = .current) throws -> StackBoard {
        let envelope = try envelope(text, contract: contract)
        guard contract.surfaces[envelope.surface]?.layout == stackLayout else {
            throw BoardProblem(
                line: line(envelope.surfaceNode),
                message: "surface \(envelope.surface) is a canvas; this file holds a stack of widgets")
        }
        var entries: [StackEntry] = []
        var seen: Set<String> = []
        for item in envelope.items {
            let entry = try decodeStackEntry(item, envelope: envelope, contract: contract)
            guard seen.insert(entry.id).inserted else {
                throw BoardProblem(line: line(item), message: "id \"\(entry.id)\" is used twice")
            }
            entries.append(entry)
        }
        return StackBoard(surface: envelope.surface, entries: entries)
    }

    private struct Envelope {
        let surface: String
        let surfaceNode: Node
        let items: [Node]
        let lines: YAMLTree.SourceLines
        let contextKeys: Set<String>
    }

    private static func envelope(_ text: String, contract: WidgetContract) throws -> Envelope {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: text) else {
                throw BoardProblem(line: 1, message: "the file is empty; a board needs format, surface and widgets")
            }
            root = node
        } catch let problem as BoardProblem {
            throw problem
        } catch {
            throw yamlProblem(error)
        }
        guard let mapping = root.mapping else {
            throw BoardProblem(line: line(root), message: "a board is a mapping with format, surface and widgets")
        }
        let fields = try keyed(mapping, allowed: topKeys, context: "the board")
        guard let formatNode = fields["format"] else {
            throw BoardProblem(line: line(root), message: "format is missing; it must be \(Board.format)")
        }
        guard int(formatNode) == Board.format else {
            throw BoardProblem(line: line(formatNode), message: "format must be \(Board.format)")
        }
        guard let surfaceNode = fields["surface"], let surface = string(surfaceNode) else {
            throw BoardProblem(line: line(root), message: "surface is missing, such as surface: home")
        }
        guard let area = contract.surfaces[surface] else {
            let known = contract.surfaces.keys.sorted().joined(separator: ", ")
            throw BoardProblem(line: line(surfaceNode), message: "unknown surface \"\(surface)\"; known: \(known)")
        }
        guard let widgetsNode = fields["widgets"] else {
            throw BoardProblem(line: line(root), message: "widgets is missing; use widgets: [] for an empty board")
        }
        guard let sequence = widgetsNode.sequence else {
            throw BoardProblem(line: line(widgetsNode), message: "widgets must be a list")
        }
        return Envelope(
            surface: surface, surfaceNode: surfaceNode, items: Array(sequence), lines: YAMLTree.SourceLines(text),
            contextKeys: Set(area.context.keys))
    }

    private struct EntryCore {
        let id: String
        let type: String
        let with: [String: BoardScalar]
        let inline: InlineWidget?
        let fields: [String: Node]
        let keyLines: [String: Int]
    }

    /// `placement` runs before the inline widget is read, so a key that does
    /// not belong to the area is reported first, as the CLI orders it.
    private static func entryCore(
        _ node: Node, envelope: Envelope, contract: WidgetContract,
        placement: (_ id: String, _ fields: [String: Node], _ keyLines: [String: Int]) throws -> Void
    ) throws -> EntryCore {
        guard let mapping = node.mapping else {
            throw BoardProblem(line: line(node), message: "each widget is a mapping with id, type and frame")
        }
        let fields = try keyed(mapping, allowed: widgetKeys, context: "a widget")
        guard let idNode = fields["id"], let id = string(idNode) else {
            throw BoardProblem(line: line(node), message: "a widget needs an id")
        }
        guard id.wholeMatch(of: /[a-z0-9][a-z0-9-]*/) != nil else {
            throw BoardProblem(
                line: line(idNode), message: "id \"\(id)\" may use only a-z, 0-9 and -, and starts with a letter or digit")
        }
        var keyLines: [String: Int] = [:]
        for (keyNode, _) in mapping {
            if let key = keyNode.scalar?.string, let keyLine = line(keyNode) { keyLines[key] = keyLine }
        }
        try placement(id, fields, keyLines)
        let writesInline = fields["source"] != nil || fields["view"] != nil
        if fields["type"] != nil, writesInline {
            throw BoardProblem(line: line(node), message: "a widget has either a type or a source and a view, not both")
        }
        var inline: InlineWidget?
        if fields["type"] == nil, writesInline || fields["title"] != nil {
            inline = try decodeInline(
                node, fields: fields, id: id, lines: envelope.lines, contract: contract, contextKeys: envelope.contextKeys)
        }
        var type = ""
        var with: [String: BoardScalar] = [:]
        if inline == nil {
            guard let typeNode = fields["type"], let typeName = string(typeNode) else {
                throw BoardProblem(line: line(node), message: "widget \"\(id)\" needs a type, such as devmachine-app/clock")
            }
            guard typeName.wholeMatch(of: /[a-z][a-z0-9_-]*\/[a-z][a-z0-9-]*/) != nil else {
                throw BoardProblem(line: line(typeNode), message: "type \"\(typeName)\" must be <package>/<widget>")
            }
            type = typeName
            with = try fields["with"].map { try scalars($0, owner: id) } ?? [:]
        }
        return EntryCore(id: id, type: type, with: with, inline: inline, fields: fields, keyLines: keyLines)
    }

    private static func decodeWidget(_ node: Node, envelope: Envelope, contract: WidgetContract) throws -> BoardWidget {
        let core = try entryCore(node, envelope: envelope, contract: contract) { id, _, keyLines in
            if let collapsedLine = keyLines["collapsed"] {
                throw BoardProblem(
                    line: collapsedLine, message: "\(id): a widget on a canvas folds with minimized: true, not collapsed")
            }
        }
        let fields = core.fields
        let id = core.id
        guard let frameNode = fields["frame"] else {
            throw BoardProblem(line: line(node), message: "widget \"\(id)\" needs a frame: {x: , y: , w: , h: }")
        }
        let frame = try decodeFrame(frameNode, owner: id)
        var size = BoardWidget.customSize
        if let sizeNode = fields["size"] {
            guard let value = string(sizeNode), value == BoardWidget.customSize || contract.presets[value] != nil else {
                let names = (WidgetContract.presetOrder + [BoardWidget.customSize]).joined(separator: ", ")
                throw BoardProblem(line: line(sizeNode), message: "size of widget \"\(id)\" must be one of \(names)")
            }
            size = value
        }
        var minimized = false
        if let minimizedNode = fields["minimized"] {
            guard let value = bool(minimizedNode) else {
                throw BoardProblem(line: line(minimizedNode), message: "minimized of widget \"\(id)\" must be true or false")
            }
            minimized = value
        }
        var z = 0
        if let zNode = fields["z"] {
            guard let value = int(zNode) else {
                throw BoardProblem(line: line(zNode), message: "z of widget \"\(id)\" must be a whole number")
            }
            z = value
        }
        return BoardWidget(
            id: id, type: core.type, with: core.with, frame: frame, size: size, minimized: minimized, z: z,
            inline: core.inline)
    }

    /// Only the rules the file alone shows; what needs the catalog (fit,
    /// single, auto on a typed view) is left to resolution.
    private static func decodeStackEntry(_ node: Node, envelope: Envelope, contract: WidgetContract) throws -> StackEntry {
        let core = try entryCore(node, envelope: envelope, contract: contract) { id, _, keyLines in
            for key in contract.stackEntry.forbids {
                if let keyLine = keyLines[key] {
                    throw BoardProblem(
                        line: keyLine, message: "\(id): a widget in a sidebar has no \(key); its place is its position in the list")
                }
            }
            if let minimizedLine = keyLines["minimized"] {
                throw BoardProblem(
                    line: minimizedLine, message: "\(id): a widget in a sidebar folds with collapsed: true, not minimized")
            }
        }
        let id = core.id
        var collapsed = false
        if let collapsedNode = core.fields["collapsed"] {
            guard let value = bool(collapsedNode) else {
                throw BoardProblem(line: line(collapsedNode), message: "collapsed of widget \"\(id)\" must be true or false")
            }
            collapsed = value
        }
        if let inline = core.inline {
            if !inline.fits.isEmpty, !inline.fits.contains(stackLayout) {
                throw BoardProblem(
                    line: core.keyLines["fits"] ?? line(node),
                    message: "\(id): fits \(inline.fits.joined(separator: ", ")), and this board's area is laid out as \(stackLayout)")
            }
            let kind = inline.view.kind
            if let layouts = contract.views[kind]?.layouts, !layouts.isEmpty, !layouts.contains(stackLayout) {
                throw BoardProblem(
                    line: core.keyLines["view"] ?? line(node),
                    message: "\(id): the \(kind) view is drawn only in \(layouts.joined(separator: ", ")), and this board's area is laid out as \(stackLayout)")
            }
        }
        let size = try core.fields["size"].map { try stackSize($0, core: core, contract: contract) }
        return StackEntry(id: id, type: core.type, with: core.with, inline: core.inline, size: size, collapsed: collapsed)
    }

    /// A typed entry's sizes and view are in the catalog, so it is checked
    /// against every preset here; an inline one against its own sizes and view.
    private static func stackSize(_ node: Node, core: EntryCore, contract: WidgetContract) throws -> StackSize {
        let ownSizes = core.inline?.sizes ?? []
        let sizes = (ownSizes.isEmpty ? WidgetContract.presetOrder : ownSizes).joined(separator: ", ")
        let written = string(node) ?? ""
        let value = StackSize(text: written, contract: contract)
        if value == .auto, let kind = core.inline?.view.kind, !contract.viewGrows(kind) {
            throw BoardProblem(
                line: line(node),
                message: "\(core.id): size auto follows the content, and the \(kind) view does not grow: use \(sizes)")
        }
        guard let value, value.presetName.map({ ownSizes.isEmpty || ownSizes.contains($0) }) != false else {
            throw BoardProblem(line: line(node), message: "\(core.id): size \"\(written)\" in a sidebar is auto or one of \(sizes)")
        }
        return value
    }

    private static func decodeInline(
        _ node: Node, fields: [String: Node], id: String, lines: YAMLTree.SourceLines, contract: WidgetContract,
        contextKeys: Set<String>
    ) throws -> InlineWidget {
        let owner = "widget \"\(id)\""
        guard let title = fields["title"].flatMap(string), !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BoardProblem(line: line(node), message: "\(owner) written in the board needs a title")
        }
        if let with = fields["with"] {
            throw BoardProblem(line: line(with), message: "\(owner) written in the board has no inputs, so it takes no with")
        }
        guard let sourceNode = fields["source"], let viewNode = fields["view"] else {
            throw BoardProblem(line: line(node), message: "\(owner) written in the board needs both a source and a view")
        }
        let sourceTree = try YAMLTree(node: sourceNode, lines: lines)
        let viewTree = try YAMLTree(node: viewNode, lines: lines)
        let scope = WidgetScope.inline(contextKeys: contextKeys)
        let source: WidgetSource
        do {
            source = try WidgetSourceReader.read(sourceTree.value, scope: scope, contract: contract)
        } catch let problem as WidgetSpecProblem {
            throw BoardProblem(line: sourceTree.line(at: problem.path) ?? line(sourceNode), message: "\(owner): \(problem.message)")
        }
        let view: WidgetView
        do {
            view = try WidgetViewReader.read(
                viewTree.value, source: source, sourceWritesParse: sourceTree.value["parse"] != nil, scope: scope,
                contract: contract)
        } catch let problem as WidgetSpecProblem {
            throw BoardProblem(line: viewTree.line(at: problem.path) ?? line(viewNode), message: "\(owner): \(problem.message)")
        }
        let sizes = try names(fields["sizes"], field: "sizes", owner: owner, allowed: WidgetContract.presetOrder)
        let fits = try names(fields["fits"], field: "fits", owner: owner, allowed: contract.layouts)
        return InlineWidget(
            title: title, sourceTree: sourceTree, viewTree: viewTree, sizes: sizes, fits: fits, source: source, view: view)
    }

    private static func names(_ node: Node?, field: String, owner: String, allowed: [String]) throws -> [String] {
        guard let node else { return [] }
        guard let sequence = node.sequence else {
            throw BoardProblem(line: line(node), message: "\(field) of \(owner) must be a list, such as [\(allowed.joined(separator: ", "))]")
        }
        return try sequence.map { item in
            guard let name = string(item), allowed.contains(name) else {
                let shown = string(item) ?? "?"
                let word = field == "sizes" ? "size" : field
                throw BoardProblem(
                    line: line(item), message: "\(word) \"\(shown)\" of \(owner) is not one of \(allowed.joined(separator: ", "))")
            }
            return name
        }
    }

    private static func decodeFrame(_ node: Node, owner: String) throws -> BoardFrame {
        guard let mapping = node.mapping else {
            throw BoardProblem(line: line(node), message: "frame of widget \"\(owner)\" must be {x: , y: , w: , h: }")
        }
        let fields = try keyed(mapping, allowed: Set(frameKeys), context: "the frame of widget \"\(owner)\"")
        var values: [String: Int] = [:]
        for key in frameKeys {
            guard let valueNode = fields[key] else {
                throw BoardProblem(line: line(node), message: "frame.\(key) of widget \"\(owner)\" is missing")
            }
            guard let value = int(valueNode) else {
                throw BoardProblem(line: line(valueNode), message: "frame.\(key) of widget \"\(owner)\" must be a whole number")
            }
            if key == "x" || key == "y", value < 0 {
                throw BoardProblem(line: line(valueNode), message: "frame.\(key) of widget \"\(owner)\" must be 0 or more")
            }
            if key == "w" || key == "h", value <= 0 {
                throw BoardProblem(line: line(valueNode), message: "frame.\(key) of widget \"\(owner)\" must be more than 0")
            }
            values[key] = value
        }
        return BoardFrame(x: values["x"] ?? 0, y: values["y"] ?? 0, w: values["w"] ?? 0, h: values["h"] ?? 0)
    }

    private static func scalars(_ node: Node, owner: String) throws -> [String: BoardScalar] {
        guard let mapping = node.mapping else {
            throw BoardProblem(line: line(node), message: "with of widget \"\(owner)\" must be a mapping of input values")
        }
        var values: [String: BoardScalar] = [:]
        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.scalar?.string else {
                throw BoardProblem(line: line(keyNode), message: "with of widget \"\(owner)\" has a key that is not text")
            }
            guard let scalar = valueNode.scalar else {
                throw BoardProblem(line: line(valueNode), message: "input \"\(key)\" of widget \"\(owner)\" must be one value")
            }
            values[key] = value(of: scalar)
        }
        return values
    }

    private static func keyed(_ mapping: Node.Mapping, allowed: Set<String>, context: String) throws -> [String: Node] {
        var fields: [String: Node] = [:]
        for (keyNode, value) in mapping {
            guard let key = keyNode.scalar?.string else {
                throw BoardProblem(line: line(keyNode), message: "\(context) has a key that is not text")
            }
            guard allowed.contains(key) else {
                throw BoardProblem(line: line(keyNode), message: "unknown key \"\(key)\" in \(context)")
            }
            fields[key] = value
        }
        return fields
    }

    private static func line(_ node: Node) -> Int? { node.mark?.line }

    private static func string(_ node: Node) -> String? { node.scalar?.string }

    private static func int(_ node: Node) -> Int? {
        guard let scalar = node.scalar, scalar.style == .plain else { return nil }
        return Int(scalar.string)
    }

    private static func bool(_ node: Node) -> Bool? {
        guard let scalar = node.scalar, scalar.style == .plain else { return nil }
        switch scalar.string {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func value(of scalar: Node.Scalar) -> BoardScalar {
        let text = scalar.string
        guard scalar.style == .plain else { return .string(text) }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if let number = Int(text) { return .int(number) }
        if let special = specialFloats[text] { return .double(special) }
        if let number = Double(text), text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) {
            return .double(number)
        }
        return .string(text)
    }

    /// Yams describes a syntax error as "<line>:<column>: error: <problem>".
    static func yamlProblem(_ error: Error) -> BoardProblem {
        if case let YamlError.duplicatedKeysInMapping(duplicates, _) = error {
            return repeatedKeyProblem(duplicates)
        }
        let first = String(describing: error).split(separator: "\n").first.map(String.init) ?? ""
        if let match = first.firstMatch(of: /^(\d+):(\d+): error: (.*)$/) {
            return BoardProblem(line: Int(match.1), message: "not valid YAML: " + String(match.3))
        }
        return BoardProblem(line: nil, message: "not valid YAML: " + first)
    }

    private static func repeatedKeyProblem(_ duplicates: [Node: [Node]]) -> BoardProblem {
        let repeats = duplicates.compactMap { key, nodes -> (key: String, line: Int)? in
            let lines = nodes.compactMap { $0.mark?.line }.sorted()
            guard let line = lines.dropFirst().first ?? lines.first else { return nil }
            return (key.scalar?.string ?? "", line)
        }
        guard let first = repeats.min(by: { $0.line < $1.line }) else {
            return BoardProblem(line: nil, message: "a key appears twice")
        }
        return BoardProblem(line: first.line, message: "\"\(first.key)\" appears twice")
    }

    public static func encode(_ board: Board) -> String {
        var lines = ["format: \(Board.format)", "surface: \(text(board.surface))"]
        if board.widgets.isEmpty {
            lines.append("widgets: []")
        } else {
            lines.append("widgets:")
            for widget in board.widgets {
                lines.append("  - id: \(text(widget.id))")
                lines.append(contentsOf: bodyLines(type: widget.type, with: widget.with, inline: widget.inline))
                let frame = widget.frame
                lines.append("    frame: {x: \(frame.x), y: \(frame.y), w: \(frame.w), h: \(frame.h)}")
                lines.append("    size: \(text(widget.size))")
                lines.append("    minimized: \(widget.minimized)")
                lines.append("    z: \(widget.z)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func encodeStack(_ board: StackBoard) -> String {
        var lines = ["format: \(Board.format)", "surface: \(text(board.surface))"]
        if board.entries.isEmpty {
            lines.append("widgets: []")
        } else {
            lines.append("widgets:")
            for entry in board.entries {
                lines.append("  - id: \(text(entry.id))")
                lines.append(contentsOf: bodyLines(type: entry.type, with: entry.with, inline: entry.inline))
                if let size = entry.size { lines.append("    size: \(text(size.text))") }
                if entry.collapsed { lines.append("    collapsed: true") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The keys between id and the placement, the same on a canvas and in a stack.
    private static func bodyLines(type: String, with: [String: BoardScalar], inline: InlineWidget?) -> [String] {
        if let inline {
            var lines = ["    title: \(text(inline.title))"]
            lines.append(contentsOf: inline.sourceTree.emit(key: "source", indent: 4))
            lines.append(contentsOf: inline.viewTree.emit(key: "view", indent: 4))
            if !inline.sizes.isEmpty { lines.append("    sizes: [\(flowList(inline.sizes))]") }
            if !inline.fits.isEmpty { lines.append("    fits: [\(flowList(inline.fits))]") }
            return lines
        }
        var lines = ["    type: \(text(type))"]
        if !with.isEmpty {
            let keys = with.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            let pairs = keys.map { key in "\(YAMLScalarStyle.text(key, in: .flow)): \(with[key].map(value) ?? "\"\"")" }
            lines.append("    with: {\(pairs.joined(separator: ", "))}")
        }
        return lines
    }

    private static func text(_ value: String) -> String { YAMLScalarStyle.text(value, in: .block) }

    private static func flowList(_ items: [String]) -> String {
        items.map { YAMLScalarStyle.text($0, in: .flow) }.joined(separator: ", ")
    }

    private static func value(_ scalar: BoardScalar) -> String {
        switch scalar {
        case let .string(text): return YAMLScalarStyle.text(text, in: .flow, quoteYAML11Words: true)
        case let .int(number): return String(number)
        case let .double(number): return YAMLScalarStyle.number(number)
        case let .bool(flag): return flag ? "true" : "false"
        }
    }
}
