import SwiftUI
import DevmachineCore

/// The four numbers a machine card shows, formatted once so Home and tests
/// read the same strings.
struct MachineCardSummary: Equatable {
    let ram: String
    let diskFree: String
    let load1: String
    let containers: String

    init(snapshot: StatsSnapshot, containerCount: Int) {
        let memory = snapshot.memory
        ram = memory.totalBytes > 0
            ? String(format: "%.0f%%", Double(memory.usedBytes) / Double(memory.totalBytes) * 100)
            : "--"
        diskFree = String(format: "%.1f GB", Double(snapshot.disk.availableBytes) / 1_073_741_824)
        load1 = String(format: "%.2f", snapshot.load.load1)
        containers = snapshot.docker.available ? String(containerCount) : ContainersState.noDocker.cardValue
    }
}

/// One machine on Home: its name, the four summary numbers, how old they
/// are, and a mark when they are stale or the last read failed. Clicking it
/// opens Stats on that machine.
struct MachineStatsCard: View {
    @Environment(\.dmMetrics) private var m
    static let width: CGFloat = 184

    let machine: StatsMachine
    let state: MachineStatsState?
    let containerCount: (StatsSnapshot) -> Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: m.space.sm) {
                HStack(spacing: m.space.sm) {
                    Text(verbatim: machine.name)
                        .font(.dm(12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: m.space.xs)
                    statusMark
                }
                content
                footer
            }
            .padding(m.space.lg)
            .frame(width: m.pt(Self.width), alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: m.radius.panel))
            .dmGlass(radius: DMRadius.panel, stroke: .white.opacity(0.15))
        }
        .buttonStyle(.plain)
        .help(state?.errorText ?? "Open \(machine.name) in Stats")
    }

    @ViewBuilder
    private var statusMark: some View {
        if state?.isLoading == true, state?.snapshot != nil {
            ProgressView().controlSize(.mini)
        } else if state?.errorText != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.dm(10))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = state?.snapshot {
            let summary = MachineCardSummary(snapshot: snapshot, containerCount: containerCount(snapshot))
            VStack(alignment: .leading, spacing: m.pt(3)) {
                statLine("RAM", summary.ram)
                statLine("Disk free", summary.diskFree)
                statLine("Load 1m", summary.load1)
                statLine("Containers", summary.containers)
            }
        } else if let error = state?.errorText {
            Text(verbatim: FailureCause(message: error)?.summary ?? "Couldn't read this machine.")
                .font(.dm(10.5))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            DMSkeleton {
                VStack(alignment: .leading, spacing: m.pt(3)) {
                    ForEach(0..<4, id: \.self) { index in
                        HStack {
                            DMSkeletonText(size: 11, width: .fixed([30, 52, 44, 62][index]))
                            Spacer(minLength: m.space.sm)
                            DMSkeletonText(size: 11, weight: .medium, width: .fixed(32))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let refreshedAt = state?.refreshedAt {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let stale = StatsFreshness.isStale(since: refreshedAt, now: context.date)
                HStack(spacing: m.space.xs) {
                    if stale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.dm(9.5))
                    }
                    Text(verbatim: StatsFreshness.ageText(since: refreshedAt, now: context.date))
                        .font(.dm(10))
                }
                .foregroundStyle(stale ? Color.orange.opacity(0.9) : Color.white.opacity(0.5))
            }
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: m.space.sm)
            Text(verbatim: value)
                .font(.dm(11, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize()
        }
    }
}
