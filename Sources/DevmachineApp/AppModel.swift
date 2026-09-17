import Foundation
import AppKit
import Combine
import DevmachineCore

struct BGTask: Identifiable, Equatable {
    let id: UUID
    var label: String
    var completed: Int
    var total: Int
}

struct PaletteItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let target: SidebarItem
    let claude: Bool
}

@MainActor
final class AppModel: ObservableObject {
    /// The one model the app builds, so code outside the view tree — the
    /// terminal key monitor — can report progress without being handed it.
    private(set) static weak var shared: AppModel?

    /// Every workspace in `~/.ssh/config`, hidden ones included: Settings needs
    /// the whole list to offer the choice.
    @Published var workspaces: [Workspace] = []

    /// The workspaces in use. Everything else in the app reads this one, so a
    /// hidden workspace costs no row, no ssh and no mosh.
    var visibleWorkspaces: [Workspace] {
        WorkspaceVisibility.visible(workspaces, hidden: settings?.hiddenWorkspaces ?? [])
    }

    /// The sidebar list: the ssh workspaces, then this Mac, always last.
    var sidebarWorkspaces: [Workspace] { visibleWorkspaces + [.local] }

    /// Sessions of the local workspace: the Operator shell plus whatever
    /// folders you added. The list is remembered, the shells are not — without
    /// a multiplexer a local shell ends when the app does.
    @Published private(set) var addedLocalSessions: [LocalSession] =
        AppModel.readLocalSessions() {
        didSet { AppModel.writeLocalSessions(addedLocalSessions) }
    }

