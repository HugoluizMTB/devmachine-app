import Foundation
import DevmachineCore

/// Every command ⌘K can run: a fixed set, each with the condition that makes
/// it available, plus the ones generated from the workspaces, sessions and
/// machines the app knows right now.
enum CommandRegistry {
    static let docsURL = URL(string: "https://mydevmachine.sh")!

    struct Entry {
        let command: PaletteCommand
        var isAvailable: (PaletteContext) -> Bool = { _ in true }
    }

    static func commands(in context: PaletteContext) -> [PaletteCommand] {
        fixed(context).filter { $0.isAvailable(context) }.map(\.command)
            + sessionCommands(context)
            + workspaceCommands(context)
            + previewCommands(context)
            + machineCommands(context)
            + settingsCommands()
    }

    private static let subdomainKeywords = ["dns", "domains", "caddy", "sites", "expose", "https", "publish"]
    private static let statsKeywords = ["ram", "memory", "disk", "cpu", "load", "containers", "usage"]

    private static func fixed(_ context: PaletteContext) -> [Entry] {
        let operatorSession = context.localSessions.first { $0.handle == Workspace.operatorSession }
        let publishWorkspace = context.currentWorkspace.flatMap { $0.isLocal ? nil : $0 }
        return [
            Entry(command: PaletteCommand(
                id: "go.home", title: "Home", subtitle: "", category: .goTo,
                systemImage: "house", shortcut: "⌘0", keywords: ["dashboard", "start"],
                action: .goHome)),
            Entry(command: PaletteCommand(
                id: "go.stats", title: "Stats", subtitle: "", category: .goTo,
                systemImage: "chart.bar", keywords: statsKeywords, action: .showPage(.stats))),
            Entry(
                command: PaletteCommand(
                    id: "go.subdomains", title: "Subdomains", subtitle: "", category: .goTo,
                    systemImage: "globe", keywords: subdomainKeywords, action: .showPage(.subdomains)),
                isAvailable: { $0.hasCaddyMachine }),
            Entry(command: PaletteCommand(
                id: "go.settings", title: "Settings", subtitle: "", category: .goTo,
                systemImage: "gearshape", shortcut: "⌘,",
                keywords: ["prefs", "preferences", "config", "options"],
                action: .openSettings(.connection))),
            Entry(command: PaletteCommand(
                id: "go.health", title: "Health", subtitle: "Settings", category: .goTo,
                systemImage: "stethoscope", keywords: ["doctor", "check", "status"],
                action: .openSettings(.advanced))),
            Entry(command: PaletteCommand(
                id: "go.shortcuts", title: "Keyboard shortcuts", subtitle: "", category: .goTo,
                systemImage: "keyboard", shortcut: "⌘?", keywords: ["keys", "hotkeys", "help"],
                action: .showShortcuts)),
            Entry(
                command: PaletteCommand(
                    id: "go.operator", title: "Operator session", subtitle: Workspace.local.name,
                    category: .goTo, systemImage: "person.crop.square", keywords: ["ops", "local"],
                    action: .openSession(.localSession(
                        name: Workspace.operatorSession, path: operatorSession?.path ?? NSHomeDirectory()))),
                isAvailable: { _ in operatorSession != nil }),
            Entry(command: PaletteCommand(
                id: "action.new-session", title: "New session…", subtitle: "", category: .action,
                systemImage: "plus.rectangle", shortcut: "⌘N", keywords: ["create", "open", "terminal"],
                action: .newQuickSession)),
            Entry(
                command: PaletteCommand(
                    id: "action.send-file", title: "Send file to current session…", subtitle: "",
                    category: .action, systemImage: "arrow.up.doc",
                    keywords: ["upload", "attach", "image", "scp", "paste", "drop", "drag"],
                    action: .sendFile(context.currentTerminal ?? .local(session: "", path: ""))),
                isAvailable: { $0.currentTerminal != nil }),
            Entry(
                command: PaletteCommand(
                    id: "action.end-session", title: "End session…", subtitle: "",
                    category: .action, systemImage: "xmark.rectangle", shortcut: "⌘W",
                    keywords: ["kill", "close", "stop", "delete", "remove", "quit"],
                    action: .endSession),
                isAvailable: { $0.endableSession != nil }),
            Entry(
                command: PaletteCommand(
                    id: "action.find-file", title: "Find file…", subtitle: "", category: .action,
                    systemImage: "doc.text.magnifyingglass", shortcut: "⌘P",
                    keywords: ["search", "open", "files"], action: .findFile),
                isAvailable: { $0.currentTerminal != nil }),
            Entry(
                command: PaletteCommand(
                    id: "action.publish-port", title: "Publish a port…",
                    subtitle: publishWorkspace?.name ?? "", category: .action,
                    systemImage: "network", keywords: subdomainKeywords + ["port"],
                    action: .publishPort(workspace: publishWorkspace?.name ?? "")),
                isAvailable: { $0.hasCaddyMachine && publishWorkspace != nil }),
            Entry(
                command: PaletteCommand(
                    id: "action.add-subdomain", title: "Add subdomain…",
                    subtitle: context.subdomainsMachine ?? "", category: .action,
                    systemImage: "plus.circle", keywords: subdomainKeywords,
                    action: .addSubdomain(machine: context.subdomainsMachine)),
                isAvailable: { $0.hasCaddyMachine && !$0.machines.isEmpty }),
            Entry(
                command: PaletteCommand(
                    id: "action.open-preview", title: "Open preview…", subtitle: "",
                    category: .action, systemImage: "safari", keywords: previewKeywords,
                    action: .openPreviewField),
                isAvailable: { $0.currentTerminal != nil }),
            Entry(command: PaletteCommand(
                id: "action.refresh", title: "Refresh", subtitle: "Current screen", category: .action,
                systemImage: "arrow.clockwise", keywords: ["reload", "update"], action: .refresh)),
            Entry(command: PaletteCommand(
                id: "action.toggle-sidebar", title: "Toggle workspaces sidebar", subtitle: "",
                category: .action, systemImage: "sidebar.left", shortcut: "⌘B",
                keywords: ["hide", "show", "panel"], action: .toggleSidebar)),
            Entry(command: PaletteCommand(
                id: "action.toggle-context", title: "Toggle context sidebar", subtitle: "",
                category: .action, systemImage: "sidebar.right", shortcut: "⌘J",
                keywords: ["hide", "show", "panel", "git", "files"], action: .toggleContext)),
            Entry(command: PaletteCommand(
                id: "action.back", title: "Back", subtitle: "", category: .action,
                systemImage: "chevron.left", shortcut: "⇧⌘←", keywords: ["previous", "history"],
                action: .back)),
            Entry(command: PaletteCommand(
                id: "action.forward", title: "Forward", subtitle: "", category: .action,
                systemImage: "chevron.right", shortcut: "⇧⌘→", keywords: ["next", "history"],
                action: .forward)),
            Entry(command: PaletteCommand(
                id: "action.previous-session", title: "Previous session", subtitle: "",
                category: .action, systemImage: "arrow.up", shortcut: "⇧⌘↑", action: .previousSession)),
            Entry(command: PaletteCommand(
                id: "action.next-session", title: "Next session", subtitle: "",
                category: .action, systemImage: "arrow.down", shortcut: "⇧⌘↓", action: .nextSession)),
            Entry(
                command: PaletteCommand(
                    id: "action.maximize", title: "Maximize pane", subtitle: "", category: .action,
                    systemImage: "arrow.up.left.and.arrow.down.right", shortcut: "⇧⌘↩",
                    keywords: ["grid", "stack", "zoom"], action: .maximizePane),
                isAvailable: { context in
                    if case .stack = context.activePage { return true }
                    return context.currentTerminal != nil
                }),
            Entry(command: PaletteCommand(
                id: "action.pick-color", title: "Pick a color from the screen", subtitle: "Copies its hex",
                category: .action, systemImage: "eyedropper",
                keywords: ["color", "colour", "eyedropper", "picker", "hex", "sample"], action: .pickColor)),
            Entry(command: PaletteCommand(
                id: "action.docs", title: "Open docs", subtitle: "mydevmachine.sh", category: .action,
                systemImage: "book", keywords: ["help", "manual", "documentation", "website"],
                action: .openURL(docsURL))),
            Entry(command: PaletteCommand(
                id: "action.check-updates", title: "Check for Updates…", subtitle: "Devmachine",
                category: .action, systemImage: "arrow.down.circle",
                keywords: ["update", "upgrade", "version", "release", "new"], action: .checkForUpdates)),
            Entry(
                command: PaletteCommand(
                    id: "action.update-cli", title: "Update the devmachine CLI",
                    subtitle: context.cliUpdate.map { "\($0.installed) installed" } ?? "",
                    category: .action, systemImage: "terminal",
                    keywords: ["upgrade", "version", "brew", "cli", "release"],
                    badgeText: context.cliUpdate?.latest.description, action: .openSettings(.about)),
                isAvailable: { $0.cliUpdate != nil }),
            Entry(command: PaletteCommand(
                id: "action.quit", title: "Quit Devmachine", subtitle: "", category: .action,
                systemImage: "power", shortcut: "⌘Q", keywords: ["exit", "close"], action: .quit)),
        ]
    }

