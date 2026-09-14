import Foundation

/// Removes the terminal's answer to the kitty keyboard query (`ESC [ ? <flags> u`)
/// from an outgoing byte stream. A program that never sees the answer keeps the
/// legacy key encoding, where Enter and dead keys behave.
public enum KittyQueryFilter {
    public static func strip(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if let end = queryAnswerEnd(in: bytes, from: i) {
                i = end
                continue
            }
            out.append(bytes[i])
            i += 1
        }
        return out
    }

    private static func queryAnswerEnd(in bytes: [UInt8], from start: Int) -> Int? {
        guard bytes.count - start >= 5,
              bytes[start] == 0x1B, bytes[start + 1] == UInt8(ascii: "["), bytes[start + 2] == UInt8(ascii: "?")
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
}
