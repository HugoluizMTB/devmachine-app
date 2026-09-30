import SwiftUI
import DevmachineCore

private func gb(_ bytes: Int64) -> String {
    String(format: "%.1f", Double(bytes) / 1_073_741_824)
}

/// MB below a gigabyte, GB above it — a container using 120 MB should not
/// read as "0.1 GB".
private func memSize(_ bytes: Int64) -> String {
    bytes < 1_073_741_824
        ? String(format: "%.0f MB", Double(bytes) / 1_048_576)
        : "\(gb(bytes)) GB"
}

struct StatsView: View {
    @EnvironmentObject var store: StatsStore
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // A single machine reads without tabs: there is nothing to pick.
            if store.showsSwitcher {
                machineSwitcher
            }
            content
        }
        .animation(.easeOut(duration: 0.2), value: store.showsSkeleton)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
        .onAppear {
            store.start()
            if let machine = store.selectedMachine { store.refreshIfStale(machine) }
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
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(verbatim: StatsFreshness.ageText(since: refreshedAt, now: context.date))
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .help(Self.timeFormatter.string(from: refreshedAt))
                }
            }

            if store.isLoading && !store.showsSkeleton {
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

    private var machineSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(store.machines) { machine in
                machineTab(machine)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func machineTab(_ machine: StatsMachine) -> some View {
        let selected = store.selectedMachine == machine.name
        return Button {
            store.select(machine.name)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: machine.name)
                    .font(.dm(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.dmRowText : Color.dmMuted)
                if let address = machine.firstAddress {
                    Text(verbatim: address)
                        .font(.dm(9.5))
                        .foregroundStyle(Color.dmMuted.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DMRadius.control, style: .continuous)
                    .fill(selected ? Color.dmSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

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
            .transition(.opacity)
        } else if let err = store.errorText {
            errorView(err)
        } else if store.showsSkeleton {
            StatsSkeleton()
                .transition(.opacity)
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
        DMStatusView(kind: .failed(
            title: store.selectedMachine.map { "Couldn't read \($0)" } ?? "Couldn't read the stats",
            message: message, retry: refresh))
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
            columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 12, alignment: .top), count: 4),
            spacing: 12
        ) {
            DMStatBubble(value: "\(gb(snapshot.memory.usedBytes)) GB", label: "RAM used")
            DMStatBubble(value: "\(gb(snapshot.disk.availableBytes)) GB", label: "Disk free")
            let containers = containersState(snapshot)
            DMStatBubble(value: containers.tileValue, label: containers.tileLabel)
            DMStatBubble(value: String(format: "%.2f", snapshot.load.load1), label: "Load 1m")
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
                            done: Int(snapshot.memory.usedBytes / 1_048_576),
                            total: Int(snapshot.memory.totalBytes / 1_048_576)
                        )
                        Text(verbatim: "\(gb(snapshot.memory.usedBytes)) / \(gb(snapshot.memory.totalBytes)) GB used")
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                    }
                    if snapshot.swap.totalBytes > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            DMProgressBar(
                                done: Int(snapshot.swap.usedBytes / 1_048_576),
                                total: Int(snapshot.swap.totalBytes / 1_048_576),
                                fillColor: .orange
                            )
                            Text(verbatim: "\(gb(snapshot.swap.usedBytes)) / \(gb(snapshot.swap.totalBytes)) GB swap")
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
                    DMProgressBar(done: snapshot.disk.usedPercent, total: 100)
                    Text(verbatim: "\(gb(snapshot.disk.usedBytes)) GB used · \(gb(snapshot.disk.availableBytes)) GB free")
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
            content: { containersContent(snapshot) }
        )
    }

    @ViewBuilder
    private func containersContent(_ snapshot: StatsSnapshot) -> some View {
        switch containersState(snapshot) {
        case .noDocker:
            noDockerHint
        case .empty:
            calmLine(ContainersState.emptyText)
        case .running(let containers):
            VStack(alignment: .leading, spacing: 1) {
                ForEach(containers, id: \.name) { container in
                    DMRow(
                        systemImage: "shippingbox",
                        iconColor: .dmMuted,
                        title: container.name,
                        trailing: AnyView(
                            Text(verbatim: "\(memSize(container.memUsedBytes)) · \(String(format: "%.1f", container.cpuPercent))%")
                                .font(.dm(11))
                                .foregroundStyle(Color.dmMuted)
                                .fixedSize()
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var noDockerHint: some View {
        let machine = store.selectedMachine ?? "this machine"
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: DockerInstallHint.message(machine: machine))
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
            Text("To add it, run:")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            DMCommandBlock(DockerInstallHint.commands(machine: machine))
                .frame(maxWidth: 520, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func calmLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }

    private func containersState(_ snapshot: StatsSnapshot) -> ContainersState {
        ContainersState(docker: snapshot.docker, visible: containers(snapshot))
    }

    /// A workspace turned off in Settings is not on screen anywhere else, so
    /// its containers and its memory do not belong in this list either.
    private func containers(_ snapshot: StatsSnapshot) -> [ContainerStat] {
        model.visibleContainers(in: snapshot)
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
            content: { usersContent(users(snapshot)) }
        )
    }

    @ViewBuilder
    private func usersContent(_ users: [UserRAM]) -> some View {
        if users.isEmpty {
            calmLine("No memory by user reported.")
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(users, id: \.user) { user in
                    DMRow(
                        systemImage: "person",
                        iconColor: .dmMuted,
                        title: user.user,
                        trailing: AnyView(
                            Text(verbatim: "\(gb(user.rssBytes)) GB")
                                .font(.dm(11))
                                .foregroundStyle(Color.dmMuted)
                                .fixedSize()
                        )
                    )
                }
            }
        }
    }
}

/// The Stats page before its first snapshot: the same sections, tiles and
/// rows as `snapshotView`, drawn as placeholders that stretch with the page.
private struct StatsSkeleton: View {
    var body: some View {
        ScrollView {
            DMSkeleton {
                VStack(alignment: .leading, spacing: 16) {
                    tiles
                    barSection("MEMORY", captionShare: 0.28)
                    barSection("DISK", captionShare: 0.36)
                    rowsSection("CONTAINERS", count: 4)
                    rowsSection("RAM BY USER", count: 3)
                }
                .padding(.bottom, 16)
            }
        }
        .scrollDisabled(true)
    }

    private var tiles: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 12, alignment: .top), count: 4),
            spacing: 12
        ) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 3) {
                    DMSkeletonText(
                        size: 24, weight: .semibold, width: .fraction([0.5, 0.56, 0.3, 0.42][index]),
                        alignment: .center)
                    DMSkeletonText(size: 12, weight: .medium, width: .fraction(0.4), alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .dmSurface(Color.dmHover, radius: DMRadius.bubble)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.dm(11, weight: .semibold))
            .foregroundStyle(Color.dmMuted)
            .kerning(0.8)
    }

    private func barSection(_ title: String, captionShare: CGFloat) -> some View {
        DMSection(
            contentSpacing: 6,
            padding: EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16),
            label: { label(title) },
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    DMSkeletonBlock(height: 5, radius: 3)
                    DMSkeletonText(size: 11, width: .fraction(captionShare))
                }
            }
        )
    }

    private func rowsSection(_ title: String, count: Int) -> some View {
        DMSection(
            contentSpacing: 2,
            padding: EdgeInsets(top: 12, leading: 10, bottom: 0, trailing: 10),
            label: { label(title).padding(.leading, 6) },
            content: {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<count, id: \.self) { index in
                        HStack(spacing: 8) {
                            DMSkeletonBlock(width: .fixed(8), height: 8, radius: 2)
                            DMSkeletonText(size: 13, width: .varied(index, shares: [0.34, 0.22, 0.4, 0.28]))
                            DMSkeletonText(size: 11, width: .fixed(72))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 6)
                    }
                }
            }
        )
    }
}

extension AppModel {
    /// A workspace turned off in Settings is not on screen anywhere else, so
    /// its containers are left out of every count and list.
    func visibleContainers(in snapshot: StatsSnapshot) -> [ContainerStat] {
        snapshot.containers.filter { container in
            showsOwner(Ownership.owner(
                ofContainer: container.name,
                labelled: container.owner,
                knownUsers: knownUsers))
        }
    }
}
