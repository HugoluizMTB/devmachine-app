import SwiftUI

/// The context panel's "Publish a port…" button, shown for a workspace
/// session while a machine runs Caddy.
struct PublishPortWidgetView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if case let .session(alias, _) = model.selection, model.hasCaddyMachine,
           let workspaceName = model.visibleWorkspaces.first(where: { $0.alias == alias })?.name {
            DMButton("Publish a port…", systemImage: "globe", variant: .outline, size: .small) {
                model.requestPublish(workspace: workspaceName)
            }
            .padding(.horizontal, m.pt(14))
            .padding(.top, m.space.md)
        } else {
            StackEmptyWidgetHeader()
        }
    }
}
