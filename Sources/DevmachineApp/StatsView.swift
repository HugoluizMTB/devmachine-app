import SwiftUI
import DevmachineCore

private func gb(_ bytes: Int64) -> String {
    String(format: "%.1f", Double(bytes) / 1_073_741_824)
}

struct StatsView: View {
    @EnvironmentObject var store: StatsStore
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .onAppear {
            if store.snapshot == nil { refresh() }
        }
    }

    private func refresh() {
        store.refresh()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Stats")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)

            Spacer()

            if let refreshedAt = store.refreshedAt {
                Text(verbatim: "updated \(Self.timeFormatter.string(from: refreshedAt))")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
            }

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { refresh() }
                .help("Refresh")
        }
        .padding(10)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @ViewBuilder
    private var content: some View {
        // A snapshot already on screen stays there under an error banner: a
        // blip does not have to blank a panel the person was just reading.
        if let snapshot = store.snapshot {
            VStack(spacing: 0) {
                if let err = store.errorText {
                    errorBanner(err)
                }
                snapshotView(snapshot)
            }
        } else if let err = store.errorText {
            errorView(err)
        } else if store.isLoading {
            loadingView
        } else {
            emptyView
        }
    }

    private func errorBanner(_ message: String) -> some View {
        DMBanner(message: message) {
            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { refresh() }
        }
    }

    private func errorView(_ message: String) -> some View {
        DMStatusView(kind: .failed(message: message, retry: refresh))
    }

    private var loadingView: some View {
        DMStatusView(kind: .loading("Loading…"))
    }

    private var emptyView: some View {
        DMStatusView(kind: .empty(systemImage: "chart.bar", text: "No stats available"))
    }

    private func snapshotView(_ snapshot: StatsSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                bubblesRow(snapshot)
                memorySection(snapshot)
                diskSection(snapshot)
                containersSection(snapshot)
                usersSection(snapshot)
            }
            .padding(.bottom, 16)
        }
    }

    private func bubblesRow(_ snapshot: StatsSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
            spacing: 12
        ) {
            DMStatBubble(value: "\(gb(snapshot.memUsed)) GB", label: "RAM used")
            DMStatBubble(value: "\(gb(snapshot.diskAvail)) GB", label: "Disk free")
            DMStatBubble(value: "\(containers(snapshot).count)", label: "Containers")
            DMStatBubble(value: String(format: "%.2f", snapshot.load1), label: "Load 1m")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func memorySection(_ snapshot: StatsSnapshot) -> some View {
        DMSection(
            contentSpacing: 6,
            padding: EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16),
            label: {
                Text("MEMORY")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .kerning(0.8)
            },
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        DMProgressBar(
                            done: Int(snapshot.memUsed / 1_048_576),
                            total: Int(snapshot.memTotal / 1_048_576)
                        )
                        Text(verbatim: "\(gb(snapshot.memUsed)) / \(gb(snapshot.memTotal)) GB used")
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                    }
                    if snapshot.swapTotal > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            DMProgressBar(
                                done: Int(snapshot.swapUsed / 1_048_576),
                                total: Int(snapshot.swapTotal / 1_048_576),
                                fillColor: .orange
                            )
                            Text(verbatim: "\(gb(snapshot.swapUsed)) / \(gb(snapshot.swapTotal)) GB swap")
                                .font(.dm(11))
                                .foregroundStyle(Color.dmMuted)
                        }
                    }
                }
            }
        )
    }

    private func diskSection(_ snapshot: StatsSnapshot) -> some View {
        DMSection(
            contentSpacing: 6,
            padding: EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16),
            label: {
                Text("DISK")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .kerning(0.8)
            },
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    DMProgressBar(done: snapshot.diskPercent, total: 100)
                    Text(verbatim: "\(gb(snapshot.diskUsed)) GB used · \(gb(snapshot.diskAvail)) GB free")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }
        )
    }

    private func containersSection(_ snapshot: StatsSnapshot) -> some View {
        DMSection(
            contentSpacing: 2,
            padding: EdgeInsets(top: 12, leading: 10, bottom: 0, trailing: 10),
            label: {
                Text("CONTAINERS")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .kerning(0.8)
                    .padding(.leading, 6)
            },
            content: {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(containers(snapshot), id: \.name) { container in
                        DMRow(
                            systemImage: "shippingbox",
                            iconColor: .dmMuted,
                            title: container.name,
                            trailing: AnyView(
                                Text(verbatim: "\(container.mem) · \(container.cpu)")
                                    .font(.dm(11))
                                    .foregroundStyle(Color.dmMuted)
                            )
                        )
                    }
                }
            }
        )
    }

    /// A workspace turned off in Settings is not on screen anywhere else, so
    /// its containers and its memory do not belong in this list either.
    private func containers(_ snapshot: StatsSnapshot) -> [ContainerStat] {
        snapshot.containers.filter { container in
            model.showsOwner(Ownership.owner(
                ofContainer: container.name,
                labelled: container.owner,
                knownUsers: model.knownUsers))
        }
    }

    private func users(_ snapshot: StatsSnapshot) -> [UserRAM] {
        snapshot.users.filter { model.showsOwner($0.user) }
    }

    private func usersSection(_ snapshot: StatsSnapshot) -> some View {
        DMSection(
            contentSpacing: 2,
            padding: EdgeInsets(top: 12, leading: 10, bottom: 0, trailing: 10),
            label: {
                Text("RAM BY USER")
                    .font(.dm(11, weight: .semibold))
                    .foregroundStyle(Color.dmMuted)
                    .kerning(0.8)
                    .padding(.leading, 6)
            },
            content: {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(users(snapshot), id: \.user) { user in
                        DMRow(
                            systemImage: "person",
                            iconColor: .dmMuted,
                            title: user.user,
                            trailing: AnyView(
                                Text(verbatim: "\(gb(user.rssBytes)) GB")
                                    .font(.dm(11))
                                    .foregroundStyle(Color.dmMuted)
                            )
                        )
                    }
                }
            }
        )
    }
}
