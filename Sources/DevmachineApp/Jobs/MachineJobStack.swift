import SwiftUI

/// The center's jobs as cards in the corner stack, and the full log of one
/// of them in a sheet.
struct MachineJobStack: View {
    @EnvironmentObject private var jobs: MachineJobCenter
    @Environment(\.dmMetrics) private var m
    @State private var fullLog: FullLog?

    var body: some View {
        VStack(alignment: .trailing, spacing: m.space.md) {
            ForEach(jobs.jobs) { job in
                MachineJobToast(job: job, startsFull: jobs.startsFull(job.id), actions: actions(for: job.id))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .sheet(item: $fullLog) { log in
            MachineJobLogSheet(id: log.id).environmentObject(jobs)
        }
    }

    private func actions(for id: UUID) -> MachineJobToast.Actions {
        MachineJobToast.Actions(
            start: { full in jobs.start(id, full: full) },
            later: { jobs.cancel(id) },
            cancel: { jobs.cancel(id) },
            retry: { jobs.retry(id) },
            dismiss: { jobs.dismiss(id) },
            toggleLog: { jobs.toggleExpanded(id) },
            openFullLog: { fullLog = FullLog(id: id) })
    }
}

private struct FullLog: Identifiable {
    let id: UUID
}

/// The whole output of one job, live while it runs. It keeps the last log
/// it saw, so a job that ends and leaves the stack does not blank it.
struct MachineJobLogSheet: View {
    let id: UUID
    @EnvironmentObject private var jobs: MachineJobCenter
    @Environment(\.dmMetrics) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var kept: MachineJob?

    private var job: MachineJob? { jobs.job(id) ?? kept }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: job?.plan.title ?? "Output")
                .font(.dm(15, weight: .semibold))
            DMLogView(lines: job?.log.shown ?? [], fills: true, title: "Output")
            HStack {
                Spacer()
                DMButton("Close", variant: .outline, size: .small) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(m.space.xl)
        .frame(minWidth: m.pt(640), minHeight: m.pt(420))
        .onAppear { kept = jobs.job(id) }
        .onChange(of: jobs.job(id)) { _, latest in
            if let latest { kept = latest }
        }
    }
}
