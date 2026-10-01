import XCTest
@testable import DevmachineCore

final class PreviewNavigationTests: XCTestCase {
    private func main(_ raw: String, download: Bool = false) -> PreviewNavigation {
        PreviewURLPolicy.navigation(to: URL(string: raw), isMainFrame: true, shouldDownload: download)
    }

    private func subframe(_ raw: String) -> PreviewNavigation {
        PreviewURLPolicy.navigation(to: URL(string: raw), isMainFrame: false, shouldDownload: false)
    }

    func testTheMainFrameLoadsWebAndInPageSchemes() {
        for raw in ["https://example.com", "http://localhost:3000", "about:blank", "about:srcdoc",
                    "data:text/plain,hello", "blob:http://localhost:3000/0f1e2d3c"] {
            XCTAssertEqual(main(raw), .allow, raw)
        }
    }

    func testANavigationWithoutAnAddressIsAllowed() {
        XCTAssertEqual(PreviewURLPolicy.navigation(to: nil, isMainFrame: true, shouldDownload: false), .allow)
    }

    func testADownloadLinkBecomesADownload() {
        XCTAssertEqual(main("blob:http://localhost:3000/0f1e2d3c", download: true), .download)
        XCTAssertEqual(main("https://example.com/report.pdf", download: true), .download)
    }

    func testSubframesLoadAnythingButTheDisk() {
        for raw in ["about:srcdoc", "about:blank", "data:text/html,x", "blob:https://example.com/1",
                    "https://example.net/embed", "javascript:void(0)"] {
            XCTAssertEqual(subframe(raw), .allow, raw)
        }
        XCTAssertEqual(subframe("file:///etc/hosts"), .block(URL(string: "file:///etc/hosts")!))
    }

    func testAnotherAppsSchemeInTheMainFrameIsOfferedToThatApp() {
        for raw in ["mailto:alice@example.com", "tel:+15555550100", "zoommtg://example.com/join", "vscode://file/x"] {
            XCTAssertEqual(main(raw), .openElsewhere(URL(string: raw)!), raw)
        }
    }

    func testScriptAndDiskAddressesAreNeverFollowedInTheMainFrame() {
        for raw in ["javascript:alert(1)", "file:///etc/hosts", "FILE:///tmp/x"] {
            XCTAssertEqual(main(raw), .block(URL(string: raw)!), raw)
        }
    }

    func testAPopupFollowsTheMainFrameRules() {
        XCTAssertEqual(PreviewURLPolicy.popup(to: nil), .allow)
        XCTAssertEqual(PreviewURLPolicy.popup(to: URL(string: "about:blank")), .allow)
        XCTAssertEqual(PreviewURLPolicy.popup(to: URL(string: "https://example.com/oauth")), .allow)
        XCTAssertEqual(PreviewURLPolicy.popup(to: URL(string: "mailto:bob@example.com")),
                       .openElsewhere(URL(string: "mailto:bob@example.com")!))
        XCTAssertEqual(PreviewURLPolicy.popup(to: URL(string: "file:///etc/hosts")),
                       .block(URL(string: "file:///etc/hosts")!))
    }

    func testAResponseTheEngineCannotShowIsDownloaded() {
        XCTAssertTrue(PreviewURLPolicy.isDownload(canShowMIMEType: false, contentDisposition: nil))
        XCTAssertFalse(PreviewURLPolicy.isDownload(canShowMIMEType: true, contentDisposition: nil))
        XCTAssertFalse(PreviewURLPolicy.isDownload(canShowMIMEType: true, contentDisposition: "inline"))
    }

    func testAnAttachmentIsDownloadedEvenWhenItCouldBeShown() {
        XCTAssertTrue(PreviewURLPolicy.isDownload(
            canShowMIMEType: true, contentDisposition: "attachment; filename=\"report.csv\""))
        XCTAssertTrue(PreviewURLPolicy.isDownload(canShowMIMEType: true, contentDisposition: " Attachment"))
    }
}

