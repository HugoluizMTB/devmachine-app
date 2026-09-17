import Foundation

/// Which context user a container or a port belongs to. The app hides what
/// belongs to a workspace you turned off, and for that it has to know the
/// owner of each row, which neither `docker stats` nor the Caddyfile says.
public enum Ownership {
    /// `/home/<user>/…` is how this host lays out context users, so the folder
    /// a container was started from names its owner.
    public static func user(fromHome path: String) -> String? {
        guard path.hasPrefix("/home/") else { return nil }
        let rest = path.dropFirst("/home/".count)
        let name = rest.prefix { $0 != "/" }
        return name.isEmpty ? nil : String(name)
    }

    /// The owner of a container: the folder it was started from, or its name
    /// when that begins with a context user's name — `acme-pg` and the like,
    /// started by hand and carrying no label. A name that matches no known user
    /// is left without an owner rather than guessed at.
    public static func owner(
        ofContainer name: String, labelled: String?, knownUsers: Set<String>
    ) -> String? {
        if let labelled { return labelled }
        for user in knownUsers where name.hasPrefix(user + "-") || name == user {
            return user
        }
        return nil
    }

    /// `docker ps --format '{{.Names}}|{{working_dir}}|{{.Ports}}'`.
    public static func containerOwners(_ output: String) -> [String: String] {
        var owners: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let owner = user(fromHome: String(parts[1])) else { continue }
            owners[name] = owner
        }
        return owners
    }

    /// The published host ports of a container, from the `{{.Ports}}` column:
    /// `0.0.0.0:8810->80/tcp, [::]:8810->80/tcp` and `127.0.0.1:8110->80/tcp`.
    public static func publishedPorts(_ column: String) -> Set<Int> {
        var ports = Set<Int>()
        for mapping in column.split(separator: ",") {
            guard let arrow = mapping.range(of: "->") else { continue }
            let left = mapping[mapping.startIndex..<arrow.lowerBound]
            guard let colon = left.lastIndex(of: ":") else { continue }
            // Docker writes a run of ports as `9000-9001`, one mapping for both.
            let value = left[left.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let bounds = value.split(separator: "-").compactMap { Int($0) }
            switch bounds.count {
            case 1: ports.insert(bounds[0])
            case 2 where bounds[0] <= bounds[1]: ports.formUnion(bounds[0]...bounds[1])
            default: continue
            }
        }
        return ports
    }

    /// Port → owning user, from the three parts of `RemoteCommands.portOwners`.
    /// A container wins over the process holding the port: what listens for a
    /// published port is docker's own proxy, which belongs to root and would
    /// hide nothing.
    public static func portOwners(_ output: String) -> [Int: String] {
        let sections = split(output)
        var owners: [Int: String] = [:]

        for line in (sections.processesByPort).keys.sorted() {
            if let user = sections.processesByPort[line] { owners[line] = user }
        }
        for (ports, user) in sections.containerPorts {
            for port in ports { owners[port] = user }
        }
        return owners
    }

    private static func split(_ output: String)
        -> (containerPorts: [(Set<Int>, String)], processesByPort: [Int: String]) {
        var dockerLines: [Substring] = []
        var listeners: [Substring] = []
        var processes: [Substring] = []
        var current = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@LISTENERS@@") { current = 1; continue }
            if line.hasPrefix("@@PROCESSES@@") { current = 2; continue }
            switch current {
            case 0: dockerLines.append(line)
            case 1: listeners.append(line)
            default: processes.append(line)
            }
        }

        var userOfPid: [Int: String] = [:]
        for line in processes {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int(parts[0]) else { continue }
            userOfPid[pid] = String(parts[1])
        }

        var processesByPort: [Int: String] = [:]
        for line in listeners {
            guard let port = listeningPort(line), let pid = firstPid(line),
                  let user = userOfPid[pid] else { continue }
            processesByPort[port] = user
        }

        var containerPorts: [(Set<Int>, String)] = []
        for line in dockerLines {
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let owner = user(fromHome: String(parts[1])) else { continue }
            let ports = publishedPorts(String(parts[2]))
            if !ports.isEmpty { containerPorts.append((ports, owner)) }
        }
        return (containerPorts, processesByPort)
    }

    /// The local port of an `ss -lntpH` row: the fourth column, `*:7000` or
    /// `127.0.0.1:3000` or `[::1]:3000`.
    static func listeningPort(_ line: Substring) -> Int? {
        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 4, let colon = columns[3].lastIndex(of: ":") else { return nil }
        return Int(columns[3][columns[3].index(after: colon)...])
    }

    static func firstPid(_ line: Substring) -> Int? {
        guard let range = line.range(of: "pid=") else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

/// The port a Caddy site forwards to, which is how a domain is tied to whoever
/// runs that port.
public enum CaddySiteOwnership {
    public static func port(of target: String) -> Int? {
        guard let colon = target.lastIndex(of: ":") else { return nil }
        let digits = target[target.index(after: colon)...].prefix { $0.isNumber }
        return Int(digits)
    }
}
