import Foundation

public enum RemoteTransport: String, Sendable, Equatable {
    case mosh
    case ssh
}

/// Settings → Terminal: how a remote pane reaches its machine.
public enum RemoteTerminalMode: String, Codable, Sendable, CaseIterable {
    case automatic
    case alwaysSSH
    case alwaysMosh

    public var title: String {
        switch self {
        case .automatic: return "Automatic (mosh, falling back to ssh)"
        case .alwaysSSH: return "Always ssh"
        case .alwaysMosh: return "Always mosh"
        }
    }
}

/// What `mosh-server new` hands back: where to send packets and the key to
/// seal them with.
public struct MoshSession: Equatable, Sendable {
    public let port: Int
    public let key: String
    public let serverPID: Int?

    public init(port: Int, key: String, serverPID: Int?) {
        self.port = port
        self.key = key
        self.serverPID = serverPID
    }
}

public enum MoshBootstrapOutcome: Equatable, Sendable {
    case ready(MoshSession)
    case noServer(String)
    case serverFailed(String)
    case unreachable(String)
}

/// The part of the `mosh` wrapper the app does itself: start `mosh-server`
/// over ssh, read its answer, and hand the key to `mosh-client`.
public enum MoshBootstrap {
    /// Only used when the server's own locale is not UTF-8 (mosh-server tries
    /// the one ssh forwarded first). C.UTF-8 ships with every Debian and
    /// Ubuntu, where en_US.UTF-8 exists only if someone generated it.
    public static let localeFallback = "LANG=C.UTF-8"

    public static func serverCommand(session: String) -> String {
        "mosh-server new -s -c 256 -l \(localeFallback) -- "
            + RemoteCommands.newSession(name: session)
    }

    /// No terminal on purpose: mosh-server detaches from its output once it
    /// has printed the key, so ssh returns at once and nothing echoes into
    /// the lines this reads.
    public static func sshArguments(alias: String, session: String) -> [String] {
        RemoteCommands.sshBaseArgs(alias: alias) + ["-n", "-T", "--", serverCommand(session: session)]
    }

    public static func parse(stdout: String, stderr: String, exitCode: Int32) -> MoshBootstrapOutcome {
        if let session = connectLine(in: stdout) {
            return .ready(MoshSession(port: session.port, key: session.key, serverPID: serverPID(in: stderr)))
        }
        let detail = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "exit \(exitCode)"
        switch exitCode {
        case 127: return .noServer(detail)
        case 255: return .unreachable(detail)
        default: return .serverFailed(detail)
        }
    }

    private static func connectLine(in output: String) -> (port: Int, key: String)? {
        for raw in output.split(whereSeparator: \.isNewline) {
            let words = raw.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard words.count == 4, words[0] == "MOSH", words[1] == "CONNECT",
                  let port = Int(words[2]), (1...65_535).contains(port),
                  isKey(words[3])
            else { continue }
            return (port, String(words[3]))
        }
        return nil
    }

    private static func isKey(_ word: Substring) -> Bool {
        word.count == 22 && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/") }
    }

    private static func serverPID(in output: String) -> Int? {
        guard let range = output.range(of: "[mosh-server detached, pid = ") else { return nil }
        return Int(output[range.upperBound...].prefix { $0.isNumber })
    }

    public static func clientArguments(ip: String, session: MoshSession) -> [String] {
        [ip, String(session.port)]
    }

    /// The key travels in the environment, the way mosh's own wrapper does it:
    /// an argument would show in `ps` for every user on this Mac.
    public static func clientEnvironment(session: MoshSession, base: [String]) -> [String] {
        base + ["MOSH_KEY=\(session.key)"]
    }

    /// A mosh-server nobody can reach keeps a tmux client attached until its
    /// own 60-second timeout, and two clients of different sizes make the
    /// screen flap, so the ssh that replaces it ends it first.
    public static func sshFallbackCommand(session: String, strayServerPID: Int?) -> String {
        let attach = RemoteCommands.newSession(name: session)
        guard let strayServerPID else { return attach }
        return "kill \(strayServerPID) 2>/dev/null; " + attach
    }
}

