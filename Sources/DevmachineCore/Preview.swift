import Foundation

/// Where a preview or a link opens: inside the app, or in the browser the
/// person set as default in macOS.
public enum LinkOpening: String, Codable, Sendable, CaseIterable {
    case inApp
    case defaultBrowser

    public var title: String {
        switch self {
        case .inApp: return "Devmachine (in-app)"
        case .defaultBrowser: return "Default browser"
        }
    }

    public var opposite: LinkOpening {
        self == .inApp ? .defaultBrowser : .inApp
    }
}

public enum LinkRouting {
    /// ⌥-click, or the context menu's other entry, flips the setting for
    /// one link only.
    public static func destination(preference: LinkOpening, inverted: Bool) -> LinkOpening {
        inverted ? preference.opposite : preference
    }

    /// The in-app browser shows web pages only, so any other link goes to
    /// the system, whatever the setting says.
    public static func destination(for url: URL, preference: LinkOpening, inverted: Bool) -> LinkOpening {
        guard PreviewURLPolicy.isWeb(url) else { return .defaultBrowser }
        return destination(preference: preference, inverted: inverted)
    }
}

/// What the in-app browser may load. A web view that follows a `file:` link
/// reads this Mac's disk, and a custom scheme starts another app.
public enum PreviewURLPolicy {
    public static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// An address the app itself is asked to open: typed in the address bar
    /// or handed over from a link. Only a web page.
    public static func allows(_ url: URL) -> Bool {
        isWeb(url) || url.absoluteString.lowercased() == "about:blank"
    }
}

/// What the person typed in the preview field.
public enum PreviewInput: Equatable, Sendable {
    /// A port on the machine the session runs on. `localhost` means that
    /// machine too: a dev server prints its own `localhost` address.
    case port(Int, path: String)
    case url(URL)

    public static func parse(_ raw: String) -> PreviewInput? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if text.hasPrefix(":") { text.removeFirst() }
        if text.allSatisfy(\.isNumber) {
            return Int(text).flatMap(validPort).map { .port($0, path: "") }
        }
        if let colon = text.firstIndex(of: ":"), !text[text.index(after: colon)...].hasPrefix("//"),
           !text[..<colon].contains(".") && !isLoopback(String(text[..<colon])) {
            return nil
        }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme), PreviewURLPolicy.isWeb(url),
              let host = url.host, !host.isEmpty else { return nil }
        if isLoopback(host) {
            let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
            guard validPort(port) != nil else { return nil }
            return .port(port, path: pathAndQuery(of: url))
        }
        guard host.contains(".") || url.port != nil else { return nil }
        return .url(url)
    }

    private static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
    }

    private static func validPort(_ port: Int) -> Int? {
        (1...65535).contains(port) ? port : nil
    }

    private static func pathAndQuery(of url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        var result = components.percentEncodedPath
        if let query = components.percentEncodedQuery { result += "?" + query }
        return result
    }
}

/// One port something listens on here on this Mac, and the program holding it.
public struct ListeningPort: Equatable, Sendable {
    public let port: Int
    public let command: String

    public init(port: Int, command: String) {
        self.port = port
        self.command = command
    }
}

/// Reads `lsof -nP -iTCP -sTCP:LISTEN -Fpcn`: `p` starts a process, `c` is
/// its command, `n` each address it listens on.
public enum ListeningPortsParser {
    public static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]

    /// macOS's own listeners (AirPlay, Handoff) and the kernel's ephemeral
    /// range are never a dev server.
    static let systemCommands: Set<String> = [
        "ControlCe", "ControlCenter", "rapportd", "sharingd", "identityservicesd", "launchd", "remoted",
    ]

    public static func parse(_ output: String) -> [ListeningPort] {
        var command = ""
        var seen = Set<Int>()
        var ports: [ListeningPort] = []
        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p": command = ""
            case "c": command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]),
                      port < 49152, !systemCommands.contains(command),
                      !PreviewTargets.nonWebPorts.contains(port),
                      seen.insert(port).inserted else { continue }
                ports.append(ListeningPort(port: port, command: command))
            default: continue
            }
        }
        return ports.sorted { $0.port < $1.port }
    }
}

/// One row of the Preview tab.
public struct PreviewTarget: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable, Hashable {
        case site(host: String)
        case port(Int)
    }

    public let kind: Kind
    public let title: String
    public let label: String

    public var id: Kind { kind }

    public init(kind: Kind, title: String, label: String) {
        self.kind = kind
        self.title = title
        self.label = label
    }

    public var siteURL: URL? {
        guard case let .site(host) = kind else { return nil }
        return URL(string: "https://\(host)")
    }
}

public enum PreviewTargets {
    /// Databases and caches answer on a port but draw no page.
    static let nonWebPorts: Set<Int> = [22, 25, 53, 3306, 5432, 6379, 11211, 27017]

    static let knownPorts: [Int: String] = [
        1313: "hugo", 3000: "web", 3001: "web", 4000: "web", 4200: "angular", 4321: "astro",
        5000: "web", 5173: "vite", 5174: "vite", 6006: "storybook", 8000: "web", 8080: "http",
        8888: "jupyter", 54321: "supabase", 54323: "supabase studio",
    ]

    /// A remote workspace: the sites published for it, then the ports its
    /// own user listens on. A port owned by another user is someone else's.
    public static func remote(
        workspace: String, user: String, sites: [ExposedSite], ports: [PortOwner], containers: [ContainerStat]
    ) -> [PreviewTarget] {
        let rows = SubdomainRowBuilder.rows(
            sites: sites, ports: ports,
            workspaceUsers: [WorkspaceUser(workspace: workspace, user: user)], containers: containers)
        let siteTargets = rows
            .filter { $0.resolvedWorkspace == workspace }
            .map { PreviewTarget(kind: .site(host: $0.site.host), title: $0.site.host, label: String($0.site.port)) }
            .sorted { $0.title < $1.title }
        let owned = containers.filter { $0.owner == user }
        let containerName = owned.count == 1 ? owned[0].name : nil
        var seen = Set<Int>()
        let portTargets = ports
            .filter { $0.owner == user && !nonWebPorts.contains($0.port) && seen.insert($0.port).inserted }
            .sorted { $0.port < $1.port }
            .map { port($0.port, fallback: containerName) }
        return siteTargets + portTargets
    }

    public static func local(_ listening: [ListeningPort]) -> [PreviewTarget] {
        listening
            .sorted { $0.port < $1.port }
            .map { port($0.port, fallback: $0.command.isEmpty ? nil : $0.command) }
    }

    private static func port(_ port: Int, fallback: String?) -> PreviewTarget {
        PreviewTarget(kind: .port(port), title: String(port), label: knownPorts[port] ?? fallback ?? "")
    }
}

public enum TunnelPortPicker {
    /// The remote port when it is free here, so the address matches what the
    /// dev server prints; else any free port. Below 1024 needs root on a Mac.
    public static func pick(preferred: Int, isFree: (Int) -> Bool, freePort: () -> Int?) -> Int? {
        if preferred >= 1024, isFree(preferred) { return preferred }
        return freePort()
    }
}
