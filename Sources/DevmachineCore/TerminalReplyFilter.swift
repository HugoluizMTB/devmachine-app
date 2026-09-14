import Foundation

/// Removes two terminal replies from an outgoing byte stream: the answer to the
/// kitty keyboard query (`ESC [ ? <flags> u`) and the XTVERSION reply
/// (`ESC P > | <identity> ESC \`). tmux reads "XTerm(...)" in the latter as
/// "supports extended keys" and then forwards the kitty protocol Claude Code
/// turns on; without either reply every program keeps the legacy key
/// encoding, where Enter and dead keys behave.
public enum TerminalReplyFilter {
    public static func strip(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if let end = kittyAnswerEnd(in: bytes, from: i) ?? xtVersionReplyEnd(in: bytes, from: i) {
                i = end
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        return out
    }

    private static let esc: UInt8 = 0x1B

    private static func kittyAnswerEnd(in bytes: [UInt8], from start: Int) -> Int? {
        guard bytes.count - start >= 5,
              bytes[start] == esc, bytes[start + 1] == UInt8(ascii: "["), bytes[start + 2] == UInt8(ascii: "?")
        else { return nil }
        var i = start + 3
        var digits = 0
        while i < bytes.count, bytes[i] >= UInt8(ascii: "0"), bytes[i] <= UInt8(ascii: "9") {
            i += 1
            digits += 1
        }
        guard digits > 0, i < bytes.count, bytes[i] == UInt8(ascii: "u") else { return nil }
        return i + 1
    }

    private static func xtVersionReplyEnd(in bytes: [UInt8], from start: Int) -> Int? {
        guard bytes.count - start >= 6,
              bytes[start] == esc, bytes[start + 1] == UInt8(ascii: "P"),
              bytes[start + 2] == UInt8(ascii: ">"), bytes[start + 3] == UInt8(ascii: "|")
        else { return nil }
        var i = start + 4
        while i + 1 < bytes.count {
            if bytes[i] == esc, bytes[i + 1] == UInt8(ascii: "\\") { return i + 2 }
            i += 1
        }
        return nil
    }
}
