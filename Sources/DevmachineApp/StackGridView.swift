import SwiftUI
import DevmachineCore

struct StackGridView: View {
    let refs: [SessionRef]
    @EnvironmentObject var model: AppModel

    private let gap = FloatingCardLayout.gap
    // Each cell is centered in its rect with gap/2 on every side, so the pane
    // edge needs only the remaining half to reach the full margin.
    private let pad = FloatingCardLayout.margin - FloatingCardLayout.gap / 2

    var body: some View {
        GeometryReader { geo in
            let innerWidth = max(0, geo.size.width - pad * 2)
            let innerHeight = max(0, geo.size.height - pad * 2)
            let rects = StackGrid.layout(refs.map { model.stackCellSize($0) })

            ZStack {
                WallpaperBackground(style: .ambient)

                ForEach(refs, id: \.self) { ref in
                    if let index = refs.firstIndex(of: ref),
                       let rect = rects.first(where: { $0.index == index }) {
                        cell(ref)
                            .frame(
                                width: max(1, rect.width * innerWidth - gap),
                                height: max(1, rect.height * innerHeight - gap)
                            )
                            .position(
                                x: pad + rect.x * innerWidth + rect.width * innerWidth / 2,
                                y: pad + rect.y * innerHeight + rect.height * innerHeight / 2
                            )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.18), value: layoutKey)
        }
    }

    private var layoutKey: String {
        refs.map { "\($0.alias)/\($0.name):\(model.stackCellSize($0).rawValue)" }.joined(separator: ",")
    }

    /// The title is a row of its own, not a badge floating over the terminal.
    /// As an overlay it needed a matching inset below it, and that number was
    /// fixed while the title's own height follows the app font size — so the
    /// first line of the session ended up under the badge.
    private func cell(_ ref: SessionRef) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(ref.alias == Workspace.local.alias
                     ? model.displayName(for: ref) : "\(ref.alias) / \(ref.name)")
                    .font(.dm(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                controlStrip(ref)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            TerminalPaneView(
                kind: model.terminalKind(for: ref),
                translucent: true
            )
            .terminalFindBar(for: model.terminalKind(for: ref))
            .terminalUploads(for: model.terminalKind(for: ref))
        }
        .floatingCard()
    }

    private func controlStrip(_ ref: SessionRef) -> some View {
        let index = refs.firstIndex(of: ref)
        let isFirst = index == 0
        let isLast = index == (refs.count - 1)

        return HStack(spacing: 2) {
            DMIconButton(systemImage: "chevron.left", tint: nil, hitSize: DMHitSize.strip) {
                model.moveStackCell(ref, by: -1)
            }
            .disabled(isFirst)

            DMIconButton(
                systemImage: sizeIcon(model.stackCellSize(ref)), tint: nil,
                hitSize: DMHitSize.strip
            ) {
                model.cycleStackCellSize(ref)
            }
            .help("Size: auto/half/full — click to cycle")

            DMIconButton(systemImage: "chevron.right", tint: nil, hitSize: DMHitSize.strip) {
                model.moveStackCell(ref, by: 1)
            }
            .disabled(isLast)
        }
        .font(.dm(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .dmGlass(in: Capsule(), stroke: .clear)
    }

    private func sizeIcon(_ size: StackCellSize) -> String {
        switch size {
        case .auto: return "square.grid.2x2"
        case .half: return "rectangle.lefthalf.filled"
        case .full: return "rectangle.fill"
        }
    }
}
