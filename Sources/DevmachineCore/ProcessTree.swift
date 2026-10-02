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

    /// A shell is back at its prompt when it is its own terminal's
    /// foreground group again (a shell leads its group, so the group is its
    /// pid). Nil when `ps` printed nothing usable.
    public static func isAtPrompt(shellPID: Int, tpgidOutput: String) -> Bool? {
        foregroundGroup(fromTPGID: tpgidOutput).map { $0 == shellPID }
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

    /// Every process on the machine, as pid, parent and program. One call is
    /// enough to answer "what is running inside this session" for every
    /// session, instead of one `ps` per session per poll.
    public static let listArguments = ["-axo", "pid=,ppid=,comm="]

    public struct Entry: Equatable, Sendable {
        public let pid: Int
        public let parent: Int
        public let command: String

        public init(pid: Int, parent: Int, command: String) {
            self.pid = pid
            self.parent = parent
            self.command = command
        }

        /// The program name without its folder and without its arguments. A
        /// login shell is printed as `-zsh`, so the leading dash comes off too.
        public var program: String {
            let head = command.split(separator: " ").first.map(String.init) ?? command
            var name = (head as NSString).lastPathComponent
            if name.hasPrefix("-") { name.removeFirst() }
            return name
        }
    }

    public static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let pid = Int(fields[0]), let parent = Int(fields[1])
            else { return nil }
            let command = fields.dropFirst(2).joined(separator: " ")
            return Entry(pid: pid, parent: parent, command: command)
        }
    }

    /// Every recognized descendant program under each root. The process graph
    /// is built once and every requested program is matched in the same walk,
    /// so adding a harness does not require another process snapshot or parse.
    public static func matchingPrograms(
        _ programs: Set<String>, roots: [Int], in entries: [Entry]
    ) -> [Int: Set<String>] {
        var children: [Int: [Int]] = [:]
        var byPid: [Int: Entry] = [:]
        for entry in entries {
            children[entry.parent, default: []].append(entry.pid)
            byPid[entry.pid] = entry
        }
        var matches: [Int: Set<String>] = [:]
        for root in roots {
            var stack = children[root] ?? []
            var seen = Set<Int>()
            while let pid = stack.popLast() {
                guard seen.insert(pid).inserted else { continue }
                if let program = byPid[pid]?.program, programs.contains(program) {
                    matches[root, default: []].insert(program)
                }
                stack.append(contentsOf: children[pid] ?? [])
            }
        }
        return matches
    }

    /// Compatibility for callers that still ask about one program at a time.
    public static func rootsRunning(
        _ program: String, roots: [Int], in entries: [Entry]
    ) -> Set<Int> {
        Set(matchingPrograms([program], roots: roots, in: entries).keys)
    }
}
