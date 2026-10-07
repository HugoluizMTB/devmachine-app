import Foundation
import Yams

/// Reads a board with a full YAML parser, so any style a person, the CLI or
/// an agent writes is accepted, and writes it in the one fixed shape the
/// spec gives every writer.
public enum BoardCodec {
    private static let topKeys: Set<String> = ["format", "surface", "widgets"]
    private static let widgetKeys: Set<String> = ["id", "type", "with", "frame", "size", "minimized", "z", "source", "view"]
    private static let frameKeys = ["x", "y", "w", "h"]
    private static let specialFloats: [String: Double] = [".inf": .infinity, "-.inf": -.infinity, ".nan": .nan]

    public static func decode(_ text: String, contract: WidgetContract = .current) throws -> Board {
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
        guard contract.surfaces[surface] != nil else {
            let known = contract.surfaces.keys.sorted().joined(separator: ", ")
            throw BoardProblem(line: line(surfaceNode), message: "unknown surface \"\(surface)\"; known: \(known)")
        }
        guard let widgetsNode = fields["widgets"] else {
            throw BoardProblem(line: line(root), message: "widgets is missing; use widgets: [] for an empty board")
        }
        guard let sequence = widgetsNode.sequence else {
            throw BoardProblem(line: line(widgetsNode), message: "widgets must be a list")
        }
        var widgets: [BoardWidget] = []
        var seen: Set<String> = []
        for item in sequence {
            let widget = try decodeWidget(item, contract: contract)
            guard seen.insert(widget.id).inserted else {
                throw BoardProblem(line: line(item), message: "id \"\(widget.id)\" is used twice")
            }
            widgets.append(widget)
        }
        return Board(surface: surface, widgets: widgets)
    }

    private static func decodeWidget(_ node: Node, contract: WidgetContract) throws -> BoardWidget {
        guard let mapping = node.mapping else {
            throw BoardProblem(line: line(node), message: "each widget is a mapping with id, type and frame")
        }
        let fields = try keyed(mapping, allowed: widgetKeys, context: "a widget")
        if fields["type"] == nil, fields["source"] != nil || fields["view"] != nil {
            throw BoardProblem(
                line: line(node),
                message: "a widget written in place (source and view, no type) needs engine 1.1; "
                    + "this app implements engine \(contract.engine)")
        }
        if let extra = fields["source"] ?? fields["view"] {
            throw BoardProblem(
                line: line(extra), message: "a widget with a type takes no source or view; they come from its widget.yml")
        }
        guard let idNode = fields["id"], let id = string(idNode) else {
            throw BoardProblem(line: line(node), message: "a widget needs an id")
        }
        guard id.wholeMatch(of: /[a-z0-9][a-z0-9-]*/) != nil else {
            throw BoardProblem(
                line: line(idNode), message: "id \"\(id)\" may use only a-z, 0-9 and -, and starts with a letter or digit")
        }
        guard let typeNode = fields["type"], let type = string(typeNode) else {
            throw BoardProblem(line: line(node), message: "widget \"\(id)\" needs a type, such as devmachine-app/clock")
        }
        guard type.wholeMatch(of: /[a-z][a-z0-9_-]*\/[a-z][a-z0-9-]*/) != nil else {
            throw BoardProblem(line: line(typeNode), message: "type \"\(type)\" must be <package>/<widget>")
        }
        let with = try fields["with"].map { try scalars($0, owner: id) } ?? [:]
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
        return BoardWidget(id: id, type: type, with: with, frame: frame, size: size, minimized: minimized, z: z)
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
                lines.append("    type: \(text(widget.type))")
                if !widget.with.isEmpty {
                    let keys = widget.with.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                    let pairs = keys.map { key in
                        "\(YAMLScalarStyle.text(key, in: .flow)): \(widget.with[key].map(value) ?? "\"\"")"
                    }
                    lines.append("    with: {\(pairs.joined(separator: ", "))}")
                }
                let frame = widget.frame
                lines.append("    frame: {x: \(frame.x), y: \(frame.y), w: \(frame.w), h: \(frame.h)}")
                lines.append("    size: \(text(widget.size))")
                lines.append("    minimized: \(widget.minimized)")
                lines.append("    z: \(widget.z)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func text(_ value: String) -> String { YAMLScalarStyle.text(value, in: .block) }

    private static func value(_ scalar: BoardScalar) -> String {
        switch scalar {
        case let .string(text): return YAMLScalarStyle.text(text, in: .flow, quoteYAML11Words: true)
        case let .int(number): return String(number)
        case let .double(number): return YAMLScalarStyle.number(number)
        case let .bool(flag): return flag ? "true" : "false"
        }
    }
}
