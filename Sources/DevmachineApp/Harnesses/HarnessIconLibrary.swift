import AppKit
import DevmachineCore

struct HarnessIcon {
    let image: NSImage
    /// Drawn in `currentColor`, so it takes the row's text colour instead of
    /// a brand colour of its own.
    let isTemplate: Bool
}

/// Harness icons are files named after the harness id (`claude.svg`), so a
/// new harness gets its icon by adding a file, not by adding a case.
@MainActor
final class HarnessIconLibrary {
    static let bundled = HarnessIconLibrary(directory: bundledDirectory())

    private let directory: URL?
    private var cache: [HarnessID: HarnessIcon?] = [:]

    init(directory: URL?) {
        self.directory = directory
    }

    func icon(for id: HarnessID) -> HarnessIcon? {
        if let cached = cache[id] { return cached }
        let icon = load(id)
        cache[id] = icon
        return icon
    }

    func hasIcon(for id: HarnessID) -> Bool {
        icon(for: id) != nil
    }

    private func load(_ id: HarnessID) -> HarnessIcon? {
        guard let directory, Self.isPlainName(id.rawValue) else { return nil }
        let url = directory.appendingPathComponent(id.rawValue).appendingPathExtension("svg")
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        let isTemplate = String(decoding: data, as: UTF8.self).contains("currentColor")
        image.isTemplate = isTemplate
        return HarnessIcon(image: image, isTemplate: isTemplate)
    }

    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func directory(inCheckout root: URL) -> URL {
        root.appendingPathComponent("Resources/HarnessIcons", isDirectory: true)
    }

    /// The app bundle's copy, or the checkout's for a plain `swift build` binary.
    private static func bundledDirectory() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("HarnessIcons", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return WallpaperAsset.checkoutRoot(from: Bundle.main.bundleURL).map(directory(inCheckout:))
    }
}

/// What a sidebar session row draws for its harnesses: with icons on, the
/// first harness that has an icon moves before the name and leaves the hover
/// dots; every row then keeps the same leading slot so names line up.
struct SessionRowGlyph {
    let icon: HarnessID?
    let reservesLeadingSlot: Bool
    let hoverBadges: [HarnessBadgePresentation]

    init(showsHarnessIcons: Bool, badges: [HarnessBadgePresentation], hasIcon: (HarnessID) -> Bool) {
        guard showsHarnessIcons else {
            icon = nil
            reservesLeadingSlot = false
            hoverBadges = badges
            return
        }
        let shown = badges.first { hasIcon($0.id) }?.id
        icon = shown
        reservesLeadingSlot = true
        hoverBadges = badges.filter { $0.id != shown }
    }
}
