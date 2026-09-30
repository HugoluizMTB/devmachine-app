import Foundation
import AppKit
import DevmachineCore

/// A workspace port reached through `devmachine tunnel`.
struct TunnelKey: Hashable, Sendable {
    let workspace: String
    let remotePort: Int
}

protocol TunnelProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    var errorOutput: String { get }
    func terminate()
}

protocol TunnelLaunching: Sendable {
    func launch(workspace: String, remotePort: Int, localPort: Int) throws -> any TunnelProcess
}

protocol LocalPortProbing: Sendable {
    func isFree(_ port: Int) -> Bool
    func freePort() -> Int?
    func isAccepting(_ port: Int) -> Bool
}

struct TunnelError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Owns every tunnel the app opened. A tunnel lives while something holds
/// it (a preview tab, or a page sent to the browser) and ends when the last
/// holder lets go or the app quits, so no ssh is left behind.
@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    enum State: Equatable {
        case starting
        case open
    }

    struct Tunnel: Equatable, Identifiable {
        let key: TunnelKey
        let localPort: Int
        var state: State
        var holders: Set<String>

        var id: TunnelKey { key }
    }

    @Published private(set) var tunnels: [TunnelKey: Tunnel] = [:]

    private let launcher: any TunnelLaunching
    private let probe: any LocalPortProbing
    private let readyTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private var processes: [TunnelKey: any TunnelProcess] = [:]
    private var starting: [TunnelKey: Task<Int, Error>] = [:]
    private var quitObserver: NSObjectProtocol?

    init(
        launcher: any TunnelLaunching = CLITunnelLauncher(),
        probe: any LocalPortProbing = LoopbackPortProbe(),
        readyTimeout: TimeInterval = 20,
        pollInterval: TimeInterval = 0.2
    ) {
        self.launcher = launcher
        self.probe = probe
        self.readyTimeout = readyTimeout
        self.pollInterval = pollInterval
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
    }

    var openTunnels: [Tunnel] {
        tunnels.values.sorted { ($0.key.workspace, $0.key.remotePort) < ($1.key.workspace, $1.key.remotePort) }
    }

    func tunnel(for key: TunnelKey) -> Tunnel? { tunnels[key] }

    /// The local port that reaches `key`, starting the tunnel when none is up.
    func open(_ key: TunnelKey, holder: String) async throws -> Int {
        if let tunnel = tunnels[key], tunnel.state == .open, processes[key]?.isRunning == true {
            tunnels[key]?.holders.insert(holder)
            return tunnel.localPort
        }
        if let pending = starting[key] {
            let port = try await pending.value
            tunnels[key]?.holders.insert(holder)
            return port
        }
        stop(key)
        let task = Task { try await start(key, holder: holder) }
        starting[key] = task
        defer { starting[key] = nil }
        let port = try await task.value
        if tunnels[key]?.holders.isEmpty == true {
            stop(key)
            throw CancellationError()
        }
        return port
    }

    func release(holder: String) {
        for key in Array(tunnels.keys) {
            tunnels[key]?.holders.remove(holder)
            if tunnels[key]?.holders.isEmpty == true, starting[key] == nil { stop(key) }
        }
    }

    func stop(_ key: TunnelKey) {
        processes.removeValue(forKey: key)?.terminate()
        tunnels[key] = nil
    }

    func stopAll() {
        for key in Array(tunnels.keys) { stop(key) }
    }

    private func start(_ key: TunnelKey, holder: String) async throws -> Int {
        let used = Set(tunnels.values.map(\.localPort))
        let probe = self.probe
        guard let localPort = TunnelPortPicker.pick(
            preferred: key.remotePort,
            isFree: { !used.contains($0) && probe.isFree($0) },
            freePort: { probe.freePort() })
        else {
            throw TunnelError(message: "No free port on this Mac to open the tunnel on.")
        }
        let process = try launcher.launch(workspace: key.workspace, remotePort: key.remotePort, localPort: localPort)
        processes[key] = process
        tunnels[key] = Tunnel(key: key, localPort: localPort, state: .starting, holders: [holder])
        do {
            try await waitUntilReady(process, localPort: localPort)
        } catch {
            if processes[key] === process { stop(key) } else { process.terminate() }
            throw error
        }
        tunnels[key]?.state = .open
        return localPort
    }

    private func waitUntilReady(_ process: any TunnelProcess, localPort: Int) async throws {
        let deadline = Date().addingTimeInterval(readyTimeout)
        while true {
            if !process.isRunning {
                let said = process.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw TunnelError(message: said.isEmpty ? "The tunnel closed before it opened." : said)
            }
            if probe.isAccepting(localPort) { return }
            if Date() >= deadline {
                throw TunnelError(message: "The tunnel did not open within \(Int(readyTimeout)) seconds.")
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }
}

/// Spawns `devmachine tunnel` and keeps it. SIGTERM ends it cleanly: the
/// CLI stops its ssh child on that signal.
struct CLITunnelLauncher: TunnelLaunching {
    func launch(workspace: String, remotePort: Int, localPort: Int) throws -> any TunnelProcess {
        let cli = try DevmachineCLI.resolve()
        let command = cli.tunnelCommand(workspace: workspace, remotePort: remotePort, localPort: localPort)
        return try SpawnedTunnel(command.executable, command.args, command.environment)
    }
}

final class SpawnedTunnel: TunnelProcess, @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var stderr = Data()

    init(_ executable: String, _ args: [String], _ environment: [String: String]) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.lock.withLock {
                if self.stderr.count < 8192 { self.stderr.append(chunk) }
            }
        }
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    var errorOutput: String {
        lock.withLock { String(data: stderr, encoding: .utf8) ?? "" }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Asks the loopback interface directly: the same check the CLI makes before
/// it binds, so a port this calls free is one the tunnel can take.
struct LoopbackPortProbe: LocalPortProbing {
    func isFree(_ port: Int) -> Bool {
        withSocket { fd in
            var address = Self.loopback(port)
            return withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        } ?? false
    }

    func freePort() -> Int? {
        withSocket { fd -> Int? in
            var address = Self.loopback(0)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            guard bound else { return nil }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) == 0 }
            }
            return named ? Int(UInt16(bigEndian: address.sin_port)) : nil
        } ?? nil
    }

    func isAccepting(_ port: Int) -> Bool {
        withSocket { fd in
            var address = Self.loopback(port)
            return withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        } ?? false
    }

    private func withSocket<T>(_ body: (Int32) -> T) -> T? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return body(fd)
    }

    private static func loopback(_ port: Int) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }
}
