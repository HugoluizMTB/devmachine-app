import SwiftUI
import DevmachineCore

/// The app's own sidebar views, by view kind. Tasks add their case here;
/// a kind without one says this app cannot draw it.
struct StackAppWidgetView: View {
    let kind: StackAppViewKind
    let isLead: Bool

    var body: some View {
        switch kind {
        default:
            WidgetPlaceholderView(
                icon: "puzzlepiece.extension", title: "Needs a newer app",
                detail: "This app cannot draw \(kind.viewKind) in a sidebar yet.")
        }
    }
}
