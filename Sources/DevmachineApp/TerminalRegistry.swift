import AppKit
import Foundation
import SwiftTerm
import DevmachineCore

/// One live terminal (and one mosh/tmux client) per session for the whole app.
/// SwiftUI containers come and go — single pane, stack grid — and re-attach
/// the same view, so switching layouts never reconnects.
@MainActor
final class TerminalRegistry: NSObject {
    static let shared = TerminalRegistry()
    /// How many detached terminals (and their clients) to keep around. Settable,
    /// because the right number is one per workspace plus the local ones: at
    /// six, moving between workspaces closed clients behind you, and coming
    /// back showed `[mosh is exiting.]` instead of the session.
    static var detachedLimit: Int {
        Appearance.clampKeptTerminals(
            SettingsStore.shared.settings?.keptTerminals ?? Appearance.defaultKeptTerminals)
    }

    private var terminals: [TerminalKind: LocalProcessTerminalView] = [:]
    private var optionKeyMonitor: Any?
    private var detachedAt: [TerminalKind: Date] = [:]
    /// Terminals whose process ended on its own — a dropped connection, a shell
    /// that exited. The view is kept so returning to it reconnects in place.
    private var dead: Set<TerminalKind> = []
    /// Views built but not started yet. A process must not begin while the view
    /// still has its placeholder size: whatever runs inside draws the screen for
    /// the size it is told at startup, and a program that repaints only on its
    /// own schedule never corrects it.
    private var awaitingSize: Set<TerminalKind> = []
    /// Panes that were put away and are now back on screen.
    private var reattached: Set<TerminalKind> = []
    private(set) var pendingFocusKind: TerminalKind?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { TerminalRegistry.shared.closeAll() }
        }
        installOptionKeyMonitor()
    }

    /// Option composes accents on this Mac (U.S. layout: ⌥c is ç, ⌥e a is á), so
    /// the terminals run with `optionAsMetaKey = false`. Arrows and other function
    /// keys still need Meta, or the shell loses word jumps — flip the flag for the
    /// length of those events only.
    private func installOptionKeyMonitor() {
        optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { () -> Bool in
                let registry = TerminalRegistry.shared
                // SwiftTerm's `keyDown` is not open, so Shift+Enter is answered
                // here: the focused terminal gets the newline byte and the event
                // stops, or the legacy encoding would send a plain Return.
                if TerminalKeyboard.sendsNewline(keyCode: keyCode, flags: flags),
                   let focused = registry.focusedTerminal() {
                    focused.send(TerminalKeyboard.newlineBytes)
                    return true
                }
                // A page key is answered by the terminal itself, which scrolls
                // its own buffer. That is right for a session running here, and
                // wrong for one inside tmux: the buffer holds a single screen,
                // so nothing moves and the host never sees the key.
                if let bytes = TerminalKeyboard.pageKeyBytes(keyCode: keyCode, flags: flags),
                   let (kind, view) = registry.focusedEntry(),
                   case .remote = kind {
                    view.send(bytes)
                    return true
                }
                // An image on the clipboard cannot be typed into a terminal,
                // and the agent reads the clipboard of the machine it runs on,
                // which for a remote session is not this Mac. So the bytes are
                // written over there and the path is typed instead.
                // The terminal answers ⌘F itself by doing nothing, and the
                // pane has no other way to reach SwiftTerm's search.
                if TerminalKeyboard.opensFind(keyCode: keyCode, flags: flags),
                   let (kind, _) = registry.focusedEntry() {
                    AppModel.shared?.findTarget = kind
                    return true
                }
                if TerminalKeyboard.pastesClipboard(keyCode: keyCode, flags: flags),
                   let (kind, _) = registry.focusedEntry(),
                   let image = ImagePasteService.image(from: .general) {
                    registry.pasteImage(image, into: kind)
                    return true
                }
                guard TerminalKeyboard.optionActsAsMeta(for: flags) else { return false }
                for term in registry.terminals.values where term.window?.firstResponder === term {
                    term.optionAsMetaKey = true
                    DispatchQueue.main.async { term.optionAsMetaKey = false }
                }
                return false
            }
            return handled ? nil : event
        }
    }

    /// ⌘-click opens the link, ⌘⇧-click copies it. A link that names no page
    /// and no file on this Mac is dropped, and the log says which one: what a
    /// terminal prints is text from elsewhere, not a command for this Mac.
    func openLink(_ link: String, from kind: TerminalKind?, flags: NSEvent.ModifierFlags) {
        var folder: String?
        if case let .local(_, path) = kind { folder = path }
        guard let target = TerminalLink.target(for: link, folder: folder) else {
            PaneLog.log("dropped link \(link)")
            return
        }
        guard !flags.contains(.shift) else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(target.text, forType: .string)
            return
        }
        switch target {
        case let .web(url): NSWorkspace.shared.open(url)
        case let .file(path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    /// Searches the pane's own scrollback and selects the match.
    @discardableResult
    func find(_ term: String, in kind: TerminalKind, forward: Bool) -> Bool {
        let clean = term.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let view = terminals[kind] else { return false }
        return forward ? view.findNext(clean) : view.findPrevious(clean)
    }

    /// Drops the highlight and gives the keyboard back to the session.
    func endFind(in kind: TerminalKind) {
        terminals[kind]?.clearSearch()
        requestFocus(kind)
    }

    /// The terminal that currently owns the keyboard, if any.
    private func focusedTerminal() -> LocalProcessTerminalView? {
        focusedEntry()?.view
    }

    private func focusedEntry() -> (kind: TerminalKind, view: LocalProcessTerminalView)? {
        for (kind, view) in terminals where view.window?.firstResponder === view {
            return (kind, view)
        }
        return nil
    }

    /// Stores the image where the session's agent can read it, then types the
    /// path without a newline: the sentence around it is yours to write.
    private func pasteImage(_ image: (data: Data, fileExtension: String), into kind: TerminalKind) {
        let service = ImagePasteService(runner: ProcessRunner())
        let model = AppModel.shared
        model?.beginTransfer(label: Self.sendingLabel(for: kind), total: image.data.count)
        Task.detached {
            let path = try? service.store(
                image.data, fileExtension: image.fileExtension, on: kind,
                onBytesWritten: { written in
                    Task { @MainActor in AppModel.shared?.advanceTransfer(done: written) }
                }
            )
            await MainActor.run {
                AppModel.shared?.endTransfer()
                guard let path, let view = TerminalRegistry.shared.terminals[kind] else { return }
                view.send(txt: path + " ")
            }
        }
    }

    static func sendingLabel(for kind: TerminalKind) -> String {
        switch kind {
        case let .remote(alias, _): return "Sending image to \(alias)…"
        case .local: return "Saving image…"
        }
    }

    func terminal(for kind: TerminalKind) -> LocalProcessTerminalView {
        detachedAt[kind] = nil
        if let live = terminals[kind] {
            reviveIfDead(kind, view: live)
            return live
        }
        let term = LegacyKeyboardTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        term.processDelegate = self
        term.optionAsMetaKey = false
        term.kind = kind
        // ⌘ and a click, the way every other Mac terminal opens a link. A plain
        // click stays what it is, so clicking a web address inside a program
        // that reads the mouse still reaches the program.
        term.linkHighlightMode = .hoverWithModifier
        // Explicit hyperlinks plus bare addresses: the local multiplexer loses
        // the hyperlink when it repaints its screen, and the text is all that
        // is left to match.
        term.linkReporting = .implicit
        awaitingSize.insert(kind)
        terminals[kind] = term
        return term
    }

    /// No SwiftUI pane shows this terminal any more. It keeps running, and the
    /// longest-detached ones are closed once too many pile up — tmux holds the
    /// session server-side, so opening it again reconnects.
    func detach(_ kind: TerminalKind) {
        guard terminals[kind] != nil else { return }
        PaneLog.log("detach pane=\(kind)")
        reattached.insert(kind)
        detachedAt[kind] = Date()
        for stale in LRUEviction.keysToEvict(detachedAt: detachedAt, cap: Self.detachedLimit) {
            close(stale)
        }
    }

    /// Give the keyboard to this session as soon as its view is on screen. The
    /// request comes from an explicit user action (opening a session); mounting
    /// alone must never grab focus, or SwiftUI loses the sidebar's clicks.
    func requestFocus(_ kind: TerminalKind) {
        pendingFocusKind = kind
        applyPendingFocus()
    }

    /// A pane just put the shared view back in a window.
    func viewDidAttach(_ kind: TerminalKind) {
        if let view = terminals[kind] {
            reviveIfDead(kind, view: view)
            view.requestRedraw()
        }
        guard pendingFocusKind == kind else { return }
        // Next runloop: SwiftUI is still mid-layout, and taking first responder
        // inside it is what used to make the sidebar unclickable.
        DispatchQueue.main.async { [weak self] in self?.applyPendingFocus() }
    }

    private func applyPendingFocus() {
        guard let kind = pendingFocusKind,
              let term = terminals[kind],
              let window = term.window
        else { return }
        pendingFocusKind = nil
        // A sheet (rename, new session, setup) owns the keyboard while it is up.
        guard window.isKeyWindow else { return }
        window.makeFirstResponder(term)
    }

    /// Called by the pane once the view has the size it will be drawn at. This
    /// is when a process may begin: it then learns the real number of rows and
    /// columns from its first breath.
    func viewDidSize(_ kind: TerminalKind) {
        if awaitingSize.remove(kind) != nil, let term = terminals[kind] {
            start(kind, in: term)
            return
        }
        redrawAfterReattach(kind)
    }

    /// A pane that comes back at the size it left gets no size change, so the
    /// program inside is never told to draw again and the screen stays as it
    /// was left, which can be nearly empty. Each multiplexer is asked to repaint
    /// in its own way.
    /// Asks the program in a pane to draw its screen again, for a pane that is
    /// back on screen without anything having changed.
    func requestRepaint(_ kind: TerminalKind) {
        guard terminals[kind] != nil else { return }
        reattached.insert(kind)
        redrawAfterReattach(kind)
    }

    private func redrawAfterReattach(_ kind: TerminalKind) {
        terminals[kind]?.requestRedraw()
        guard reattached.remove(kind) != nil else { return }
        switch kind {
        case let .remote(alias, session):
            PaneLog.log("refresh pane=\(kind)")
            Task.detached {
                _ = try? ProcessRunner().run(
                    executable: "/usr/bin/ssh",
                    args: RemoteCommands.sshBaseArgs(alias: alias)
                        + [RemoteCommands.refreshClient(session: session)],
                    environment: RemoteCommands.sshEnvironment())
            }
        case let .local(session, _):
            // No refresh command in the local multiplexer, so the program is
            // asked directly with the window-changed signal — the same one a
            // resize sends. Nothing is killed and no size changes.
            guard let zmx = LocalTools.zmxPath() else { return }
            PaneLog.log("repaint pane=\(kind)")
            let socketDirectory = Zmx.socketDirectory()
            let name = Zmx.sessionName(from: session, socketDirectory: socketDirectory)
            Task.detached {
                let runner = ProcessRunner()
                guard let listing = try? runner.run(
                    executable: zmx, args: Zmx.listArguments,
                    environment: ["ZMX_DIR": socketDirectory]),
                    let pid = Zmx.pid(of: name, in: listing),
                    let tpgid = try? runner.run(
                        executable: "/bin/ps", args: ProcessTree.tpgidArguments(pid: pid),
                        environment: nil),
                    let group = ProcessTree.foregroundGroup(fromTPGID: tpgid)
                else { return }
                _ = try? runner.run(
                    executable: "/bin/kill",
                    args: ProcessTree.windowChangedArguments(group: group),
                    environment: nil)
            }
        }
    }

    /// Starts the process again in the same view, so the pane you return to
    /// shows the session instead of the message its client left behind.
    private func reviveIfDead(_ kind: TerminalKind, view: LocalProcessTerminalView) {
        guard dead.contains(kind) else { return }
        PaneLog.log("revive pane=\(kind)")
        dead.remove(kind)
        start(kind, in: view)
    }

    /// Told when a session ends for good, so the app can drop its row and let
    /// the layout close over the gap.
    var onSessionEnded: ((TerminalKind) -> Void)?

    func close(_ kind: TerminalKind) {
        PaneLog.log("close pane=\(kind)")
        dead.remove(kind)
        awaitingSize.remove(kind)
        reattached.remove(kind)
        detachedAt[kind] = nil
        if pendingFocusKind == kind { pendingFocusKind = nil }
        guard let term = terminals.removeValue(forKey: kind) else { return }
        term.terminate()
        term.removeFromSuperview()
    }

    func close(alias: String, session: String) {
        close(.remote(alias: alias, session: session))
    }

    /// Ends the multiplexer session behind a local pane, so removing a session
    /// from the sidebar removes the shell too.
    func killLocalSession(named name: String) {
        guard let zmx = LocalTools.zmxPath() else { return }
        let socketDirectory = Zmx.socketDirectory()
        let session = Zmx.sessionName(from: name, socketDirectory: socketDirectory)
        Task.detached {
            _ = try? ProcessRunner().run(
                executable: zmx,
                args: Zmx.killArguments(name: session),
                environment: ["ZMX_DIR": socketDirectory]
            )
        }
    }

    /// Every pane of one workspace, closed together: hiding a workspace should
    /// end the connections it holds, not only stop drawing them.
    func closeWorkspace(alias: String) {
        for kind in Array(terminals.keys) {
            if case let .remote(paneAlias, _) = kind, paneAlias == alias { close(kind) }
        }
    }

    func closeAll() {
        for kind in Array(terminals.keys) { close(kind) }
    }

    private func start(_ kind: TerminalKind, in term: LocalProcessTerminalView) {
        PaneLog.log("start pane=\(kind)")
        switch kind {
        case let .remote(alias, session):
            // Interactive: mosh (survives roaming/drops). Tailscale only
            // (UDP on tailscale0). Falls back to ssh if mosh isn't on the Mac.
            let mosh = "/opt/homebrew/bin/mosh"
            if FileManager.default.isExecutableFile(atPath: mosh) {
                term.startProcess(
                    executable: mosh,
                    args: [alias, "--", "tmux", "new-session", "-A", "-s", session],
                    environment: RemoteCommands.terminalEnvironment(term: RemoteCommands.remoteTerm)
                )
            } else {
                term.startProcess(
                    executable: "/usr/bin/ssh",
                    args: [alias, "-t", RemoteCommands.newSession(name: session)],
                    environment: RemoteCommands.terminalEnvironment(term: RemoteCommands.remoteTerm)
                )
            }
        case let .local(session, path):
            // The multiplexer holds the shell, so the session survives the app.
            // Without it the pane is still usable, just not persistent.
            guard let zmx = LocalTools.zmxPath() else {
                term.startProcess(
                    executable: "/bin/zsh",
                    args: ["-i", "-l"],
                    environment: RemoteCommands.terminalEnvironment(),
                    execName: "-zsh",
                    currentDirectory: path
                )
                return
            }
            let socketDirectory = Zmx.socketDirectory()
            term.startProcess(
                executable: zmx,
                args: Zmx.attachArguments(
                    name: Zmx.sessionName(from: session, socketDirectory: socketDirectory)),
                environment: Zmx.environment(socketDirectory: socketDirectory),
                // The session's own directory comes from here: the multiplexer
                // starts the shell in the directory it was launched from.
                currentDirectory: path
            )
        }
    }
}

extension TerminalRegistry: @preconcurrency LocalProcessTerminalViewDelegate {
    /// The size the program itself is told. The pane's frame in points is not
    /// that number, and the difference is what a half-drawn screen is made of.
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        let kind = terminals.first { $0.value === source }?.key
        PaneLog.log("pty size pane=\(kind.map(String.init(describing:)) ?? "?") "
            + "cols=\(newCols) rows=\(newRows)")
    }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    // A dead process must not be handed out again: the next mount starts a
    // fresh one.
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // The view stays: the session it was showing usually outlived the
        // client (tmux and zmx both do), so coming back should reconnect rather
        // than leave a dead screen or lose the pane.
        guard let kind = terminals.first(where: { $0.value === source })?.key else { return }
        PaneLog.log("process ended pane=\(kind) exit=\(exitCode.map(String.init) ?? "-")")
        dead.insert(kind)
        detachedAt[kind] = nil
        if case let .local(session, _) = kind {
            closeIfSessionIsGone(kind, session: session)
        }
    }

    /// Telling the two endings apart: the client stopped, or the shell itself
    /// ended (`exit`). Only the multiplexer knows, so it is asked. A session
    /// that is gone takes its pane with it.
    private func closeIfSessionIsGone(_ kind: TerminalKind, session: String) {
        guard let zmx = LocalTools.zmxPath() else {
            // No multiplexer: the shell was the session, so it ended with it.
            sessionDidEnd(kind)
            return
        }
        let socketDirectory = Zmx.socketDirectory()
        let name = Zmx.sessionName(from: session, socketDirectory: socketDirectory)
        Task.detached {
            let listing = (try? ProcessRunner().run(
                executable: zmx, args: Zmx.listArguments,
                environment: ["ZMX_DIR": socketDirectory])) ?? ""
            let alive = ZmxListParser.parse(listing).contains { $0.name == name }
            guard !alive else { return }
            await MainActor.run { TerminalRegistry.shared.sessionDidEnd(kind) }
        }
    }

    private func sessionDidEnd(_ kind: TerminalKind) {
        PaneLog.log("session ended pane=\(kind)")
        close(kind)
        onSessionEnded?(kind)
    }
}

