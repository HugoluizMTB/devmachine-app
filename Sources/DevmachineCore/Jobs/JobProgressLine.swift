import Foundation

/// The one line a running job's card shows. A sync first prints its whole
/// plan — every package on the machine, then the extension files — and only
/// then runs Ansible, so the last raw line reads like work being done when
/// it is only the plan.
public enum JobProgressLine {
    public static func current(lines: [String], isSync: Bool, machine: String) -> String? {
        let plain = lines.map { LogText.plain($0) }
        if let task = plain.last(where: { $0.hasPrefix("TASK [") }).flatMap(taskName) {
            return task
        }
        if isSync {
            return plain.contains(where: { $0.hasPrefix("PLAY [") })
                ? "Starting the sync on \(machine)…"
                : "Planning the sync on \(machine)…"
        }
        return plain.last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "* ")) }
    }

    /// `TASK [heroku : Install the CLI] *****` → `heroku : Install the CLI`.
    static func taskName(_ line: String) -> String? {
        guard let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]"), open < close else { return nil }
        let name = line[line.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
