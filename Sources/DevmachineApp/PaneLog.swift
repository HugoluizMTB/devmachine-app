import Foundation

/// A short log of what happens around a terminal pane, on disk, so a bug that
/// only shows up while you are working can be read afterwards instead of
/// guessed at. Off unless the file's directory exists.
enum PaneLog {
    static let path = NSHomeDirectory() + "/.devmachine-app/terminal.log"

    private static let queue = DispatchQueue(label: "devmachine.pane-log")
    /// Built per line: a formatter is not safe to share across threads, and
    /// this runs on a queue of its own.
    private static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: (path as NSString).deletingLastPathComponent)
    }

    static func log(_ message: @autoclosure @escaping () -> String) {
        guard isEnabled else { return }
        let line = "\(stamp(Date())) \(message())\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
