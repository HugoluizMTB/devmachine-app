# Coding agents, Chats and the Operator session

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Coding agents (`harness` in code)

The UI and prose say **coding agent** (Settings → Coding agents, "Show
coding agent icon…", the widget field "Coding agent"). Code and JSON keep
`harness` (`CodingHarness`, `HarnessID`, `harnesses`).

- **Detection never depends on the toggle.** Every harness in
  `HarnessRegistry.builtIn` is detected, badged, gets its icon, upload folder
  and Context panel, enabled or not and whether or not its CLI is on this Mac:
  many run only on a server. Enabling one only adds it to the launch choices
  and session defaults (and its usage card), and never needs its CLI here.
- **Identifying a harness and activating it are different.** Identification
  (icons, Context, process matching) covers every harness in the registry
  and never looks at packages. Activation is the Settings → Coding agents switch,
  shown only for a harness whose `HarnessDescriptor.packageName` (the
  workspace package that installs it: claude-code, codex, pi, antigravity,
  opencode, kimi-code, cline) is in the pinned release's
  `packages list` (`CodingAgentPackages.activatable`; before the list is
  read, the declared name is trusted). Any other harness shows its row with
  no switch, and its saved on/off is left as it was. New workspace's
  Coding agents group offers only the packages of harnesses turned on
  (`CodingAgentPackages.choose`), hides the others and what needs them
  (claude-plugins needs claude-code), and with none on says so and links to
  Settings → Coding agents. The first run's skills picker is unrelated: it offers what
  `skills add --agent` accepts (`SkillAgent`). Views never name a package.
- **A harness on without its CLI on this Mac starts on remote workspaces
  only** (`LaunchPlace`): it is offered in the remote fallback, the
  per-workspace defaults and a remote workspace's new-session menu and ⌘K
  commands, never for Local. A Local default naming one starts a plain
  shell (`HarnessSettingsFacade.localSessionProgram`), the way a harness
  turned off does, and its Settings row says "Not on this Mac — remote
  workspaces only". Whether a CLI is here comes from `CLIAvailability`:
  looked up (a missing one costs a login shell) off the main thread at launch
  and when Settings opens, then cached; only a read before the first lookup
  ends pays for it itself.
- Local has one Terminal-or-coding-agent default (Settings → Coding agents →\n  Session defaults → Local). Remote workspaces inherit one
  remote fallback and may override it individually.
- Remote choices are declarative. Never probe or modify a VPS to validate a
  harness; its shell reports a missing command when the session starts.
- Session badges, launch commands, process matching, upload storage, context
  support, and usage capabilities come from adapters/facades. Views do not
  switch on Claude, Codex, executable names, or provider colors.
- Home stacks one usage card per enabled harness that has a usage provider
  (Claude, Codex; the others have none). A harness whose CLI is not
  found still gets its card, showing "CLI not found", so Home never disagrees
  with Settings. The CLI is looked up on every read: inherited PATH, known
  directories, then the login shell's `command -v` (mise/asdf/nvm installs an
  app opened from Finder cannot see); Codex runs with its own directory first
  on PATH so an npm `#!/usr/bin/env node` script finds `node`. The
  menu-bar Usage tab uses one column for one harness and two columns for two;
  the Pull Requests tab remains 420 points wide.
- Codex usage reads `account/rateLimits/read` and `account/usage/read` through
  `codex app-server`. It never calls `thread/start` or `turn/start`, so the
  refresh does not start a model turn or consume inference tokens.
- Sidebar coding agent icons (Settings → Coding agents → Sidebar, off by default) are files in
  `Resources/HarnessIcons/`, loaded by name (`HarnessIconLibrary`): a new
  harness gets its icon by adding a file. `<HarnessID>.svg` is always the
  monochrome drawing in `currentColor` (it takes the row's tint, and every
  built-in harness must have one); `<HarnessID>-color.svg` is the optional
  brand-color version. Settings → Coding agents → Icon style
  (`AppSettings.harnessIconStyle`, `.color` by default) picks it: Original
  colors uses `-color` when it exists, else the monochrome file; Monochrome
  never reads `-color`. A `-color` name is never a harness id. No monochrome
  file → no icon, the hover dot stays. A session with no harness at all shows
  the `apple.terminal` symbol in the same slot. Brand colors exist for Claude,
  Codex, Antigravity, Kimi and Herdr; Pi, opencode and Cline are black and
  white anyway.
  Claude, Codex and Pi come from Orca (MIT, `LICENSE-orca.txt`); codex-color,
  Antigravity, opencode, Kimi and Cline from lobe-icons (MIT,
  `LICENSE-lobe-icons.txt`); Herdr from its own repo (Apache-2.0,
  `LICENSE-herdr.txt`). A new icon names its source in one of those files.
