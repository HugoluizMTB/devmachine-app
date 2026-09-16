import Foundation

/// Whether a terminal size is one a program can be told about.
public enum TerminalSizeGuard {
    /// Below this, a size is a measurement in progress, not a window anyone
    /// means to draw in: a prompt alone needs more than a couple of columns.
    public static let minimumColumns = 40
    public static let minimumRows = 10

    public static func isUsable(cols: Int, rows: Int) -> Bool {
        cols >= minimumColumns && rows >= minimumRows
    }
}
