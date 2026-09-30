import SwiftUI
import DevmachineCore

/// The pane's share of the width beside the terminal, for the one main
/// window. Saved when a drag ends, never while it runs.
@MainActor
final class DocumentSplitState: ObservableObject {
    static let shared = DocumentSplitState()
    static let key = "documentSplitFraction"

    @Published private(set) var fraction: Double
    @Published private(set) var isMaximized = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fraction = DocumentSplit.stored(defaults.object(forKey: Self.key) as? Double)
    }

    func commit(_ fraction: Double) {
        let value = DocumentSplit.stored(fraction)
        guard value != self.fraction else { return }
        self.fraction = value
        defaults.set(value, forKey: Self.key)
    }

    func reset() {
        fraction = DocumentSplit.defaultFraction
        defaults.set(fraction, forKey: Self.key)
    }

    func toggleMaximized() {
        isMaximized.toggle()
    }

    func paneClosed() {
        isMaximized = false
    }

    /// ⇧⌘↩ belongs to the preview while its page has the keyboard, and to a
    /// maximized pane whatever has it; otherwise it stays the terminal's.
    func handleMaximizeShortcut(previewFocused: Bool, paneVisible: Bool) -> Bool {
        guard isMaximized || (previewFocused && paneVisible) else { return false }
        toggleMaximized()
        return true
    }
}

/// The terminal and the pane beside it. Widths come from the space the split
/// is given and the saved fraction, so a window resize writes nothing and a
/// drag lives in this view alone until it ends. The leading side keeps its
/// width while the pane is maximized over it: the program inside is not
/// resized, and it comes back exactly as it was.
struct DocumentSplitView<Leading: View, Trailing: View>: View {
    @ObservedObject var split: DocumentSplitState
    let showsTrailing: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @State private var dragStart: Double?
    @State private var live: Double?

    private let handleWidth: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let available = Double(max(size.width - (showsTrailing ? handleWidth : 0), 0))
            let trailingWidth = showsTrailing
                ? CGFloat(DocumentSplit.trailingWidth(fraction: live ?? split.fraction, available: available))
                : 0
            let leadingWidth = CGFloat(available) - trailingWidth
            let maximized = showsTrailing && split.isMaximized
            ZStack(alignment: .topLeading) {
                leading()
                    .frame(width: max(leadingWidth, 0), height: size.height)
                if showsTrailing {
                    if !maximized {
                        ResizeHandle(
                            onDrag: { dx in drag(by: dx, available: available) },
                            onEnd: endDrag,
                            onDoubleClick: split.reset)
                            .frame(height: size.height)
                            .offset(x: leadingWidth)
                    }
                    trailing()
                        .frame(width: maximized ? size.width : trailingWidth, height: size.height)
                        .offset(x: maximized ? 0 : leadingWidth + handleWidth)
                }
            }
        }
    }

    private func drag(by translation: CGFloat, available: Double) {
        let start = dragStart ?? split.fraction
        if dragStart == nil { dragStart = start }
        live = DocumentSplit.dragged(from: start, by: Double(translation), available: available)
    }

    private func endDrag() {
        if let live { split.commit(live) }
        dragStart = nil
        live = nil
    }
}
