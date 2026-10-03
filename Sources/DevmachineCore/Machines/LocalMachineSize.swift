import Foundation

/// How big a Lima machine on this Mac is made: `create-local --cpus
/// --memory --disk`, memory and disk in GiB.
public struct LocalMachineSize: Equatable, Sendable {
    public var cpus: Int
    public var memoryGiB: Int
    public var diskGiB: Int

    public init(cpus: Int, memoryGiB: Int, diskGiB: Int) {
        self.cpus = cpus
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
    }

    public var arguments: [String] {
        ["--cpus", String(cpus), "--memory", String(memoryGiB), "--disk", String(diskGiB)]
    }

    public var summary: String {
        "\(cpus) \(cpus == 1 ? "CPU" : "CPUs"), \(memoryGiB) GiB of memory, a \(diskGiB) GiB disk"
    }
}

/// What this Mac can give a Lima machine: every core, its memory but what
/// macOS needs to keep running, and its free disk but a margin.
public struct LocalMachineSizeLimits: Equatable, Sendable {
    public static let minimumMemoryGiB = 2
    public static let minimumDiskGiB = 10
    /// Lima's disk grows as it fills, so free space is a cap, not a cost;
    /// with no answer about it, this is the cap.
    public static let maximumDiskGiB = 1024
    static let memoryKeptForMacGiB = 2
    static let diskKeptFreeGiB = 10

    public let cpus: ClosedRange<Int>
    public let memoryGiB: ClosedRange<Int>
    public let diskGiB: ClosedRange<Int>

    public init(cores: Int, memoryBytes: UInt64, freeDiskBytes: Int64?) {
        let macGiB = Int(memoryBytes >> 30)
        cpus = 1...max(1, cores)
        memoryGiB = Self.minimumMemoryGiB...max(Self.minimumMemoryGiB, macGiB - Self.memoryKeptForMacGiB)
        let diskCap = freeDiskBytes.map { min(Int($0 >> 30) - Self.diskKeptFreeGiB, Self.maximumDiskGiB) }
            ?? Self.maximumDiskGiB
        diskGiB = Self.minimumDiskGiB...max(Self.minimumDiskGiB, diskCap)
        macMemoryGiB = macGiB
    }

    private let macMemoryGiB: Int

    /// Half the cores and a quarter of the memory, kept between the CLI's
    /// own default and a size that leaves the Mac responsive, and a disk
    /// with room for Docker images.
    public var defaultSize: LocalMachineSize {
        clamped(LocalMachineSize(
            cpus: min(max(cpus.upperBound / 2, 2), 4),
            memoryGiB: min(max(macMemoryGiB / 4, 4), 8),
            diskGiB: 40))
    }

    public func contains(_ size: LocalMachineSize) -> Bool {
        cpus.contains(size.cpus) && memoryGiB.contains(size.memoryGiB) && diskGiB.contains(size.diskGiB)
    }

    public func clamped(_ size: LocalMachineSize) -> LocalMachineSize {
        LocalMachineSize(
            cpus: size.cpus.clamped(to: cpus),
            memoryGiB: size.memoryGiB.clamped(to: memoryGiB),
            diskGiB: size.diskGiB.clamped(to: diskGiB))
    }
}

/// The CLI whose `create-local` takes `--cpus`, `--memory` and `--disk`.
/// An older one makes every machine at its own default size.
public enum LocalMachineSizing {
    public static let minimumCLIVersion = SemanticVersion(major: 0, minor: 7, patch: 28)

    public static func isSupported(cliVersion: SemanticVersion?) -> Bool {
        guard let cliVersion else { return false }
        return cliVersion >= minimumCLIVersion
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
