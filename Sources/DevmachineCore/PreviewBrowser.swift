import Foundation

/// How the terminal and the pane beside it share the width between them. The
/// pane's share is kept as a fraction, so a window resize moves both sides
/// together instead of pushing one of them off the window.
public enum DocumentSplit {
    public static let minimumSide: Double = 320
    public static let defaultFraction: Double = 0.5

    public static func trailingWidth(fraction: Double, available: Double) -> Double {
        guard available > 2 * minimumSide else { return max(available, 0) / 2 }
        return min(max(fraction * available, minimumSide), available - minimumSide)
    }

    public static func fraction(forTrailingWidth width: Double, available: Double) -> Double {
        guard available > 2 * minimumSide else { return defaultFraction }
        return min(max(width, minimumSide), available - minimumSide) / available
    }

    public static func stored(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0, value < 1 else { return defaultFraction }
        return value
    }
}

/// The name a preview tab shows: the page's own title, else the host it is on
/// now, never the host it was opened with.
public enum PreviewTitle {
    public static func display(pageTitle: String?, url: URL?, fallback: String) -> String {
        let title = (pageTitle ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if !title.isEmpty { return title }
        guard let host = url?.host, !host.isEmpty else { return fallback }
        return url?.port.map { "\(host):\($0)" } ?? host
    }
}

/// The user agent of the system's Safari. WebKit's default leaves out the
/// `Version/… Safari/…` tokens, and sites that sniff for them (Google among
/// them) serve their page for an old browser.
public enum SafariUserAgent {
    /// Safari freezes these tokens (macOS 10_15_7, WebKit 605.1.15) whatever
    /// the real versions are; only `Version/` moves with each release.
    static let frozenWebKit = "605.1.15"
    static let prefix = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"

    public static func applicationName(safariVersion: String?, osVersion: OperatingSystemVersion) -> String {
        "Version/\(version(safariVersion) ?? systemSafariVersion(osVersion)) Safari/\(frozenWebKit)"
    }

    public static func full(applicationName: String) -> String {
        "\(prefix) \(applicationName)"
    }

    private static func version(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty,
              raw.split(separator: ".").allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return raw
    }

    /// Safari was three majors ahead of macOS up to macOS 15 (Safari 18);
    /// from macOS 26 both carry the year's number.
    private static func systemSafariVersion(_ os: OperatingSystemVersion) -> String {
        let major = os.majorVersion >= 26 ? os.majorVersion : os.majorVersion + 3
        return "\(major).\(os.minorVersion)"
    }
}

extension DocumentSplit {
    /// A drag moves the divider by `translation` from where it started: to
    /// the left grows the pane, to the right shrinks it.
    public static func dragged(from fraction: Double, by translation: Double, available: Double) -> Double {
        self.fraction(forTrailingWidth: trailingWidth(fraction: fraction, available: available) - translation,
                      available: available)
    }
}