/// How a running mosh-client says it has not heard from the server.
public enum MoshClientProbe {
    /// mosh-client draws this on the top row 250 ms after starting, and
    /// clears it with the first packet from the server.
    public static let connectingMarker = "Nothing received from server"
    public static let timeout: TimeInterval = 5
}

public enum MoshClientLocator {
    /// Homebrew's, for a local build without the embedded client.
    public static let homebrewPaths = ["/opt/homebrew/bin/mosh-client", "/usr/local/bin/mosh-client"]

    public static func path(bundled: String?, exists: (String) -> Bool) -> String? {
        ([bundled].compactMap { $0 } + homebrewPaths).first(where: exists)
    }
}

/// Where to send mosh's packets. mosh-server answers from the address ssh
/// reached it on, so the client has to aim at that same machine.
public enum MoshAddress {
    public static let resolveHelpArguments = ["resolve", "--help"]

    public static func supportsResolve(exitCode: Int32, output: String) -> Bool {
        exitCode == 0 && output.contains("resolve")
    }

    public static func resolveArguments(machine: String) -> [String] {
        ["resolve", "--machine", machine, "--format", "json"]
    }

    public static func addresses(fromResolveJSON json: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return [] }
        if let dict = object as? [String: Any], let list = dict["addresses"] as? [[String: Any]] {
            return list.compactMap { $0["address"] as? String }.filter(isIPAddress)
        }
        return anyIP(in: object).map { [$0] } ?? []
    }

    private static let addressKeys = ["address", "ip", "host", "tailnet_ip", "public_ip"]

    private static func anyIP(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            for key in addressKeys {
                if let value = dict[key] as? String, isIPAddress(value) { return value }
            }
            for value in dict.values {
                if let found = anyIP(in: value) { return found }
            }
        }
        if let list = object as? [Any] {
            for value in list {
                if let found = anyIP(in: value) { return found }
            }
        }
        return nil
    }

    public static func sshConfigArguments(alias: String) -> [String] {
        ["-G", alias]
    }

    public static func hostname(fromSSHConfig output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "hostname" {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    public static func ip(for host: String, lookup: (String) -> [String]) -> String? {
        if isIPAddress(host) { return host }
        let found = lookup(host).filter(isIPAddress)
        return found.first(where: { !$0.contains(":") }) ?? found.first
    }

    public static func isLoopback(_ ip: String) -> Bool {
        ip == "::1" || ip.hasPrefix("127.")
    }

    public static func isIPAddress(_ value: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, value, &v4) == 1 || inet_pton(AF_INET6, value, &v6) == 1
    }

    /// The system resolver, so a name resolves here the way ssh resolved it.
    public static func systemLookup(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
            cursor = info.pointee.ai_next
        }
        return addresses
    }
}

/// Why a remote pane runs ssh instead of mosh.
public enum MoshFallbackReason: Equatable, Sendable {
    case noClient
    case noServer
    case serverFailed
    case unreachable
    case noAddress
    case loopback
    case udpBlocked
    case clientExited

    /// Only an answer about the machine itself is worth remembering; a
    /// connection that failed outright says nothing about mosh.
    public var isRemembered: Bool {
        switch self {
        case .noServer, .serverFailed, .loopback, .udpBlocked, .clientExited: return true
        case .noClient, .unreachable, .noAddress: return false
        }
    }

    /// The pane says so only when mosh was started and could not get
    /// through: a machine without mosh-server is a choice, not a problem.
    public var showsNotice: Bool {
        self == .udpBlocked || self == .clientExited
    }