final class DownloadNameTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Users/alice/Downloads", isDirectory: true)

    func testAFreeNameIsKept() {
        let url = DownloadName.available("report.pdf", in: folder) { _ in false }
        XCTAssertEqual(url.path, "/Users/alice/Downloads/report.pdf")
    }

    func testATakenNameGetsTheNextNumberBeforeTheExtension() {
        let taken: Set<String> = ["report.pdf", "report-2.pdf"]
        let url = DownloadName.available("report.pdf", in: folder) { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(url.lastPathComponent, "report-3.pdf")
    }

    func testANameWithoutExtensionIsNumberedAtTheEnd() {
        let url = DownloadName.available("notes", in: folder) { $0.lastPathComponent == "notes" }
        XCTAssertEqual(url.lastPathComponent, "notes-2")
    }

    func testATarballKeepsBothExtensions() {
        let url = DownloadName.available("site.tar.gz", in: folder) { $0.lastPathComponent == "site.tar.gz" }
        XCTAssertEqual(url.lastPathComponent, "site-2.tar.gz")
    }

    func testANameFromTheSiteCannotLeaveTheFolder() {
        XCTAssertEqual(DownloadName.sanitized("../../.ssh/config"), "config")
        XCTAssertEqual(DownloadName.sanitized("a/b:c.txt"), "c.txt")
        XCTAssertEqual(DownloadName.sanitized(".hidden"), "hidden")
        XCTAssertEqual(DownloadName.sanitized("   "), "download")
        XCTAssertEqual(DownloadName.sanitized(".."), "download")
    }

    func testTheSavedPathIsShownFromTheHomeFolder() {
        XCTAssertEqual(DownloadName.display(URL(fileURLWithPath: "/Users/alice/Downloads/report.pdf"),
                                            home: "/Users/alice"), "~/Downloads/report.pdf")
        XCTAssertEqual(DownloadName.display(URL(fileURLWithPath: "/tmp/x.pdf"), home: "/Users/alice"), "/tmp/x.pdf")
        XCTAssertEqual(DownloadName.display(URL(fileURLWithPath: "/Users/alicex/y"), home: "/Users/alice"),
                       "/Users/alicex/y")
    }
}

final class PreviewDialogTextTests: XCTestCase {
    func testTheOriginNamesTheHostAndAPortThatIsNotTheDefault() {
        XCTAssertEqual(PreviewDialogText.origin(host: "localhost", port: 3000), "localhost:3000")
        XCTAssertEqual(PreviewDialogText.origin(host: "example.com", port: 0), "example.com")
        XCTAssertEqual(PreviewDialogText.origin(host: "", port: 0), "This page")
        XCTAssertEqual(PreviewDialogText.origin(host: nil, port: 0), "This page")
    }

    func testADialogSaysWhoIsAsking() {
        XCTAssertEqual(PreviewDialogText.says("localhost:3000"), "localhost:3000 says")
        XCTAssertEqual(PreviewDialogText.says("This page"), "This page says")
    }

    func testAnotherAppIsNamedWhenThereIsOne() {
        let url = URL(string: "mailto:alice@example.com")!
        XCTAssertEqual(PreviewDialogText.openElsewhere(url, appName: "Mail", origin: "localhost:3000"),
                       PreviewDialogText.Message(
                        title: "Open this link in Mail?",
                        body: "localhost:3000 wants to open mailto:alice@example.com."))
    }

    func testALinkNoAppOpensSaysSo() {
        XCTAssertEqual(PreviewDialogText.noApp(for: URL(string: "zoommtg://example.com/j")!),
                       "No app on this Mac opens zoommtg: links.")
    }

    func testABlockedAddressSaysWhy() {
        XCTAssertEqual(PreviewDialogText.blocked(URL(string: "file:///etc/hosts")!),
                       "Blocked a link to file:///etc/hosts: a preview never opens files on this Mac.")
        XCTAssertEqual(PreviewDialogText.blocked(URL(string: "javascript:alert(1)")!),
                       "Blocked a link to javascript:alert(1): a preview never runs a script address in the page.")
    }

