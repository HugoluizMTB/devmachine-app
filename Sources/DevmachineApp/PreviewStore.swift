import Foundation
import AppKit
import DevmachineCore

/// Which machine a preview's port lives on.
enum PreviewPlace: Equatable, Sendable {
    case thisMac
    case workspace(String)
}

struct PreviewRequest: Equatable, Sendable {
    let place: PreviewPlace
    let input: PreviewInput

    var title: String {
        switch (input, place) {
        case let (.url(url), _): return url.host ?? url.absoluteString
        case let (.port(port, _), .thisMac): return "localhost:\(port)"
        case let (.port(port, _), .workspace(name)): return "\(name):\(port)"
        }
    }
}

/// How a request becomes an address this Mac can load: a remote port needs a
/// tunnel first, everything else is already reachable.
enum PreviewResolution: Equatable {
    case direct(URL)
    case tunnel(TunnelKey, path: String)

    static func resolve(_ request: PreviewRequest) -> PreviewResolution {
        switch (request.input, request.place) {
        case let (.url(url), _):
            return .direct(url)
        case let (.port(port, path), .thisMac):
            return .direct(localhost(port, path: path))
        case let (.port(port, path), .workspace(name)):
            return .tunnel(TunnelKey(workspace: name, remotePort: port), path: path)
        }
    }

    static func localhost(_ port: Int, path: String) -> URL {
        URL(string: "http://localhost:\(port)\(path)") ?? URL(string: "http://localhost:\(port)")!
    }
}

struct PreviewTab: Identifiable, Equatable {
    enum State: Equatable {
        case connecting(String)
        case ready(URL)
        case failed(String)
        /// A page drawn from a string, for the demo build: nothing is fetched.
        case page(html: String, baseURL: URL)
    }

    let id: UUID
    var title: String
    let request: PreviewRequest?
    var state: State
    /// The session the tab was opened in; nil when no session was selected.
    var owner: SessionRef? = nil
}

@MainActor
protocol ExternalURLOpening {
    func open(_ url: URL)
}

@MainActor
struct WorkspaceURLOpener: ExternalURLOpening {
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// The open preview tabs, and the one place that decides where a preview or
/// a link goes: a tab here, or the default browser. A tab belongs to the
/// session it was opened in: each session shows its own tabs and its own
/// selected one, and ending the session closes them.
@MainActor
final class PreviewStore: ObservableObject {
    static let shared = PreviewStore()

    /// Holds the tunnels behind pages sent to the browser: nothing here knows
    /// when that page closes, so they stay until stopped or the app quits.
    static let browserHolder = "browser"

    @Published private(set) var allTabs: [PreviewTab] = []
    @Published private(set) var owner: SessionRef?
    @Published private var selections: [SessionRef?: UUID] = [:]

    var tabs: [PreviewTab] { allTabs.filter { $0.owner == owner } }
    var selectedTabID: UUID? { selections[owner] }
    @Published private(set) var isOpeningInBrowser = false

    let tunnels: TunnelManager
    private let preference: () -> LinkOpening
    private let external: any ExternalURLOpening
    private let report: (String) -> Void

    init(
        tunnels: TunnelManager = .shared,
        preference: @escaping () -> LinkOpening = {
            SettingsStore.shared.settings?.linkOpening ?? .defaultBrowser
        },
        external: any ExternalURLOpening = WorkspaceURLOpener(),
        report: @escaping (String) -> Void = { AppModel.shared?.flashToast($0) }
    ) {
        self.tunnels = tunnels
        self.preference = preference
        self.external = external
        self.report = report
    }

    var selectedTab: PreviewTab? { tabs.first { $0.id == selectedTabID } }

    func open(_ request: PreviewRequest, inverted: Bool = false) {
        if DemoMode.isActive {
            showPage(title: request.title, html: DemoData.previewPage, baseURL: DemoData.previewBaseURL)
            return
        }
        let destination: LinkOpening
        if case let .url(url) = request.input {
            destination = LinkRouting.destination(for: url, preference: preference(), inverted: inverted)
        } else {
            destination = LinkRouting.destination(preference: preference(), inverted: inverted)
        }
        switch destination {
        case .inApp: openTab(request)
        case .defaultBrowser: openInBrowser(request)
        }
    }

