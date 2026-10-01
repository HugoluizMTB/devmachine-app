#if DEBUG
import AppKit
import WebKit
import DevmachineCore

/// The browser walk (`DEVMACHINE_DEMO_WALK=preview-browser`): opens
/// `DEVMACHINE_PREVIEW_CHECK_URL` in a preview tab and drives every part a
/// bare web view lacks through the page's own scripts, answering the sheets
/// in code. Each line of `preview-browser.txt` is one check and its result.
/// No other app is ever opened and the open panel is never shown: the walk
/// answers it with `DEVMACHINE_PREVIEW_CHECK_FILE`.
@MainActor
enum DemoPreviewBrowserCheck {
    private final class WalkPrompts: SheetPreviewPrompts {
        let file: URL?
        init(file: URL?) { self.file = file }

        override func openFiles(_ options: OpenPanelOptions, in window: NSWindow?, done: @escaping ([URL]?) -> Void) {
            done(file.map { [$0] })
        }
    }

    private final class RecordingApps: ExternalAppOpening {
        var opened: [URL] = []
        func appName(for url: URL) -> String? { WorkspaceAppOpener().appName(for: url) ?? "Another App" }
        func open(_ url: URL) { opened.append(url) }
    }

    private struct SheetText {
        let title: String
        let body: String
    }

