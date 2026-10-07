import Foundation

/// The edit form of an inline widget the templates cannot show: its title,
/// and how often it runs unless it is a stream. The rest stays as written.
public struct InlineBasicsForm: Equatable, Sendable {
    public let old: InlineWidget
    public var title: String
    public var every: String?

    public init(inline: InlineWidget) {
        old = inline
        title = inline.title
        every = Self.writtenEvery(of: inline)
    }

    /// As the file spells it ("60s", not "1m"), so an untouched field reads as unchanged.
    private static func writtenEvery(of inline: InlineWidget) -> String? {
        guard let computed = InlineWidgetForm.text(of: inline.source.every) else { return nil }
        return inline.sourceTree.value.object?["every"]?.text ?? computed
    }

    public func everyLabel(contract: WidgetContract = .current) -> String {
        switch old.source {
        case let .provider(provider):
            return EntryOverrideRules.everyLabel(floor: contract.providers[provider.name]?.minEvery, allowsManual: false)
        case .packageProvider:
            return EntryOverrideRules.everyLabel(floor: contract.packageProvider.minEvery, allowsManual: false)
        default:
            return EntryOverrideRules.everyLabel(floor: contract.sources[old.source.kind]?.minEvery, allowsManual: true)
        }
    }

    public var fields: Set<String> { every == nil ? ["title"] : ["title", "every"] }

    /// The changed entry goes through `BoardCodec` and the resolver, as a
    /// template's form does, so `every` meets the same rules and minimum.
    public func read(
        surface: String, id: String, catalog: WidgetCatalog? = nil, contract: WidgetContract = .current
    ) -> Result<InlineWidget, FormProblem> {
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleText.isEmpty else { return .failure(FormProblem(field: "title", message: "Give the widget a title.")) }
        var candidate = old
        candidate.title = titleText
        let everyText = every?.trimmingCharacters(in: .whitespacesAndNewlines)
        let everyChanged = everyText != nil && everyText != Self.writtenEvery(of: old)
        if everyChanged, let everyText { candidate.sourceTree = old.sourceTree.setting("every", to: everyText) }

        let canvas = contract.layout(of: surface) == "canvas"
        let text = canvas
            ? BoardCodec.encode(Board(surface: surface, widgets: [BoardWidget(
                id: id, type: "", frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 1, inline: candidate)]))
            : BoardCodec.encodeStack(StackBoard(surface: surface, entries: [StackEntry(id: id, type: "", inline: candidate)]))
        let read: InlineWidget?
        do {
            read = canvas
                ? try BoardCodec.decode(text, contract: contract).widgets.first?.inline
                : try BoardCodec.decodeStack(text, contract: contract).entries.first?.inline
        } catch let problem as BoardProblem {
            let field = problem.line.flatMap { Self.field(atLine: $0, in: text, everyChanged: everyChanged) }
            return .failure(FormProblem(field: field, message: InlineWidgetForm.plain(problem.message, id: id)))
        } catch {
            return .failure(FormProblem(field: nil, message: "\(error)"))
        }
        guard let read else { return .failure(FormProblem(field: nil, message: "The widget could not be read.")) }
        if everyChanged {
            let refusal = { (inline: InlineWidget) in
                InlineWidgetForm.refusal(of: inline, surface: surface, id: id, catalog: catalog, contract: contract)
            }
            if let reason = refusal(read), reason != refusal(old) {
                return .failure(FormProblem(field: "every", message: InlineWidgetForm.plain(reason, id: id)))
            }
        }
        return .success(InlineWidget(
            title: read.title, sourceTree: candidate.sourceTree, viewTree: old.viewTree,
            sizes: old.sizes, fits: old.fits, source: read.source, view: read.view))
    }

    private static func field(atLine number: Int, in text: String, everyChanged: Bool) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard number >= 1, number <= lines.count else { return nil }
        let line = lines[number - 1]
        if line.hasPrefix("    title:") { return "title" }
        guard everyChanged, let start = lines.firstIndex(where: { $0.hasPrefix("    source:") }) else { return nil }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    ") && !$0.hasPrefix("     ") } ?? lines.count
        return (start..<end).contains(number - 1) ? "every" : nil
    }
}
