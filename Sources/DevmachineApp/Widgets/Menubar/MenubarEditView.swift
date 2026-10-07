import SwiftUI
import DevmachineCore

struct MenubarEditRow: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let choices: [ChoiceInput]

    static func rows(
        board: StackBoard, resolve: (StackEntry) -> WidgetResolution?, catalog: WidgetCatalog?,
        choices: (StackEntry) -> [ChoiceInput] = { _ in [] }
    ) -> [MenubarEditRow] {
        board.entries.enumerated().map { index, entry in
            let resolution = resolve(entry)
            var detail: String?
            if let resolution, case .ready = resolution {
                detail = nil
            } else if let resolution {
                detail = WidgetResolutionCopy.detail(resolution, release: catalog?.packagesRelease ?? "")
            }
            return MenubarEditRow(
                id: entry.id, title: MenubarTitles.title(entry, resolution: resolution, catalog: catalog), detail: detail,
                canMoveUp: index > 0, canMoveDown: index < board.entries.count - 1,
                choices: choices(entry))
        }
    }
}

private struct MenubarChoosing: Equatable {
    let surface: String
    let request: WidgetChoiceRequest
}

private struct MenubarEditing: Equatable {
    let surface: String
    let request: WidgetEditRequest
}

/// The popover's Edit mode: both areas as lists. Add opens the gallery in
/// place, because a popover from inside the menu bar window is not reliable.
struct MenubarEditView: View {
    @ObservedObject var slots: StackBoardController
    @ObservedObject var panel: StackBoardController
    @State private var adding: String?
    @State private var choosing: MenubarChoosing?
    @State private var editing: MenubarEditing?
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if let editing, let board = [slots, panel].first(where: { $0.surface == editing.surface }) {
            WidgetEditorSheet(request: editing.request, target: board, onDone: { self.editing = nil })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let choosing, let board = [slots, panel].first(where: { $0.surface == choosing.surface }) {
            WidgetChoiceSheet(request: choosing.request, target: board, onDone: { self.choosing = nil })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let surface = adding, let board = [slots, panel].first(where: { $0.surface == surface }) {
            VStack(alignment: .leading, spacing: m.space.sm) {
                DMButton("Back", systemImage: "chevron.left", variant: .ghost, size: .small) { adding = nil }
                WidgetGalleryView(
                    surface: board.surface, catalog: board.catalog.catalog, entries: board.galleryEntries(),
                    failure: galleryFailure(board), blockedReason: { board.addBlockedReason(for: $0) },
                    onAdd: { if board.add($0) { adding = nil } }, onRetry: { board.catalog.reloadSoon() },
                    templates: InlineWidgetTemplate.offered(on: WidgetContract.current.layout(of: board.surface)),
                    onNewWidget: { template in
                        adding = nil
                        editing = MenubarEditing(surface: board.surface, request: .new(template))
                    })
            }
            .padding(m.space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { board.catalog.reloadSoon() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: m.space.lg) {
                    section("MENU BAR", hint: "Up to 3 widgets, left to right.", board: slots)
                    section("TABS", hint: "One widget per tab, in this order.", board: panel)
                }
                .padding(m.space.lg)
            }
        }
    }

    private func section(_ title: String, hint: String, board: StackBoardController) -> some View {
        let rows = MenubarEditRow.rows(
            board: board.board, resolve: { board.resolution(of: $0) }, catalog: board.catalog.catalog,
            choices: { board.choices(for: $0.id) })
        return VStack(alignment: .leading, spacing: m.space.sm) {
            DMSectionLabel(text: title)
            Text(verbatim: hint).font(.dm(11)).foregroundStyle(Color.dmMuted)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                DMTableRow(index: index) {
                    HStack(spacing: m.space.sm) {
                        VStack(alignment: .leading, spacing: m.space.xxs) {
                            Text(verbatim: row.title).font(.dm(12, weight: .semibold))
                            if let detail = row.detail {
                                Text(verbatim: detail)
                                    .font(.dm(11))
                                    .foregroundStyle(Color.dmMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: m.space.sm)
                        if !row.choices.isEmpty || board.offersEdit(row.id) {
                            Menu {
                                ForEach(row.choices) { choice in
                                    Button {
                                        choosing = MenubarChoosing(
                                            surface: board.surface,
                                            request: WidgetChoiceRequest(entryID: row.id, input: choice, title: row.title))
                                    } label: {
                                        Text(verbatim: choice.menuTitle)
                                    }
                                }
                                if board.offersEdit(row.id) {
                                    Button("Edit…") {
                                        editing = MenubarEditing(surface: board.surface, request: .edit(row.id))
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .disabled(!board.canEdit)
                            .help(Text(verbatim: "More"))
                            .accessibilityLabel("More")
                        }
                        DMIconButton(systemImage: "chevron.up") { board.moveUp(row.id) }
                            .disabled(!board.canEdit || !row.canMoveUp)
                            .help(Text(verbatim: "Move up"))
                        DMIconButton(systemImage: "chevron.down") { board.moveDown(row.id) }
                            .disabled(!board.canEdit || !row.canMoveDown)
                            .help(Text(verbatim: "Move down"))
                        DMIconButton(systemImage: "trash") { board.remove(row.id) }
                            .disabled(!board.canEdit)
                            .help(Text(verbatim: "Remove"))
                    }
                    .padding(.horizontal, m.space.sm)
                    .padding(.vertical, m.space.xs)
                }
            }
            let full = StackGallery.fullReason(board.board)
            DMButton("Add widget", systemImage: "plus", variant: .ghost, size: .small) { adding = board.surface }
                .disabled(!board.canEdit || full != nil)
            if let full {
                Text(verbatim: full).font(.dm(11)).foregroundStyle(Color.dmMuted)
            }
        }
    }

    private func galleryFailure(_ board: StackBoardController) -> String? {
        if case let .failed(message) = board.catalog.state { return message }
        return nil
    }
}
