import SwiftUI
import AppKit
import ClaudeUsageKit

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var usage: ClaudeUsageStore

    private var totalSessions: Int {
        model.sessionsByAlias.values.reduce(0) { $0 + $1.count }
    }
    private var claudeSessions: Int {
        model.sessionsByAlias.values.reduce(0) { $0 + $1.filter(\.hasClaude).count }
    }
    private var workspaceCount: Int { model.workspaces.count }

    private var systemName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                Spacer()

                TimelineView(.everyMinute) { ctx in
                    VStack(spacing: 6) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 150, weight: .thin, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 18, y: 2)
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(systemName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()
            }

            VStack {
                HStack(alignment: .top, spacing: 14) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 14) {
                        usageCard
                        notificationsCard
                    }
                }
                Spacer()
            }
            .padding(24)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    compactStatCluster
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WallpaperBackground())
        .clipped()
        .onAppear {
            usage.beginObserving()
            usage.refresh()
            usage.refreshStats()
        }
        .onDisappear { usage.endObserving() }
    }

    private var usageBlocks: [UsageBlock] {
        usage.blocks
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Claude Usage")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            if usageBlocks.isEmpty {
                Text(verbatim: "Loading usage…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                UsageBarsView(blocks: usageBlocks)
            }

            Text(verbatim: "Today: \(UsageFormat.tokens(usage.stats?.todayTokens ?? 0)) tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Notifications")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(verbatim: "No notifications")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var compactStatCluster: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(totalSessions) sessões")
            Text(verbatim: "·")
            Text(verbatim: "\(claudeSessions) com Claude")
            Text(verbatim: "·")
            Text(verbatim: "\(workspaceCount) workspaces")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.65))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

}
