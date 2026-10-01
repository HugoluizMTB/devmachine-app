import SwiftUI
import AppKit
import WebKit
import DevmachineCore

/// The app that opens a link a page hands to another app (mail, a call).
@MainActor
protocol ExternalAppOpening {
    func appName(for url: URL) -> String?
    func open(_ url: URL)
}

@MainActor
struct WorkspaceAppOpener: ExternalAppOpening {
    func appName(for url: URL) -> String? {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// What a page was told about the camera and microphone, per origin, for
/// the app run: asking again on every call would teach people to click Allow.
@MainActor
final class PreviewMediaDecisions {
    private var decisions: [String: Bool] = [:]

    func decision(origin: String, camera: Bool, microphone: Bool) -> Bool? {
        decisions[key(origin, camera, microphone)]
    }

    func record(_ allowed: Bool, origin: String, camera: Bool, microphone: Bool) {
        decisions[key(origin, camera, microphone)] = allowed
    }

    private func key(_ origin: String, _ camera: Bool, _ microphone: Bool) -> String {
        "\(origin)|\(camera)|\(microphone)"
    }
}

/// The web view of a preview: the browser keys a page expects while it has
/// the keyboard, and tabs where WebKit's menu offers windows.
final class PreviewWebKitView: WKWebView {
    weak var page: PreviewPage?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        if hasKeyboard, let page,
           let key = PreviewKey.command(
            characters: event.charactersIgnoringModifiers ?? "", command: flags.contains(.command),
            shift: flags.contains(.shift), option: flags.contains(.option), control: flags.contains(.control)) {
            page.handle(key)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        Self.retitle(menu)
        super.willOpenMenu(menu, with: event)
    }

    static func retitle(_ menu: NSMenu) {
        for item in menu.items { item.title = PreviewContextMenu.title(for: item.title) }
    }

    private var hasKeyboard: Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current === self { return true }
            view = current.superview
        }
        return false
    }
}

