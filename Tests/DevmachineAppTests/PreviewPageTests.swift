import XCTest
import AppKit
import WebKit
import DevmachineCore
@testable import DevmachineApp

@MainActor
private final class FakePrompts: PreviewPrompting {
    var asked: [PreviewDialogText.Message] = []
    var credentialsAsked: [PreviewDialogText.Message] = []
    var panelOptions: [OpenPanelOptions] = []
    var answer = true
    var credentials: Credentials?
    var chosen: [URL]?

    func alert(title: String, message: String, in window: NSWindow?, done: @escaping () -> Void) {
        asked.append(PreviewDialogText.Message(title: title, body: message))
        done()
    }

    func ask(_ message: PreviewDialogText.Message, confirm: String, in window: NSWindow?, done: @escaping (Bool) -> Void) {
        asked.append(message)
        done(answer)
    }

    func prompt(title: String, message: String, defaultText: String?, in window: NSWindow?,
                done: @escaping (String?) -> Void) {
        asked.append(PreviewDialogText.Message(title: title, body: message))
        done(defaultText)
    }

    func credentials(_ message: PreviewDialogText.Message, in window: NSWindow?, done: @escaping (Credentials?) -> Void) {
        credentialsAsked.append(message)
        done(credentials)
    }

    func openFiles(_ options: OpenPanelOptions, in window: NSWindow?, done: @escaping ([URL]?) -> Void) {
        panelOptions.append(options)
        done(chosen)
    }
}

@MainActor
private final class FakeApps: ExternalAppOpening {
    var name: String? = "Mail"
    var opened: [URL] = []
    func appName(for url: URL) -> String? { name }
    func open(_ url: URL) { opened.append(url) }
}

@MainActor
final class PreviewPageTests: XCTestCase {
    private let prompts = FakePrompts()
    private let apps = FakeApps()
    private var store = PreviewStore(tunnels: TunnelManager(launcher: FakeTunnelLauncher(), probe: FakePortProbe()),
                                     preference: { .inApp }, external: WorkspaceURLOpener(), report: { _ in })

    private func webViews() -> PreviewWebViews {
        let store = self.store
        return PreviewWebViews(store: { store }, prompts: prompts, downloader: PreviewDownloader(), apps: apps)
    }

    private func page() -> PreviewPage { webViews().page(for: UUID()) }

    func testThePageAnswersEveryQuestionABrowserWindowWould() {
        let page = page()
        XCTAssertTrue(page.webView.uiDelegate === page)
        XCTAssertTrue(page.webView.navigationDelegate === page)
        let selectors: [Selector] = [
            #selector(WKUIDelegate.webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)),
            #selector(WKUIDelegate.webView(_:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)),
            #selector(WKUIDelegate.webView(_:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:)),
            #selector(WKUIDelegate.webView(_:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:)),
            #selector(WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)),
            #selector(WKUIDelegate.webViewDidClose(_:)),
            #selector(WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)),
            #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:)),
            NSSelectorFromString("webView:decidePolicyForNavigationResponse:decisionHandler:"),
            #selector(WKNavigationDelegate.webView(_:navigationAction:didBecome:)),
            #selector(WKNavigationDelegate.webView(_:navigationResponse:didBecome:)),
        ]
        for selector in selectors {
            XCTAssertTrue(page.responds(to: selector), NSStringFromSelector(selector))
        }
    }