    func testTheLoginSheetNamesTheSiteAndTheRealm() {
        XCTAssertEqual(PreviewDialogText.login(origin: "localhost:8000", realm: "staging", failed: 0),
                       PreviewDialogText.Message(
                        title: "Log in to localhost:8000",
                        body: "The site asks for a user name and password (“staging”). Devmachine never stores them."))
        XCTAssertEqual(PreviewDialogText.login(origin: "localhost:8000", realm: nil, failed: 2).body,
                       "That user name or password was refused. Try again. Devmachine never stores them.")
    }

    func testTheCameraQuestionNamesWhatIsAsked() {
        XCTAssertEqual(PreviewDialogText.media(origin: "localhost:3000", camera: true, microphone: false),
                       "Allow localhost:3000 to use your camera?")
        XCTAssertEqual(PreviewDialogText.media(origin: "localhost:3000", camera: false, microphone: true),
                       "Allow localhost:3000 to use your microphone?")
        XCTAssertEqual(PreviewDialogText.media(origin: "localhost:3000", camera: true, microphone: true),
                       "Allow localhost:3000 to use your camera and microphone?")
    }
}

final class PreviewKeyTests: XCTestCase {
    func testBrowserShortcutsAreRecognised() {
        XCTAssertEqual(PreviewKey.command(characters: "f", command: true, shift: false, option: false, control: false), .find)
        XCTAssertEqual(PreviewKey.command(characters: "g", command: true, shift: false, option: false, control: false), .findNext)
        XCTAssertEqual(PreviewKey.command(characters: "G", command: true, shift: true, option: false, control: false), .findPrevious)
        XCTAssertEqual(PreviewKey.command(characters: "g", command: true, shift: true, option: false, control: false), .findPrevious)
        XCTAssertEqual(PreviewKey.command(characters: "=", command: true, shift: false, option: false, control: false), .zoomIn)
        XCTAssertEqual(PreviewKey.command(characters: "+", command: true, shift: true, option: false, control: false), .zoomIn)
        XCTAssertEqual(PreviewKey.command(characters: "-", command: true, shift: false, option: false, control: false), .zoomOut)
        XCTAssertEqual(PreviewKey.command(characters: "0", command: true, shift: false, option: false, control: false), .actualSize)
    }

    func testOtherKeysReachThePage() {
        XCTAssertNil(PreviewKey.command(characters: "f", command: false, shift: false, option: false, control: false))
        XCTAssertNil(PreviewKey.command(characters: "\u{1b}", command: false, shift: false, option: false, control: false))
        XCTAssertNil(PreviewKey.command(characters: "f", command: true, shift: false, option: true, control: false))
        XCTAssertNil(PreviewKey.command(characters: "f", command: true, shift: false, option: false, control: true))
        XCTAssertNil(PreviewKey.command(characters: "c", command: true, shift: false, option: false, control: false))
    }
}

final class PreviewZoomTests: XCTestCase {
    func testZoomStepsThroughFixedLevels() {
        XCTAssertEqual(PreviewZoom.zoomedIn(from: 1), 1.1)
        XCTAssertEqual(PreviewZoom.zoomedOut(from: 1), 0.9)
        XCTAssertEqual(PreviewZoom.zoomedIn(from: 1.05), 1.1)
        XCTAssertEqual(PreviewZoom.zoomedOut(from: 1.05), 1)
    }

    func testZoomStopsAtTheEnds() {
        XCTAssertEqual(PreviewZoom.zoomedIn(from: 3), 3)
        XCTAssertEqual(PreviewZoom.zoomedOut(from: 0.5), 0.5)
    }
}

final class PreviewContextMenuTests: XCTestCase {
    func testANewWindowEntryOpensATab() {
        XCTAssertEqual(PreviewContextMenu.title(for: "Open Link in New Window"), "Open Link in New Tab")
        XCTAssertEqual(PreviewContextMenu.title(for: "Open Image in New Window"), "Open Image in New Tab")
        XCTAssertEqual(PreviewContextMenu.title(for: "Copy Link"), "Copy Link")
    }
}
