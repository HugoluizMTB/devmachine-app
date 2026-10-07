import AppKit
import SwiftUI

enum MenubarPanelSignal: Equatable {
    case appeared
    case disappeared
    case becameKey
    case resignedKey(stillVisible: Bool)
}

/// Whether a signal from the popover or its window opens or closes it.
/// nil means nothing changes, so a second signal for the same open or
/// close never runs the open or close code again.
enum MenubarPanelPresence {
    static func change(after signal: MenubarPanelSignal, isOpen: Bool) -> Bool? {
        let next: Bool?
        switch signal {
        case .appeared, .becameKey: next = true
        case .disappeared: next = false
        case let .resignedKey(stillVisible): next = stillVisible ? nil : false
        }
        return next == isOpen ? nil : next
    }
}

/// Reports the key changes of the window it sits in, which for the popover
/// is the menu bar window and no other. A window that gives up key but stays
/// on screen (a sheet, the color sampler) keeps the popover open.
struct MenubarPanelWindowWatch: NSViewRepresentable {
    let onSignal: (MenubarPanelSignal) -> Void

    func makeNSView(context: Context) -> WatchView {
        let view = WatchView()
        view.onSignal = onSignal
        return view
    }

    func updateNSView(_ nsView: WatchView, context: Context) {
        nsView.onSignal = onSignal
    }

    final class WatchView: NSView {
        var onSignal: ((MenubarPanelSignal) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            guard let window else { return }
            center.addObserver(self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(resignedKey), name: NSWindow.didResignKeyNotification, object: window)
        }

        @objc private func becameKey() { onSignal?(.becameKey) }

        @objc private func resignedKey() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.onSignal?(.resignedKey(stillVisible: window.isVisible))
            }
        }
    }
}