- **Herdr is a harness with no package.** It is the runtime agents run in,
  not an agent: a session that started `herdr` is known by it and gets its
  icon, but it has no Settings switch (`packageName` nil), no skills option
  and no Context reader.
  `DEVMACHINE_DEMO_ICON_STYLE=monochrome` switches the `harness-icons` demo walk.
- The Context / Files / Git panel belongs to every selected session. Unsupported
  provider context shows an empty state while Files and Git remain available.
- **Context reads a harness through one `ContextHarnessReader`** (Core,
  `ContextRoots.readers`, the one table): it finds the project's sessions,
  newest first, and reads one into a `ContextHarnessPass`. Each reader loads its
  own storage: JSONL per session (Claude, Codex, Pi, Kimi, Antigravity), a JSON
  file listed in SQLite (Cline), or rows in one SQLite file (opencode). SQLite
  is opened `mode=ro` (never `immutable=1`, which misses rows still in the
  WAL); a locked or missing database reads as no sessions. `ContextFacade`
  serves every harness in the table, local or remote: the remote
  `devmachine-infer` answers with the same ids. A harness is detected by exact
  program name (`pi` is never `pip`); the session's detected harnesses pick the
  transcript before the newest-file fallback.
- **A remote pane is matched by every program under it, not only the one in
  front.** tmux names the foreground program, and Cline's npm launcher is
  `node`; the native `.cline` it starts is a child. So the session listing
  (`RemoteCommands.listSessions`, still one ssh per poll) also returns each
  pane's pid and the host's `ps -A -o pid=,ppid=,comm=`, and
  `TmuxListParser` walks the pane's descendants with
  `ProcessTree.matchingPrograms`, as the local scan does. Bare `node` matches
  nothing. tmux runs last in that command: its exit code is the command's,
  and 127 is how a host without tmux is told apart. Without a process table
  the pane's own command still counts.

## Chats
- **The engine is `devmachine chat`; the app only draws.** One process per
  message (`chat send`, `chat ask`), NDJSON `started/text/tool/denied/done/error`
  (`denied`: a tool claude refused because `-p` cannot approve it, drawn
  "Blocked: <name> needs approval")
  (`ChatEventDecoder`, Core). stdout and stderr share one pipe, so a line that
  is not an event is kept only as the failure's details. `ChatProcess` reads
  the pipe to the end before it returns: `StreamingProcess` could hand the last
  line over after the exit, and the turn then read as failed. Each turn carries
  a token (`ChatStore.turns`): the previous turn's process may report its end
  after the next turn started, and only the current turn may end it.
- **Warm sessions.** A message goes through a long-lived `chat session`
  (`chat ask --serve` for Ask) when it can: `{"type":"send"}` lines in,
  `ready`, the same turn events, and `closed` out (`ChatSessionLine`, Core).
  `ChatSessionPool` keeps one warm session for the next new chat (started
  when the quick panel or the new chat page shows, replaced when its harness,
  workspace or MCP changes), one per open chat (the CLI ends it after 10 min
  idle) and one per visible Ask section. A turn ends on `done`/`error`, not on
  the exit; Stop writes `cancel`; quit closes every stdin. A session that dies
  mid-turn fails the turn and the next message opens another. A CLI that
  refuses the command or a flag before `ready` is older: the turn goes out
  again with `chat send` and sessions stay off until relaunch. Tests and demo
  never start one (`ChatCommandRunning.openSession` throws by default).
- **Status.** `{"type":"status","stage","message"}` lines (connecting,
  reading the transcript, starting, loading MCP, waiting) set
  `ChatConversation.status`, drawn muted beside the cursor in the pane, the
  quick panel and Ask; the first `text`/`tool`/`denied`, `done`, `error`, a
  stop or the exit clear it. A send into a warm session that is still starting
  shows that session's latest start-up status; into a ready one, "<Harness> is
  thinking…" until the CLI's `waiting` (not for Ask, which reads the
  transcript first and says so). An older CLI sends none and nothing is
  made up. VoiceOver hears each status once, as a low-priority announcement.
- **MCP.** Chats start without MCP servers, hooks and plugins (`chat.mcp`
  off); the chip (`ChatMCPChip`) is kept per chat as the record's `mcp`, and
  `--mcp`/`--mcp=false` goes out only when it differs (`ChatMCP.flag`).
- A new chat is listed at once under `pending-<uuid>` and moves to the CLI's id
  on `started` (`ChatStore.current`). A process that ends with no `done` or
  `error` is a failure (`ChatConversation.processEnded`); `unknown command
  "chat"` is an older CLI (`needsNewerCLI`, the card offers Update the CLI);
  a usage error (`error: …` and no NDJSON) is `refused`.
- **Where chats run belongs to the CLI** (`chat.default_workspace`,
  `chat.folder`, `chat.harness` via `config set|unset`, read from
  `--format json config show`), so a chat from a terminal lands where one from
  the app does. The app keeps only the shortcut, the menu bar rows and the
  harness switches (`AppSettings.chats`). Read only is fixed and never a setting.
