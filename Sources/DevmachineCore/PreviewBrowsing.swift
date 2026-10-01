import Foundation

/// What the in-app browser does with one navigation a page starts.
public enum PreviewNavigation: Equatable, Sendable {
    case allow
    case download
    /// A link for another app (mail, a phone call, a meeting): asked first.
    case openElsewhere(URL)
    case block(URL)
}

extension PreviewURLPolicy {
    /// Schemes a page uses inside itself: an iframe's `srcdoc`, a generated
    /// file, an inline image. Blocking them broke iframes, downloads and apps.
    static let inPageSchemes: Set<String> = ["http", "https", "about", "blob", "data"]

    /// A `file:` address reads this Mac's disk; a `javascript:` one in the
    /// address bar runs whatever it carries.
    static let neverSchemes: Set<String> = ["file", "javascript"]

    /// Only the main frame's own address is limited: a subframe is part of
    /// the page, and WebKit already keeps it in the page's origin.
    public static func navigation(to url: URL?, isMainFrame: Bool, shouldDownload: Bool) -> PreviewNavigation {
        guard let url, let scheme = url.scheme?.lowercased() else { return .allow }
        if scheme == "file" { return .block(url) }
        if shouldDownload { return .download }
        guard isMainFrame else { return .allow }
        if neverSchemes.contains(scheme) { return .block(url) }
        return inPageSchemes.contains(scheme) ? .allow : .openElsewhere(url)
    }

    /// `window.open` or `target="_blank"`: a new tab under the main frame's rules.
    public static func popup(to url: URL?) -> PreviewNavigation {
        navigation(to: url, isMainFrame: true, shouldDownload: false)
    }

    public static func isDownload(canShowMIMEType: Bool, contentDisposition: String?) -> Bool {
        guard canShowMIMEType else { return true }
        let disposition = contentDisposition?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return disposition.hasPrefix("attachment")
    }
}

/// Where a download lands: the name the site suggests, cut to a plain file
/// name, numbered when the folder already holds one.
public enum DownloadName {
    static let fallback = "download"

    public static func sanitized(_ suggested: String) -> String {
        let last = suggested.split(whereSeparator: { $0 == "/" || $0 == ":" || $0 == "\\" }).last.map(String.init) ?? ""
        var name = last.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    /// `-2`, `-3` before the extension, the counter the Files tab and the CLI use.
    public static func available(_ suggested: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let name = FileTransfer.freeName(sanitized(suggested)) { exists(folder.appendingPathComponent($0)) }
        return folder.appendingPathComponent(name)
    }
}

/// The words of every question the in-app browser asks for a page.
public enum PreviewDialogText {
    public struct Message: Equatable, Sendable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public static func origin(host: String?, port: Int) -> String {
        guard let host, !host.isEmpty else { return "This page" }
        return port > 0 ? "\(host):\(port)" : host
    }

    public static func says(_ origin: String) -> String { "\(origin) says" }

    public static func openElsewhere(_ url: URL, appName: String, origin: String) -> Message {
        Message(title: "Open this link in \(appName)?", body: "\(origin) wants to open \(url.absoluteString).")
    }

    public static func noApp(for url: URL) -> String {
        "No app on this Mac opens \(url.scheme?.lowercased() ?? "these"): links."
    }

    public static func blocked(_ url: URL) -> String {
        let reason = url.scheme?.lowercased() == "javascript"
            ? "a preview never runs a script address in the page"
            : "a preview never opens files on this Mac"
        return "Blocked a link to \(url.absoluteString): \(reason)."
    }

    public static func login(origin: String, realm: String?, failed: Int) -> Message {
        let ask: String
        if failed > 0 {
            ask = "That user name or password was refused. Try again."
        } else if let realm, !realm.isEmpty {
            ask = "The site asks for a user name and password (“\(realm)”)."
        } else {
            ask = "The site asks for a user name and password."
        }
        return Message(title: "Log in to \(origin)", body: "\(ask) Devmachine never stores them.")
    }

    public static func media(origin: String, camera: Bool, microphone: Bool) -> String {
        let what = camera && microphone ? "camera and microphone" : camera ? "camera" : "microphone"
        return "Allow \(origin) to use your \(what)?"
    }
}

/// The browser shortcuts a preview answers while its page has the keyboard.
/// Everything else, Esc included, goes to the page.
public enum PreviewKey: Equatable, Sendable {
    case find, findNext, findPrevious, zoomIn, zoomOut, actualSize

    public static func command(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> PreviewKey? {
        guard command, !option, !control else { return nil }
        switch characters.lowercased() {
        case "f": return shift ? nil : .find
        case "g": return shift ? .findPrevious : .findNext
        case "=", "+": return .zoomIn
        case "-": return shift ? nil : .zoomOut
        case "0": return shift ? nil : .actualSize
        default: return nil
        }
    }
}

public enum PreviewZoom {
    public static let levels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    public static func zoomedIn(from current: Double) -> Double {
        levels.first { $0 > current + 0.001 } ?? levels.last ?? current
    }

    public static func zoomedOut(from current: Double) -> Double {
        levels.last { $0 < current - 0.001 } ?? levels.first ?? current
    }
}

/// WebKit's menu offers new windows; a preview opens tabs instead.
public enum PreviewContextMenu {
    public static func title(for original: String) -> String {
        original.replacingOccurrences(of: "in New Window", with: "in New Tab")
    }
}