    private static func sessionCommands(_ context: PaletteContext) -> [PaletteCommand] {
        context.sessions.map { item in
            PaletteCommand(
                id: "session.\(item.id)", title: item.title, subtitle: item.subtitle,
                category: .session, systemImage: "terminal", keywords: ["switch", "jump"],
                badges: item.badges, action: .openSession(item.target))
        }
    }

    private static func workspaceCommands(_ context: PaletteContext) -> [PaletteCommand] {
        (context.workspaces + [.local]).flatMap { workspace in
            workspaceCommands(workspace, context: context)
        }
    }

    private static func workspaceCommands(_ workspace: Workspace, context: PaletteContext) -> [PaletteCommand] {
        let alias = workspace.alias
        let prefix = "ws.\(alias)"
        let keywords = [workspace.name, "workspace"]
        var commands = context.launchOptions.map { option in
            PaletteCommand(
                id: "\(prefix).new.\(option.id)", title: "New \(option.title) session",
                subtitle: workspace.name, category: .workspace, systemImage: option.systemImage,
                keywords: keywords + ["new", "start", "create", option.shortTitle],
                action: .newSession(alias: alias, choice: option.choice))
        }
        commands += (context.savedCommands[alias] ?? []).map { command in
            PaletteCommand(
                id: "\(prefix).run.\(command)", title: "Run \(command)", subtitle: workspace.name,
                category: .workspace, systemImage: "chevron.forward.square",
                keywords: keywords + ["new", "session", "command", "saved"],
                action: .runSavedCommand(alias: alias, command: command))
        }
        commands.append(PaletteCommand(
            id: "\(prefix).custom", title: "Custom command…", subtitle: workspace.name,
            category: .workspace, systemImage: "square.and.pencil",
            keywords: keywords + ["new", "session", "run", "type"], action: .customCommand(alias: alias)))
        commands.append(PaletteCommand(
            id: "\(prefix).home", title: "Open workspace home", subtitle: workspace.name,
            category: .workspace, systemImage: "rectangle.grid.2x2",
            keywords: keywords + ["grid", "stack", "all sessions"], action: .workspaceHome(alias: alias)))
        if workspace.isLocal {
            commands += context.localSessions.map { session in
                PaletteCommand(
                    id: "\(prefix).reveal.\(session.handle)", title: "Reveal \(session.name) in Finder",
                    subtitle: workspace.name, category: .workspace, systemImage: "folder",
                    keywords: keywords + ["finder", "folder", "show"],
                    action: .revealInFinder(path: session.path))
            }
        } else {
            commands.append(PaletteCommand(
                id: "\(prefix).named", title: "New named session…", subtitle: workspace.name,
                category: .workspace, systemImage: "plus.rectangle",
                keywords: keywords + ["new", "create", "session"], action: .newNamedSession(alias: alias)))
            commands.append(PaletteCommand(
                id: "\(prefix).files", title: "Files…", subtitle: workspace.name,
                category: .workspace, systemImage: "folder",
                keywords: keywords + ["browse", "upload", "download"], action: .openFiles(alias: alias)))
            if context.hasCaddyMachine {
                commands.append(PaletteCommand(
                    id: "\(prefix).publish", title: "Publish a port…", subtitle: workspace.name,
                    category: .workspace, systemImage: "network",
                    keywords: keywords + subdomainKeywords + ["port"],
                    action: .publishPort(workspace: workspace.name)))
            }
        }
        return commands
    }