// Claude Code 2.1.269+ turns on the kitty keyboard protocol wherever it can,
// and tmux forwards it to any client whose XTVERSION reply says "XTerm(...)".
// SwiftTerm's kitty encoding still breaks Enter and dead keys, so the view
// drops both replies: programs keep the legacy encoding this app always ran.
final class LegacyKeyboardTerminalView: LocalProcessTerminalView {
    /// The session this view shows, so a link can be resolved in its folder.
    var kind: TerminalKind?

    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        TerminalRegistry.shared.openLink(link, from: kind, flags: NSEvent.modifierFlags)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        let find = NSMenuItem(title: "Find…", action: #selector(openFind), keyEquivalent: "f")
        find.target = self
        menu.addItem(find)
        return menu
    }

    @objc private func openFind() {
        guard let kind else { return }
        AppModel.shared?.findTarget = kind
    }

    /// The rows and columns handed to the program, logged as they are. An
    /// earlier version refused small sizes and returned the last good one; that
    /// made SwiftTerm believe the program had already been told the real size,
    /// so when the pane settled nothing was sent and every pane stayed blank.
    override func getWindowSize() -> winsize {
        let size = super.getWindowSize()
        PaneLog.log("window size cols=\(size.ws_col) rows=\(size.ws_row)")
        return size
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let filtered = TerminalReplyFilter.strip(Array(data))
        guard !filtered.isEmpty else { return }
        super.send(source: source, data: filtered[...])
    }
}

