import Foundation
import AppKit
import Combine
import DevmachineCore

/// One job the app is doing, shown as a card by `DMToastCard`. Every part of
/// the app that has to say "this is running" uses one of these, so there is a
/// single place a job is drawn and nothing pushes the layout around.
struct BGTask: Identifiable, Equatable {
    let id: UUID
    var label: String
    var completed: Int
    var total: Int
    /// Bytes read as "1048576 of 2097152", which says nothing. A job counted in
    /// bytes shows the bar alone.
    var showsCount: Bool = true
}

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let target: SidebarItem
    let badges: [HarnessBadgePresentation]
}

/// What a new session runs first: the workspace's configured program, one
/// picked for this session only, or a command typed by hand.
enum SessionStartup: Equatable {
    case configured
    case program(SessionLaunchChoice)
    case command(String)
}

protocol SessionCommandSending: Sendable {
    func send(_ command: String, into target: CommandTarget) throws
}

extension HostRunner: SessionCommandSending {}

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
    @Published private(set) var addedLocalSessions: [LocalSession] = [] {
        didSet { AppModel.writeLocalSessions(addedLocalSessions, to: defaults) }
    }

    /// Renames the sidebar shows, by handle. Kept apart from the stored list so
    /// the Operator session, which is not in that list, can be renamed too.
    @Published private(set) var localSessionNames: [String: String] = [:] {
        didSet { defaults.set(localSessionNames, forKey: AppModel.localNamesKey) }
    }

    /// The pane whose find bar is open, if any. ⌘F sets it for the terminal
    /// that holds the keyboard; Esc clears it.
    @Published var findTarget: TerminalKind?

    /// What `zmx ls` last reported and the active harnesses detected in each
    /// session, keyed by the multiplexer name.
    @Published private(set) var liveLocalSessions: [ZmxSession] = []
    @Published private(set) var localSessionHarnesses: [String: Set<HarnessID>] = [:]

    var localSessions: [LocalSession] {
        // Demo sessions never go through `addedLocalSessions`: that property
        // persists to `UserDefaults` on every change, and a demo session has
        // no business surviving into the next real launch.
        if DemoMode.isActive { return DemoData.localSessions }
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
        localSessionHarnesses[LocalSessionScan.multiplexerName(of: session)]?.contains(.claude)
            == true
    }

    func badges(for session: TmuxSession) -> [HarnessBadgePresentation] {
        sessionHarnessFacade.badges(for: session.harnesses)
    }

    func badges(for session: LocalSession) -> [HarnessBadgePresentation] {
        let name = LocalSessionScan.multiplexerName(of: session)
        return sessionHarnessFacade.badges(for: localSessionHarnesses[name] ?? [])
    }

    func imageStoragePolicy(for kind: TerminalKind) -> ImageStoragePolicy {
        let harnesses: Set<HarnessID>
        switch kind {
        case let .remote(alias, session):
            harnesses = sessionsByAlias[alias]?.first { $0.name == session }?.harnesses ?? []
        case let .local(session, _):
            let name = Zmx.sessionName(from: session, socketDirectory: Zmx.socketDirectory())
            harnesses = localSessionHarnesses[name] ?? []
        }
        return sessionHarnessFacade.imageStoragePolicy(for: harnesses)
    }

    var sessionCount: Int {
        sessionsByAlias.values.reduce(0) { $0 + $1.count } + localSessions.count
    }

    var harnessSessionCount: Int {
        let remote = sessionsByAlias.values.reduce(0) { count, sessions in
            count + sessions.filter { !$0.harnesses.isEmpty }.count
        }
        let local = localSessions.filter { !badges(for: $0).isEmpty }.count
        return remote + local
    }

    /// Reads the multiplexer's own list, then one `ps` to see what runs inside
    /// each session. Both are local and cheap; neither touches the network.
    func scanLocalSessions() {
        guard !localScanInFlight else { return }
        localScanInFlight = true
        let source = services.sessionSource
        let settings = settings ?? .empty
        Task.detached {
            let snapshot = try? source.localSessions(settings: settings)
            await MainActor.run {
                self.localScanInFlight = false
                guard let snapshot else { return }
                if self.liveLocalSessions != snapshot.sessions {
                    self.liveLocalSessions = snapshot.sessions
                }
                if self.localSessionHarnesses != snapshot.harnesses {
                    self.localSessionHarnesses = snapshot.harnesses
                }
                // The working directory can change even when harnesses do not.
                self.syncContext()
            }
        }
    }

    private var localScanInFlight = false

    /// Fills what a scan would have found, for tests that must not run `zmx`.
    func acceptLocalScanForTesting(
        sessions: [ZmxSession], harnesses: [String: Set<HarnessID>]
    ) {
        liveLocalSessions = sessions
        localSessionHarnesses = harnesses
    }

    private var operatorPath: String {
        settings?.opsRepoPath ?? NSHomeDirectory()
    }

    /// Adds the folder as a session and opens it. A repeated folder is a
    /// separate session, numbered, rather than a jump to the existing one:
    /// two shells in one repository is a normal thing to want.
    func addLocalSession(path: String) {
        // Numbered against the handles, never the sidebar names: a renamed
        // session hides its handle, and a second session born under that same
        // handle is one row the multiplexer and the registry cannot tell apart.
        let handle = LocalSessionNaming.name(for: path, existing: localSessions.map(\.handle))
        addedLocalSessions.append(LocalSession(name: handle, path: path))
        selection = .localSession(name: handle, path: path)
        startProgram(in: .local(session: handle, path: path))
    }

    /// Types the startup line once the session exists. A local session is born
    /// when its pane mounts, not when the row is added, so the line waits for
    /// the multiplexer to list it.
    func startProgram(in target: CommandTarget, startup: SessionStartup = .configured) {
        guard let line = startupLine(startup, for: target) else { return }
        let sender = sessionCommandSender
        let runner = localRunner
        let zmxPath = zmxPath
        Task.detached {
            guard case let .local(session, _) = target else {
                try? sender.send(line, into: target)
                return
            }
            let socketDirectory = Zmx.socketDirectory()
            let name = Zmx.sessionName(from: session, socketDirectory: socketDirectory)
            guard let zmx = zmxPath else { return }
            for _ in 0..<30 {
                let listing = (try? runner.run(
                    executable: zmx, args: Zmx.listArguments,
                    environment: ["ZMX_DIR": socketDirectory])) ?? ""
                if ZmxListParser.parse(listing).contains(where: { $0.name == name }) {
                    // The shell prints its prompt after the socket exists; a
                    // line typed before that is swallowed by the terminal setup.
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    try? sender.send(line, into: target)
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// Asks before the shell dies. The Operator session is not removable, so it
    /// is never asked about.
    func askToRemoveLocalSession(handle: String) {
        guard handle != Workspace.operatorSession,
              let s = localSessions.first(where: { $0.handle == handle })
        else { return }
        pendingLocalDelete = (handle: s.handle, name: s.name)
    }

    func removeLocalSession(handle: String) {
        pendingLocalDelete = nil
        guard let s = localSessions.first(where: { $0.handle == handle }) else { return }
        TerminalRegistry.shared.close(.local(session: s.handle, path: s.path))
        // Closing the pane only drops this app's client; the multiplexer would
        // keep the shell running with nothing pointing at it.
        TerminalRegistry.shared.killLocalSession(named: s.handle)
        addedLocalSessions.removeAll { $0.handle == handle }
        let multiplexerName = LocalSessionScan.multiplexerName(of: s)
        liveLocalSessions.removeAll { $0.name == multiplexerName }
        localSessionHarnesses[multiplexerName] = nil
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

    private static func readLocalSessions(from defaults: UserDefaults) -> [LocalSession] {
        guard let data = defaults.data(forKey: localSessionsKey),
              let list = try? JSONDecoder().decode([LocalSession].self, from: data)
        else { return [] }
        return list
    }

    private static func writeLocalSessions(_ list: [LocalSession], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: localSessionsKey)
    }
    @Published var sessionsByAlias: [String: [TmuxSession]] = [:]
    @Published var offlineAliases: Set<String> = []
    /// True once the workspace list has been read at launch.
    @Published private(set) var hasLoadedWorkspaces = false
    /// Workspaces whose session read has come back at least once, with a list
    /// or with a failure.
    @Published private(set) var answeredAliases: Set<String> = []

    /// The sidebar holds a workspace's place with placeholder rows until its
    /// first read answers. A paused sweep will not read it soon, so a
    /// workspace waiting on the pause shows as it is instead.
    func showsSessionSkeleton(alias: String) -> Bool {
        !answeredAliases.contains(alias) && !isPollingPaused
    }

    private func markAnswered(_ alias: String) {
        if !answeredAliases.contains(alias) {
            answeredAliases.insert(alias)
        }
    }

    /// The sweep and an image transfer are jobs like any other: they are cards
    /// in the corner, not a strip above the sidebar. That strip had no fixed
    /// height, so every sweep pushed the whole list down and back.
    private var sweepTaskID: UUID?
    private var transferTaskID: UUID?

    func beginTransfer(label: String, total: Int) {
        transferTaskID = beginTask(label: label, total: total, showsCount: false)
    }

    func advanceTransfer(done: Int) {
        guard let id = transferTaskID else { return }
        setTask(id, completed: done)
    }

    func endTransfer() {
        guard let id = transferTaskID else { return }
        transferTaskID = nil
        finishTask(id)
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
            recordNavigation()
        }
    }
    @Published var activePage: AppPage? = nil {
        didSet {
            syncContext()
            recordNavigation()
            // Coming back from a page leaves the pane exactly as it was, so the
            // program inside is never told to draw again and the screen stays
            // stale. Same repaint the app asks for after a pane is put away.
            guard activePage == nil, oldValue != nil, let selection else { return }
            TerminalRegistry.shared.requestRepaint(selection.terminalKind)
        }
    }
    /// True while the devmachine CLI executable is not found on disk. The gate
    /// page owns the whole window while this is true, the same way `.setup`
    /// does — no background service (session sweep, stats, context) is started
    /// until this clears.
    @Published private(set) var cliMissing = false
    @Published var settings: AppSettings? = nil
    /// What the CLI answered about this Mac's setup — the config folder,
    /// admin machine, base domain, and workspace aliases Setup shows
    /// read-only instead of asking the person to type them.
    @Published private(set) var detected: CLIDetectedSettings = .empty
    /// Gates the main UI the same way `cliMissing` does, once the CLI itself
    /// is found: stats, Caddy logs and subdomain logs all need the
    /// `devmachine-app` package on the admin machine.
    @Published private(set) var packageGate: PackageGateState = .ok
    /// Whether the sidebar's Subdomains icon has anything to show for: at
    /// least one configured machine has Caddy. Starts `true` so the icon does
    /// not flash away before the first check answers.
    @Published private(set) var hasCaddyMachine = true
    @Published var stackCellSizes: [String: StackCellSize] = AppModel.loadStackCellSizes() {
        didSet { AppModel.saveStackCellSizes(stackCellSizes) }
    }
    @Published var pendingNewSessionAlias: String? = nil
    @Published var showNewSessionChooser = false
    /// The workspace whose "Custom command…" sheet is open.
    @Published var pendingCustomCommandAlias: String? = nil
    @Published var pendingRename: (alias: String, old: String)? = nil
    @Published var pendingLocalRename: (handle: String, current: String)? = nil
    /// The local session waiting for an answer. Removing one ends the shell it
    /// holds, so it is asked for the same way a remote session is.
    @Published var pendingLocalDelete: (handle: String, name: String)? = nil
    @Published var pendingDelete: (alias: String, name: String)? = nil
    @Published var pendingBulkDelete: [SessionRef]? = nil
    @Published var selectedSessions: Set<SessionRef> = []
    @Published var activeTasks: [BGTask] = []
    @Published var showCommandPalette = false
    /// The file finder, opened over any session.
    @Published var showFileSearch = false
    @Published var showShortcuts = false
    /// The workspace whose "Publish a port…" sheet should open.
    @Published var pendingPublishWorkspace: String?
    /// Asks the Subdomains page to open its Add subdomain sheet once shown.
    @Published var pendingAddSubdomain = false
    /// The Settings pane to open on, read once by the Settings page.
    @Published var requestedSettingsSection: SettingsSection?
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
        didSet {
            UserDefaults.standard.set(contextCollapsed, forKey: "contextCollapsed")
            syncContext()
        }
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
    let context: ContextStore

    private let store: SessionStore
    private let services: DevmachineServices
    private let harnessSettingsFacade: HarnessSettingsFacade
    private let sessionHarnessFacade: SessionHarnessFacade
    private let localRunner: any CommandRunner
    private let sessionCommandSender: any SessionCommandSending
    private let zmxPath: String?
    private let sessionSuffix: @Sendable () -> String
    private let cliAvailabilityCheck: @Sendable () -> Bool
    private var navigationHistory = NavigationHistory(initial: .home)
    private var isRestoringNavigation = false
    private var selectionPollTimer: Timer? = nil
    private var selectionPollAlias: String? = nil
    private var refreshingAliases: Set<String> = []
    private var sweepInFlight = false
    private var sweepTimer: Timer? = nil
    private var localScanTimer: Timer? = nil
    private var pollPausedUntil = Date.distantPast
    private let defaults: UserDefaults

    /// `swift test` runs unsandboxed on the developer's own Mac, so
    /// `UserDefaults.standard` is a real, persistent domain — a session added
    /// by one test run stays on disk and leaks into the next. Under XCTest
    /// this hands out a fresh, never-reused suite per `AppModel` instead, so
    /// no test ever sees another run's (or the real app's) local sessions.
    ///
    /// `XCTestConfigurationFilePath` is only set when Xcode launches the test
    /// host; the `swift test` CLI never sets it, so this used to read false
    /// under plain `swift test` and every `AppModel()` fell through to the
    /// real, shared `UserDefaults.standard` — the whole `AppModelTests` class
    /// sharing one on-disk domain, and failing depending on run order.
    /// `NSClassFromString` finds the XCTest framework itself, which is loaded
    /// under both.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    private static func defaultDefaults() -> UserDefaults {
        guard isRunningTests else { return .standard }
        return UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)") ?? .standard
    }

    init(
        store: SessionStore = SessionStore(runner: ProcessRunner()),
        services: DevmachineServices? = nil,
        harnessSettingsFacade: HarnessSettingsFacade = HarnessSettingsFacade(),
        localRunner: any CommandRunner = ProcessRunner(),
        sessionCommandSender: any SessionCommandSending = HostRunner(),
        zmxPath: String? = LocalTools.zmxPath(),
        sessionSuffix: @escaping @Sendable () -> String = {
            String(UUID().uuidString.prefix(2)).lowercased()
        },
        cliAvailabilityCheck: @escaping @Sendable () -> Bool = {
            (try? DevmachineCLI.resolve()) != nil
        },
        defaults: UserDefaults = AppModel.defaultDefaults()
    ) {
        self.store = store
        self.defaults = defaults
        self.addedLocalSessions = AppModel.readLocalSessions(from: defaults)
        self.localSessionNames = defaults.dictionary(forKey: AppModel.localNamesKey) as? [String: String] ?? [:]
        let services = services ?? DevmachineServices(sessionSource: CommandSessionSource(
            store: store, localRunner: localRunner, zmxPath: zmxPath,
            facade: SessionHarnessFacade(registry: harnessSettingsFacade.registry)))
        self.services = services
        self.context = ContextStore(services: services)
        self.harnessSettingsFacade = harnessSettingsFacade
        self.sessionHarnessFacade = SessionHarnessFacade(registry: harnessSettingsFacade.registry)
        self.localRunner = localRunner
        self.sessionCommandSender = sessionCommandSender
        self.zmxPath = zmxPath
        self.sessionSuffix = sessionSuffix
        self.cliAvailabilityCheck = cliAvailabilityCheck
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
            let multiplexerName = Zmx.sessionName(
                from: handle, socketDirectory: Zmx.socketDirectory())
            liveLocalSessions.removeAll {
                $0.name == multiplexerName
            }
            localSessionHarnesses[multiplexerName] = nil
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

    /// Opens a brand new session in one workspace from the sidebar's "+"
    /// menu, running the program or command picked there instead of the
    /// configured default.
    func openSession(in alias: String, startup: SessionStartup) {
        if case let .command(raw) = startup, CustomSessionCommand.normalized(raw) == nil { return }
        if alias == Workspace.local.alias {
            openLocalSession(startup: startup)
        } else {
            let directory = "~"
            let name = automaticSessionName(
                directory: directory, existing: Set(sessionsByAlias[alias]?.map(\.name) ?? []))
            createRemoteSession(alias: alias, name: name, directory: directory, startup: startup)
        }
    }

    /// Starts in the current local session's own folder when there is one
    /// (mirroring a duplicated session), else the home directory.
    private func openLocalSession(startup: SessionStartup) {
        let path: String
        if case let .localSession(name, _) = selection,
           let existing = localSessions.first(where: { $0.handle == name }) {
            path = localWorkingDirectory(of: existing) ?? existing.path
        } else {
            path = NSHomeDirectory()
        }
        let handle = LocalSessionNaming.name(for: path, existing: localSessions.map(\.handle))
        addedLocalSessions.append(LocalSession(name: handle, path: path))
        selection = .localSession(name: handle, path: path)
        startProgram(in: .local(session: handle, path: path), startup: startup)
    }

    /// The first line typed into a new session, or nil for a plain shell.
    private func startupLine(_ startup: SessionStartup, for target: CommandTarget) -> String? {
        switch startup {
        case .configured:
            guard let settings else { return nil }
            switch target {
            case .local:
                return harnessSettingsFacade.startupCommand(for: settings.localSessionProgram)
            case let .remote(alias, _):
                return harnessSettingsFacade.startupCommand(for: settings.sessionProgram(for: alias))
            }
        case let .program(choice):
            return harnessSettingsFacade.startupCommand(for: choice)
        case let .command(raw):
            return CustomSessionCommand.normalized(raw)
        }
    }

    /// ⌘N behaves like a terminal tab: duplicate the current location without
    /// asking, or ask for a destination when no terminal is actually visible.
    func requestQuickSession() {
        requestQuickSession(focusedRef: FocusedTerminal.ref())
    }

    func requestQuickSession(focusedRef: SessionRef?) {
        let item: SidebarItem?
        if activePage == nil {
            item = selection
        } else if case let .stack(refs) = activePage,
                  let ref = focusedRef.flatMap({ refs.contains($0) ? $0 : nil }) ?? refs.first {
            item = sidebarItem(for: ref)
        } else {
            item = nil
        }
        guard let target = commandTarget(for: item) else {
            showNewSessionChooser = true
            return
        }
        switch target {
        case let .local(_, path):
            addQuickLocalSession(path: path)
        case let .remote(alias, session):
            duplicateRemoteSession(alias: alias, session: session)
        }
    }

    func createQuickSession(destinationAlias: String, directory: String) {
        let path = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        showNewSessionChooser = false
        newSessionDirectory = path
        if destinationAlias == Workspace.local.alias {
            addQuickLocalSession(path: path)
        } else {
            let name = automaticSessionName(
                directory: path,
                existing: Set(sessionsByAlias[destinationAlias]?.map(\.name) ?? []))
            createRemoteSession(alias: destinationAlias, name: name, directory: path)
        }
    }

    private func addQuickLocalSession(path: String) {
        let name = automaticSessionName(
            directory: path, existing: Set(localSessions.map(\.handle)))
        addedLocalSessions.append(LocalSession(name: name, path: path))
        selection = .localSession(name: name, path: path)
        startProgram(in: .local(session: name, path: path))
    }

    private func duplicateRemoteSession(alias: String, session: String) {
        let taskID = beginTask(label: "Creating session", total: 1)
        let store = self.store
        Task.detached {
            let reported = try? store.run(
                alias: alias, command: RemoteCommands.sessionDirectory(session: session))
            let path = reported?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                let directory = (path?.isEmpty == false ? path : nil) ?? "~"
                let name = self.automaticSessionName(
                    directory: directory,
                    existing: Set(self.sessionsByAlias[alias]?.map(\.name) ?? []))
                self.createRemoteSession(
                    alias: alias, name: name, directory: directory, taskID: taskID)
            }
        }
    }

    private func automaticSessionName(directory: String, existing: Set<String>) -> String {
        var candidate = ""
        for _ in 0..<8 {
            candidate = SessionName.automatic(directory: directory, suffix: sessionSuffix())
            if !existing.contains(candidate) { return candidate }
        }
        var number = 2
        while existing.contains("\(candidate)-\(number)") { number += 1 }
        return "\(candidate)-\(number)"
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

    private var sessionNavigationItems: [SidebarItem] {
        let remote = visibleWorkspaces.flatMap { workspace in
            (sessionsByAlias[workspace.alias] ?? []).map {
                SidebarItem.session(alias: workspace.alias, name: $0.name)
            }
        }
        let local = localSessions.map {
            SidebarItem.localSession(name: $0.handle, path: $0.path)
        }
        return remote + local
    }

    func moveToNextSession() {
        moveSession(by: 1)
    }

    func moveToPreviousSession() {
        moveSession(by: -1)
    }

    private func moveSession(by offset: Int) {
        let items = sessionNavigationItems
        guard !items.isEmpty else { return }
        let current = activePage == nil ? selection.flatMap(items.firstIndex) : nil
        let next: Int
        if let current {
            next = (current + offset + items.count) % items.count
        } else {
            next = offset > 0 ? 0 : items.count - 1
        }
        openSession(items[next])
    }

    func goBack() {
        while let destination = navigationHistory.back() {
            guard let resolved = resolved(destination) else { continue }
            restoreNavigation(resolved)
            return
        }
    }

    func goForward() {
        while let destination = navigationHistory.forward() {
            guard let resolved = resolved(destination) else { continue }
            restoreNavigation(resolved)
            return
        }
    }

    private var navigationDestination: NavigationDestination {
        if let activePage { return .page(activePage) }
        if let selection { return .session(selection) }
        return .home
    }

    private func recordNavigation() {
        guard !isRestoringNavigation else { return }
        navigationHistory.record(navigationDestination)
    }

    private func resolved(_ destination: NavigationDestination) -> NavigationDestination? {
        switch destination {
        case .home:
            return .home
        case let .session(item):
            return sessionNavigationItems.contains(item) ? destination : nil
        case let .page(.stack(refs)):
            let available = refs.filter { sessionNavigationItems.contains(sidebarItem(for: $0)) }
            return available.isEmpty ? nil : .page(.stack(available))
        case .page:
            return destination
        }
    }

    private func restoreNavigation(_ destination: NavigationDestination) {
        isRestoringNavigation = true
        defer { isRestoringNavigation = false }
        switch destination {
        case .home:
            selection = nil
            selectedSessions = []
            selectionAnchor = nil
            activePage = nil
        case let .session(item):
            openSession(item)
        case let .page(page):
            activePage = page
        }
    }

    private func openSession(_ item: SidebarItem) {
        switch item {
        case let .session(alias, name):
            let ref = SessionRef(alias: alias, name: name)
            selectedSessions = [ref]
            selectionAnchor = ref
        case .localSession:
            selectedSessions = []
            selectionAnchor = nil
        }
        selection = item
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

    func clickLocalSession(_ item: SidebarItem) {
        guard case .localSession = item else { return }
        if selection == item, activePage == nil {
            goHome()
        } else {
            selection = item
        }
    }

    func goHome() {
        selection = nil
        selectedSessions = []
        selectionAnchor = nil
        activePage = nil
    }

    func paletteItems() -> [PaletteItem] {
        var items = visibleWorkspaces.flatMap { ws in
            (sessionsByAlias[ws.alias] ?? []).map { s in
                PaletteItem(
                    id: "\(ws.alias)/\(s.name)",
                    title: s.name,
                    subtitle: ws.name,
                    target: .session(alias: ws.alias, name: s.name),
                    badges: badges(for: s)
                )
            }
        }
        for s in localSessions {
            items.append(PaletteItem(
                id: "local/\(s.handle)",
                title: s.name,
                subtitle: Workspace.local.name,
                target: .localSession(name: s.handle, path: s.path),
                badges: badges(for: s)
            ))
        }
        return items
    }

    func openPalette(_ item: PaletteItem) {
        jump(to: item.target)
        showCommandPalette = false
    }

    func jump(to item: SidebarItem) {
        selection = item
        if case let .session(alias, name) = item {
            let ref = SessionRef(alias: alias, name: name)
            selectedSessions = [ref]
            selectionAnchor = ref
        }
    }

    func openSettings(_ section: SettingsSection) {
        requestedSettingsSection = section
        activePage = .setup
    }

    func requestPublish(workspace: String) {
        pendingPublishWorkspace = workspace
    }

    func requestAddSubdomain() {
        activePage = .subdomains
        pendingAddSubdomain = true
    }

    /// The terminal a command such as "Send file" acts on: the selected
    /// session, or the focused cell of a stack.
    var currentTerminalKind: TerminalKind? {
        switch activePage {
        case nil:
            return selection?.terminalKind
        case let .stack(refs):
            let ref = FocusedTerminal.ref().flatMap { refs.contains($0) ? $0 : nil } ?? refs.first
            return ref.map { sidebarItem(for: $0).terminalKind }
        default:
            return nil
        }
    }

    var currentWorkspaceAlias: String? {
        switch currentTerminalKind {
        case let .remote(alias, _): return alias
        case .local: return Workspace.local.alias
        case nil: return nil
        }
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
    func beginTask(label: String, total: Int, showsCount: Bool = true) -> UUID {
        let id = UUID()
        activeTasks.append(
            BGTask(id: id, label: label, completed: 0, total: total, showsCount: showsCount))
        return id
    }

    private func bumpTask(_ id: UUID) {
        if let i = activeTasks.firstIndex(where: { $0.id == id }) {
            activeTasks[i].completed += 1
        }
    }

    /// Progress that arrives as a running total, such as bytes written.
    func setTask(_ id: UUID, completed: Int) {
        guard let i = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        guard activeTasks[i].completed != completed else { return }
        activeTasks[i].completed = completed
    }

    /// Drops the card at once, for a job that finished too fast to be worth a
    /// tick of "done": the 60s sweep would otherwise blink a card every minute.
    func dropTask(_ id: UUID) {
        activeTasks.removeAll { $0.id == id }
    }

    func flashToast(_ label: String) {
        finishTask(beginTask(label: label, total: 1))
    }

    func finishTask(_ id: UUID) {
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
        createRemoteSession(alias: alias, name: clean, directory: directory)
    }

    private func createRemoteSession(
        alias: String, name: String, directory: String, taskID: UUID? = nil, startup: SessionStartup = .configured
    ) {
        // Created here rather than left to the terminal's own `new-session -A`,
        // because only a session created up front can be told which directory to
        // start in, and harnesses resolve project files from that location.
        let store = self.store
        let startup = startupLine(startup, for: .remote(alias: alias, session: name))
        let sender = sessionCommandSender
        Task.detached {
            _ = try? store.run(
                alias: alias, command: RemoteCommands.createSession(name: name, directory: directory))
            if let startup {
                try? sender.send(startup, into: .remote(alias: alias, session: name))
            }
            await MainActor.run {
                self.selection = .session(alias: alias, name: name)
                if let taskID {
                    self.bumpTask(taskID)
                    self.finishTask(taskID)
                }
            }
        }
        // With no global poll, a single refresh can race the create, so re-poll
        // a few times until the new session shows up in the sidebar.
        for delay in [1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.refresh(alias: alias) }
        }
    }

    /// Runs at launch and from the gate page's "Check again" button. While the
    /// CLI is missing this only updates `cliMissing`, so the gate stays up and
    /// nothing below it starts. Once found, it falls through exactly where a
    /// normal launch would: Setup if unconfigured, else load the workspaces.
    func checkCLIAndProceed(isConfigured: Bool) {
        if DemoMode.isActive {
            seedDemoState()
            return
        }
        cliMissing = !cliAvailabilityCheck()
        guard !cliMissing else { return }
        if isConfigured {
            loadWorkspaces()
        } else {
            activePage = .setup
        }
    }

    /// `DEVMACHINE_DEMO=1`: skips the CLI gate, Setup, and every ssh/CLI call
    /// `loadWorkspaces()` would make, and instead seeds the sidebar directly
    /// from `DemoData`. Every terminal pane renders a static transcript
    /// (`TerminalRegistry.start` short-circuits the same way) instead of
    /// spawning mosh/ssh/zmx.
    private func seedDemoState() {
        cliMissing = false
        settings = .empty
        packageGate = .ok
        hasCaddyMachine = true
        activePage = nil
        guard !DemoMode.holdsLoading else { return }
        workspaces = DemoData.workspaces
        sessionsByAlias = DemoData.sessionsByAlias
        hasLoadedWorkspaces = true
        answeredAliases = Set(DemoData.workspaces.map(\.alias))
        let socketDirectory = Zmx.socketDirectory()
        localSessionHarnesses = Dictionary(uniqueKeysWithValues: DemoData.localSessionHarnesses.map { name, harnesses in
            (Zmx.sessionName(from: name, socketDirectory: socketDirectory), harnesses)
        })
        // `localSessions` (below) reads `DemoData.localSessions` directly in
        // demo mode; `addedLocalSessions` is left untouched so nothing here
        // is ever written to `UserDefaults`.
    }

    /// The loading demo's second stage: the workspace list is in, and only
    /// `answered` has its sessions; every other workspace is still waiting.
    func seedDemoWorkspacesAwaitingSessions(answered alias: String) {
        guard DemoMode.holdsLoading else { return }
        workspaces = DemoData.workspaces
        sessionsByAlias = DemoData.sessionsByAlias.filter { $0.key == alias }
        answeredAliases = [alias]
        hasLoadedWorkspaces = true
    }

    func loadWorkspaces() {
        guard let settings else { return }
        let detected = CLIAutoDetect.detect(cli: { try DevmachineCLI.resolve() })
        self.detected = detected
        var settingsWithAliases = settings
        settingsWithAliases.workspaceAliases = detected.workspaceAliases
        self.settings = settingsWithAliases
        workspaces = (try? services.workspaceSource.workspaces(
            resolveAlias: { settingsWithAliases.hostAlias(forWorkspace: $0) })) ?? []
        hasLoadedWorkspaces = true
        refreshAll()
        checkPackageGate()
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

    /// Runs at launch (`loadWorkspaces`) and from the package gate page's
    /// "Check again" button. Fails open: a `packages` read that itself fails
    /// leaves the gate as it was rather than blocking the app on a flaky CLI.
    func checkPackageGate() {
        Task {
            let state = await Task.detached {
                PackageGateChecker.check(cli: { try DevmachineCLI.resolve() })
            }.value
            self.packageGate = state
        }
        Task {
            let hasCaddy = await Task.detached {
                CaddyAvailabilityChecker.check(cli: { try DevmachineCLI.resolve() })
            }.value
            if let hasCaddy { self.hasCaddyMachine = hasCaddy }
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
        let sweepTask = beginTask(label: "Connecting workspaces…", total: targets.count)
        sweepTaskID = sweepTask
        for ws in targets { refreshingAliases.insert(ws.alias) }
        let source = services.sessionSource
        let settings = settings ?? .empty
        Task.detached {
            var remaining = targets[...]
            var stopped: SSHFailure?
            while let ws = remaining.first {
                remaining = remaining.dropFirst()
                let outcome = Result {
                    try source.sessions(for: ws, settings: settings)
                }
                let stop = await MainActor.run { () -> SSHFailure? in
                    let stop = self.apply(outcome, alias: ws.alias)
                    self.bumpTask(sweepTask)
                    return stop
                }
                if let stop { stopped = stop; break }
            }
            // The aliases the stopped sweep never reached share the same host,
            // so an unreachable host takes them with it. A refused login says
            // nothing about the host, so it leaves them as they were.
            let unreached = Array(remaining)
            await MainActor.run {
                if stopped == .unreachable {
                    for ws in unreached where !self.offlineAliases.contains(ws.alias) {
                        self.offlineAliases.insert(ws.alias)
                    }
                }
                for ws in unreached { self.markAnswered(ws.alias) }
                for ws in targets { self.refreshingAliases.remove(ws.alias) }
                self.sweepInFlight = false
                self.sweepTaskID = nil
                self.dropTask(sweepTask)
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
        let source = services.sessionSource
        let settings = settings ?? .empty
        Task.detached {
            let outcome = Result {
                try source.sessions(for: ws, settings: settings)
            }
            await MainActor.run {
                self.refreshingAliases.remove(alias)
                _ = self.apply(outcome, alias: alias)
            }
        }
    }

    // Returns the failure that must pause polling: the host or the ssh agent is
    // down. Nil means the sweep goes on.
    private func apply(_ outcome: Result<[TmuxSession], Error>, alias: String) -> SSHFailure? {
        markAnswered(alias)
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
            return nil
        case .failure(let error):
            let failure = (error as? SessionStoreError)?.failure
            // Red means the host does not answer. A login this Mac cannot sign
            // — a locked agent after waking — says nothing about the host, and
            // the sessions on it keep running: the bar already says polling is
            // paused, and a red dot on top of that is a lie that stays on
            // screen until the next successful sweep.
            if failure == .authDenied {
                offlineAliases.remove(alias)
            } else if !offlineAliases.contains(alias) {
                offlineAliases.insert(alias)
            }
            syncContext()
            guard let failure else { return nil }
            pausePolling(after: failure)
            return failure
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

    /// Provider context polls only while its tab is actually on screen.
    func syncContext() {
        guard showsContextPanel, !contextCollapsed, contextTab == .context,
              let target = selectedSessionTarget else {
            context.stop()
            updateSelectionPoll()
            return
        }
        context.start(target, harnesses: selectedSessionHarnesses, settings: settings ?? .empty)
        updateSelectionPoll()
    }

    var showsContextPanel: Bool { selection != nil && activePage == nil }

    /// Context, Files and Git share the selected session's current location.
    var selectedSessionTarget: CommandTarget? {
        switch selection {
        case let .session(alias, name):
            return .remote(alias: alias, session: name)
        case let .localSession(name, path):
            let session = localSessions.first { $0.handle == name }
            return .local(session: name, path: session.flatMap(localWorkingDirectory) ?? path)
        case nil:
            return nil
        }
    }

    private var selectedSessionHarnesses: Set<HarnessID> {
        switch selection {
        case let .session(alias, name):
            return sessionsByAlias[alias]?.first { $0.name == name }?.harnesses ?? []
        case let .localSession(name, _):
            let multiplexerName = Zmx.sessionName(from: name, socketDirectory: Zmx.socketDirectory())
            return localSessionHarnesses[multiplexerName] ?? []
        case nil:
            return []
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
