import Foundation

/// What a machine's containers amount to on screen. A machine without Docker
/// is not a machine with zero containers, and must not read like one.
public enum ContainersState: Equatable, Sendable {
    case noDocker
    case empty
    case running([ContainerStat])

    public static let emptyText = "No containers running."

    public init(docker: StatsSnapshot.Docker, visible: [ContainerStat]) {
        if !docker.available {
            self = .noDocker
        } else if visible.isEmpty {
            self = .empty
        } else {
            self = .running(visible)
        }
    }

    public var tileValue: String {
        switch self {
        case .noDocker: return "—"
        case .empty: return "0"
        case .running(let containers): return String(containers.count)
        }
    }

    public var tileLabel: String {
        self == .noDocker ? "No Docker" : "Containers"
    }

    public var cardValue: String { tileValue }
}

public enum DockerInstallHint {
    public static func message(machine: String) -> String {
        "Docker isn't installed on \(machine)."
    }

    public static func commands(machine: String) -> [String] {
        [
            "devmachine packages add docker --machine \(machine)",
            "devmachine sync --machine \(machine)",
        ]
    }
}