    private static let previewKeywords = ["browser", "web", "localhost", "dev server", "port", "tunnel", "open"]

    private static func previewCommands(_ context: PaletteContext) -> [PaletteCommand] {
        context.previewTargets.flatMap { group -> [PaletteCommand] in
            let name: String
            switch group.place {
            case .thisMac: name = "This Mac"
            case let .workspace(workspace): name = workspace
            }
            return group.targets.map { target in
                switch target.kind {
                case let .port(port):
                    return PaletteCommand(
                        id: "preview.\(group.place.key).port.\(port)", title: "Preview \(name) port \(port)",
                        subtitle: target.label, category: .workspace, systemImage: "play.display",
                        keywords: previewKeywords + [name, target.label],
                        action: .preview(PreviewRequest(place: group.place, input: .port(port, path: ""))))
                case let .site(host):
                    return PaletteCommand(
                        id: "preview.\(group.place.key).site.\(host)", title: "Preview \(host)",
                        subtitle: name, category: .workspace, systemImage: "globe",
                        keywords: previewKeywords + [name, "site", "https"],
                        action: .preview(PreviewRequest(
                            place: group.place, input: .url(target.siteURL ?? URL(string: "https://\(host)")!))))
                }
            }
        }
    }

    private static func machineCommands(_ context: PaletteContext) -> [PaletteCommand] {
        var commands = context.machines.flatMap { machine -> [PaletteCommand] in
            var list = [PaletteCommand(
                id: "machine.\(machine).stats", title: "Stats for \(machine)", subtitle: "",
                category: .machine, systemImage: "chart.bar", keywords: [machine] + statsKeywords,
                action: .stats(machine: machine))]
            list.append(PaletteCommand(
                id: "machine.\(machine).host-key", title: "Check SSH host key for \(machine)", subtitle: "",
                category: .machine, systemImage: "key", keywords: [machine, "ssh", "host key", "fingerprint", "trust"],
                action: .hostKey(machine: machine)))
            if context.hasCaddyMachine {
                list.append(PaletteCommand(
                    id: "machine.\(machine).subdomains", title: "Subdomains on \(machine)",
                    subtitle: "", category: .machine, systemImage: "globe",
                    keywords: [machine] + subdomainKeywords, action: .subdomains(machine: machine)))
                list.append(PaletteCommand(
                    id: "machine.\(machine).add-subdomain", title: "Add subdomain on \(machine)…",
                    subtitle: "", category: .machine, systemImage: "plus.circle",
                    keywords: [machine] + subdomainKeywords, action: .addSubdomain(machine: machine)))
            }
            return list
        }
        commands.append(PaletteCommand(
            id: "machine.health", title: "Run health check", subtitle: "Every machine",
            category: .machine, systemImage: "stethoscope", keywords: ["doctor", "check", "status"],
            action: .runHealthCheck))
        return commands
    }

    private static func settingsCommands() -> [PaletteCommand] {
        SettingsSection.allCases.map { section in
            PaletteCommand(
                id: "settings.\(section.rawValue)", title: section.title, subtitle: "Settings",
                category: .settings, systemImage: section.systemImage,
                keywords: ["settings", "prefs", "preferences", section.subtitle],
                action: .openSettings(section))
        }
    }
}
