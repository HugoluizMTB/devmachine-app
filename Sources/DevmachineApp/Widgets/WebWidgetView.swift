import SwiftUI
import AppKit
import WebKit
import DevmachineCore

/// One non-persistent store for every web widget in this app run, apart
/// from the preview browser's: a widget page never keeps cookies on disk.
@MainActor
enum WidgetWebStore {
    static let shared = WKWebsiteDataStore.nonPersistent()
}

/// What a web widget does with a navigation: the page stays in the card,
/// a clicked link or a popup goes to the default browser, and anything
/// that is not http(s) goes nowhere.
enum WebWidgetNavigation: Equatable {
    case allow, cancel, openInBrowser(URL)

    static func decide(url: URL?, isMainFrame: Bool, isLinkClick: Bool) -> WebWidgetNavigation {
        guard isMainFrame else { return .allow }
        guard let url, PreviewURLPolicy.isWeb(url) else { return .cancel }
        return isLinkClick ? .openInBrowser(url) : .allow
    }

    static func popup(url: URL?) -> WebWidgetNavigation {
        guard let url, PreviewURLPolicy.isWeb(url) else { return .cancel }
        return .openInBrowser(url)
    }
}

/// Loads the page itself and reloads it every `every` while the view
/// exists; minimized or off Home, the view is gone and so is the reload.
struct WebWidgetView: View {
    let address: String
    let zoom: Double
    let every: TimeInterval?
    @State private var reloads = 0

    var body: some View {
        WidgetWebPage(address: address, zoom: zoom, reloads: reloads)
            .clipShape(RoundedRectangle(cornerRadius: DMRadius.card))
            .task(id: address) {
                guard let every, every > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(every))
                    if !Task.isCancelled { reloads += 1 }
                }
            }
    }
}

private struct WidgetWebPage: NSViewRepresentable {
    let address: String
    let zoom: Double
    let reloads: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WidgetWebStore.shared
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.pageZoom = zoom
        load(view, context: context)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.pageZoom != zoom { view.pageZoom = zoom }
        if context.coordinator.address != address {
            load(view, context: context)
        } else if context.coordinator.reloads != reloads {
            context.coordinator.reloads = reloads
            view.reload()
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    private func load(_ view: WKWebView, context: Context) {
        context.coordinator.address = address
        context.coordinator.reloads = reloads
        guard let url = URL(string: address), PreviewURLPolicy.isWeb(url) else { return }
        view.load(URLRequest(url: url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var address = ""
        var reloads = 0

        nonisolated func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            MainActor.assumeIsolated {
                let decision = WebWidgetNavigation.decide(
                    url: navigationAction.request.url, isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                    isLinkClick: navigationAction.navigationType == .linkActivated)
                switch decision {
                case .allow:
                    decisionHandler(.allow)
                case .cancel:
                    decisionHandler(.cancel)
                case let .openInBrowser(url):
                    decisionHandler(.cancel)
                    NSWorkspace.shared.open(url)
                }
            }
        }

        nonisolated func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            MainActor.assumeIsolated {
                guard navigationAction.navigationType == .linkActivated,
                      case let .openInBrowser(url) = WebWidgetNavigation.popup(url: navigationAction.request.url)
                else { return }
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
