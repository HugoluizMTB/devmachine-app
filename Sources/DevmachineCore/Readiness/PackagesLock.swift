import Foundation

/// What the CLI's `packages.lock` says the last sync applied to each machine.
/// The configuration only says what a machine asks for; the lock is what was
/// actually put on it, read without logging in to look.
public struct PackagesLock: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let version: String?

        public init(name: String, version: String? = nil) {
            self.name = name
            self.version = version
        }
    }

    public let appliedAt: String?
    public let machines: [String: [Entry]]

    public init(appliedAt: String? = nil, machines: [String: [Entry]]) {
        self.appliedAt = appliedAt
        self.machines = machines
    }

    public static let fileName = "packages.lock"

    public func entry(_ package: String, onMachine machine: String) -> Entry? {
        machines[machine]?.first { $0.name == package }
    }

    public func has(_ package: String, onMachine machine: String) -> Bool {
        entry(package, onMachine: machine) != nil
    }

    /// Reads the YAML the CLI writes (`yaml.v3`, any indent). Only the
    /// `machines` map is read; nil means the text is not a lock at all.
    public static func parse(_ text: String) -> PackagesLock? {
        var appliedAt: String?
        var machines: [String: [Entry]] = [:]
        var inMachines = false
        var machineIndent: Int?
        var machine: String?
        var sawTopLevelKey = false

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" { continue }
            let indent = line.prefix { $0 == " " }.count

            if indent == 0 {
                sawTopLevelKey = true
                guard let (key, value) = keyValue(trimmed) else { return nil }
                inMachines = key == "machines"
                machineIndent = nil
                machine = nil
                if key == "applied_at" { appliedAt = value.isEmpty ? nil : value }
                if inMachines, value == "{}" { inMachines = false }
                continue
            }
            guard inMachines else { continue }

            if !trimmed.hasPrefix("-"), machineIndent == nil || indent == machineIndent,
               let (key, value) = keyValue(trimmed) {
                machineIndent = indent
                machine = key
                machines[key, default: []] = []
                if value == "[]" { machine = nil }
                continue
            }
            guard let machine else { continue }
            let item = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : trimmed
            guard let (key, value) = keyValue(item) else { continue }
            if key == "name", trimmed.hasPrefix("-") {
                machines[machine, default: []].append(Entry(name: value))
            } else if key == "version", var entries = machines[machine], let last = entries.popLast() {
                entries.append(Entry(name: last.name, version: value.isEmpty ? nil : value))
                machines[machine] = entries
            }
        }
        guard sawTopLevelKey else { return nil }
        return PackagesLock(appliedAt: appliedAt, machines: machines)
    }

    private static func keyValue(_ text: String) -> (String, String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let key = unquote(String(text[..<colon]).trimmingCharacters(in: .whitespaces))
        let value = unquote(String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }
}
