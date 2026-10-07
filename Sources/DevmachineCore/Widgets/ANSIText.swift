import Foundation

/// A terminal colour: one of the 256 palette entries or a 24-bit value.
public enum ANSIColor: Hashable, Sendable {
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)
}

/// A stretch of terminal text that shares one style.
public struct ANSIRun: Hashable, Sendable {
    public var text: String
    public var foreground: ANSIColor?
    public var background: ANSIColor?
    public var bold = false
    public var italic = false
    public var underline = false
    public var dim = false

    public init(
        text: String, foreground: ANSIColor? = nil, background: ANSIColor? = nil, bold: Bool = false,
        italic: Bool = false, underline: Bool = false, dim: Bool = false
    ) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.dim = dim
    }
}

/// A read-only screen (`capture-pane -e`, `zmx history --vt`) as styled runs:
/// colour and weight kept, every other escape dropped.
public enum ANSIText {
    private static let escape: Unicode.Scalar = "\u{1B}"
    private static let bell: Unicode.Scalar = "\u{07}"
    private static let csiFinal: ClosedRange<UInt32> = 0x40...0x7E

    private enum ExtendedColor {
        case color(ANSIColor, codes: Int)
        case outOfRange(codes: Int)
        case malformed
    }

    public static func lines(_ text: String) -> [[ANSIRun]] {
        var style = ANSIRun(text: "")
        var result: [[ANSIRun]] = []
        var rawLines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        if rawLines.last == "" { rawLines.removeLast() }
        for line in rawLines {
            let redraw = line.split(separator: "\r", omittingEmptySubsequences: false).last ?? ""
            result.append(runs(of: Array(redraw.unicodeScalars), style: &style))
        }
        return result
    }

    private static func runs(of scalars: [Unicode.Scalar], style: inout ANSIRun) -> [ANSIRun] {
        var runs: [ANSIRun] = []
        var current = String.UnicodeScalarView()
        func flush() {
            guard !current.isEmpty else { return }
            let text = String(current)
            current = String.UnicodeScalarView()
            if let last = runs.last, sameStyle(last, style) {
                runs[runs.count - 1].text += text
            } else {
                var run = style
                run.text = text
                runs.append(run)
            }
        }
        var index = 0
        while index < scalars.count {
            guard scalars[index] == escape else {
                current.append(scalars[index])
                index += 1
                continue
            }
            let next = index + 1
            guard next < scalars.count else { break }
            switch scalars[next] {
            case "[":
                var end = next + 1
                while end < scalars.count, !csiFinal.contains(scalars[end].value) { end += 1 }
                guard end < scalars.count else {
                    index = scalars.count
                    continue
                }
                if scalars[end] == "m" {
                    flush()
                    var parameters = String.UnicodeScalarView()
                    parameters.append(contentsOf: scalars[(next + 1)..<end])
                    apply(String(parameters), to: &style)
                }
                index = end + 1
            case "]":
                var end = next + 1
                while end < scalars.count, scalars[end] != bell, scalars[end] != escape { end += 1 }
                if end < scalars.count, scalars[end] == bell {
                    index = end + 1
                } else if end + 1 < scalars.count, scalars[end + 1] == "\\" {
                    index = end + 2
                } else {
                    index = end
                }
            default:
                index = next + 1
            }
        }
        flush()
        return runs
    }

    private static func sameStyle(_ a: ANSIRun, _ b: ANSIRun) -> Bool {
        a.foreground == b.foreground && a.background == b.background && a.bold == b.bold && a.italic == b.italic
            && a.underline == b.underline && a.dim == b.dim
    }

    private static func apply(_ parameters: String, to style: inout ANSIRun) {
        let codes: [Int?] = parameters.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? 0 : Int($0) }
        var i = 0
        while i < codes.count {
            guard let code = codes[i] else {
                i += 1
                continue
            }
            switch code {
            case 0: style = ANSIRun(text: "")
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 30...37: style.foreground = .palette(code - 30)
            case 39: style.foreground = nil
            case 40...47: style.background = .palette(code - 40)
            case 49: style.background = nil
            case 90...97: style.foreground = .palette(code - 90 + 8)
            case 100...107: style.background = .palette(code - 100 + 8)
            case 38, 48:
                switch extendedColor(Array(codes.dropFirst(i + 1))) {
                case let .color(color, used):
                    if code == 38 { style.foreground = color } else { style.background = color }
                    i += used
                case let .outOfRange(used):
                    i += used
                case .malformed:
                    return
                }
            default: break
            }
            i += 1
        }
    }

    private static func extendedColor(_ codes: [Int?]) -> ExtendedColor {
        guard let mode = codes.first ?? nil else { return .malformed }
        switch mode {
        case 5:
            guard codes.count >= 2, let entry = codes[1] else { return .malformed }
            return (0...255).contains(entry) ? .color(.palette(entry), codes: 2) : .outOfRange(codes: 2)
        case 2:
            guard codes.count >= 4, let r = codes[1], let g = codes[2], let b = codes[3] else { return .malformed }
            return .color(.rgb(UInt8(clamping: r), UInt8(clamping: g), UInt8(clamping: b)), codes: 4)
        default:
            return .malformed
        }
    }
}
