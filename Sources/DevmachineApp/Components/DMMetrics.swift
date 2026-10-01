import SwiftUI

/// Every layout size of the app's own interface, in the same unit as its
/// text: one rem is the 13-point body size times the text size setting, so a
/// padding, a button or a card grows with the text it holds, like CSS `rem`.
///
/// Tokens are written as the points they take at 100% and come back scaled.
/// A component parameter is in those 100% points too, like a `.dm(_:)` font
/// size, and the component scales it; never pass it an already scaled value.
struct DMMetrics: Equatable, Sendable {
    static let baseFontSize: CGFloat = 13

    let scale: CGFloat

    init(scale: Double) {
        self.scale = CGFloat(scale)
    }

    /// The metrics for the text size the interface is drawn at right now.
    static var current: DMMetrics { DMMetrics(scale: DMFont.scale) }

    /// `value` rems, in points.
    func rem(_ value: CGFloat) -> CGFloat {
        snap(value * Self.baseFontSize * scale)
    }

    /// A size given in points at 100%, at the current scale.
    func pt(_ base: CGFloat) -> CGFloat {
        snap(base * scale)
    }

    /// The 100% points of a scaled value, to store a size the user dragged.
    func base(_ scaled: CGFloat) -> CGFloat {
        scale > 0 ? scaled / scale : scaled
    }

    func size(_ base: CGSize) -> CGSize {
        CGSize(width: pt(base.width), height: pt(base.height))
    }

    func insets(_ base: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: pt(base.top), leading: pt(base.leading), bottom: pt(base.bottom),
            trailing: pt(base.trailing))
    }

    /// Half points, like the font sizes, so an edge never lands between pixels
    /// on a non-Retina display and 100% gives back the exact point values.
    private func snap(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }

    var space: Spacing { Spacing(m: self) }
    var control: ControlHeights { ControlHeights(m: self) }
    var radius: Radii { Radii(m: self) }
    var icon: IconSizes { IconSizes(m: self) }
    var hit: HitSizes { HitSizes(m: self) }
    var row: RowInsets { RowInsets(m: self) }
    var section: SectionInsets { SectionInsets(m: self) }
    var card: CardWidths { CardWidths(m: self) }
    var pane: PaneWidths { PaneWidths(m: self) }

    struct Spacing {
        let m: DMMetrics
        var xxs: CGFloat { m.pt(DMSpace.xxs) }
        var xs: CGFloat { m.pt(DMSpace.xs) }
        var sm: CGFloat { m.pt(DMSpace.sm) }
        var md: CGFloat { m.pt(DMSpace.md) }
        var lg: CGFloat { m.pt(DMSpace.lg) }
        var xl: CGFloat { m.pt(DMSpace.xl) }
        var xxl: CGFloat { m.pt(DMSpace.xxl) }
    }

    struct ControlHeights {
        let m: DMMetrics
        var small: CGFloat { m.pt(DMControlHeight.small) }
        var regular: CGFloat { m.pt(DMControlHeight.regular) }
        var large: CGFloat { m.pt(DMControlHeight.large) }
    }

    struct Radii {
        let m: DMMetrics
        var terminal: CGFloat { m.pt(DMRadius.terminal) }
        var keyCap: CGFloat { m.pt(DMRadius.keyCap) }
        var row: CGFloat { m.pt(DMRadius.row) }
        var control: CGFloat { m.pt(DMRadius.control) }
        var tile: CGFloat { m.pt(DMRadius.tile) }
        var pill: CGFloat { m.pt(DMRadius.pill) }
        var toast: CGFloat { m.pt(DMRadius.toast) }
        var panel: CGFloat { m.pt(DMRadius.panel) }
        var card: CGFloat { m.pt(DMRadius.card) }
        var bubble: CGFloat { m.pt(DMRadius.bubble) }
    }

    struct IconSizes {
        let m: DMMetrics
        var dot: CGFloat { m.pt(DMIconSize.dot) }
        var xs: CGFloat { m.pt(DMIconSize.xs) }
        var sm: CGFloat { m.pt(DMIconSize.sm) }
        var md: CGFloat { m.pt(DMIconSize.md) }
        var lg: CGFloat { m.pt(DMIconSize.lg) }
    }

    struct HitSizes {
        let m: DMMetrics
        var compact: CGSize { m.size(DMHitSize.compact) }
        var regular: CGSize { m.size(DMHitSize.regular) }
        var header: CGSize { m.size(DMHitSize.header) }
        var strip: CGSize { m.size(DMHitSize.strip) }
        var footer: CGSize { m.size(DMHitSize.footer) }
    }

    struct RowInsets {
        let m: DMMetrics
        var horizontal: CGFloat { m.pt(DMRowInset.horizontal) }
        var vertical: CGFloat { m.pt(DMRowInset.vertical) }
        var outer: CGFloat { m.pt(DMRowInset.outer) }
    }

    struct SectionInsets {
        let m: DMMetrics
        var panel: EdgeInsets { m.insets(DMSectionInset.panel) }
        var sidebarGroup: EdgeInsets { m.insets(DMSectionInset.sidebarGroup) }
        var sidebarFooter: EdgeInsets { m.insets(DMSectionInset.sidebarFooter) }
    }

    struct CardWidths {
        let m: DMMetrics
        var toast: CGFloat { m.pt(DMCardWidth.toast) }
        var banner: CGFloat { m.pt(DMCardWidth.banner) }
        var sheetSmall: CGFloat { m.pt(DMCardWidth.sheetSmall) }
        var sheet: CGFloat { m.pt(DMCardWidth.sheet) }
        var sheetLarge: CGFloat { m.pt(DMCardWidth.sheetLarge) }
        var sheetWide: CGFloat { m.pt(DMCardWidth.sheetWide) }
        var palette: CGFloat { m.pt(DMCardWidth.palette) }
        var errorState: CGFloat { m.pt(DMCardWidth.errorState) }
    }

    struct PaneWidths {
        let m: DMMetrics
        var sidebar: DMPaneWidth { DMPaneWidth.sidebar.scaled(by: m) }
        var context: DMPaneWidth { DMPaneWidth.context.scaled(by: m) }
    }
}

/// A side pane's width: the narrowest a drag can make it, where it starts,
/// and the widest. Stored at 100%; drawn at `scaled(by:)`.
struct DMPaneWidth: Equatable, Sendable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat

    static let sidebar = DMPaneWidth(min: 200, ideal: 260, max: 460)
    static let context = DMPaneWidth(min: 240, ideal: 300, max: 520)

    func scaled(by m: DMMetrics) -> DMPaneWidth {
        DMPaneWidth(min: m.pt(min), ideal: m.pt(ideal), max: m.pt(max))
    }

    func clamp(_ width: CGFloat) -> CGFloat {
        Swift.min(Swift.max(width, min), max)
    }

    func contains(_ width: CGFloat) -> Bool {
        width >= min && width <= max
    }
}

private struct DMMetricsKey: EnvironmentKey {
    static var defaultValue: DMMetrics { .current }
}

extension EnvironmentValues {
    /// Set once at the root of every window from the text size setting.
    var dmMetrics: DMMetrics {
        get { self[DMMetricsKey.self] }
        set { self[DMMetricsKey.self] = newValue }
    }
}