    func testTheWebViewIsADeveloperBrowser() {
        let page = page()
        XCTAssertTrue(page.webView.isInspectable)
        XCTAssertTrue(page.webView.configuration.preferences.isElementFullscreenEnabled)
        XCTAssertFalse(page.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertFalse(page.webView.configuration.websiteDataStore.isPersistent)
    }

    func testAFileInputGetsWhatThePanelChose() {
        let page = page()
        let file = URL(fileURLWithPath: "/Users/alice/Desktop/mockup.png")
        prompts.chosen = [file]
        var received: [URL]?

        page.chooseFiles(OpenPanelOptions(allowsMultipleSelection: true, allowsDirectories: false)) { received = $0 }

        XCTAssertEqual(received, [file])
        XCTAssertEqual(prompts.panelOptions, [OpenPanelOptions(allowsMultipleSelection: true, allowsDirectories: false)])
    }

    func testACancelledPanelSendsNothing() {
        let page = page()
        prompts.chosen = nil
        var received: [URL]? = [URL(fileURLWithPath: "/tmp/x")]

        page.chooseFiles(OpenPanelOptions(allowsMultipleSelection: false, allowsDirectories: true)) { received = $0 }

        XCTAssertNil(received)
    }

    func testABasicLoginAsksAndUsesTheAnswerForThisRunOnly() {
        let page = page()
        prompts.credentials = Credentials(user: "alice", password: "secret")
        var disposition: URLSession.AuthChallengeDisposition?
        var credential: URLCredential?

        page.answerLogin(method: NSURLAuthenticationMethodHTTPBasic, origin: "localhost:8000", realm: "staging",
                         failed: 0) { disposition = $0; credential = $1 }

        XCTAssertEqual(disposition, .useCredential)
        XCTAssertEqual(credential?.user, "alice")
        XCTAssertEqual(credential?.password, "secret")
        XCTAssertEqual(credential?.persistence, .forSession)
        XCTAssertEqual(prompts.credentialsAsked.first?.title, "Log in to localhost:8000")
    }

    func testACancelledLoginShowsTheSitesOwnRefusal() {
        let page = page()
        prompts.credentials = nil
        var disposition: URLSession.AuthChallengeDisposition?

        page.answerLogin(method: NSURLAuthenticationMethodHTTPDigest, origin: "localhost:8000", realm: nil,
                         failed: 1) { disposition = $0; _ = $1 }

        XCTAssertEqual(disposition, .performDefaultHandling)
    }

    func testServerTrustIsLeftToWebKit() {
        let page = page()
        var disposition: URLSession.AuthChallengeDisposition?

        page.answerLogin(method: NSURLAuthenticationMethodServerTrust, origin: "example.com", realm: nil,
                         failed: 0) { disposition = $0; _ = $1 }

        XCTAssertEqual(disposition, .performDefaultHandling)
        XCTAssertTrue(prompts.credentialsAsked.isEmpty)
    }

    func testAnotherAppsLinkOpensThereOnlyAfterAYes() {
        let page = page()
        let mail = URL(string: "mailto:alice@example.com")!
        prompts.answer = false

        XCTAssertEqual(page.apply(.openElsewhere(mail)), .cancel)
        XCTAssertTrue(apps.opened.isEmpty)
        XCTAssertEqual(prompts.asked.first?.title, "Open this link in Mail?")

        prompts.answer = true
        _ = page.apply(.openElsewhere(mail))
        XCTAssertEqual(apps.opened, [mail])
    }

    func testALinkNoAppOpensLeavesANotice() {
        let page = page()
        apps.name = nil

        XCTAssertEqual(page.apply(.openElsewhere(URL(string: "zoommtg://example.com/j")!)), .cancel)

        XCTAssertEqual(page.notice, "No app on this Mac opens zoommtg: links.")
        XCTAssertTrue(prompts.asked.isEmpty)
    }

    func testABlockedAddressLeavesANotice() {
        let page = page()

        XCTAssertEqual(page.apply(.block(URL(string: "file:///etc/hosts")!)), .cancel)

        XCTAssertEqual(page.notice, PreviewDialogText.blocked(URL(string: "file:///etc/hosts")!))
    }

    func testInPageNavigationsAndDownloadsPass() {
        let page = page()
        XCTAssertEqual(page.apply(.allow), .allow)
        XCTAssertEqual(page.apply(.download), .download)
    }

    func testAPopupBecomesATabBesideItsOpenerWithAWebViewFromWebKitsConfiguration() {
        let views = webViews()
        store.openTab(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        let openerID = store.tabs[0].id
        let page = views.page(for: openerID)
        let configuration = PreviewPage.configuration(dataStore: .nonPersistent())

        let child = page.openWindow(to: URL(string: "http://localhost:3000/oauth"), configuration: configuration)

        XCTAssertNotNil(child)
        XCTAssertTrue(child?.configuration.websiteDataStore === configuration.websiteDataStore)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs[1].state, .opened)
        XCTAssertEqual(store.selectedTabID, store.tabs[1].id)
        XCTAssertTrue(views.existingPage(for: store.tabs[1].id)?.webView === child)
        XCTAssertEqual(views.existingPage(for: store.tabs[1].id)?.isPopup, true)
    }

    func testAPopupThatClosesItselfClosesItsTab() {
        let views = webViews()
        store.openTab(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        let openerID = store.tabs[0].id
        let child = views.page(for: openerID).openWindow(
            to: nil, configuration: PreviewPage.configuration(dataStore: .nonPersistent()))
        let popupID = store.tabs[1].id
        let popup = views.existingPage(for: popupID)

        popup?.webViewDidClose(child!)

        XCTAssertEqual(store.tabs.map(\.id), [openerID])
    }

    func testAPopupToAnotherAppsLinkOpensNoTab() {
        let views = webViews()
        store.openTab(PreviewRequest(place: .thisMac, input: .port(3000, path: "")))
        let page = views.page(for: store.tabs[0].id)
        prompts.answer = false

        let child = page.openWindow(to: URL(string: "mailto:bob@example.com"),
                                    configuration: PreviewPage.configuration(dataStore: .nonPersistent()))

        XCTAssertNil(child)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(prompts.asked.count, 1)
    }

    func testTheCameraIsAskedOncePerSiteForTheRun() {
        let page = page()
        prompts.answer = false
        var answers: [Bool] = []

        page.askForMedia(origin: "localhost:3000", camera: true, microphone: false) { answers.append($0) }
        page.askForMedia(origin: "localhost:3000", camera: true, microphone: false) { answers.append($0) }
        page.askForMedia(origin: "localhost:4000", camera: true, microphone: false) { answers.append($0) }

        XCTAssertEqual(answers, [false, false, false])
        XCTAssertEqual(prompts.asked.map(\.title), [
            "Allow localhost:3000 to use your camera?", "Allow localhost:4000 to use your camera?",
        ])
    }

    func testZoomKeysStepThePageZoomAndActualSizeResetsIt() {
        let page = page()
        page.handle(.zoomIn)
        XCTAssertEqual(page.webView.pageZoom, 1.1, accuracy: 0.001)
        page.handle(.zoomOut)
        page.handle(.zoomOut)
        XCTAssertEqual(page.webView.pageZoom, 0.9, accuracy: 0.001)
        page.handle(.actualSize)
        XCTAssertEqual(page.webView.pageZoom, 1, accuracy: 0.001)
    }

    func testFindKeyOpensTheFindBar() {
        let page = page()
        page.handle(.find)
        XCTAssertTrue(page.isFinding)
        page.endFind()
        XCTAssertFalse(page.isFinding)
    }

    func testTheContextMenuOffersTabsInsteadOfWindows() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Link in New Window", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Copy Link", action: nil, keyEquivalent: "")

        PreviewWebKitView.retitle(menu)

        XCTAssertEqual(menu.items.map(\.title), ["Open Link in New Tab", "Copy Link"])
    }
}

@MainActor
final class PreviewDownloaderTests: XCTestCase {
    func testTwoDownloadsWithTheSameNameGetTwoFiles() {
        let folder = URL(fileURLWithPath: "/Users/alice/Downloads", isDirectory: true)
        let downloader = PreviewDownloader(folder: { folder }, fileExists: { $0.lastPathComponent == "report.pdf" },
                                           finished: { _ in }, failed: { _ in })

        let first = downloader.destination(for: "report.pdf")
        let second = downloader.destination(for: "report.pdf")
        downloader.release(first)
        let third = downloader.destination(for: "report.pdf")

        XCTAssertEqual(first.lastPathComponent, "report-2.pdf")
        XCTAssertEqual(second.lastPathComponent, "report-3.pdf")
        XCTAssertEqual(third.lastPathComponent, "report-2.pdf")
    }

    func testANameFromTheSiteStaysInTheFolder() {
        let folder = URL(fileURLWithPath: "/Users/alice/Downloads", isDirectory: true)
        let downloader = PreviewDownloader(folder: { folder }, fileExists: { _ in false },
                                           finished: { _ in }, failed: { _ in })

        XCTAssertEqual(downloader.destination(for: "../../.zshrc").path, "/Users/alice/Downloads/zshrc")
    }
}
