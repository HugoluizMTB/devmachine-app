import Foundation

/// Reading `ps` output, to find which process is in the foreground of a
/// terminal and to ask it to draw again.
public enum ProcessTree {
    /// The foreground process group of a shell, which is the program the user is
    /// actually looking at. `ps -o tpgid= -p <pid>` prints it.
    public static func foregroundGroup(fromTPGID output: String) -> Int? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    public static func tpgidArguments(pid: Int) -> [String] {
        ["-o", "tpgid=", "-p", "\(pid)"]
    }

    /// The window-changed signal, which is what a resize sends. Programs that
    /// draw a whole screen repaint on it, and it changes nothing else, so it is
    /// safe to send when a pane comes back unchanged.
    public static func windowChangedArguments(group: Int) -> [String] {
        ["-WINCH", "-\(group)"]
    }
}