- **Code, Chats or Schedule** (`AppModel.appMode`, ⌘1, ⌘2, ⌘3): the sidebar's
  title is the switch ("CODE WORKSPACES ▾" / "CHAT WORKSPACES ▾" /
  "SCHEDULE ▾"; native menus in real use, `ChatMenuCard` only in demo frames,
  `SidebarModeHeader`), with refresh and close at the right of that row and
  "New session" / "New chat" under it. Chats replaces the main row; picking a
  session, a page or Settings goes back to Code. In Chats, a dot by the title
  says a session in Code waits for the person. Pickers are drawn in the view
  (`ChatMenuCard`), not `NSMenu`, so a demo frame shows them; they lock after
  the first message (a chat keeps its harness and workspace).
- **Quick panel**: `QuickChatPanelController`, a non-activating `NSPanel`
  opened by a Carbon `RegisterEventHotKey` (no Accessibility permission),
  default ⌃⌥Space. Tests hand `QuickChatHotkeyController` a fake registrar;
  nothing registers a real hotkey under XCTest or in demo mode. Recording a
  new shortcut in Settings suspends the old one. The panel has no SwiftUI
  `.help`: AppKit asked SwiftUI's tooltip bridge for a tooltip while the
  panel resized under a streaming answer, and the bridge read a view that was
  already gone (EXC_BAD_ACCESS in `TooltipResponder.text`, App v0.7.3). Views
  in `Chats/` and `Components/` use `.dmHelp(_:)`, which the panel turns off
  with `dmShowsHelp`; `DMHelpGuardTests` fails on a plain `.help` there.
- **Ask** (`app.ask`, provider `app/session-ask`, engine 1.8, after Links in
  the default Context tab): `AskStore` keeps one thread per session
  (`AskSessionKey`); a session on this Mac passes its folder. "Clear" (shown once a
  thread has messages) runs `chat delete` on that thread and starts a new one,
  so it does not come back after a restart; a refused delete keeps the thread
  and says why under it. Clear waits while an answer is coming. Ask chats left
  in the CLI's store from before Clear deleted (only the newest shows) are
  never deleted on their own: after a restart the next one shows, and Clear
  removes it too.
- Demo walk `DEVMACHINE_DEMO_WALK=chats` (`DemoChats`): the 14 screens of the
  approved mockups drawn from the real views over invented chats.
  `DEVMACHINE_CHAT_E2E=<devmachine binary>` runs `ChatCLILiveTests`: a real
  chat with the local claude in a temp configuration.

## Operator session
- **The Operator is the local session in the CLI's configuration folder**
  (`Workspace.operatorSession`, path `AppSettings.opsRepoPath`). Every way
  in (sidebar click, ⌘K `go.operator`) goes through
  `AppModel.openOperatorSession`, which decides with `OperatorLaunch.plan`
  (Core): a shell the multiplexer already holds (`zmx ls`) or a pane already
  started is only shown, never typed into.
- **Every start asks**, not only the first: once the shell has exited
  (`exit` inside it), the next open shows a central page
  (`AppPage.operatorChooser`, `OperatorChooserPage`) with one
  `DMPictureChoice` per harness whose CLI is on this Mac
  (`HarnessSettingsFacade.installedHarnesses`, turned on or not: the point is
  finding out what you have) and "Terminal only". The pick is saved as
  `operatorProgram` and starts the session; the next chooser shows it
  selected (`last`). Settings → Coding agents → Session defaults → Operator
  session changes that selection. A saved harness whose CLI is gone is
  offered as "Terminal only".
- **Only the first pick** (`operatorProgram == nil`) asks the harness what
  the folder is for: Claude Code and Codex get `HarnessPrompt.operatorIntro`
  as their positional first message (`SessionStartup.asking`, shared with
  Packages' "New package"), any other harness starts plain. Later picks start
  the program plain; asking the same question on every start is noise.
- **No harness installed: the terminal opens and nothing is saved**, so the
  chooser shows once one is installed. Settings written before this decode
  as not chosen, so an existing Mac sees the chooser once too.
- **Settings → General → Enable Operator session** (`operatorSessionEnabled`,
  on by default and for older settings). Off filters it out of
  `AppModel.localSessions` after the multiplexer merge, which empties the
  sidebar row, ⌘K's `go.operator` and the per-session palette item; Save
  leaves it for Home if it was open (`applyOperatorVisibility`). Its shell is
  never killed: turning it on again shows the same session.
- Demo walk `DEVMACHINE_DEMO_WALK=operator`: `200` the chooser over the demo
  Mac's CLIs, `201`/`202` General with the switch on and off (the sidebar
  without the row), `203` the Operator's program in Settings → Coding agents, `204` the chooser
  again with Codex as the last pick.
  `18-operator` selects the Operator directly: through the click it would
  show the chooser.
