import Foundation

/// A typed entry's `with` must match its inputs' shape: a list only for a
/// `many` choice. The board alone cannot tell, so resolution checks it.
public enum InputShapes {
    public struct Problem: Equatable, Sendable {
        public let input: String
        public let message: String
    }

    public static func problem(_ with: [String: BoardScalar], inputs: [String: CatalogInput], id: String) -> Problem? {
        for key in with.keys.sorted() {
            guard let input = inputs[key], let value = with[key] else { continue }
            let list = value.listValue
            let shown = "[" + (list ?? []).joined(separator: ", ") + "]"
            if input.isChoice, input.many, list == nil {
                return Problem(
                    input: key, message: "\(id): input \"\(key)\" takes a list of names, written [a, b], and \(value.text) is not one")
            }
            if input.isChoice, !input.many, list != nil {
                return Problem(input: key, message: "\(id): input \"\(key)\" takes one name, and \(shown) is not one")
            }
            if !input.isChoice, list != nil {
                return Problem(input: key, message: "\(id): input \"\(key)\" is a \(input.type), and \(shown) is not")
            }
        }
        return nil
    }
}

/// A board's `title` and `every` on a typed entry. `every` never goes below
/// what the widget's source allows, a stream has none, and an app provider
/// runs on a schedule, so it takes no `manual`.
/// A prompt in a mode with no checks takes only manual.
public enum EntryOverrideRules {
    public static func floorText(
        of resolved: ResolvedWidget, catalog: WidgetCatalog? = nil, contract: WidgetContract = .current
    ) -> String? {
        guard let source = resolved.source else { return contract.providers[resolved.provider]?.minEvery }
        if case let .packageProvider(provider) = source.source {
            let spec = catalog.flatMap { try? $0.packageProviderIndex.spec(for: provider.name) }
            return spec?.minEvery ?? contract.packageProvider.minEvery
        }
        return contract.sources[source.source.kind]?.minEvery
    }

    public static func floor(
        of resolved: ResolvedWidget, catalog: WidgetCatalog? = nil, contract: WidgetContract = .current
    ) -> TimeInterval {
        if let text = floorText(of: resolved, catalog: catalog, contract: contract), let seconds = GoDuration.seconds(text) {
            return seconds
        }
        return resolved.source == nil ? 0 : contract.packageProviderFloor
    }

    public static func everyProblem(
        id: String, type: String, every text: String, resolved: ResolvedWidget, catalog: WidgetCatalog? = nil,
        contract: WidgetContract = .current
    ) -> String? {
        if resolved.source?.every == .continuous {
            return "\(id): a stream runs while the widget is on screen, so it takes no every"
        }
        let readsProvider = resolved.widget.source.kind == "provider"
        if text == "manual" {
            guard readsProvider else { return nil }
            return "\(id): every manual: \(type) reads a provider, which runs on a schedule: write a duration like 60s"
        }
        guard let seconds = GoDuration.seconds(text) else {
            return readsProvider
                ? "\(id): every \"\(text)\" is not a duration: write it like 60s or 5m"
                : "\(id): every \"\(text)\" is neither a duration nor manual: write it like 60s, 5m or manual"
        }
        if case let .prompt(prompt)? = resolved.source?.source, let mode = prompt.permissionMode, PermissionModes.isDangerous(mode) {
            return "\(id): " + PermissionModes.timerProblem(mode)
        }
        let least = floor(of: resolved, catalog: catalog, contract: contract)
        guard seconds >= least else {
            let shown = floorText(of: resolved, catalog: catalog, contract: contract) ?? GoDurationText.short(least)
            return "\(id): every \(text) is below \(type)'s minimum of \(shown)"
        }
        return nil
    }

    public static func applied(_ resolved: ResolvedWidget, title: String?, every text: String?) -> ResolvedWidget {
        var every = resolved.every
        var source = resolved.source
        if text == "manual" {
            every = 0
            source = source?.withEvery(.manual)
        } else if let text, let seconds = GoDuration.seconds(text) {
            every = seconds
            source = source?.withEvery(.interval(seconds))
        }
        var result = ResolvedWidget(
            widget: resolved.widget, provider: resolved.provider, viewKind: resolved.viewKind,
            arguments: resolved.arguments, every: every, minimum: resolved.minimum, source: source,
            title: title ?? resolved.title)
        result.listArguments = resolved.listArguments
        return result
    }
}

/// A provider argument written as exactly `{{inputs.<name>}}` of a `many`
/// input reaches the app as the list itself, not the joined text.
public enum ListArguments {
    public static func of(_ widget: CatalogWidget, values: [String: BoardScalar]) -> [String: [String]] {
        var lists: [String: [String]] = [:]
        for (argument, template) in widget.source.with {
            guard let match = template.wholeMatch(of: /\s*\{\{\s*inputs\.([A-Za-z0-9_-]+)\s*\}\}\s*/) else { continue }
            let name = String(match.1)
            guard let input = widget.inputs[name], input.many else { continue }
            lists[argument] = values[name]?.listValue ?? input.defaultValue?.listValue ?? []
        }
        return lists
    }
}