    /// A link from the context panel: a pull request, an issue, a doc.
    func openLink(_ url: URL, inverted: Bool = false) {
        open(PreviewRequest(place: .thisMac, input: .url(url)), inverted: inverted)
    }

    func showPage(title: String, html: String, baseURL: URL) {
        add(PreviewTab(id: UUID(), title: title, request: nil, state: .page(html: html, baseURL: baseURL)))
    }

    func setOwner(_ owner: SessionRef?) {
        guard owner != self.owner else { return }
        self.owner = owner
    }

    func select(_ id: UUID?) {
        selections[owner] = id
    }

    func close(_ id: UUID) {
        guard let tab = allTabs.first(where: { $0.id == id }) else { return }
        let siblings = allTabs.filter { $0.owner == tab.owner }
        let index = siblings.firstIndex { $0.id == id } ?? 0
        allTabs.removeAll { $0.id == id }
        tunnels.release(holder: id.uuidString)
        PreviewWebViews.shared.forget(id)
        if selections[tab.owner] == id {
            let rest = siblings.filter { $0.id != id }
            selections[tab.owner] = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        }
    }

    func closeAll() {
        for tab in allTabs { close(tab.id) }
    }

    /// The session ended or was removed: its tabs go, and so do the tunnels
    /// no other tab still holds.
    func closeSession(_ session: SessionRef) {
        for tab in allTabs where tab.owner == session { close(tab.id) }
        selections[session] = nil
    }

    func closeWorkspace(alias: String) {
        for tab in allTabs where tab.owner?.alias == alias { close(tab.id) }
        selections = selections.filter { $0.key?.alias != alias }
    }

    func moveSession(from old: SessionRef, to new: SessionRef) {
        for index in allTabs.indices where allTabs[index].owner == old {
            allTabs[index].owner = new
        }
        if let selected = selections.removeValue(forKey: old) { selections[new] = selected }
        if owner == old { owner = new }
    }

    func pageChanged(_ id: UUID, title: String?, url: URL?) {
        guard let tab = allTabs.first(where: { $0.id == id }) else { return }
        let name = PreviewTitle.display(pageTitle: title, url: url, fallback: tab.request?.title ?? tab.title)
        guard name != tab.title else { return }
        update(id) { $0.title = name }
    }

    func retry(_ id: UUID) {
        guard let tab = allTabs.first(where: { $0.id == id }), let request = tab.request else { return }
        load(request, into: id)
    }

    private func openTab(_ request: PreviewRequest) {
        let id = UUID()
        add(PreviewTab(id: id, title: request.title, request: request, state: .connecting("")))
        load(request, into: id)
    }

    private func add(_ tab: PreviewTab) {
        var tab = tab
        tab.owner = owner
        allTabs.append(tab)
        selections[owner] = tab.id
    }

    private func load(_ request: PreviewRequest, into id: UUID) {
        switch PreviewResolution.resolve(request) {
        case let .direct(url):
            update(id) { $0.state = .ready(url) }
        case let .tunnel(key, path):
            update(id) { $0.state = .connecting("Opening a tunnel to \(request.title)…") }
            Task {
                do {
                    let port = try await tunnels.open(key, holder: id.uuidString)
                    update(id) { $0.state = .ready(PreviewResolution.localhost(port, path: path)) }
                } catch is CancellationError {
                    return
                } catch {
                    update(id) { $0.state = .failed(error.localizedDescription) }
                }
            }
        }
    }

    private func openInBrowser(_ request: PreviewRequest) {
        switch PreviewResolution.resolve(request) {
        case let .direct(url):
            external.open(url)
        case let .tunnel(key, path):
            isOpeningInBrowser = true
            Task {
                defer { isOpeningInBrowser = false }
                do {
                    let port = try await tunnels.open(key, holder: Self.browserHolder)
                    external.open(PreviewResolution.localhost(port, path: path))
                } catch {
                    report("Couldn't open \(request.title): \(error.localizedDescription)")
                }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout PreviewTab) -> Void) {
        guard let index = allTabs.firstIndex(where: { $0.id == id }) else { return }
        change(&allTabs[index])
    }
}
