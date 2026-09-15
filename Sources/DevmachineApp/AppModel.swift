import Foundation
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

    @Published var workspaces: [Workspace] = []

    /// The sidebar list: the ssh workspaces, then this Mac, always last.
    var sidebarWorkspaces: [Workspace] { workspaces + [.local] }

    /// Sessions of the local workspace: the Operator shell plus whatever
    /// folders you added. The list is remembered, the shells are not — without
    /// a multiplexer a local shell ends when the app does.
    @Published private(set) var addedLocalSessions: [LocalSession] =
        AppModel.readLocalSessions() {
        didSet { AppModel.writeLocalSessions(addedLocalSessions) }
    }

    var localSessions: [LocalSession] {
        [LocalSession(name: Workspace.operatorSession, path: operatorPath)] + addedLocalSessions
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
    }

    func removeLocalSession(name: String) {
        guard let s = addedLocalSessions.first(where: { $0.name == name }) else { return }
        TerminalRegistry.shared.close(.local(session: s.name, path: s.path))
        // Closing the pane only drops this app's client; the multiplexer would
        // keep the shell running with nothing pointing at it.
        TerminalRegistry.shared.killLocalSession(named: s.name)
        addedLocalSessions.removeAll { $0.name == name }
        if selection == .localSession(name: s.name, path: s.path) { selection = nil }
    }

    private static let localSessionsKey = "localSessions"

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
    @Published var activePage: AppPage? = nil
    @Published var settings: AppSettings? = nil
    @Published var stackCellSizes: [String: StackCellSize] = AppModel.loadStackCellSizes() {
        didSet { AppModel.saveStackCellSizes(stackCellSizes) }
    }
    @Published var pendingNewSessionAlias: String? = nil
    @Published var pendingRename: (alias: String, old: String)? = nil
    @Published var pendingDelete: (alias: String, name: String)? = nil
    @Published var pendingBulkDelete: [SessionRef]? = nil
    @Published var selectedSessions: Set<SessionRef> = []
    @Published var activeTasks: [BGTask] = []
    @Published var showCommandPalette = false
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
    private var pollPausedUntil = Date.distantPast

    init(store: SessionStore = SessionStore(runner: ProcessRunner())) {
        self.store = store
        AppModel.shared = self
    }

    var hasSelectionPollTimer: Bool { selectionPollTimer != nil }
    var selectionPollTarget: String? { selectionPollAlias }

    func newSession(alias: String) {
        pendingNewSessionAlias = alias
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
        let refs = (sessionsByAlias[alias] ?? []).map { SessionRef(alias: alias, name: $0.name) }
        stackSessions(refs)
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
            guard let ref = FocusedTerminal.ref().flatMap({ refs.contains($0) ? $0 : nil }) ?? refs.first else { return }
            selectedSessions = [ref]
            selectionAnchor = ref
            selection = .session(alias: ref.alias, name: ref.name)
        } else if case let .session(alias, _) = selection {
            stackWorkspace(alias)
        }
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
        workspaces.flatMap { ws in
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
        var items = workspaces.flatMap { ws in
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
                id: "local/\(s.name)",
                title: s.name,
                subtitle: Workspace.local.name,
                target: .localSession(name: s.name, path: s.path),
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
        Task.detached {
            _ = try? store.run(
                alias: alias,
                command: RemoteCommands.createSession(name: clean, directory: directory))
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
    }

    // One ssh at a time, and the sweep stops at the first ssh-level failure:
    // nine parallel auths against a locked agent are nine denied logins in
    // one second, which is a fail2ban ban of this Mac.
    func refreshAll() {
        guard Date() >= pollPausedUntil, !sweepInFlight else { return }
        let targets = workspaces.filter { !refreshingAliases.contains($0.alias) }
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
              let ws = workspaces.first(where: { $0.alias == alias }) else { return }
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
        if case let .session(alias, name) = selection,
           let ws = sessionsByAlias[alias]?.first(where: { $0.name == name }), ws.hasClaude,
           contextTab == .context {
            context.start(alias: alias, session: name)
        } else {
            context.stop()
        }
        updateSelectionPoll()
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