    /// Renames the sidebar shows, by handle. Kept apart from the stored list so
    /// the Operator session, which is not in that list, can be renamed too.
    @Published private(set) var localSessionNames: [String: String] =
        UserDefaults.standard.dictionary(forKey: AppModel.localNamesKey) as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(localSessionNames, forKey: AppModel.localNamesKey) }
    }

    /// What `zmx ls` last reported, and which of those sessions hold a Claude.
    @Published private(set) var liveLocalSessions: [ZmxSession] = []
    @Published private(set) var localClaudeSessions: Set<String> = []

    var localSessions: [LocalSession] {
        let remembered = [LocalSession(name: Workspace.operatorSession, path: operatorPath)]
            + addedLocalSessions
        let all = LocalSessionScan.merge(
            stored: remembered, live: liveLocalSessions, fallbackPath: NSHomeDirectory())
        return all.map { session in
            guard let shown = localSessionNames[session.handle] else { return session }
            return LocalSession(handle: session.handle, name: shown, path: session.path)
        }
    }

    /// The context users behind the workspaces still on: what Stats and the
    /// subdomain list are allowed to show. A row the host cannot attribute to
    /// any of them (a system container, the apex site) is left alone — hiding
    /// what we cannot name would hide the machine itself.
    var visibleUsers: Set<String> {
        Set(visibleWorkspaces.map(\.name))
    }

    func showsOwner(_ owner: String?) -> Bool {
        guard let owner, knownUsers.contains(owner) else { return true }
        return visibleUsers.contains(owner)
    }

    /// Every context user the app knows of, hidden ones included.
    var knownUsers: Set<String> {
        Set(workspaces.map(\.name))
    }

    /// True while the multiplexer has this session, so the sidebar can tell a
    /// shell that is running from one that only exists in the app's list.
    func localSessionIsLive(_ session: LocalSession) -> Bool {
        let name = LocalSessionScan.multiplexerName(of: session)
        return liveLocalSessions.contains { $0.name == name }
    }

    /// Where the shell is now, which is not always where it started: the
    /// multiplexer reports the live folder, and that is what the context engine
    /// has to read.
    func localWorkingDirectory(of session: LocalSession) -> String? {
        let name = LocalSessionScan.multiplexerName(of: session)
        return liveLocalSessions.first { $0.name == name }?.directory
    }

    func localSessionHasClaude(_ session: LocalSession) -> Bool {
        localClaudeSessions.contains(LocalSessionScan.multiplexerName(of: session))
    }

    /// Reads the multiplexer's own list, then one `ps` to see what runs inside
    /// each session. Both are local and cheap; neither touches the network.
    func scanLocalSessions() {
        guard !localScanInFlight, let zmx = LocalTools.zmxPath() else { return }
        localScanInFlight = true
        let socketDirectory = Zmx.socketDirectory()
        Task.detached {
            let runner = ProcessRunner()
            let listing = (try? runner.run(
                executable: zmx, args: Zmx.listArguments,
                environment: ["ZMX_DIR": socketDirectory])) ?? ""
            let sessions = ZmxListParser.parse(listing)
            var withClaude = Set<String>()
            if !sessions.isEmpty,
               let processes = try? runner.run(
                executable: "/bin/ps", args: ProcessTree.listArguments, environment: nil) {
                let roots = ProcessTree.rootsRunning(
                    "claude", roots: sessions.map(\.pid), in: ProcessTree.parse(processes))
                withClaude = Set(sessions.filter { roots.contains($0.pid) }.map(\.name))
            }
            await MainActor.run {
                self.localScanInFlight = false
                if self.liveLocalSessions != sessions { self.liveLocalSessions = sessions }
                if self.localClaudeSessions != withClaude {
                    self.localClaudeSessions = withClaude
                    // The context panel asks for a session that holds a Claude.
                    // The first scan lands after the session is already picked,
                    // so without this the panel stays empty until the next
                    // click.
                    self.syncContext()
                }
            }
        }
    }

    private var localScanInFlight = false

    /// Fills what a scan would have found, for tests that must not run `zmx`.
    func acceptLocalScanForTesting(sessions: [ZmxSession], withClaude: Set<String>) {
        liveLocalSessions = sessions
        localClaudeSessions = withClaude
    }

    private var operatorPath: String {
        settings?.opsRepoPath ?? NSHomeDirectory()
    }

    /// Adds the folder as a session and opens it. A repeated folder is a
    /// separate session, numbered, rather than a jump to the existing one:
    /// two shells in one repository is a normal thing to want.
    func addLocalSession(path: String) {
        let name = LocalSessionNaming.name(for: path, existing: localSessions.map(\.name))
        addedLocalSessions.append(LocalSession(name: name, path: path))
        selection = .localSession(name: name, path: path)
        startProgram(in: .local(session: name, path: path))
    }

    /// Types the startup line once the session exists. A local session is born
    /// when its pane mounts, not when the row is added, so the line waits for
    /// the multiplexer to list it.
    func startProgram(in target: CommandTarget) {
        guard let line = settings?.newSessionProgram.startupLine else { return }
        let host = HostRunner()
        Task.detached {
            guard case let .local(session, _) = target else {
                try? host.send(line, into: target)
                return
            }
            let socketDirectory = Zmx.socketDirectory()
            let name = Zmx.sessionName(from: session, socketDirectory: socketDirectory)
            guard let zmx = await MainActor.run(body: { LocalTools.zmxPath() }) else { return }
            let runner = ProcessRunner()
            for _ in 0..<30 {
                let listing = (try? runner.run(
                    executable: zmx, args: Zmx.listArguments,
                    environment: ["ZMX_DIR": socketDirectory])) ?? ""
                if ZmxListParser.parse(listing).contains(where: { $0.name == name }) {
                    // The shell prints its prompt after the socket exists; a
                    // line typed before that is swallowed by the terminal setup.
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    try? host.send(line, into: target)
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func removeLocalSession(handle: String) {
        guard let s = localSessions.first(where: { $0.handle == handle }) else { return }
        TerminalRegistry.shared.close(.local(session: s.handle, path: s.path))
        // Closing the pane only drops this app's client; the multiplexer would
        // keep the shell running with nothing pointing at it.
        TerminalRegistry.shared.killLocalSession(named: s.handle)
        addedLocalSessions.removeAll { $0.handle == handle }
        liveLocalSessions.removeAll { $0.name == LocalSessionScan.multiplexerName(of: s) }
        localSessionNames[handle] = nil
        if selection == .localSession(name: s.handle, path: s.path) { selection = nil }
    }

    /// Only the sidebar name changes: the shell keeps running under the handle
    /// it was created with, because the multiplexer cannot rename a session.
    func renameLocalSession(handle: String, to newName: String) {
        pendingLocalRename = nil
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        guard localSessions.contains(where: { $0.handle == handle }) else { return }
        if clean == handle {
            localSessionNames[handle] = nil
        } else {
            localSessionNames[handle] = String(clean.prefix(40))
        }
    }

    private static let localSessionsKey = "localSessions"
    private static let localNamesKey = "localSessionNames"

    private static func readLocalSessions() -> [LocalSession] {
        guard let data = UserDefaults.standard.data(forKey: localSessionsKey),
              let list = try? JSONDecoder().decode([LocalSession].self, from: data)
        else { return [] }
        return list
    }

    private static func writeLocalSessions(_ list: [LocalSession]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: localSessionsKey)
    }
    @Published var sessionsByAlias: [String: [TmuxSession]] = [:]
    @Published var offlineAliases: Set<String> = []

    /// Progress of the workspace sweep, for the sidebar's connecting bar. The
    /// total is workspaces, not sessions: how many sessions a workspace has is
    /// only known once it answers. Zero total means no sweep is running.
    @Published private(set) var sweepTotal = 0
    @Published private(set) var sweepDone = 0

    /// Drives the label from a test without running a sweep.
    func sweepDoneForTesting(_ value: Int) { sweepDone = value }

    /// A short job worth a bar in the sidebar: sending an image, for now.
    /// It takes the same place as the sweep's bar and wins while it runs,
    /// because it is the thing you just asked for.
    struct Transfer: Equatable {
        let label: String
        let done: Int
        let total: Int
    }

    @Published var transfer: Transfer?

    func beginTransfer(label: String, total: Int) {
        transfer = Transfer(label: label, done: 0, total: total)
    }

    func advanceTransfer(done: Int) {
        guard let current = transfer else { return }
        transfer = Transfer(label: current.label, done: done, total: current.total)
    }

    func endTransfer() { transfer = nil }

    /// "Connecting 3 of 10 workspaces…", or nil when nothing is connecting.
    var connectingLabel: String? {
        guard sweepTotal > 0 else { return nil }
        let current = min(sweepDone + 1, sweepTotal)
        return "Connecting \(current) of \(sweepTotal) workspaces…"
    }
    @Published var selection: SidebarItem? = nil {
        didSet {
            if let selection {
                activePage = nil
                TerminalRegistry.shared.requestFocus(selection.terminalKind)
            }
            // Leaving the session list (ops shell, Home) drops the session
            // highlight: two places lit at once reads as being in two sessions.
            if case .session = selection {} else {
                selectedSessions = []
                selectionAnchor = nil
            }
            syncContext()
        }
    }
    @Published var activePage: AppPage? = nil {
        didSet {
            // Coming back from a page leaves the pane exactly as it was, so the
            // program inside is never told to draw again and the screen stays
            // stale. Same repaint the app asks for after a pane is put away.
            guard activePage == nil, oldValue != nil, let selection else { return }
            TerminalRegistry.shared.requestRepaint(selection.terminalKind)
        }
    }
    @Published var settings: AppSettings? = nil
    @Published var stackCellSizes: [String: StackCellSize] = AppModel.loadStackCellSizes() {
        didSet { AppModel.saveStackCellSizes(stackCellSizes) }
    }
    @Published var pendingNewSessionAlias: String? = nil
    @Published var pendingRename: (alias: String, old: String)? = nil
    @Published var pendingLocalRename: (handle: String, current: String)? = nil
    @Published var pendingDelete: (alias: String, name: String)? = nil
    @Published var pendingBulkDelete: [SessionRef]? = nil
    @Published var selectedSessions: Set<SessionRef> = []
    @Published var activeTasks: [BGTask] = []
    @Published var showCommandPalette = false
    /// The file finder, opened over any session.
    @Published var showFileSearch = false
    @Published var showShortcuts = false
    var selectionAnchor: SessionRef? = nil

    @Published var sidebarCollapsed: Bool = (UserDefaults.standard.object(forKey: "sidebarCollapsed") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }
    @Published var sidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "sidebarWidth")
        return (saved >= 200 && saved <= 460) ? CGFloat(saved) : 260
    }() {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth") }
    }

    @Published var contextCollapsed: Bool = (UserDefaults.standard.object(forKey: "contextCollapsed") as? Bool) ?? false {
        didSet { UserDefaults.standard.set(contextCollapsed, forKey: "contextCollapsed") }
    }
    @Published var contextWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "contextWidth")
        return (saved >= 240 && saved <= 520) ? CGFloat(saved) : 300
    }() {
        didSet { UserDefaults.standard.set(Double(contextWidth), forKey: "contextWidth") }
    }
    @Published var viewerWidth: CGFloat =
        CGFloat(UserDefaults.standard.double(forKey: "viewerWidth") == 0
            ? 640 : UserDefaults.standard.double(forKey: "viewerWidth")) {
        didSet { UserDefaults.standard.set(Double(viewerWidth), forKey: "viewerWidth") }
    }

    func setViewerWidth(_ width: CGFloat) {
        viewerWidth = min(max(width, 320), 1200)
    }

    @Published var contextTab: ContextTab =
        ContextTab(rawValue: UserDefaults.standard.string(forKey: "contextTab") ?? "") ?? .context {
        didSet {
            UserDefaults.standard.set(contextTab.rawValue, forKey: "contextTab")
            syncContext()
        }
    }
    let context = ContextStore()

    private let store: SessionStore
    private var selectionPollTimer: Timer? = nil
    private var selectionPollAlias: String? = nil
    private var refreshingAliases: Set<String> = []
    private var sweepInFlight = false
    private var sweepTimer: Timer? = nil
    private var localScanTimer: Timer? = nil
    private var pollPausedUntil = Date.distantPast

    init(store: SessionStore = SessionStore(runner: ProcessRunner())) {
        self.store = store
        AppModel.shared = self
        observeWake()
        TerminalRegistry.shared.onSessionEnded = { [weak self] kind in
            self?.sessionEnded(kind)
        }
    }

    /// Hiding a workspace has to cost nothing at once, not at the next restart:
    /// its panes are closed, which ends the mosh or ssh they hold, its sessions
    /// are forgotten, and the poll has nothing left to visit.
    func applyHiddenWorkspaces() {
        let hidden = settings?.hiddenWorkspaces ?? []
        guard !hidden.isEmpty else { return }
        for alias in hidden where WorkspaceVisibility.isHidden(alias, hidden: hidden) {
            for session in sessionsByAlias[alias] ?? [] {
                drop(SessionRef(alias: alias, name: session.name),
                     item: .session(alias: alias, name: session.name))
            }
            TerminalRegistry.shared.closeWorkspace(alias: alias)
            sessionsByAlias[alias] = nil
            offlineAliases.remove(alias)
            if selectionPollAlias == alias {
                selectionPollTimer?.invalidate()
                selectionPollTimer = nil
                selectionPollAlias = nil
            }
        }
        if case let .session(alias, _) = selection,
           WorkspaceVisibility.isHidden(alias, hidden: hidden) {
            selection = nil
        }
        syncContext()
    }

    /// A session that ended (`exit`) leaves no pane behind: the row goes, the
    /// stack closes over the gap, and the selection moves off it.
    func sessionEnded(_ kind: TerminalKind) {
        switch kind {
        case let .local(handle, path):
            addedLocalSessions.removeAll { $0.handle == handle }
            localSessionNames[handle] = nil
            liveLocalSessions.removeAll {
                $0.name == Zmx.sessionName(from: handle, socketDirectory: Zmx.socketDirectory())
            }
            drop(SessionRef(alias: Workspace.local.alias, name: handle),
                 item: .localSession(name: handle, path: path))
        case let .remote(alias, session):
            drop(SessionRef(alias: alias, name: session),
                 item: .session(alias: alias, name: session))
        }
    }

    private func drop(_ ref: SessionRef, item: SidebarItem) {
        if case let .stack(refs) = activePage, refs.contains(ref) {
            let left = refs.filter { $0 != ref }
            activePage = left.isEmpty ? nil : .stack(left)
        }
        selectedSessions.remove(ref)
        if selectionAnchor == ref { selectionAnchor = nil }
        if selection == item { selection = nil }
        TerminalRegistry.shared.close(item.terminalKind)
    }

    /// Sessions this app still shows for a workspace that the workspace itself
    /// no longer has: killed from another client, or ended with `exit`.
    private func dropMissingSessions(alias: String, present: [TmuxSession]) {
        let names = Set(present.map(\.name))
        var refs: [SessionRef] = []
        if case let .stack(stacked) = activePage {
            refs += stacked.filter { $0.alias == alias && !names.contains($0.name) }
        }
        if case let .session(selectedAlias, name) = selection,
           selectedAlias == alias, !names.contains(name) {
            refs.append(SessionRef(alias: alias, name: name))
        }
        for ref in Set(refs) {
            drop(ref, item: .session(alias: ref.alias, name: ref.name))
        }
    }

    var hasSelectionPollTimer: Bool { selectionPollTimer != nil }
    var selectionPollTarget: String? { selectionPollAlias }

    func newSession(alias: String) {
        pendingNewSessionAlias = alias
    }

    /// Types text where a session is waiting for input, without sending it.
    func typeInSession(_ target: CommandTarget, text: String) {
        let host = HostRunner()
        Task.detached {
            try? host.type(text, into: target)
        }
    }

    func showPage(_ page: AppPage) {
        activePage = page
    }

    func stackSessions(_ refs: [SessionRef]) {
        guard let first = refs.first else { return }
        activePage = .stack(refs)
        TerminalRegistry.shared.requestFocus(.remote(alias: first.alias, session: first.name))
    }

    func stackWorkspace(_ alias: String) {
        let refs = alias == Workspace.local.alias
            ? localSessions.map { SessionRef(alias: alias, name: $0.handle) }
            : (sessionsByAlias[alias] ?? []).map { SessionRef(alias: alias, name: $0.name) }
        stackSessions(refs)
    }

    /// Which terminal a reference stands for. The local workspace is the one
    /// whose sessions run here, and those need the folder they started in.
    func terminalKind(for ref: SessionRef) -> TerminalKind {
        guard ref.alias == Workspace.local.alias else {
            return .remote(alias: ref.alias, session: ref.name)
        }
        let path = localSessions.first { $0.handle == ref.name }?.path ?? NSHomeDirectory()
        return .local(session: ref.name, path: path)
    }

    /// What a session is called on screen. A local session keeps its handle as
    /// a reference, so the name has to be looked up.
    func displayName(for ref: SessionRef) -> String {
        guard ref.alias == Workspace.local.alias else { return ref.name }
        return localSessions.first { $0.handle == ref.name }?.name ?? ref.name
    }

    func isStacked(_ ref: SessionRef) -> Bool {
        if case let .stack(refs) = activePage { return refs.contains(ref) }
        return false
    }

    func isWorkspaceStacked(_ alias: String) -> Bool {
        guard case let .stack(refs) = activePage, !refs.isEmpty else { return false }
        return refs.allSatisfy { $0.alias == alias }
    }

    func stackCellSize(_ ref: SessionRef) -> StackCellSize {
        stackCellSizes[Self.stackCellKey(ref)] ?? .auto
    }

    func cycleStackCellSize(_ ref: SessionRef) {
        let key = Self.stackCellKey(ref)
        stackCellSizes[key] = stackCellSize(ref).next
    }

    func moveStackCell(_ ref: SessionRef, by delta: Int) {
        guard case let .stack(refs) = activePage,
              let index = refs.firstIndex(of: ref) else { return }
        let target = index + delta
        guard refs.indices.contains(target) else { return }
        var newRefs = refs
        newRefs.swapAt(index, target)
        activePage = .stack(newRefs)
    }

    // ⌘⇧↩ — like maximizing/restoring a pane: grid cell → that session alone;
    // single session → its workspace grid.
    func toggleMaximize() {
        if case let .stack(refs) = activePage {
            guard let ref = FocusedTerminal.ref().flatMap({ refs.contains($0) ? $0 : nil })
                ?? refs.first else { return }
            // A local reference is not a remote one: opening it as `.session`
            // sent the Local workspace's alias to mosh, which then looked for a
            // host called "local".
            let item = sidebarItem(for: ref)
            if case .session = item {
                selectedSessions = [ref]
                selectionAnchor = ref
            } else {
                selectedSessions = []
                selectionAnchor = nil
            }
            selection = item
        } else if case let .session(alias, _) = selection {
            stackWorkspace(alias)
        } else if case .localSession = selection {
            stackWorkspace(Workspace.local.alias)
        }
    }

    /// The sidebar row a reference stands for. The Local workspace has its own
    /// kind of row, and mixing the two is what starts a remote client for a
    /// session that runs here.
    func sidebarItem(for ref: SessionRef) -> SidebarItem {
        guard ref.alias == Workspace.local.alias else {
            return .session(alias: ref.alias, name: ref.name)
        }
        let path = localSessions.first { $0.handle == ref.name }?.path ?? NSHomeDirectory()
        return .localSession(name: ref.name, path: path)
    }

    private static func stackCellKey(_ ref: SessionRef) -> String {
        "\(ref.alias)/\(ref.name)"
    }

    private static func loadStackCellSizes() -> [String: StackCellSize] {
        guard let data = UserDefaults.standard.data(forKey: "stackCellSizes"),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues { StackCellSize(rawValue: $0) }
    }

    private static func saveStackCellSizes(_ sizes: [String: StackCellSize]) {
        let raw = sizes.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw) else { return }
        UserDefaults.standard.set(data, forKey: "stackCellSizes")
    }

    func setSidebarWidth(_ w: CGFloat) {
        sidebarWidth = min(max(w, 200), 460)
    }

    func setContextWidth(_ w: CGFloat) {
        contextWidth = min(max(w, 240), 520)
    }

    func flattenedSessions() -> [SessionRef] {
        visibleWorkspaces.flatMap { ws in
            (sessionsByAlias[ws.alias] ?? []).map { SessionRef(alias: ws.alias, name: $0.name) }
        }
    }

    func clickSession(_ ref: SessionRef) {
        // re-clicking the open session (no multi-select) goes back home
        if selection == .session(alias: ref.alias, name: ref.name), selectedSessions == [ref], activePage == nil {
            selection = nil
            selectedSessions = []
            selectionAnchor = nil
            return
        }
        selectedSessions = [ref]
        selectionAnchor = ref
        selection = .session(alias: ref.alias, name: ref.name)
    }

    func goHome() {
        selection = nil
        selectedSessions = []
        selectionAnchor = nil
    }

    func paletteItems() -> [PaletteItem] {
        var items = visibleWorkspaces.flatMap { ws in
            (sessionsByAlias[ws.alias] ?? []).map { s in
                PaletteItem(
                    id: "\(ws.alias)/\(s.name)",
                    title: s.name,
                    subtitle: ws.name,
                    target: .session(alias: ws.alias, name: s.name),
                    claude: s.hasClaude
                )
            }
        }
        for s in localSessions {
            items.append(PaletteItem(
                id: "local/\(s.handle)",
                title: s.name,
                subtitle: Workspace.local.name,
                target: .localSession(name: s.handle, path: s.path),
                claude: false
            ))
        }
        return items
    }

    func openPalette(_ item: PaletteItem) {
        selection = item.target
        if case let .session(alias, name) = item.target {
            let ref = SessionRef(alias: alias, name: name)
            selectedSessions = [ref]
            selectionAnchor = ref
        }
        showCommandPalette = false
    }

    func cmdClickSession(_ ref: SessionRef) {
        if selectedSessions.contains(ref) {
            selectedSessions.remove(ref)
        } else {
            selectedSessions.insert(ref)
        }
        selectionAnchor = ref
    }

    func shiftClickSession(_ ref: SessionRef) {
        let flattened = flattenedSessions()
        let anchor = selectionAnchor ?? ref
        guard let anchorIndex = flattened.firstIndex(of: anchor),
              let refIndex = flattened.firstIndex(of: ref) else {
            selectedSessions = [ref]
            return
        }
        let range = anchorIndex <= refIndex ? anchorIndex...refIndex : refIndex...anchorIndex
        selectedSessions = Set(flattened[range])
    }

    @discardableResult
    private func beginTask(label: String, total: Int) -> UUID {
        let id = UUID()
        activeTasks.append(BGTask(id: id, label: label, completed: 0, total: total))
        return id
    }

    private func bumpTask(_ id: UUID) {
        if let i = activeTasks.firstIndex(where: { $0.id == id }) {
            activeTasks[i].completed += 1
        }
    }

    func flashToast(_ label: String) {
        finishTask(beginTask(label: label, total: 1))
    }

    private func finishTask(_ id: UUID) {
        if let i = activeTasks.firstIndex(where: { $0.id == id }) {
            activeTasks[i].completed = activeTasks[i].total
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.activeTasks.removeAll { $0.id == id }
        }
    }

    func deleteSessions(_ refs: [SessionRef]) {
        pendingBulkDelete = nil
        guard !refs.isEmpty else { return }
        let taskId = beginTask(label: "Deleting sessions", total: refs.count)
        Task.detached { [store] in
            for ref in refs {
                _ = try? store.run(alias: ref.alias, command: RemoteCommands.killSession(name: ref.name))
                await MainActor.run { self.bumpTask(taskId) }
            }
            let affectedAliases = Set(refs.map(\.alias))
            await MainActor.run {
                for alias in affectedAliases { self.refresh(alias: alias) }
                for ref in refs {
                    self.selectedSessions.remove(ref)
                    TerminalRegistry.shared.close(alias: ref.alias, session: ref.name)
                    let item = SidebarItem.session(alias: ref.alias, name: ref.name)
                    if self.selection == item {
                        self.selection = nil
                    }
                }
                self.finishTask(taskId)
            }
        }
    }

    func renameSession(alias: String, old: String, new: String) {
        let clean = new.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { pendingRename = nil; return }
        let range = NSRange(clean.startIndex..., in: clean)
        guard Self.validSessionName.firstMatch(in: clean, range: range) != nil else {
            pendingRename = nil
            return
        }
        pendingRename = nil
        let taskId = beginTask(label: "Renaming \(old)", total: 1)
        Task.detached { [store] in
            _ = try? store.run(alias: alias, command: RemoteCommands.rename(session: old, to: clean))
            await MainActor.run {
                self.bumpTask(taskId)
                self.refresh(alias: alias)
                // The old client is still attached to the renamed tmux session;
                // drop it so the new name mounts as the only client.
                TerminalRegistry.shared.close(alias: alias, session: old)
                let oldItem = SidebarItem.session(alias: alias, name: old)
                if self.selection == oldItem {
                    self.selection = .session(alias: alias, name: clean)
                }
                self.finishTask(taskId)
            }
        }
    }

    func deleteSession(alias: String, name: String) {
        pendingDelete = nil
        let taskId = beginTask(label: "Deleting \(name)", total: 1)
        Task.detached { [store] in
            _ = try? store.run(alias: alias, command: RemoteCommands.killSession(name: name))
            await MainActor.run {
                self.bumpTask(taskId)
                self.refresh(alias: alias)
                TerminalRegistry.shared.close(alias: alias, session: name)
                let item = SidebarItem.session(alias: alias, name: name)
                if self.selection == item {
                    self.selection = nil
                }
                self.finishTask(taskId)
            }
        }
    }

    private static let validSessionName = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]+$")

    /// Remembered so the next session starts where the last one did.
    @Published var newSessionDirectory: String =
        UserDefaults.standard.string(forKey: "newSessionDirectory") ?? "~/dev" {
        didSet { UserDefaults.standard.set(newSessionDirectory, forKey: "newSessionDirectory") }
    }

    func confirmNewSession(alias: String, name: String, directory: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { pendingNewSessionAlias = nil; return }
        let range = NSRange(clean.startIndex..., in: clean)
        guard Self.validSessionName.firstMatch(in: clean, range: range) != nil else {
            pendingNewSessionAlias = nil
            return
        }
        newSessionDirectory = directory
        pendingNewSessionAlias = nil
        // Created here rather than left to the terminal's own `new-session -A`,
        // because only a session created up front can be told which directory to
        // start in, and that is what gives Claude Code its file list.
        let store = self.store
        let startup = settings?.newSessionProgram.startupLine
        Task.detached {
            _ = try? store.run(
                alias: alias,
                command: RemoteCommands.createSession(name: clean, directory: directory))
            if let startup {
                try? HostRunner().send(startup, into: .remote(alias: alias, session: clean))
            }
            await MainActor.run { self.selection = .session(alias: alias, name: clean) }
        }
        // With no global poll, a single refresh can race the create, so re-poll
        // a few times until the new session shows up in the sidebar.
        for delay in [1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.refresh(alias: alias) }
        }
    }

    func loadWorkspaces() {
        guard let settings else { return }
        let path = NSHomeDirectory() + "/.ssh/config"
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        workspaces = SSHConfigParser.parse(text, suffix: settings.workspaceSuffix)
        refreshAll()
        // A slow sweep of every workspace so an offline one comes back on its
        // own; the 5s timer only follows the selected one.
        sweepTimer?.invalidate()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        scanLocalSessions()
        localScanTimer?.invalidate()
        localScanTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanLocalSessions() }
        }
    }

    // One ssh at a time, and the sweep stops at the first ssh-level failure:
    // nine parallel auths against a locked agent are nine denied logins in
    // one second, which is a fail2ban ban of this Mac.
    func refreshAll() {
        guard Date() >= pollPausedUntil, !sweepInFlight else { return }
        let targets = visibleWorkspaces.filter { !refreshingAliases.contains($0.alias) }
        guard !targets.isEmpty else { return }
        sweepInFlight = true
        sweepTotal = targets.count
        sweepDone = 0
        for ws in targets { refreshingAliases.insert(ws.alias) }
        Task.detached { [store] in
            var remaining = targets[...]
            while let ws = remaining.first {
                remaining = remaining.dropFirst()
                let outcome = Result { try store.sessions(for: ws) }
                let stop = await MainActor.run { () -> Bool in
                    let stop = self.apply(outcome, alias: ws.alias)
                    self.sweepDone += 1
                    return stop
                }
                if stop { break }
            }
            // The aliases the stopped sweep never reached share the same host,
            // so they are offline too, not "0 sessions".
            let unreached = Array(remaining)
            await MainActor.run {
                for ws in unreached where !self.offlineAliases.contains(ws.alias) {
                    self.offlineAliases.insert(ws.alias)
                }
                for ws in targets { self.refreshingAliases.remove(ws.alias) }
                self.sweepInFlight = false
                self.sweepTotal = 0
                self.sweepDone = 0
            }
        }
    }

    func refresh(alias: String) {
        guard Date() >= pollPausedUntil,
              let ws = visibleWorkspaces.first(where: { $0.alias == alias }) else { return }
        // A tick that arrives while the previous ssh for this alias is still
        // running is dropped: a slow host would otherwise stack one blocked
        // process per 5s tick.
        guard !refreshingAliases.contains(alias) else { return }
        refreshingAliases.insert(alias)
        Task.detached { [store] in
            let outcome = Result { try store.sessions(for: ws) }
            await MainActor.run {
                self.refreshingAliases.remove(alias)
                _ = self.apply(outcome, alias: alias)
            }
        }
    }

    // Returns true when polling must pause: the host or the ssh agent is down.
    private func apply(_ outcome: Result<[TmuxSession], Error>, alias: String) -> Bool {
        switch outcome {
        case .success(let result):
            // Assign only on a real change: every write to a @Published
            // re-renders the whole tree, and the 5s poll usually returns
            // exactly what is already on screen.
            if sessionsByAlias[alias] != result {
                sessionsByAlias[alias] = result
                dropMissingSessions(alias: alias, present: result)
            }
            if offlineAliases.contains(alias) {
                offlineAliases.remove(alias)
            }
            syncContext()
            return false
        case .failure(let error):
            if !offlineAliases.contains(alias) {
                offlineAliases.insert(alias)
            }
            syncContext()
            guard let failure = (error as? SessionStoreError)?.failure else { return false }
            pausePolling(after: failure)
            return true
        }
    }

    /// True while a failure is holding the sweep back.
    var isPollingPaused: Bool { Date() < pollPausedUntil }

    /// Sleeping made every ssh fail at once, which paused the sweep and turned
    /// the whole sidebar red. Waking is the evidence that the pause no longer
    /// applies, so it is lifted and the sweep runs at once instead of leaving
    /// the sidebar wrong for up to two minutes.
    func resumePollingAfterWake() {
        pollPausedUntil = .distantPast
        sweepInFlight = false
        refreshingAliases.removeAll()
        refreshAll()
    }

    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppModel.shared?.resumePollingAfterWake() }
            }
        }
    }

    private func pausePolling(after failure: SSHFailure) {
        let seconds: TimeInterval = failure == .authDenied ? 300 : 60
        pollPausedUntil = Date().addingTimeInterval(seconds)
        let label = failure == .authDenied
            ? "SSH auth denied — polling paused 5 min (unlock the ssh agent)"
            : "Host unreachable — polling paused 1 min"
        let id = beginTask(label: label, total: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.finishTask(id) }
    }

    // whenever selection changes to a Claude session, (re)start the poll; else stop.
    // Another context tab on screen also stops it: only the visible tab polls.
    func syncContext() {
        guard contextTab == .context, let target = contextTarget(for: selection) else {
            context.stop()
            updateSelectionPoll()
            return
        }
        context.start(target)
        updateSelectionPoll()
    }

    /// Only a session that holds a Claude has a context to read, and a local one
    /// also needs the engine installed here.
    private func contextTarget(for item: SidebarItem?) -> CommandTarget? {
        switch item {
        case let .session(alias, name):
            guard let ws = sessionsByAlias[alias]?.first(where: { $0.name == name }),
                  ws.hasClaude else { return nil }
            return .remote(alias: alias, session: name)
        case let .localSession(name, path):
            guard LocalContext.isInstalled,
                  let session = localSessions.first(where: { $0.handle == name }),
                  localSessionHasClaude(session) else { return nil }
            return .local(session: name, path: localWorkingDirectory(of: session) ?? path)
        case nil:
            return nil
        }
    }

    /// Asked for by whoever opens a file, so the tree follows it. The panel
    /// owns the tree, so it listens for this instead of being called directly.
    @Published var revealInTree: String?

    func openedFile(at path: String) {
        contextTab = .files
        revealInTree = path
    }

    /// Where a panel or the search field reads from, for whatever is selected.
    /// The one place that turns a sidebar row into a target.
    func commandTarget(for item: SidebarItem?) -> CommandTarget? {
        switch item {
        case let .session(alias, name):
            return .remote(alias: alias, session: name)
        case let .localSession(name, path):
            let session = localSessions.first { $0.handle == name }
            return .local(
                session: name, path: session.flatMap(localWorkingDirectory) ?? path)
        case nil:
            return nil
        }
    }

    // 5s poll of only the selected session's workspace; no session selected, no poll.
    private func updateSelectionPoll() {
        guard case let .session(alias, _) = selection else {
            selectionPollTimer?.invalidate()
            selectionPollTimer = nil
            selectionPollAlias = nil
            return
        }
        guard selectionPollAlias != alias || selectionPollTimer == nil else { return }

        selectionPollAlias = alias
        selectionPollTimer?.invalidate()
        selectionPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(alias: alias) }
        }
    }
}
