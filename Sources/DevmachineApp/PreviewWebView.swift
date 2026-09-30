import SwiftUI
import AppKit
import WebKit
import DevmachineCore

/// One tab's browser. It lives as long as its tab, not its view: switching
/// tabs or sessions re-parents the same web view instead of reloading it.
@MainActor
final class PreviewPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var failure: String?
    @Published private(set) var blocked: URL?

    let webView: WKWebView
    private var shown: PreviewTab.State?
    private var observations: [NSKeyValueObservation] = []

    init(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.url = view.url }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
        ]
    }

    func show(_ state: PreviewTab.State) {
        guard state != shown else { return }
        shown = state
        failure = nil
        switch state {
        case let .ready(url):
            go(to: url)
        case let .page(html, baseURL):
            webView.loadHTMLString(html, baseURL: baseURL)
        case .connecting, .failed:
            break
        }
    }

    func go(to url: URL) {
        guard PreviewURLPolicy.allows(url) else {
            blocked = url
            return
        }
        failure = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        failure = nil
        if webView.url == nil, case let .ready(url) = shown {
            go(to: url)
        } else {
            webView.reload()
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func dismissBlocked() { blocked = nil }

    nonisolated func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        MainActor.assumeIsolated {
            guard let url, !PreviewURLPolicy.allows(url) else {
                decisionHandler(.allow)
                return
            }
            blocked = url
            decisionHandler(.cancel)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        MainActor.assumeIsolated { fail(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { fail(error) }
    }

    /// `target="_blank"` stays in this tab: a second window would escape
    /// the pane and its rules.
    nonisolated func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        MainActor.assumeIsolated {
            if let url = navigationAction.request.url { go(to: url) }
        }
        return nil
    }

    private func fail(_ error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        failure = error.localizedDescription
    }
}

/// Every open tab's page. The data store is shared by the tabs of one app
/// run and never written to disk, so a login made in a preview ends when
/// the app quits.
@MainActor
final class PreviewWebViews {
    static let shared = PreviewWebViews()

    private let dataStore = WKWebsiteDataStore.nonPersistent()
    private var pages: [UUID: PreviewPage] = [:]

    func page(for id: UUID) -> PreviewPage {
        if let page = pages[id] { return page }
        let page = PreviewPage(dataStore: dataStore)
        pages[id] = page
        return page
    }

    func forget(_ id: UUID) {
        guard let page = pages.removeValue(forKey: id) else { return }
        page.webView.stopLoading()
        page.webView.removeFromSuperview()
    }
}

struct PreviewWebViewHost: NSViewRepresentable {
    let page: PreviewPage

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
    }

    private func attach(to container: NSView) {
        let webView = page.webView
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