    public func notice(machine: String) -> String {
        switch self {
        case .udpBlocked:
            return "Using ssh: mosh couldn't reach \(machine) (UDP 60000\u{2013}61000 closed?)"
        case .clientExited:
            return "Using ssh: mosh stopped before it reached \(machine)"
        default:
            return "Using ssh: \(summary(machine: machine))"
        }
    }

    public func summary(machine: String) -> String {
        switch self {
        case .noClient: return "mosh-client was not found on this Mac"
        case .noServer: return "\(machine) has no mosh-server"
        case .serverFailed: return "mosh-server on \(machine) did not start"
        case .unreachable: return "ssh could not reach \(machine) to start mosh"
        case .noAddress: return "no address for \(machine) to send mosh's packets to"
        case .loopback: return "\(machine) is reached through a local port forward, which carries no UDP"
        case .udpBlocked: return "nothing came back from \(machine) over UDP"
        case .clientExited: return "mosh-client stopped before it heard from \(machine)"
        }
    }

    /// The one likely fix, for the details popover.
    public var cause: String {
        switch self {
        case .udpBlocked, .clientExited:
            return "The firewall package keeps mosh's UDP ports closed until firewall.mosh_interface "
                + "is set for the machine (for example tailscale0), then devmachine sync."
        case .noServer:
            return "Add the base package to the machine, which installs mosh, then devmachine sync."
        case .serverFailed:
            return "mosh-server started but did not answer; the details show what it printed."
        case .noClient:
            return "This build has no embedded mosh-client; brew install mosh adds one."
        case .unreachable:
            return "The machine did not answer over ssh either."
        case .noAddress:
            return "Neither devmachine resolve nor ssh -G gave an address."
        case .loopback:
            return "A local VM answers ssh on a forwarded TCP port; mosh's UDP never reaches it, so ssh is used."
        }
    }
}

public enum RemoteTransportPlan: Equatable, Sendable {
    case mosh(client: String, watchdog: Bool)
    case ssh(reason: MoshFallbackReason?)
}

public enum RemoteTransportPolicy {
    public static func plan(
        mode: RemoteTerminalMode, remembered: MoshFallbackReason?, clientPath: String?
    ) -> RemoteTransportPlan {
        if mode == .alwaysSSH { return .ssh(reason: nil) }
        guard let clientPath else { return .ssh(reason: .noClient) }
        if mode == .alwaysMosh { return .mosh(client: clientPath, watchdog: false) }
        if let remembered { return .ssh(reason: remembered) }
        return .mosh(client: clientPath, watchdog: true)
    }

    public static func fallback(after outcome: MoshBootstrapOutcome) -> MoshFallbackReason? {
        switch outcome {
        case .ready: return nil
        case .noServer: return .noServer
        case .serverFailed: return .serverFailed
        case .unreachable: return .unreachable
        }
    }
}

/// What the app learned about each machine during this run: a machine whose
/// mosh failed goes straight to ssh until the entry is old enough to try again.
public struct RemoteTransportMemory: Sendable {
    public static let reprobeAfter: TimeInterval = 30 * 60

    private var failures: [String: (reason: MoshFallbackReason, at: Date)] = [:]

    public init() {}

    public mutating func record(_ reason: MoshFallbackReason, for machine: String, at now: Date) {
        guard reason.isRemembered else { return }
        failures[machine] = (reason, now)
    }

    public mutating func recordSuccess(for machine: String) {
        failures[machine] = nil
    }

    public mutating func forget(_ machine: String) {
        failures[machine] = nil
    }

    public func remembered(for machine: String, now: Date) -> MoshFallbackReason? {
        guard let entry = failures[machine], now.timeIntervalSince(entry.at) < Self.reprobeAfter else { return nil }
        return entry.reason
    }
}

/// Whether the installed CLI has `resolve`, asked once per app run.
public final class ResolveSupport: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Bool?

    public init() {}

    func value(orAsk ask: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let answer { return answer }
        let fresh = ask()
        answer = fresh
        return fresh
    }
}

