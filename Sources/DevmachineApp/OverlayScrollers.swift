import AppKit
import SwiftUI

extension View {
    /// The thin overlay scroller, with no track, on the scroll view around
    /// this content, even when System Settings shows scroll bars always.
    func overlayScrollers() -> some View {
        background(OverlayScrollers())
    }
}

private struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollerProbe {
        OverlayScrollerProbe(center: .default)
    }

    func updateNSView(_ view: OverlayScrollerProbe, context: Context) {
        view.apply()
    }
}

/// Sits inside a SwiftUI `ScrollView`'s content and sets the `NSScrollView`
/// that holds it to `.overlay`.
final class OverlayScrollerProbe: NSView {
    init(center: NotificationCenter) {
        super.init(frame: .zero)
        center.addObserver(
            self, selector: #selector(preferenceChanged),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // AppKit resets every scroll view to the new preference on this same
    // notification; applying on the next turn keeps ours after its reset.
    @objc private func preferenceChanged() {
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply() {
        guard let scroll = enclosingScrollView, scroll.scrollerStyle != .overlay else { return }
        scroll.scrollerStyle = .overlay
    }
}
