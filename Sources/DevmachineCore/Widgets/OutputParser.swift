import Foundation

/// `{{json.<path>}}`: which part of a JSON answer a view shows.
public enum JSONPath {
    static var template: Regex<(Substring, Substring)> { /\{\{\s*json\.([A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+|\[\d+\])*)\s*\}\}/ }

    public static func isTemplate(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: template) != nil
    }

    public static func path(of text: String) -> String? {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: template).map { String($0.1) }
    }
}