/// Starts mosh-server and finds the address for mosh-client. Blocking: call
/// it off the main actor.
public struct MoshConnector: Sendable {
    public enum Result: Equatable, Sendable {
        case mosh(ip: String, session: MoshSession)
        case ssh(reason: MoshFallbackReason, detail: String, strayServerPID: Int?)
    }

    public static let sshExecutable = "/usr/bin/ssh"

    let runner: any CommandRunner
    let sshEnvironment: [String: String]
    let cliExecutable: String?
    let cliEnvironment: [String: String]?
    let resolveSupport: ResolveSupport
    let lookup: @Sendable (String) -> [String]

    public init(
        runner: any CommandRunner, sshEnvironment: [String: String], cliExecutable: String?,
        cliEnvironment: [String: String]?, resolveSupport: ResolveSupport,
        lookup: @escaping @Sendable (String) -> [String] = MoshAddress.systemLookup
    ) {
        self.runner = runner
        self.sshEnvironment = sshEnvironment
        self.cliExecutable = cliExecutable
        self.cliEnvironment = cliEnvironment
        self.resolveSupport = resolveSupport
        self.lookup = lookup
    }

    public func connect(alias: String, session: String, machine: String?) -> Result {
        let outcome: MoshBootstrapOutcome
        do {
            let reply = try runner.runCapturing(
                executable: Self.sshExecutable,
                args: MoshBootstrap.sshArguments(alias: alias, session: session),
                environment: sshEnvironment)
            outcome = MoshBootstrap.parse(stdout: reply.stdout, stderr: reply.stderr, exitCode: reply.exitCode)
        } catch {
            return .ssh(reason: .unreachable, detail: "\(error)", strayServerPID: nil)
        }
        switch outcome {
        case let .ready(moshSession):
            guard let ip = address(alias: alias, machine: machine) else {
                return .ssh(reason: .noAddress, detail: "no address for \(alias)",
                            strayServerPID: moshSession.serverPID)
            }
            // A local VM is reached through a TCP forward to loopback, and
            // mosh-server listens on the VM's own interface: no UDP gets there.
            if MoshAddress.isLoopback(ip) {
                return .ssh(reason: .loopback, detail: "\(alias) resolves to \(ip)",
                            strayServerPID: moshSession.serverPID)
            }
            return .mosh(ip: ip, session: moshSession)
        case let .noServer(detail):
            return .ssh(reason: .noServer, detail: detail, strayServerPID: nil)
        case let .serverFailed(detail):
            return .ssh(reason: .serverFailed, detail: detail, strayServerPID: nil)
        case let .unreachable(detail):
            return .ssh(reason: .unreachable, detail: detail, strayServerPID: nil)
        }
    }

    func address(alias: String, machine: String?) -> String? {
        if let machine, let cliExecutable, cliSupportsResolve(cliExecutable),
           let reply = try? runner.runCapturing(
               executable: cliExecutable, args: MoshAddress.resolveArguments(machine: machine),
               environment: cliEnvironment),
           reply.exitCode == 0,
           let first = MoshAddress.addresses(fromResolveJSON: reply.stdout).first {
            return first
        }
        guard let config = try? runner.runCapturing(
                  executable: Self.sshExecutable, args: MoshAddress.sshConfigArguments(alias: alias),
                  environment: sshEnvironment),
              config.exitCode == 0,
              let host = MoshAddress.hostname(fromSSHConfig: config.stdout)
        else { return nil }
        return MoshAddress.ip(for: host, lookup: lookup)
    }

    private func cliSupportsResolve(_ executable: String) -> Bool {
        resolveSupport.value {
            guard let reply = try? runner.runCapturing(
                executable: executable, args: MoshAddress.resolveHelpArguments, environment: cliEnvironment)
            else { return false }
            return MoshAddress.supportsResolve(exitCode: reply.exitCode, output: reply.stdout + reply.stderr)
        }
    }
}
