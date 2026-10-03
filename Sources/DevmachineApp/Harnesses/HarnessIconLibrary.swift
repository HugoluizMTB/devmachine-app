import AppKit
import DevmachineCore

struct HarnessIcon {
    let image: NSImage
    /// Drawn in `currentColor`, so it takes the row's text colour instead of
    /// a brand colour of its own.
    let isTemplate: Bool
}

/// Harness icons are files named after the harness id, so a new harness gets
/// its icon by adding a file, not by adding a case. `<id>.svg` is always the
/// monochrome drawing in `currentColor`; `<id>-color.svg`, when there is one,
/// is the brand-color version the `.color` style prefers.
@MainActor
final class HarnessIconLibrary {
    static let bundled = HarnessIconLibrary(directory: bundledDirectory())
    static let colorSuffix = "-color"

    private struct Key: Hashable {
        let id: HarnessID
        let style: HarnessIconStyle
    }

    private let directory: URL?
    private var cache: [Key: HarnessIcon?] = [:]

    init(directory: URL?) {
        self.directory = directory
    }

    func icon(for id: HarnessID, style: HarnessIconStyle) -> HarnessIcon? {
        let key = Key(id: id, style: style)
        if let cached = cache[key] { return cached }
        let icon = load(id, style: style)
        cache[key] = icon
        return icon
    }

    /// Every style falls back to the monochrome file, so it alone decides.
    func hasIcon(for id: HarnessID) -> Bool {
        icon(for: id, style: .monochrome) != nil
    }

    private func load(_ id: HarnessID, style: HarnessIconStyle) -> HarnessIcon? {
        guard directory != nil, Self.isHarnessName(id.rawValue),
              let mono = read(id.rawValue) else { return nil }
        if style == .color, let color = read(id.rawValue + Self.colorSuffix) { return color }
        return mono
    }

    private func read(_ name: String) -> HarnessIcon? {
        guard let url = directory?.appendingPathComponent(name).appendingPathExtension("svg"),
              let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        let isTemplate = String(decoding: data, as: UTF8.self).contains("currentColor")
        image.isTemplate = isTemplate
        return HarnessIcon(image: image, isTemplate: isTemplate)
    }

    /// A plain file name, and never a color variant's own name.
    private static func isHarnessName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasSuffix(colorSuffix)
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
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
