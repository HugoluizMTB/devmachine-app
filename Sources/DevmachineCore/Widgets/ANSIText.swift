import Foundation

public enum ANSIColor: Hashable, Sendable {
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)
}

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
    public static func lines(_ text: String) -> [[ANSIRun]] {
        var style = ANSIRun(text: "")
        var result: [[ANSIRun]] = []
        var rawLines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if rawLines.last == "" { rawLines.removeLast() }
        for line in rawLines {
            let redraw = line.split(separator: "\r", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            var runs: [ANSIRun] = []
            var current = ""
            var index = redraw.startIndex
            func flush() {
                guard !current.isEmpty else { return }
                var run = style
                run.text = current
                if let last = runs.last, sameStyle(last, run) {
                    runs[runs.count - 1].text += current
                } else {
                    runs.append(run)
                }
                current = ""
            }
            while index < redraw.endIndex {
                let character = redraw[index]
                guard character == "\u{1B}" else {
                    current.append(character)
                    index = redraw.index(after: index)
                    continue
                }
                let next = redraw.index(after: index)
                guard next < redraw.endIndex else { break }
                if redraw[next] == "[" {
                    var end = redraw.index(after: next)
                    while end < redraw.endIndex, !(redraw[end].isLetter || redraw[end] == "~") { end = redraw.index(after: end) }
                    guard end < redraw.endIndex else { break }
                    if redraw[end] == "m" {
                        flush()
                        apply(String(redraw[redraw.index(after: next)..<end]), to: &style)
                    }
                    index = redraw.index(after: end)
                } else if redraw[next] == "]" {
                    var end = redraw.index(after: next)
                    while end < redraw.endIndex, redraw[end] != "\u{07}", redraw[end] != "\u{1B}" { end = redraw.index(after: end) }
                    index = end < redraw.endIndex ? redraw.index(after: end) : end
                    if index < redraw.endIndex, redraw[index] == "\\" { index = redraw.index(after: index) }
                } else {
                    index = redraw.index(after: next)
                }
            }
            flush()
            result.append(runs)
        }
        return result
    }

    private static func sameStyle(_ a: ANSIRun, _ b: ANSIRun) -> Bool {
        a.foreground == b.foreground && a.background == b.background && a.bold == b.bold && a.italic == b.italic
            && a.underline == b.underline && a.dim == b.dim
    }

    private static func apply(_ parameters: String, to style: inout ANSIRun) {
        var codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        if codes.isEmpty { codes = [0] }
        var i = 0
        while i < codes.count {
            let code = codes[i]
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
                var color: ANSIColor?
                if i + 2 < codes.count, codes[i + 1] == 5 {
                    color = .palette(codes[i + 2])
                    i += 2
                } else if i + 4 < codes.count, codes[i + 1] == 2 {
                    color = .rgb(UInt8(clamping: codes[i + 2]), UInt8(clamping: codes[i + 3]), UInt8(clamping: codes[i + 4]))
                    i += 4
                }
                if code == 38 { style.foreground = color } else { style.background = color }
            default: break
            }
            i += 1
        }
    }
}
