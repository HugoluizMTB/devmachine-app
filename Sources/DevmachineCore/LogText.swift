import Foundation

/// A line of program output as a person reads it: colour and cursor codes
/// out, the carriage-return redraws of a progress bar reduced to their last
/// state, tabs as spaces.
public enum LogText {
    public static func plain(_ line: String) -> String {
        var text = line
        if let regex = try? NSRegularExpression(pattern: #"\x{1B}\[[0-9;?]*[A-Za-z]|\x{1B}\][^\x{07}]*\x{07}"#) {
            text = regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let last = text.split(separator: "\r", omittingEmptySubsequences: true).last {
            text = String(last)
        } else {
            text = ""
        }
        return text.replacingOccurrences(of: "\t", with: "    ")
    }
}
