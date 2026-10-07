import SwiftUI
import DevmachineCore

/// The menu bar title: text and at most one SF Symbol per slot, so macOS
/// can template it. One item is drawn alone, as the title always was.
struct MenuBarLabel: View {
    let items: [MenubarSlotItem]

    init(items: [MenubarSlotItem]) {
        self.items = items
    }

    var body: some View {
        if items.count == 1, let only = items.first {
            MenuBarSlotView(item: only)
        } else {
            HStack(spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MenuBarSlotView(item: item)
                }
            }
        }
    }
}

extension MenuBarLabel {
    /// The default board with no file, catalog or sources yet: the same
    /// function the controller runs, fed only the pull request count.
    init(prStore: PRStore) {
        let board = DefaultStackBoard.make(surface: DefaultStackBoard.menubar)
        self.init(items: MenubarLabelModel.items(MenubarLabelInputs.make(
            board: board, resolve: { StackResolution.resolve($0, on: board, catalog: nil) },
            openCount: prStore.openCount, output: { _ in nil }, approval: { _, _ in .notNeeded })))
    }
}

struct MenuBarSlotView: View {
    let item: MenubarSlotItem

    var body: some View {
        switch item {
        case .brand:
            Text(verbatim: "❯_").font(.dm(13, weight: .bold, design: .monospaced))
        case let .text(text):
            Text(verbatim: text)
        case let .status(level, label):
            HStack(spacing: 2) {
                Image(systemName: MenubarLabelModel.symbol(level))
                Text(verbatim: label)
            }
        case .waiting:
            Text(verbatim: "!").fontWeight(.bold)
        }
    }
}

/// Watches only the title's items, so nothing else redraws it.
struct MenuBarLabelHost: View {
    @ObservedObject var label: MenubarLabelState

    var body: some View { MenuBarLabel(items: label.items) }
}