/// Tools the app carries in its own bundle rather than expecting on the Mac.
enum LocalTools {
    static func zmxPath(
        bundle: Bundle = .main,
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        guard let url = bundle.url(forResource: "zmx", withExtension: nil, subdirectory: "zmx"),
              exists(url.path)
        else { return nil }
        return url.path
    }
}

enum TerminalKeyboard {
    /// Option means Meta only together with a function key (arrows, F-keys); on
    /// its own it is the accent composer of the Mac's keyboard layout.
    static func optionActsAsMeta(for flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && flags.contains(.function)
    }

    /// ⌘F, and only ⌘F: ⌥⌘F and ⌃⌘F belong to whatever runs in the session.
    static func opensFind(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == findKeyCode
            && flags.contains(.command)
            && !flags.contains(.option) && !flags.contains(.control) && !flags.contains(.shift)
    }

    static let findKeyCode: UInt16 = 3

    static let returnKeyCode: UInt16 = 36

    /// Ctrl+J, which Claude Code reads as "insert a newline" in every terminal.
    static let newlineBytes: [UInt8] = [0x0A]

    static let pageUpKeyCode: UInt16 = 116
    static let pageDownKeyCode: UInt16 = 121

    /// What a terminal sends for Page Up and Page Down. Plain keys only: with a
    /// modifier they mean something else (⇧⇞ is the terminal's own scroll).
    static func pageKeyBytes(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> [UInt8]? {
        guard flags.intersection([.command, .control, .shift, .option]).isEmpty else { return nil }
        switch keyCode {
        case pageUpKeyCode: return Array("\u{1b}[5~".utf8)
        case pageDownKeyCode: return Array("\u{1b}[6~".utf8)
        default: return nil
        }
    }

    /// The legacy key encoding this app keeps on purpose cannot tell Shift+Enter
    /// from Enter, so the terminal sends the newline byte itself. Enter alone
    /// still submits, and Command+Shift+Return stays an app shortcut.
    static let vKeyCode: UInt16 = 9

    /// Command+V, the paste the app answers itself when the clipboard holds an
    /// image. Everything else still reaches SwiftTerm's own paste.
    static func pastesClipboard(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        return keyCode == vKeyCode
            && mods.contains(.command)
            && !mods.contains(.shift)
            && !mods.contains(.control)
            && !mods.contains(.option)
    }

    static func sendsNewline(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        return keyCode == returnKeyCode
            && mods.contains(.shift)
            && !mods.contains(.command)
            && !mods.contains(.control)
            && !mods.contains(.option)
    }
}
