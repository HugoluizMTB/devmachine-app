import SwiftUI
import DevmachineCore

enum SessionOpening {
    static func item(target: WidgetTarget, session: String, workspaces: [Workspace], localSessions: [LocalSession]) -> SidebarItem? {
        switch target {
        case let .workspace(name):
            guard let workspace = workspaces.first(where: { $0.name == name }) else { return nil }
            return .session(alias: workspace.alias, name: session)
        case .local:
            guard let local = localSessions.first(where: { $0.handle == session }) else { return nil }
            return .localSession(name: local.handle, path: local.path)
        case .machine:
            return nil
        }
    }
}

enum SourceWidgetCardMode: Equatable {
    case approval
    case demo
    case content

    static func of(approval: ApprovalState, isDemo: Bool, viewKind: String) -> SourceWidgetCardMode {
        guard approval.canRun else { return .approval }
        return isDemo && viewKind != "web" ? .demo : .content
    }
}

enum WidgetApprovalText {
    static func headline(kind: String, denied: Bool) -> String {
        denied ? "Paused: you denied this \(kind) widget" : "Allow this \(kind) widget to run?"
    }

    static func whereAndWhen(_ source: ResolvedSource) -> String {
        "Runs \(ApprovalCopy.place(source.source.target)), \(ApprovalCopy.howOften(source.every))."
    }

    static let warning = "It was written into home.yml, by you or an agent. Allow it only if you know what it does."
}

/// An inline widget that runs something waits here until the owner says
/// so; the board file can be written by an agent, this card cannot.
struct WidgetApprovalCard: View {
    let source: ResolvedSource
    let state: ApprovalState
    let size: CGSize
    let onAllow: () -> Void
    let onDeny: () -> Void
    @Environment(\.dmMetrics) private var m

    private var denied: Bool {
        if case .denied = state { return true }
        return false
    }

    var body: some View {
        let what = ApprovalCopy.what(source.source)
        VStack(alignment: .leading, spacing: m.space.sm) {
            Label {
                Text(verbatim: WidgetApprovalText.headline(kind: source.source.kind, denied: denied))
                    .lineLimit(2)
            } icon: {
                Image(systemName: denied ? "pause.circle" : "hand.raised")
            }
            .font(.dm(12, weight: .semibold))
            .foregroundStyle(.white)
            Text(verbatim: what)
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(Text(verbatim: what))
                .padding(m.space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dmSurface(Color.dmBand, radius: DMRadius.row)
            Text(verbatim: WidgetApprovalText.whereAndWhen(source))
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(2)
            if !denied, WidgetDensity.of(width: size.width / m.pt(1), height: size.height / m.pt(1)) == .full {
                Text(verbatim: WidgetApprovalText.warning)
                    .font(.dm(10))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: m.space.sm) {
                DMButton("Allow", variant: denied ? .outline : .primary, size: .small, action: onAllow)
                if !denied { DMButton("Deny", variant: .outline, size: .small, action: onDeny) }
                Spacer(minLength: m.size(DMHitSize.compact).width)
            }
            .layoutPriority(1)
        }
        .padding(m.space.lg)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .dmGlass(radius: DMRadius.card)
    }
}

/// A source widget on the canvas: the approval card while it waits or is
/// denied, otherwise its view.
struct SourceWidgetCard: View {
    let id: String
    let title: String
    let source: ResolvedSource
    @ObservedObject var controller: WidgetSourceController
    let size: CGSize
    let onOpenSession: (WidgetTarget, String) -> Void

    var body: some View {
        let approval = controller.approvalState(id)
        switch SourceWidgetCardMode.of(approval: approval, isDemo: controller.isDemoMode, viewKind: source.view.kind) {
        case .approval:
            WidgetApprovalCard(
                source: source, state: approval, size: size,
                onAllow: { controller.approve(id) }, onDeny: { controller.deny(id) })
        case .demo:
            WidgetPlaceholderView(icon: "play.slash", title: title, detail: "Demo mode never runs widget commands.")
        case .content:
            SourceWidgetContent(
                title: title, source: source, state: controller.state(id), history: controller.history(id), size: size,
                onRun: { controller.runNow(id) }, onOpenSession: sessionAction)
        }
    }

    private var sessionAction: (() -> Void)? {
        guard case let .session(session) = source.source else { return nil }
        if case .machine = session.target { return nil }
        return { onOpenSession(session.target, session.session) }
    }
}
