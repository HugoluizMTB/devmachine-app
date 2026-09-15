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

    private func cell(_ ref: SessionRef) -> some View {
        TerminalPaneView(
            kind: .remote(alias: ref.alias, session: ref.name),
            translucent: true,
            contentInsets: NSEdgeInsets(top: 34, left: 10, bottom: 8, right: 10)
        )
            .overlay(alignment: .topLeading) {
                Text("\(ref.alias) / \(ref.name)")
                    .font(.dm(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                controlStrip(ref).padding(8)
            }
            .floatingCard()
    }

    private func controlStrip(_ ref: SessionRef) -> some View {
        let index = refs.firstIndex(of: ref)
        let isFirst = index == 0
        let isLast = index == (refs.count - 1)

        return HStack(spacing: 2) {
            Button {
                model.moveStackCell(ref, by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(isFirst)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())

            Button {
                model.cycleStackCellSize(ref)
            } label: {
                Image(systemName: sizeIcon(model.stackCellSize(ref)))
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help("Size: auto/half/full — click to cycle")

            Button {
                model.moveStackCell(ref, by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(isLast)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .font(.dm(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func sizeIcon(_ size: StackCellSize) -> String {
        switch size {
        case .auto: return "square.grid.2x2"
        case .half: return "rectangle.lefthalf.filled"
        case .full: return "rectangle.fill"
        }
    }
}
