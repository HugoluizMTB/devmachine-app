import SwiftUI
import DevmachineCore

/// The app's own sidebar views, by view kind. Tasks add their case here;
/// a kind without one says this app cannot draw it.
struct StackAppWidgetView: View {
    let kind: StackAppViewKind
    let preceding: [StackAppViewKind]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch kind {
        case .workspaces:
            WorkspacesWidgetView()
        case .shortcuts:
            if let target = model.selectedSessionTarget {
                ShortcutsSection(target: target)
            } else {
                StackEmptyWidgetHeader()
            }
        case .publishPort:
            PublishPortWidgetView()
        case .monitors, .shells, .subAgents, .todo, .pullRequests, .links:
            ContextSectionWidgetView(kind: kind, store: model.context, preceding: preceding)
        case .ask:
            AskWidgetView(context: model.context)
        default:
            WidgetPlaceholderView(
                icon: "puzzlepiece.extension", title: "Needs a newer app",
                detail: "This app cannot draw \(kind.viewKind) in a sidebar yet.")
        }
    }
}
