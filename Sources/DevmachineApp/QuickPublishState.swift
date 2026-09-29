import SwiftUI
import DevmachineCore

/// Drives the "Publish a port…" flow started from a remote workspace: it
/// asks the workspace's own listening ports before opening `AddSubdomainSheet`
/// already filled in, so the sheet never opens blank.
@MainActor
final class QuickPublishState: ObservableObject {
    @Published var workspace: String?
    @Published var suggestions = QuickPublishSuggestions()

    func start(workspace: String) {
        Task {
            let suggestions = await Task.detached {
                PublishSuggestionsService().suggestions(forWorkspace: workspace)
            }.value
            self.suggestions = suggestions
            self.workspace = workspace
        }
    }
}

extension View {
    /// Presents `AddSubdomainSheet` once `state.workspace` is set, preselected
    /// and pre-filled with that workspace's own ports.
    func quickPublishSheet(_ state: QuickPublishState, settings: AppSettings?, workspaces: [Workspace]) -> some View {
        sheet(isPresented: Binding(
            get: { state.workspace != nil },
            set: { if !$0 { state.workspace = nil } }
        )) {
            if let workspace = state.workspace, let settings {
                AddSubdomainSheet(
                    settings: settings, workspaces: workspaces, preselectedWorkspace: workspace,
                    suggestedPorts: state.suggestions.ports,
                    suggestedLabel: workspace)
            }
        }
    }
}