    static func run(window: NSWindow, directory: URL, session: SessionRef, model: AppModel) async {
        var lines: [String] = []
        func log(_ line: String) { lines.append(line) }
        defer {
            try? lines.joined(separator: "\n").appending("\n")
                .write(to: directory.appendingPathComponent("preview-browser.txt"), atomically: true, encoding: .utf8)
        }
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["DEVMACHINE_PREVIEW_CHECK_URL"].flatMap(URL.init(string:)) else {
            return log("FAIL no DEVMACHINE_PREVIEW_CHECK_URL")
        }
        if DemoSnapshots.isHidden { window.setFrameOrigin(NSPoint(x: -30000, y: -30000)) }
        let apps = RecordingApps()
        PreviewWebViews.shared.prompts = WalkPrompts(
            file: environment["DEVMACHINE_PREVIEW_CHECK_FILE"].map { URL(fileURLWithPath: $0) })
        PreviewWebViews.shared.apps = apps

        model.clickSession(session)
        model.contextTab = .preview
        let previews = PreviewStore.shared
        previews.openTab(PreviewRequest(place: .thisMac, input: .url(base)))
        guard let tabID = previews.selectedTabID else { return log("FAIL no tab") }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let page = PreviewWebViews.shared.existingPage(for: tabID) else { return log("FAIL no page") }
        await waitFor { page.url != nil && !page.isLoading }
        try? await Task.sleep(nanoseconds: 500_000_000)
        log("loaded \(page.url?.absoluteString ?? "nil") inWindow=\(page.webView.window != nil)")

        log("inspectable \(page.webView.isInspectable)")
        log("fullscreenEnabled \(await js(page, "return document.fullscreenEnabled || document.webkitFullscreenEnabled"))")
        log("srcdoc iframe \(await js(page, "return document.getElementById('srcdoc').contentDocument.body.textContent.trim()"))")
        log("blob iframe \(await js(page, "return document.getElementById('blobframe').contentDocument.body.textContent.trim()"))")
        log("data iframe \(await js(page, "return window.__msgs.includes('data-frame-ok')"))")

        let alert = await withSheet(window, answer: .alertFirstButtonReturn) {
            await js(page, "alert('hello from the page'); return 'after-alert'")
        }
        log("alert sheet=\(alert.sheet.map { "\($0.title) / \($0.body)" } ?? "none") js=\(alert.result)")
        let confirmYes = await withSheet(window, answer: .alertFirstButtonReturn) {
            await js(page, "return confirm('Delete it?')")
        }
        log("confirm OK sheet=\(confirmYes.sheet?.title ?? "none") js=\(confirmYes.result)")
        let confirmNo = await withSheet(window, answer: .alertSecondButtonReturn) {
            await js(page, "return confirm('Delete it?')")
        }
        log("confirm Cancel js=\(confirmNo.result)")
        let prompt = await withSheet(window, answer: .alertFirstButtonReturn, fill: ["typed in the walk"]) {
            await js(page, "return prompt('Your name?', 'x')")
        }
        log("prompt sheet=\(prompt.sheet?.body ?? "none") js=\(prompt.result)")

        log("file input \(await js(page, """
            const i = document.getElementById('file');
            return await new Promise(r => { i.onchange = () => r(i.files[0].name + ':' + i.files[0].size);
              i.click(); setTimeout(() => r('no change'), 4000) })
            """))")

        let folder = PreviewDownloader.downloadsFolder()
        for _ in 0..<2 {
            _ = await js(page, """
                const a = document.createElement('a');
                a.href = URL.createObjectURL(new Blob(['blob-bytes'], {type: 'text/plain'}));
                a.download = 'walk-blob.txt'; document.body.append(a); a.click(); return 'clicked'
                """)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        log("blob downloads \(files(in: folder))")
        let notice = FileTransferStore.shared.notice
        log("notice \(notice?.title ?? "none") reveal=\(notice?.reveal?.lastPathComponent ?? "none")")
        _ = await js(page, "const a = document.createElement('a'); a.href = '/attachment'; document.body.append(a); a.click(); return 1")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        log("attachment downloads \(files(in: folder)) page still \(page.url?.path ?? "nil") failure=\(page.failure ?? "none")")

        log("window.open \(await js(page, "return window.open('/popup.html', 'pop', 'width=420,height=300') ? 'opened' : 'null'"))")
        await waitFor { previews.tabs.count == 2 }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        log("tabs after window.open \(previews.tabs.map(\.title)) selected=\(previews.selectedTab?.title ?? "nil")")
        log("opener got \(await js(page, "return window.__msgs.join(',')"))")
        if let popupTab = previews.tabs.last, popupTab.id != tabID,
           let popup = PreviewWebViews.shared.existingPage(for: popupTab.id) {
            log("popup has opener \(await js(popup, "return !!window.opener"))")
            _ = await js(popup, "window.close(); return 1")
            await waitFor { previews.tabs.count == 1 }
            log("tabs after window.close \(previews.tabs.count)")
        }
        _ = await js(page, "document.getElementById('blank').click(); return 1")
        await waitFor { previews.tabs.count == 2 }
        log("tabs after target=_blank \(previews.tabs.count)")
        if let extra = previews.tabs.last, extra.id != tabID { previews.close(extra.id) }
        previews.select(tabID)

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            page.find("needle-word", forward: true) { found in
                log("find needle-word \(found)")
                done.resume()
            }
        }
        let width = await js(page, "return window.innerWidth")
        page.handle(.zoomIn)
        try? await Task.sleep(nanoseconds: 300_000_000)
        log("zoom in pageZoom=\(page.webView.pageZoom) innerWidth \(width) -> \(await js(page, "return window.innerWidth"))")
        page.handle(.actualSize)

        let external = await withSheet(window, answer: .alertFirstButtonReturn) {
            _ = await js(page, "location.href = 'mailto:alice@example.com'; return 1")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return ""
        }
        log("mailto sheet=\(external.sheet.map { "\($0.title) / \($0.body)" } ?? "none") handed to app=\(apps.opened)")
        _ = await js(page, "location.href = 'file:///etc/hosts'; return 1")
        try? await Task.sleep(nanoseconds: 800_000_000)
        log("file: notice=\(page.notice ?? "none") url=\(page.url?.absoluteString ?? "nil")")
        page.dismissNotice()

        _ = await js(page, "document.getElementById('datalink').click(); return 1")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        log("data: link url=\(page.url?.absoluteString ?? "nil") notice=\(page.notice ?? "none")")
        page.go(to: base)
        await waitFor { page.url == base && !page.isLoading }

        let login = await withSheet(window, answer: .alertFirstButtonReturn, fill: ["alice", "secret"]) {
            page.go(to: base.appendingPathComponent("auth"))
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return ""
        }
        await waitFor { !page.isLoading }
        log("login sheet=\(login.sheet.map { "\($0.title) / \($0.body)" } ?? "none") page=\(await js(page, "return document.getElementById('r').textContent"))")
        log("summary tabs=\(previews.tabs.count) failure=\(page.failure ?? "none")")
    }

    // MARK: Plumbing

    private static func js(_ page: PreviewPage, _ body: String) async -> String {
        await withCheckedContinuation { (done: CheckedContinuation<String, Never>) in
            page.webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case let .success(value): done.resume(returning: String(describing: value))
                case let .failure(error): done.resume(returning: "error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Runs `action` while watching the window for a sheet, reads its text,
    /// types `fill` into its fields in order and ends it with `answer`.
    private static func withSheet(
        _ window: NSWindow, answer: NSApplication.ModalResponse, fill: [String] = [],
        _ action: @escaping @MainActor () async -> String
    ) async -> (sheet: SheetText?, result: String) {
        let task = Task { @MainActor in await action() }
        var seen: SheetText?
        for _ in 0..<60 {
            if let sheet = window.attachedSheet {
                sheet.alphaValue = 0
                let texts = labels(in: sheet.contentView)
                seen = SheetText(title: texts.first ?? "", body: texts.dropFirst().first ?? "")
                for (field, value) in zip(fields(in: sheet.contentView), fill) { field.stringValue = value }
                window.endSheet(sheet, returnCode: answer)
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return (seen, await task.value)
    }

    private static func labels(in view: NSView?) -> [String] {
        guard let view else { return [] }
        var result: [String] = []
        if let field = view as? NSTextField, !field.isEditable, !field.stringValue.isEmpty {
            result.append(field.stringValue)
        }
        for sub in view.subviews { result += labels(in: sub) }
        return result
    }

    private static func fields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        var result: [NSTextField] = []
        if let field = view as? NSTextField, field.isEditable { result.append(field) }
        for sub in view.subviews { result += fields(in: sub) }
        return result
    }

    private static func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private static func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
#endif
