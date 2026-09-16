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

    private static func trimIfHuge() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
              size > sizeLimit,
              let data = FileManager.default.contents(atPath: path)
        else { return }
        let tail = data.suffix(keepAfterTrim)
        try? Data(tail).write(to: URL(fileURLWithPath: path))
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: (path as NSString).deletingLastPathComponent)
    }

    /// Half a megabyte of history is plenty to read a bug from; past a
    /// megabyte the file is cut to that, newest kept.
    private static let sizeLimit = 1_048_576
    private static let keepAfterTrim = 524_288

    nonisolated(unsafe) private static var lastLine = ""

    static func log(_ message: @autoclosure @escaping () -> String) {
        guard isEnabled else { return }
        let text = message()
        // Dragging a window measures it over and over; the same line repeated
        // says nothing and buries what does.
        guard text != lastLine else { return }
        lastLine = text
        let line = "\(stamp(Date())) \(text)\n"
        queue.async {
            trimIfHuge()
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