/// One tab's browser. It lives as long as its tab, not its view: switching
/// tabs or sessions re-parents the same web view instead of reloading it.
/// A bare web view is only the engine; everything a browser's own window
/// does for a page (dialogs, file inputs, downloads, popups, logins) is here.
@MainActor
final class PreviewPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var failure: String?
    @Published private(set) var notice: String?
    @Published var isFinding = false
    @Published private(set) var findTerm = ""
    /// Told on every change of the page's title or address, so the tab's
    /// name follows the page instead of the host it was opened with.
    var onChange: ((_ title: String?, _ url: URL?) -> Void)?
    /// A page opened a window: the new tab's web view, built from WebKit's
    /// configuration so the page keeps `window.opener`.
    var onOpenWindow: ((WKWebViewConfiguration) -> WKWebView?)?
    var onClose: (() -> Void)?

    let webView: PreviewWebKitView
    let isPopup: Bool
    private let prompts: PreviewPrompting
    private let downloader: PreviewDownloader
    private let media: PreviewMediaDecisions
    private let apps: ExternalAppOpening
    private var shown: PreviewTab.State?
    private var observations: [NSKeyValueObservation] = []

    static func configuration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }

    init(
        configuration: WKWebViewConfiguration, prompts: PreviewPrompting, downloader: PreviewDownloader,
        media: PreviewMediaDecisions, apps: ExternalAppOpening = WorkspaceAppOpener(), isPopup: Bool = false
    ) {
        webView = PreviewWebKitView(frame: .zero, configuration: configuration)
        webView.customUserAgent = PreviewUserAgent.current
        self.prompts = prompts
        self.downloader = downloader
        self.media = media
        self.apps = apps
        self.isPopup = isPopup
        super.init()
        webView.page = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    self?.url = view.url
                    self?.onChange?(view.title, view.url)
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.onChange?(view.title, view.url) }
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
        case .connecting, .failed, .opened:
            break
        }
    }

    func go(to url: URL) {
        guard PreviewURLPolicy.allows(url) else {
            notice = PreviewDialogText.blocked(url)
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
    func dismissNotice() { notice = nil }

    // MARK: Keys, find and zoom

    func handle(_ key: PreviewKey) {
        switch key {
        case .find: isFinding = true
        case .findNext: find(findTerm, forward: true) { _ in }
        case .findPrevious: find(findTerm, forward: false) { _ in }
        case .zoomIn: webView.pageZoom = PreviewZoom.zoomedIn(from: webView.pageZoom)
        case .zoomOut: webView.pageZoom = PreviewZoom.zoomedOut(from: webView.pageZoom)
        case .actualSize: webView.pageZoom = 1
        }
    }

    func find(_ term: String, forward: Bool, done: @escaping @MainActor (Bool) -> Void) {
        findTerm = term
        guard !term.isEmpty else { return done(false) }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        configuration.caseSensitive = false
        webView.find(term, configuration: configuration) { result in done(result.matchFound) }
    }

    func endFind() {
        isFinding = false
        webView.window?.makeFirstResponder(webView)
    }

    // MARK: Navigation

    nonisolated func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let shouldDownload = navigationAction.shouldPerformDownload
        MainActor.assumeIsolated {
            decisionHandler(apply(PreviewURLPolicy.navigation(
                to: url, isMainFrame: isMainFrame, shouldDownload: shouldDownload)))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")
        let download = PreviewURLPolicy.isDownload(
            canShowMIMEType: navigationResponse.canShowMIMEType, contentDisposition: disposition)
        MainActor.assumeIsolated { decisionHandler(download ? .download : .allow) }
    }

    nonisolated func webView(
        _ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload
    ) {
        MainActor.assumeIsolated { adopt(download) }
    }

    nonisolated func webView(
        _ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload
    ) {
        MainActor.assumeIsolated { adopt(download) }
    }

    func apply(_ decision: PreviewNavigation) -> WKNavigationActionPolicy {
        switch decision {
        case .allow:
            return .allow
        case .download:
            return .download
        case let .openElsewhere(url):
            offerToAnotherApp(url)
            return .cancel
        case let .block(url):
            notice = PreviewDialogText.blocked(url)
            return .cancel
        }
    }

    /// A download link opened in a new tab leaves that tab empty; the tab
    /// goes, the file still arrives.
    private func adopt(_ download: WKDownload) {
        download.delegate = downloader
        if isPopup, !webView.canGoBack, webView.url == nil || webView.url?.absoluteString == "about:blank" {
            onClose?()
        }
    }

    private func offerToAnotherApp(_ url: URL) {
        guard let app = apps.appName(for: url) else {
            notice = PreviewDialogText.noApp(for: url)
            return
        }
        let message = PreviewDialogText.openElsewhere(url, appName: app, origin: pageOrigin)
        prompts.ask(message, confirm: "Open", in: dialogWindow) { [apps] open in
            if open { apps.open(url) }
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

    private func fail(_ error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        // A navigation that became a download ends as "frame load interrupted".
        guard !(nsError.domain == "WebKitErrorDomain" && nsError.code == 102) else { return }
        failure = error.localizedDescription
    }

    // MARK: Logins

    nonisolated func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        let method = space.authenticationMethod
        let origin = PreviewDialogText.origin(host: space.host, port: space.port)
        let realm = space.realm
        let failed = challenge.previousFailureCount
        MainActor.assumeIsolated {
            answerLogin(method: method, origin: origin, realm: realm, failed: failed, done: completionHandler)
        }
    }

    /// Basic and Digest logins ask the person; everything else, server trust
    /// included, gets WebKit's own handling. The credential lives in the
    /// web view's memory for this run only and is never written or logged.
    func answerLogin(
        method: String, origin: String, realm: String?, failed: Int,
        done: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            return done(.performDefaultHandling, nil)
        }
        let message = PreviewDialogText.login(origin: origin, realm: realm, failed: failed)
        prompts.credentials(message, in: dialogWindow) { credentials in
            guard let credentials else { return done(.performDefaultHandling, nil) }
            done(.useCredential, URLCredential(
                user: credentials.user, password: credentials.password, persistence: .forSession))
        }
    }

    // MARK: Windows

    nonisolated func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url
        return MainActor.assumeIsolated { openWindow(to: url, configuration: configuration) }
    }

    /// `window.open` and `target="_blank"` open a tab beside this one. WebKit
    /// only gets here for a click or a script answering one, since
    /// `javaScriptCanOpenWindowsAutomatically` stays off.
    func openWindow(to url: URL?, configuration: WKWebViewConfiguration) -> WKWebView? {
        let decision = PreviewURLPolicy.popup(to: url)
        guard decision == .allow else {
            _ = apply(decision)
            return nil
        }
        return onOpenWindow?(configuration)
    }

    nonisolated func webViewDidClose(_ webView: WKWebView) {
        MainActor.assumeIsolated { onClose?() }
    }

    // MARK: Dialogs

    nonisolated func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let origin = Self.origin(of: frame)
        MainActor.assumeIsolated {
            prompts.alert(title: PreviewDialogText.says(origin), message: message, in: dialogWindow,
                          done: completionHandler)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let origin = Self.origin(of: frame)
        MainActor.assumeIsolated {
            prompts.ask(PreviewDialogText.Message(title: PreviewDialogText.says(origin), body: message),
                        confirm: "OK", in: dialogWindow, done: completionHandler)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let origin = Self.origin(of: frame)
        MainActor.assumeIsolated {
            prompts.prompt(title: PreviewDialogText.says(origin), message: prompt, defaultText: defaultText,
                           in: dialogWindow, done: completionHandler)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let options = OpenPanelOptions(
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories)
        MainActor.assumeIsolated { chooseFiles(options, done: completionHandler) }
    }

    func chooseFiles(_ options: OpenPanelOptions, done: @escaping @MainActor ([URL]?) -> Void) {
        prompts.openFiles(options, in: dialogWindow, done: done)
    }

    // MARK: Camera and microphone

    nonisolated func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let name = PreviewDialogText.origin(host: origin.host, port: origin.port)
        let camera = type == .camera || type == .cameraAndMicrophone
        let microphone = type == .microphone || type == .cameraAndMicrophone
        MainActor.assumeIsolated {
            askForMedia(origin: name, camera: camera, microphone: microphone) { decisionHandler($0 ? .grant : .deny) }
        }
    }

    func askForMedia(origin: String, camera: Bool, microphone: Bool, done: @escaping @MainActor (Bool) -> Void) {
        if let known = media.decision(origin: origin, camera: camera, microphone: microphone) { return done(known) }
        let message = PreviewDialogText.Message(
            title: PreviewDialogText.media(origin: origin, camera: camera, microphone: microphone),
            body: "The answer holds for this site until Devmachine quits.")
        prompts.ask(message, confirm: "Allow", in: dialogWindow) { [media] allowed in
            media.record(allowed, origin: origin, camera: camera, microphone: microphone)
            done(allowed)
        }
    }

    // MARK: Helpers

    private var pageOrigin: String {
        PreviewDialogText.origin(host: webView.url?.host, port: webView.url?.port ?? 0)
    }

    /// A tab that is not on screen has no window; its question goes to the
    /// app's own window rather than being dropped.
    private var dialogWindow: NSWindow? {
        webView.window ?? NSApp.mainWindow ?? NSApp.windows.first { $0.title == "Devmachine" }
    }

    private nonisolated static func origin(of frame: WKFrameInfo) -> String {
        let origin = frame.securityOrigin
        return PreviewDialogText.origin(host: origin.host, port: origin.port)
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
    private let store: () -> PreviewStore
    let downloader: PreviewDownloader
    let media = PreviewMediaDecisions()
    var prompts: PreviewPrompting
    var apps: ExternalAppOpening

    init(
        store: @escaping () -> PreviewStore = { PreviewStore.shared },
        prompts: PreviewPrompting = SheetPreviewPrompts(),
        downloader: PreviewDownloader = PreviewDownloader(),
        apps: ExternalAppOpening = WorkspaceAppOpener()
    ) {
        self.store = store
        self.prompts = prompts
        self.downloader = downloader
        self.apps = apps
    }

    func page(for id: UUID) -> PreviewPage {
        if let page = pages[id] { return page }
        return make(id, configuration: PreviewPage.configuration(dataStore: dataStore), isPopup: false)
    }

    func existingPage(for id: UUID) -> PreviewPage? { pages[id] }

    /// The tab a page opened, beside its opener and in the same session.
    func openPopup(from opener: UUID, configuration: WKWebViewConfiguration) -> WKWebView {
        let id = UUID()
        let page = make(id, configuration: configuration, isPopup: true)
        store().openPopup(id, from: opener)
        return page.webView
    }

    func forget(_ id: UUID) {
        guard let page = pages.removeValue(forKey: id) else { return }
        page.webView.stopLoading()
        page.webView.removeFromSuperview()
    }

    private func make(_ id: UUID, configuration: WKWebViewConfiguration, isPopup: Bool) -> PreviewPage {
        let page = PreviewPage(
            configuration: configuration, prompts: prompts, downloader: downloader, media: media, apps: apps,
            isPopup: isPopup)
        page.webView.identifier = NSUserInterfaceItemIdentifier(FocusedPreview.tag(for: id))
        page.onChange = { [store] title, url in store().pageChanged(id, title: title, url: url) }
        page.onOpenWindow = { [weak self] configuration in self?.openPopup(from: id, configuration: configuration) }
        page.onClose = { [store] in store().close(id) }
        pages[id] = page
        return page
    }
}

/// What the in-app browser tells sites it is: the Safari of this Mac, read
/// from Safari's own bundle, else the one that ships with this macOS.
enum PreviewUserAgent {
    static let current = SafariUserAgent.full(applicationName: SafariUserAgent.applicationName(
        safariVersion: installedSafariVersion(),
        osVersion: ProcessInfo.processInfo.operatingSystemVersion))

    private static func installedSafariVersion() -> String? {
        ["/Applications/Safari.app", "/System/Cryptexes/App/System/Applications/Safari.app"]
            .lazy
            .compactMap { Bundle(path: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
            .first
    }
}

/// The preview tab whose page has the keyboard, found the way
/// `FocusedTerminal` finds a pane: up from the first responder to the tagged
/// web view.
enum FocusedPreview {
    static let prefix = "preview:"

    static func tag(for id: UUID) -> String { prefix + id.uuidString }

    static func id(fromTag tag: String) -> UUID? {
        guard tag.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(tag.dropFirst(prefix.count)))
    }

    @MainActor
    static func tabID() -> UUID? {
        var view = NSApp.keyWindow?.firstResponder as? NSView
        while let current = view {
            if let tag = current.identifier?.rawValue, let id = id(fromTag: tag) { return id }
            view = current.superview
        }
        return nil
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
