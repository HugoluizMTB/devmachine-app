# CLAUDE.md — devmachine-app

Native macOS app (Swift 6 / SwiftUI / AppKit, SwiftPM) that operates the
`devmachine` VPS: tmux sessions per context-user, PRs, files, Caddy subdomains,
VPS stats, and coding-harness usage. It reads the devmachine CLI's configuration
folder (`~/.config/devmachine`) and publishes through the CLI.

## Language — ABSOLUTE, overrides everything
**All code, identifiers, comments, and git commit messages are ENGLISH.** No
Portuguese anywhere in this repo. (Chat with the owner stays Portuguese; that
never leaks into the code or commits.) This rule wins over any base preference.

## No real data — absolute, overrides everything
**This repo never holds real infrastructure or personal data**: real
workspace/context user names, client or product names, hostnames, public or
tailnet IPs, domains, emails, tokens. Not in code, tests, fixtures, docs,
comments, commit messages, screenshots or assets.

- Fixtures use invented names: workspaces `acme`, `beta`, `gamma`; people
  `alice`, `bob`; repos `acme/dash`; domains `example.com` / `example.net`; Mac
  paths under `/Users/alice`; IPs from the documentation ranges `203.0.113.x`
  (public) and `100.64.0.x` (tailnet); PR numbers arbitrary.
- Real values enter only two ways: the app's Setup/Settings page (`AppSettings`,
  persisted in `UserDefaults`) and the CLI's configuration folder on disk. A feature that needs an
  infra value reads `AppSettings`; it never carries a literal.
- Before any push run `scripts/check-real-data.sh`. It greps the tree with the
  owner's private pattern list (`~/.config/devmachine-app/private-patterns`,
  outside the repo on purpose — the list itself is real data) and must print
  nothing. The one allowed hit is `2BUA8C4S2C.com.1password` (the 1Password
  agent socket path in `RemoteCommands.swift`) — a product default.

## "Page" = a central panel, NEVER a new window
When the owner asks for a feature or "a page", he wants something that loads
**in the middle of the app** (the central content area), like a new home screen —
**not** a new macOS window. Default to a central page.

- The center is polymorphic, driven by `AppModel.activePage: AppPage?`. `nil` =
  normal behavior (the selected session's terminal, or Home when nothing is
  selected). A non-nil `activePage` renders that page full-size in the center,
  over the (still-mounted, hidden) terminals — so switching to a page never tears
  down a live ssh/tmux terminal.
- Selecting a session or the ops shell clears `activePage` (back to the terminal).
- Sidebar / menubar entries for pages (Stats, Subdomains, …) SET `activePage`;
  they do NOT `openWindow`.
- **Settings is a page too** (`AppPage.setup`, `SetupPage` in `PageHost`), with
  the sidebar beside it, never a window or a full-window card: ⌘,, the
  sidebar's gear, the palette, menus and every remedy button set it. The Add
  machine wizard opened from Settings → Machines closes back there
  (`AppModel.closeAddMachine`); opened from anywhere else it just closes.
- Create a new `Window` ONLY when the owner explicitly asks for a separate window.
  Existing exception: the **Files** window is contextual per-workspace (opened
  from the sidebar folder button) and stays a window for now.

## Command palette (⌘K)
- `CommandRegistry` builds every command from a `PaletteContext` (plain values:
  workspaces, sessions, machines, the current terminal). A fixed command carries
  an `isAvailable` check; per-workspace, per-machine and per-session commands
  are generated from state. A new screen or sheet gets a command there.
- A command is data (`PaletteAction`); `PaletteDispatcher` is the one place that
  runs it, through the same `AppModel` calls the sidebar and menus use. A sheet
  that lives in a view opens through a model request (`pendingAddSubdomain`,
  `pendingPublishWorkspace`, `requestedSettingsSection`), never a second copy.
- Ranking is `FuzzyMatch` (Core) plus the recent-use bonus from `CommandMRU`,
  persisted by `PaletteRecentsStore`.

## Menubar
`MenuBarExtra` uses `.menuBarExtraStyle(.window)` — an interactive popover with a
tab bar (`MenuBarTab`), mouse-navigable like pr-menubar. Tabs render inline
(Pull Requests, Usage, …); no separate PR window. The popover should size itself
to the active tab. Tab styling should be elegant/custom, not the raw native
segmented control.

The footer's eyedropper and ⌘K's "Pick a color from the screen" share
`ScreenColorPicker` (the system `NSColorSampler`); the clipboard text is
`ScreenColor.hex` (Core), converted to sRGB first so the hex matches what a
web page or design tool means by it.

## Reusable structure
- `DevmachineCore` (library): pure logic, parsers, command builders — unit-tested,
  no UI, no AppKit where avoidable.
- `HarnessUsageKit` is the reusable multi-provider usage data layer and views.
  It depends only on Foundation/SwiftUI/Charts, never on the app target.
- `DevmachineApp` (executable): the app shell + SwiftUI views.
- `HarnessRegistry` owns provider adapters. SwiftUI consumes descriptors and
  facades; executable names, process matching, colors, launch commands, and
  provider policies stay behind adapters.
- `DevmachineServices` is the boundary for workspace, session, and context data.
  Its current sources preserve the existing SSH and `devmachine-infer` behavior;
  a future `devmachine-cli` source can replace them without changing views.
- Shared UI lives in `Sources/DevmachineApp/Components/` + `Theme.swift`
  (`Color.dm*`). See "Component library" below.

## Component library — use what exists, never reinvent
`Sources/DevmachineApp/Components/` is the app's own component library. Before
writing any UI, look there first. The order is fixed:

1. **A `DM*` component or style already does it** → use it. Add a parameter if
   it is close but not quite right; do not copy it.
2. **Nothing in `Components/` fits** → use the native SwiftUI/AppKit control
   (`Toggle`, `Picker`, `Menu`, `.bordered`, `.borderedProminent`, `.link`,
   `.roundedBorder` in a native sheet).
3. **Neither fits and the thing appears twice** → add a new `DM*` component to
   `Components/`, then use it in both places. One-off layout stays in its view.

What is there:
- Tokens (`DMTokens.swift`): `DMRadius.*` for every corner radius, `DMHitSize.*`
  for icon click areas, `DMSpace`, `DMControlHeight`, `DMIconSize`, `DMRowInset`,
  `DMSectionInset`, `DMCardWidth`, `DMPaneWidth`, all in points at 100%;
  `Color.dm*` (incl. `dmSelection`, `dmStroke`, `dmActive`). No number literals
  for radii in views.
- Metrics (`DMMetrics.swift`): the app's `rem`. One rem is the 13-point body
  size times Settings → Appearance → text size (`uiFontScale`), and every token
  comes back scaled from `@Environment(\.dmMetrics) private var m`:
  `m.space.md`, `m.control.small`, `m.radius.row`, `m.card.banner`,
  `m.pt(7)` for a one-off point value, `m.rem(1.5)`. At 100% each token is
  exactly the old point value, so the default look never moves.
- Buttons (`DMButton.swift`): `DMButton` / `.buttonStyle(.dm(_:size:))` for every
  labelled button. Variants: `.primary` (the one action of a sheet or page),
  `.outline` (the action beside it, Cancel), `.danger` / `.dangerOutline` (ends or
  removes something), `.ghost` (toolbars, quiet inline actions), `.ghostDanger`
  (a quiet remove in a row, red only on hover), `.link` (reads as text). Sizes `.small`, `.regular`, `.large`; `isLoading:` shows a spinner and
  disables it. An icon-only button is `DMButton(icon:label:)`: the label is
  required and is what VoiceOver reads. Native buttons stay only in menus,
  context menus and `.confirmationDialog`.
- `DMButtons.swift`: `DMIconButton` / `DMIconButtonStyle` for a bare SF Symbol in
  dense chrome (sidebar, table rows, panel headers); `.dmChip` for suggestion and
  shortcut chips.
- Error state (`DMErrorState.swift`): `DMErrorStateView` for a failed read: a
  title, one plain likely cause (`FailureCause` in Core, `HarnessUsageErrorKind`
  for usage), Try again, and a collapsed "Show details" with the exact error to
  select and copy. `DMStatusView(.failed)` draws it, so a page gets it for free.
  Never dump an error string straight into a card. Usage cards get it through
  `.harnessUsageErrorView { … }`, since `HarnessUsageKit` cannot import it.
  A cause only a newer CLI fixes (`FailureCause.needsCLIUpdate`: ssh's
  `unix_listener: … too long for Unix domain socket`, an older CLI's
  connection socket under a long home folder) adds "Update the CLI", which
  opens Settings → About through `\.dmOpenCLIUpdate` (set at the root);
  Stats' banner offers it too.
- Jobs and age (`DMJobCard.swift`, `DMAgeLabel.swift`): `DMJobCard` for a job
  that runs in named steps and ends in a result to act on (same surface as
  `DMToastCard`, `.dmToastChrome()`); `DMAgeLabel` says how old cached data
  is, only once it is old enough to matter.
- Commands (`DMCommandBlock.swift`): `DMCommandBlock` for shell commands to
  select or copy (one or more lines, one Copy button); `DMCopyButton` alone.
- Logs (`DMLogView.swift`): `DMLogView` for a program's output as it comes
  (monospaced, colour codes out via `LogText`, follows the last line,
  Expand, Copy log; `fills` on a run screen). Every streamed output uses it.
- `DMReportBugButton`: opens a prefilled, redacted GitHub issue (`BugReport`)
  in the browser; every failure panel carries one.
- `DMChoiceCard(locked:)`: checked and never toggled (essentials).
- Fields (`DMFields.swift`): `DMSearchField` (magnifier + borderless field +
  trailing slot, optional focus binding); `.dmField()` for a text input on a
  dark surface.
- Surfaces (`DMSurfaces.swift`): `.dmGlass(radius:)` / `.dmGlass(in:)` for frosted
  cards, palettes, toasts; `.dmSurface(_:radius:)` for any filled shape with a
  hairline edge; `DMKeyCap`; `DMChip`.
- Rows and sections (`DMComponents.swift`): `DMRow`, `DMRowBackground`
  (radius and selected colour are parameters), `DMSection`, `DMSectionLabel`,
  `DMSectionValue`, `DMTableRow` (striped, hover-lit table row), `DMHairline`,
  `DMPill` (a status), `DMKindLabel` (a kind: one calm style, no colour per kind),
  `DMPRStateIcon` (a PR's open/draft/merged/closed glyph), `DMProgressBar`,
  `DMStatBubble`, `DMToastCard`; `DMTabStrip` (`grouped: true` for a segmented
  second level), `FlowLayout`.

Rules:
- **No fixed points in components; use tokens.** A padding, frame, stack
  spacing, radius or width in `Components/` comes from `DMMetrics`, so a bigger
  text size grows the box with the text instead of spilling out of it.
  `DMFixedPointsGuardTests` fails on a new literal (0 and 1-point hairlines
  are allowed). A component parameter is in points at 100%, like a `.dm(_:)`
  font size, and the component scales it: never pass it `m.…`. Screens use
  `m.…` too; a `static` helper with no environment reads `DMMetrics.current`.
  `DMComponentsFitTests` draws each component at 80/100/130/160% and fails when
  it spills out of its frame or stops growing with the text: add a new
  component there.
- Never hand-roll `.buttonStyle(.plain)` + `Image` + `.foregroundStyle` +
  `.frame` + `.contentShape` for an icon button: that is `DMIconButton`.
  `.buttonStyle(.plain)` stays only for a button whose label is a whole row or
  panel.
- Never write `.background(.ultraThinMaterial, in:)` + a stroke overlay: that is
  `.dmGlass`.
- `DMComponentsRenderTests` renders a gallery of every component; add a new
  component to it. `DEVMACHINE_RENDER=1 swift test --filter DMComponentsRenderTests`
  writes `/tmp/devmachine-components.png` to look at.
- `HarnessUsageKit` never imports app components (it depends only on
  Foundation/SwiftUI/Charts); it keeps its own small styles.
- No third-party UI kit (e.g. shadcn ports): they bring a web look, blur-heavy
  overlays and their own window/hosting code, which clash with the hard UI rules
  below.

## Hard UI rules
- **Few lines.** The owner reads a screen full of dividers as noise. Areas
  are separated by spacing first, then by a faint tint (`Color.dmBand`,
  `Color.dmHover`); tables have no outer border and no line between rows
  (`DMTableRow`); tab rows are pills, never underlined. A line is the last
  resort, drawn with `DMHairline`, and at most one per area.
- **Never put a `Divider` inside a `ZStack`** — it becomes horizontal and greedy.
  Use `Rectangle().frame(width:1)` / `.frame(height:1)`.
- Numbers shown to the user go through `Text(verbatim:)` with explicit formatting.
  Never `Text("\(intValue)")` — SwiftUI localizes it (pt-BR renders `5.182`,
  `740,31M`). This bug already shipped once; don't repeat it.
- A central page must fill the center (`.frame(maxWidth:.infinity, maxHeight:.infinity)`),
  never float at intrinsic size. Its content uses the whole width too: no
  `maxWidth` cap on a page body (Settings had one, and the owner asked twice
  for it to reach the edge).
- **A running job is a `BGTask` card, never a strip inside a layout.** Whatever
  the app is doing — the workspace sweep, deleting sessions, sending an image,
  adding a subdomain — registers through `AppModel.beginTask/bumpTask/setTask/
  finishTask` and is drawn by `DMToastCard` in the bottom-right stack. A strip
  that appears and disappears inside a `VStack` has no fixed height, so it
  pushes everything below it down and back on every tick; the sidebar's old
  "Connecting…" bar did that on every 60s sweep. A job counted in bytes sets
  `showsCount = false` (the bar alone), and one that ends at once uses
  `dropTask` so it does not blink a finished card. The small
  `ProgressView().controlSize(.small)` inside a panel stays what it is: that
  panel loading its own content, not a job. A `devmachine` run against a
  machine is a machine job instead (see Machine jobs).
- **`.clipped()` / `.clipShape` do NOT clip hit-testing.** A `scaledToFill` image
  overflows its container and its invisible overflow still swallows clicks over
  neighboring views (this once killed the sidebar's right edge for a whole day).
  Every decorative full-bleed view (wallpaper, gradients, shadows) gets
  `.allowsHitTesting(false)`. Never rely on clipping to contain hit regions.
- SwiftUI `Button` + `.contextMenu` on the same view in a `ScrollView` fires
  once then goes stale on macOS. Rows use `.onTapGesture` (modifiers via
  `NSEvent.modifierFlags`) + `.contentShape(Rectangle())` + `.contextMenu`.
- Never `makeFirstResponder` on an embedded AppKit view (terminal) during mount —
  it steals focus from SwiftUI and makes sidebar clicks flaky. Focus is
  request-driven instead: an explicit user action (opening or stacking a session)
  calls `TerminalRegistry.requestFocus(_:)`, and the pane hands the request back
  on the next runloop once the view is in a key window (`viewDidAttach`).
- When clicks die "in a region" and nothing looks wrong: dump the AppKit
  hierarchy + `hitTest` from inside the app (walk `window.contentView.superview`,
  log class/frame per view). A platform view wider than its container is the tell.

## Terminals (SwiftTerm)
- `TerminalRegistry` owns ONE live `LocalProcessTerminalView` (mosh or ssh → `tmux new-session -A`)
  per session for the app's lifetime. `TerminalPaneView` only attaches/detaches it;
  single pane and stack-grid cells re-parent the same view. Never mount the same
  session in two places: two tmux clients at different sizes make `window-size latest`
  flap and garble the screen. Detached views are LRU-capped (6); a dismantled pane
  never terminates the process (only delete/rename/quit do).
- Remote sessions run with `TERM=tmux-256color` (`RemoteCommands.remoteTerm`), never
  `xterm-256color`: the host's `/etc/tmux.conf` gives every `xterm*` client `extkeys`,
  tmux then forwards the kitty keyboard protocol coding harnesses can turn on, and
  SwiftTerm's kitty encoding breaks Enter and dead keys (ç, ´). Check with
  `tmux list-clients -F '#{client_termfeatures}'` on the host: the app's client must
  not list `extkeys`. `LegacyKeyboardTerminalView` also drops the kitty query answer
  and XTVERSION replies as a second guard. Do not "clean this up".
- Terminals run with `optionAsMetaKey = false`: this Mac uses the U.S. layout, where
  Option composes accents (⌥c is ç, ⌥e a is á), and SwiftTerm's default (`true`)
  turns them into `ESC c`. A local key monitor in `TerminalRegistry` flips the flag
  back on for Option+function keys only, so Option+arrow still sends `CSI 1;3D`
  (shell word jump). Verified with synthetic `NSEvent`s, never by typing into the
  owner's live sessions.
- SwiftTerm is pinned by revision (`9fc2d2f`, 2026-09-04: kitty encoding fixes);
  upstream `main` after 2026-09-09 does not link (`MetalError`). Bump on purpose only.
- **One painter per pixel.** The terminal paints its own background at the
  opacity from Settings; the padding around it is four strips beside the
  terminal, never a layer under it (`TerminalContainerView.paintPadding`). Two
  translucent layers over the same pixels can never match a strip that has one,
  and that difference is what read as a border. The strips take their colour
  from `nativeBackgroundColor`, so they follow whatever the program sets.
- **A pane that returns unchanged gets no size change, so nothing redraws it.**
  Switching sessions, closing a page, coming back from the stack: the program was
  never told anything happened. The app asks explicitly — `tmux refresh-client` for
  a remote session, the window-changed signal to the foreground process group for a
  local one (`TerminalRegistry.requestRepaint`). Do not fake a resize instead: an
  earlier version shrank the pane a row and restored it, which left the last row
  unpainted, and another killed the local client and restarted it, which left the
  keyboard wired to the process that had just died. `refresh-client -t` takes a
  client, never a session: given the session name it only said "can't find client",
  so the command names each client of the session (`RemoteCommands.refreshClient`).
- **A remote pane coming back leaves an idle tmux copy mode**
  (`RemoteCommands.leaveIdleCopyMode`), on return to the pane and when the app
  becomes active or the screen wakes. tmux's `WheelUpPane` enters copy mode
  *without scrolling* when the program does not read the mouse (Claude Code's
  normal view), so one stray wheel-up report leaves the screen looking the same,
  frozen, with every key going to copy mode until Ctrl+C or q. The tell is the
  window name `[tmux]` in the status line, not the program's. Only copy mode at
  scroll 0 with no selection is left; scrolled up, someone is reading. Not focus
  reporting: the hosts run `focus-events off` and mosh drops `?1004`.
  The activation/wake check logs in, so it is rationed
  (`CopyModeCheckSchedule`): tmux runs one server per account, so each
  workspace alias with a pane on screen needs its own login (one login per
  machine cannot reach another account's tmux without root); what is
  limited is when. One ssh at a time, aliases grouped by machine, each
  machine at most once per 5 minutes, nothing while polling is paused or
  the sweep runs, and the first ssh-level failure ends the round and pauses
  polling through `AppModel.noteSSHFailure`, the sweep's own backoff.
- **A process starts only after its pane has the size it will be drawn at**
  (`viewDidSize`). Started earlier it learns a placeholder geometry, and a program
  that repaints only what changed never corrects it.
- **`needsDisplay` never repaints a terminal. Call `requestRedraw()`.** SwiftTerm
  draws through a Metal render loop by default on macOS: `draw(_:)` returns at
  once and frames come from its own driver, so an AppKit invalidation is dropped
  without a word. That is why panes came back blank and a click fixed them — the
  click was the only thing marking a frame dirty.
- Terminal layout is explicit (`TerminalContainerView.layout()`), not autoresizing
  masks — they lost the insets after SwiftUI's first sizing pass.
- **The viewer reads, never writes.** `FileViewerStore` asks for size plus the
  first 2 MB in base64 (`FilePreviewReader.command`), decides in Core what the
  file is (code, markdown, image, binary, too large) and shows it. Highlighting
  stops above 200 KB, where highlight.js blocks the interface long enough to
  look broken.
- **A feature that reads `case .session` only is a bug in waiting.** A session
  runs on a host or on this Mac, and every path has to answer for both:
  the context panel was gated on `.session` and never showed for a local
  session; "maximize" tagged only remote panes and always picked the first cell;
  the file palette and the Files window each had their own version of this.
  Handle both cases of `TerminalKind`/`SidebarItem`, or say in a comment why one
  is out.
- **Never hand a live session a size that is not the pane's.** SwiftUI measures a
  representable with sizes that are not the pane (2 by 1 cells among them), and a
  container starts at a placeholder size; every one of those reaches the program
  as a resize, and a remote multiplexer rewraps its screen and loses characters.
  Sizes are applied only once the pane is in a window, and anything below
  `TerminalSizeGuard` is ignored (`TerminalContainerView.applyContentFrame`).
- **Page keys are swallowed by the terminal.** SwiftTerm answers an unmodified
  Page Up/Down by scrolling its own buffer, which for a session inside a
  multiplexer holds a single screen — so the key does nothing and the host never
  sees it. A remote pane gets the bytes sent explicitly
  (`TerminalKeyboard.pageKeyBytes`); a local pane keeps the terminal's own
  scrolling, which is what it should do.
- **A file sent to a session lands on the machine that runs it** (drop on a
  pane, ⌘V of an image, ⌘K Send file), always through `PaneUploadStore`: the
  original name plus the time before the extension, in the harness folder
  (`UploadStoragePolicy`), never overwriting (`-2`, `-3`, …). The remote name
  travels as base64 and is decoded on the host, so no character of it reaches a
  shell. Paths are typed quoted, without Enter. A folder is refused, not guessed.
- **The pane owns selection, in every session** (`SelectingTerminalView`,
  `TerminalPointer`). tmux turns mouse reporting on in every remote session,
  and SwiftTerm then hands every press, drag and release to it: a drag became
  tmux's yellow copy-mode selection, a click could not clear a selection
  SwiftTerm had made earlier, and the copy depended on the host's config. So
  press, drag and release always go to SwiftTerm's selection (mouse reporting
  off for that call), a plain single click is replayed afterwards for a
  program that reads the mouse, and the wheel keeps SwiftTerm's rule, so tmux
  still scrolls its history. A drag shorter than `TerminalPointer.dragThreshold`
  is a click. Copy on select (Settings → Appearance → Terminal, on by default) copies a drag,
  a word or a line on release; ⌘C with nothing selected leaves the clipboard
  alone. No key is intercepted for selection: SwiftTerm clears it on any key,
  and Esc, ⌃C and the rest reach the program unchanged.
- **A copy made by a program on a host arrives as OSC 52** (tmux's keyboard
  copy mode, an editor's yank). `TerminalDelegateGate` stands in as SwiftTerm's
  delegate, because `LocalProcessTerminalView` answers the clipboard itself and
  does not let a subclass change it: a write is taken only from the focused
  pane and up to `TerminalClipboard.maxWriteBytes`, and a query is never
  answered, so a host cannot read the Mac's clipboard. On the host, the zsh
  package's `~/.tmux.conf` sends `\E]52;c%p1%s;%p2%s\007`: tmux 3.4 sends
  nothing when `%p1` is left out, and mosh forwards only the `c` clipboard.
- **A panel reads through `CommandTarget`, never through an alias.** `HostRunner`
  runs the same command over ssh (in the tmux pane's folder) or here on the Mac
  (in the folder `zmx ls` reports), so Context, Files and Git work for a local
  session. Two commands are not portable and have a local form: `find -printf`
  is GNU only, so a local listing uses `ls -Ap1` with
  `FileTreeParser.parseNames`.
- **A worktree is removed only after a read-only check** (`WorktreeRemoval`).
  The main checkout and the session's own worktree are never offered. Dirty or
  locked needs its own checkbox before `--force` / `--force --force`; a branch
  is deleted only with `-d`, only when merged into the main checkout's branch.
  Paths and branches are single-quoted; the remove runs from the main checkout.
- **A removal reports per worktree, never one exit code.** Single or "Remove N
  merged…", one shell runs the worktrees one after the other and prints a
  record each (`WorktreeRemoval.removeCommand`/`parseRemoval`). `branch -d`
  refusing (its upstream is behind, even when merged into main) keeps the
  branch as a warning; the folder is still gone. A folder already gone counts
  as removed and is pruned, so a second click never fails on it. The batch
  once failed whole on one refused branch, kept its stale list, and the retry
  then failed on every folder it had already removed.
- **"Permission denied" is a refused login only in ssh's own words**
  (`FailureCause.isSSHLoginRefused`: `Permission denied (publickey…)`,
  `…, please try again`, too many auth failures). git and rm say it about a
  file (`fileAccessDenied`), and git exits 255 too, so the exit code proves
  nothing. The worktree sheet names the account and the path instead.
- **Files another account owns stop a worktree remove halfway** (a root
  container's bind mount, a `sudo` build). The check lists up to 10 and a
  count (`find ! -user`). git then drops its record and its `.git` file
  early and leaves the rest: the snapshot lists such folders as leftovers
  (a `.git` file pointing at a dropped record, or no `.git` at all inside
  `<main>/.worktrees`). Only a remote non-self machine, a path inside
  `/home/<user>`, and a second checkbox get "Remove as machine admin…"
  (`WorktreeAdminRemoval`): `devmachine run --machine` runs a script with
  base64 arguments that checks again as root (canonical paths, not a mount
  point, the `.git` proof) before `rm --one-file-system`; the prune and
  `branch -d` run after, as the user. This Mac never deletes as admin; it
  shows the commands. A folder already gone is a "Prune".
- **Hiding a workspace also empties its rows from Stats and the subdomain
  list.** The host is what says who owns a row: a container by the folder it was
  started from (compose or the Supabase CLI writes it, and it lives under
  `/home/<user>`), a port by that container or by the process holding it
  (`Ownership`). What cannot be attributed — a hand-made container, the apex
  site, anything outside a home folder — stays on screen: hiding what has no
  owner would hide the machine itself.
- **A missing tool is not a zero.** A machine without Docker reports
  `docker.available: false`; Stats and Home show "No Docker" / "—" and the
  install commands (`ContainersState`), never "0 Containers". The note the
  stats package puts in `errors` for it is not a failure and is not shown.
- **Hiding a workspace is a list of what to hide, not of what to show**
  (`AppSettings.hiddenWorkspaces`, filtered by `WorkspaceVisibility`). A new
  workspace from the CLI shows up without anyone opening Settings. Everything
  except Settings reads `AppModel.visibleWorkspaces`, so a hidden workspace
  costs no row, no poll and no ssh; hiding also closes its panes at once
  (`TerminalRegistry.closeWorkspace`), which is what ends the mosh it held.
- **The Local workspace lists what `zmx ls` reports**, merged with what the app
  remembers (`LocalSessionScan.merge`): a session started outside the app shows
  up, and a remembered one that has no shell yet shows without a client count.
  One `ps -axo pid=,ppid=,comm=` per poll detects every registered coding harness.
- **A local pane runs the account's login shell** (`LocalShell`: the user
  database first, then `SHELL`, then `/bin/zsh`), never a fixed zsh: a bash or
  fish user got a zsh with none of their configuration.
- **The prompt turns mouse and focus reporting off** (`ShellIntegration`). A
  program that dies without undoing them (an ssh that drops, an editor killed
  with SIGKILL) left them on, and every mouse move reached the shell as typed
  `35;48;9M…`. zsh gets it through `ZDOTDIR` (its `.zshenv` puts `ZDOTDIR`
  back before the user's files load), bash through `--init-file` (which then
  reads the login files and `.bash_logout` itself, because bash skips an init
  file in a login shell), fish through `-C`. A local session that zmx already
  holds keeps the shell it was started with. Any other shell starts plain. The files live in
  `Application Support/Devmachine/shell-integration`, checked at every pane
  start; if they cannot be written, the shell starts plain rather than without the user's files. zmx
  runs the command only when it creates a session, and needs `HOME` passed:
  bash and fish do not look it up.
- **A local session is renamed in the sidebar only.** `zmx` has no rename and its
  socket is named after the session, so `LocalSession.handle` (the multiplexer
  name, and the registry key) never changes; `name` is what the sidebar shows.

## Remote terminals (mosh, falling back to ssh)
- **The app is the mosh wrapper.** It runs `mosh-server new` over ssh
  (`MoshBootstrap`), reads `MOSH CONNECT <port> <key>` from output that may
  carry login noise, and starts the embedded `mosh-client` (`Contents/Helpers`,
  from `scripts/fetch_mosh.sh`) with the key in `MOSH_KEY`, never in argv.
  Homebrew's `mosh-client` is only the fallback for a local build.
- **`-s` binds the server to the address ssh reached**, so the client aims at
  the same machine: `devmachine resolve` first (detected once per run with
  `resolve --help`), then the `hostname` of `ssh -G <alias>`, looked up here.
- **A pane never hangs on mosh.** Exit 127 (no mosh-server) → ssh at once. A
  mosh-client still showing "Nothing received from server" after 5 s
  (`MoshClientProbe`) is killed with SIGKILL — on SIGTERM it waits for a
  shutdown ack that cannot come — and ssh starts in the same view from
  `processTerminated`, the one moment SwiftTerm lets a view relaunch. That
  ssh kills the unreachable mosh-server first (its pid comes from
  `[mosh-server detached, pid = N]`): otherwise it holds a second tmux client
  for 60 s and the screen flaps.
- **What failed is remembered per machine for the app run**
  (`RemoteTransportMemory`, 30 min, injectable clock). A remembered failure
  is not recorded again (that would push the re-probe back forever) and not
  announced again. An ssh that could not connect at all says nothing about
  mosh and is not remembered.
- Only a started mosh that could not get through shows the pane notice. A
  machine without mosh-server is a choice; the badge's tooltip says why.

## Previews
- The context panel's Preview tab lists the selected workspace's published
  sites and the ports its user listens on (`PreviewTargets`, from `expose list`
  and the stats `ports`); a local session lists what this Mac listens on
  (`lsof`). Nothing polls it: it draws from the cache on show, reads only
  what is past its TTL, and reads everything on Refresh.
- Where a preview or a context-panel link opens is one setting
  (`AppSettings.linkOpening`, default browser); ⌥-click flips it once.
  `PreviewStore` is the only place that decides.
- A workspace port is reached through `devmachine tunnel --local`, spawned and
  owned by `TunnelManager`: reused per workspace and port, held by the tabs (or
  the browser) that use it, stopped when the last one lets go and on quit. The
  local port is the remote one when free here, else any free port. The CLI
  binds 127.0.0.1 only.
- The in-app browser loads http(s) and `about:blank` only (`PreviewURLPolicy`),
  keeps `target=_blank` in the same tab, and uses one non-persistent data
  store per app run. The address bar shows the web view's real URL.
- **The terminal and the pane beside it are one split** (`DocumentSplitView`,
  `DocumentSplit` in Core). The pane's share is a fraction, saved only when a
  drag ends (`DocumentSplitState`); each side keeps 320 pt, nothing else caps
  it; a double-click on the divider goes back to half and half. Every
  `ResizeHandle` drag is measured in `.global` coordinates: measured in the
  handle's own, each step moved the origin of the next and the pane shook.
- **Maximize lays the pane over the terminal, which keeps its width**, so the
  program inside gets no resize and comes back as it was; the keyboard moves
  to the page. ⇧⌘↩ is the preview's while its page has the keyboard
  (`FocusedPreview`), and ⌘W then closes that tab instead of ending the session.
- **The pane's tab strip is a plain row, never a horizontal `ScrollView`.**
  Inside the scroll view a click on a tab's close mark hit-tested to its
  `NSClipView` and never reached the button (checked in a demo build with
  events sent through the window: no close with the scroll view, a close
  without it). Long titles are shortened instead. Middle click, the chip's
  menu and ⌘W close a tab too.
- **A preview tab belongs to the session it was opened in**
  (`PreviewTab.owner`, set from `AppModel.selection`). Each session shows its
  own tabs and selected tab; ending, removing or hiding a session closes its
  tabs, and a rename carries them over. Tunnels are held per tab, so one
  shared by two sessions stops with the last tab. The split width stays global;
  maximize is dropped on a session switch.
- The in-app browser sends the system Safari's user agent (`SafariUserAgent`,
  version read from Safari's bundle): WebKit's default lacks `Version/… Safari/…`
  and Google served its page for an old browser. A tab's name follows the page
  (`PreviewTitle`: its title, else its current host).
- **A `WKWebView` is the engine, not the browser.** Everything Safari's own
  window does for a page is `PreviewPage`'s job, and a missing delegate
  method fails silently: a file input did nothing, `alert` vanished,
  `confirm` was always false. So the page answers file inputs (`NSOpenPanel`),
  `alert`/`confirm`/`prompt` (sheets naming the asking origin), Basic and
  Digest logins (a sheet; the credential lives in the non-persistent store's
  memory for the run, never written or logged), camera and microphone (asked
  per origin, remembered for the run; `Info.plist` carries both usage strings
  and the entitlements both device keys, since macOS kills an app that
  touches either without them), downloads, popups, fullscreen video and Web
  Inspector (`isInspectable`, right-click → Inspect Element). Every question
  goes through `PreviewPrompting`, so tests and the `preview-browser` walk
  answer them without a window.
- **Only the main frame's own address is limited** (`PreviewURLPolicy.navigation`).
  Subframes load anything but `file:`; `about:`, `blob:` and `data:` are the
  page itself (an iframe's `srcdoc`, a generated file) and blocking them
  broke iframes, downloads and apps. `file:` and `javascript:` in the main
  frame are refused with a notice; any other scheme (`mailto:`, `tel:`, a
  meeting app) is offered to the app that opens it, after a yes.
- **A popup is a tab, with a real web view.** `window.open` and
  `target="_blank"` get a `WKWebView` built from the configuration WebKit
  hands over, so `window.opener` works and OAuth or payment popups can post
  back; the tab opens beside its opener in the same session (`.opened`), and
  `window.close()` closes it. `javaScriptCanOpenWindowsAutomatically` stays
  off: WebKit then lets only a click, or a script answering one, open a tab.
- **A download lands in ~/Downloads, never over a file** (`DownloadName`,
  `FileTransfer.freeName`, the Files tab's `-2`, `-3` counter), from a
  `download` link, an `attachment`, or a type WebKit cannot show; the Files
  tab's own `TransferNotice` card says where, with Reveal in Finder. A demo build saves to `DEVMACHINE_PREVIEW_DOWNLOADS`.
- **Browser keys belong to the page that has the keyboard**
  (`PreviewWebKitView.performKeyEquivalent`): ⌘F find, ⌘G / ⇧⌘G next and
  previous, ⌘= / ⌘− zoom, ⌘0 actual size (Home only when the page does not
  have the keyboard). Esc is never taken; it closes the find bar only from
  inside its field. WebKit's "Open Link in New Window" reads "New Tab".

## Coding harnesses
- **Detection never depends on the toggle.** Every harness in
  `HarnessRegistry.builtIn` is detected, badged, gets its icon, upload folder
  and Context panel, enabled or not and whether or not its CLI is on this Mac:
  many run only on a server. Enabling one only adds it to the launch choices
  and session defaults (and its usage card), and never needs its CLI here.
- **Identifying a harness and activating it are different.** Identification
  (icons, Context, process matching) covers every harness in the registry
  and never looks at packages. Activation is the Settings → Harnesses switch,
  shown only for a harness whose `HarnessDescriptor.packageName` (the
  workspace package that installs it: claude-code, codex, pi, antigravity,
  opencode, kimi-code, cline) is in the pinned release's
  `packages list` (`CodingAgentPackages.activatable`; before the list is
  read, the declared name is trusted). Any other harness shows its row with
  no switch, and its saved on/off is left as it was. The Workspaces page's
  Coding agents group offers only the packages of harnesses turned on
  (`CodingAgentPackages.choose`), hides the others and what needs them
  (claude-plugins needs claude-code), keeps one a workspace already has so
  Edit can take it off, and with none on says so and links to Settings →
  Harnesses. The first run's skills picker is unrelated: it offers what
  `skills add --agent` accepts (`SkillAgent`). Views never name a package.
- **A harness on without its CLI on this Mac starts on remote workspaces
  only** (`LaunchPlace`): it is offered in the remote fallback, the
  per-workspace defaults and a remote workspace's new-session menu and ⌘K
  commands, never for This Mac. A This Mac default naming one starts a plain
  shell (`HarnessSettingsFacade.localSessionProgram`), the way a harness
  turned off does, and its Settings row says "Not on this Mac — remote
  workspaces only". Whether a CLI is here comes from `CLIAvailability`:
  looked up (a missing one costs a login shell) off the main thread at launch
  and when Settings opens, then cached; only a read before the first lookup
  ends pays for it itself.
- This Mac has one Terminal-or-harness default. Remote workspaces inherit one
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
- Sidebar harness icons (Settings → Harnesses, off by default) are files in
  `Resources/HarnessIcons/`, loaded by name (`HarnessIconLibrary`): a new
  harness gets its icon by adding a file. `<HarnessID>.svg` is always the
  monochrome drawing in `currentColor` (it takes the row's tint, and every
  built-in harness must have one); `<HarnessID>-color.svg` is the optional
  brand-color version. Settings → Harnesses → Icon style
  (`AppSettings.harnessIconStyle`, `.color` by default) picks it: Original
  colors uses `-color` when it exists, else the monochrome file; Monochrome
  never reads `-color`. A `-color` name is never a harness id. No monochrome
  file → no icon, the hover dot stays. Brand colors exist for Claude, Codex,
  Antigravity and Kimi; Pi, opencode and Cline are black and white anyway.
  Claude, Codex and Pi come from Orca (MIT, `LICENSE-orca.txt`); codex-color,
  Antigravity, opencode, Kimi and Cline from lobe-icons (MIT,
  `LICENSE-lobe-icons.txt`). A new icon names its source in one of those files.
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

## Performance rules (learned from a 2 GB footprint)
- Poll only while a view is visible (`onAppear`/`onDisappear` begin/end, refcount),
  one in-flight run per target, publish a `@Published` only when the value changed.
- Never decode an image or run a blur inside `body`; bake once (`WallpaperBackground`)
  and cache with a cap. Hidden `.opacity(0)` views still cost a full-window drawable —
  render only what is shown. No `.shadow` on full-window cards.
- Session polling is a sequential sweep that stops at the first ssh-level failure and
  pauses (5 min on `Permission denied`, 1 min unreachable): parallel auths against a
  locked agent got this Mac banned by fail2ban. Keep it that way.

- Machine stats are the one app-wide poll, because Home shows them: `StatsStore`
  reads every non-self machine every 90s, staggered, one run per machine, backing
  off 90s → 3m → 5m on errors, paused while the Mac sleeps. The last good snapshot
  per machine lives in `Application Support/Devmachine/stats-cache.json`, so Home
  and Stats draw from it at launch; the skeleton shows only when there is no cache.

## Local-first machine data
- Everything read from a machine goes through one `DataCache` (Core,
  `LocalFirst/`), shared as `DataCache.shared`: memory plus
  `Application Support/Devmachine/machine-cache.json` (memory only under
  XCTest). Keys live in `MachineDataKeys`: `workspaces`, `sitesContext`,
  `sites:<machine>`, `dnsProviders:<machine>`, `dnsRecords:<machine>|<provider>|<zone>`,
  `sessions:<alias>`, `context:<target key>`. TTLs are per kind
  (`CachePolicy.standard`: ports 45s, sites 60s, DNS 5 min).
- A view draws the cached value at once and never waits on a fetch when one
  exists; `revalidate` refreshes in the background only what is stale,
  invalidated or forced (the Refresh button). One fetch per key at a time;
  every other caller joins it. A skeleton shows only with no cache at all;
  an old value shows its age (`DMAgeLabel`).
- An answer is laid over the list on screen by identity (`StableList`): an
  equal answer publishes nothing, and a reorder alone keeps the rows still.
- Ports are the stats poller's: `StatsStore.freshSnapshot` reuses its
  snapshot, or one read through its schedule (never during a backoff). No
  view runs its own `stats` ssh.
- A publish or removal invalidates that machine's `sites` and `dnsRecords`
  and reads them again; the Preview tab hears it through `DataCache.observe`.
- A session's Context warms its workspace (`WorkspaceMachineData.warm`), so
  Publish a port… and Preview open with something to show.

## First run (onboarding)
- **Onboarding owns the window until the Mac is set up or skipped**
  (`AppModel.launchRoute`): Home needs saved settings and the CLI (or a
  remembered "Skip for now"). A first run never lands on Settings.
- **The first run is the Add machine wizard, not a second implementation**
  (`OnboardingFlow`, a pure state machine driven by `OnboardingRunner`).
  The CLI is installed first, as a background step with its log
  (`MachinePlanStep.installCLI`: the release binary, never Homebrew),
  because the wizard reads keys and packages through it. Then
  `AddMachineWizardView` runs with `firstRun`: "Do you already have a
  server (VPS)?" (yes: address, login, key or password, `machines scan`
  fingerprint confirmed against the console; no: a Lima machine on this
  Mac, no address asked), packages, review of the exact commands, run.
  `firstRun` always syncs, always adds `devmachine-app` (essentials needs
  it, but `installed_on` lists only what a machine names itself), asks for
  the first workspace (`MachineWizard.requiresWorkspace`; a switch,
  `skipsWorkspace`, turns it off) so the app opens with one in the
  sidebar, and installs the skills (below). A Mac already connected
  but missing `devmachine-app` gets `packages add` + `sync` per machine,
  run the same way. A CLI older than `MachineUnattendedAdd` says so and
  offers the installer (`.cliTooOld`).
- **No agent setup.** The setup is deterministic and all in the UI: no
  "let your agent do it", no prompt, no "ask the agent". The owner's agent
  once hand-rolled a Lima VM with `limactl`, which the checklist can never
  see.
- **Every step is a background process with its log** (`MachineStepRunner`,
  `DMLogView`): no pane, nothing typed. Retry resumes from the failed step;
  the ones done are skipped (`machines add` is atomic on CLI 0.7.27+). A
  run that ends 0 but leaves the Mac as it was is `unresolved`, with Check
  again, never a loop. Demo mode refuses every run (`OnboardingDemoTests`).
- **The skills always install** when a harness is chosen: one
  `skills add --agent <h>… --yes` after the sync (`--agent` works for a
  harness not installed yet). The choices are the harness registry's
  harnesses that the CLI accepts (`SkillAgent.options`, which maps a
  `HarnessID` to its `--agent` name): claude, codex, pi and opencode on any
  CLI, antigravity, kimi and cline on 0.7.28+ (an older CLI refuses the
  whole command on an unknown agent). A new harness is offered once it is
  in `SkillAgent.cliAgents`. Preselected: Settings → Harnesses plus the
  harness folders this Mac has (`AddMachineModel.harnessesInUse`). A failed skills step is a warning
  with Retry (`MachinePlanStep.blocksSetup`), never a blocker for "Start
  using Devmachine".
- **A machine on this Mac installs Lima when it is missing**
  (`LimaInstall`, `LimaInstaller`): GitHub's latest release tarball for
  the Mac's processor, checked against the release's `SHA256SUMS` before
  a byte is written, unpacked into `~/.local` (`bin`, `share`, `libexec`);
  the temporary tarball is deleted whether the unpack worked or not.
  The CLI runs `limactl` by name, so `~/.local/bin` goes first on the PATH
  it gets. A failed download offers `brew install lima` when Homebrew is
  there. Only an unattended run (CLI 0.7.27+) can do this; an older CLI
  still shows `brew install lima`.
- **Every failure says how to fix it** (`SetupFailurePanel`,
  `SetupFailureHelp`/`SetupFailureAdvice` in Core): a cause read from the
  log (an outdated Xcode, a download, Lima's checksum, a changed host key,
  a refused login, an unreachable server) gets its own steps and buttons;
  anything else gets what the step ran, the last lines, Retry and Change
  answers. Every failure also has Report a bug (`DMReportBugButton`): the
  browser opens a new GitHub issue filled in by `BugReport`, with secrets,
  addresses, paths, emails, fingerprints, the typed hosts and domains, and
  the user, machine and workspace names (whole words, any length) taken
  out, under 7000 characters. The app never posts it. The
  DNS setup's failure has the same button.
- Demo walk `DEVMACHINE_DEMO_WALK=setup-flow` (`DemoSetupFlow`): `80`–`91`
  are the setup (start, CLI install and its failure, choice, server and
  local details, packages, review, running, failed, ready, old CLI),
  `92`–`95` Settings → General.
- **It ends on "Start using Devmachine"**: `completeOnboarding` reads the CLI
  again, fills the empty General fields, saves them and opens Home, with
  no restart. Settings → General shows what the CLI reports read-only
  ("Change…", "Edit"), re-reads it each time it opens, and an issue the setup
  fixes (no CLI; a folder other than the CLI's own with no `config.yml`)
  carries a button back into onboarding.
- **Leaving onboarding reads the CLI once, off the main thread**, and hands
  that answer to the workspace load. Then `onLeftOnboarding` reloads the
  machine lists (Home's stats machines, `MachinesStore`, readiness), so a
  machine the setup just added shows without a relaunch. The config
  folder watcher is made again on any check while the folder it watches
  did not exist when it was made (`isWatchingConfiguration`).
- The main window opens at 80% of the screen when AppKit has no saved frame
  for it (`MainWindowSizing`, read before any window exists); a saved frame
  always wins. Demo walk: `DEVMACHINE_DEMO_WALK=setup-flow`.

## Machine readiness
- **A machine missing `devmachine-app` gets a card, never a gate over the
  whole window** (`MachineReadinessStore`). Declared comes from `packages
  list`, applied from `packages.lock` in the CLI's config folder
  (`PackagesLock`), and a failed package call (`PackageCallReports`, posted by
  `DevmachineCLI`) overrides both until the lock changes. Anything unread
  fails open: no card.
- **Prepare syncs with `--tags devmachine-app` only** and only on CLI 0.7.24+
  (`MachinePrepare.minimumCLIVersion`). A plain sync would apply every change
  waiting in the configuration behind a button that says Prepare, and an older
  CLI's tagged sync wrote the whole plan into the lock. Never move the
  packages pin from the app: it is shared by every machine.
- **A session list never fails silently** (`SessionListProblem`): ssh looking
  the alias itself up as a hostname means no Host entry, exit 127 means no
  tmux. Neither stops the sweep or pauses polling; both show in the sidebar
  with the fix.
- The CLI's config folder is watched (`ConfigDirectoryWatcher`), so a machine
  or workspace added in a terminal shows up without a restart.

## Host keys
- **ssh refusing a host key is its own problem** (`SSHFailure.hostKeyRejected`,
  from ssh's own words on exit 255). No login was tried, so it counts toward
  no ban: the sweep goes on, polling is not paused, and the workspace is not
  painted offline. The sidebar shows one `HostKeySidebarCard` per machine,
  whether or not old sessions are still listed, and a click on one of those
  sessions opens the review. The 5s selection poll skips the alias; the 60s
  sweep still tries it. Only ssh's abort line ("Host key verification
  failed") counts: the CHANGED banner alone can precede a real login.
- **Review → `AppPage.hostKey(machine)`.** `HostKeyStore` runs `devmachine
  machines trust <m> --check --format json` (CLI 0.7.24+; an older CLI
  refuses a changed key without JSON and gets the update advice) on every
  visit, never from a remembered answer: a Lima VM writes a new key on every
  restart. The page
  shows both fingerprints and the CLI's `verify` command for the machine's
  own console, never over SSH.
- **The trust button stays off until the pasted console output holds the
  exact presented fingerprint** (`HostKeyTrust.confirms`), and the write
  passes `--expect <fingerprint>`, so the CLI refuses if a second scan meets
  a different key. It writes only the CLI's local `known_hosts`, never the
  machine.

## Publishing feedback
- `expose add` / `expose rm` run with `--format json` (CLI 0.7.21+): the
  result (`applied`, `status`, `note`) and the exact stderr drive
  `PublishProgress` (Core). The card (`PublishJobCard` on `DMJobCard`) sits
  in the corner stack: steps, then Live with Open/Copy, Saved with the
  reason, or `DMErrorStateView` with the CLI's stderr and Retry. An older CLI
  without JSON reads as Saved, saying it cannot tell.

## Tests never spawn ssh
`~/.ssh/config` maps `*-devmachine` to the real host, so a fixture alias such as
`acme-devmachine` logs into the VPS as the Mac user. `ProcessRunner` refuses
ssh/mosh/mosh-client/scp under XCTest; tests inject a fake `CommandRunner`.

## A test that blocks must let go
A fake that holds a call (`BlockingRunner`, a semaphore gate) holds one of
Swift's cooperative threads, and a CI runner has only as many as it has cores
(3 on `macos-15`). Three held calls left behind stopped every later
`Task.detached`, and ~80 unrelated tests timed out in the release job while
passing on a 12-core Mac. `BlockingRunner` opens itself when each test ends;
a new gate must be released the same way. To check, run the built bundle with
one thread: `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 xcrun xctest
.build/debug/DevmachineAppPackageTests.xctest`. (Not through `swift test`:
SwiftPM itself then hangs.) Only the tests that need two calls in flight at
once may fail there.

## Verifying UI
- Screenshot flow: `./scripts/install.sh` (relaunches), `osascript` to front the app,
  `screencapture -x -R<x,y,w,h>` of the window, downscale with `sips` before reading.
- Never send keystrokes into the app while the owner's sessions are open: `⌘K` +
  typing has landed in his live Claude sessions twice. Verify with screenshots,
  `tmux list-clients`/`capture-pane` over ssh, or ask him to try.

- **`ImageRenderer` does not lay out a `ScrollView`.** A snapshot of a view whose
  body scrolls comes back with the chrome and an empty middle, which reads as a
  bug that is not there. Snapshot the header and the state, and check scrolled
  content in the running app.

## Build / test
- `swift build` and `swift test` must be green before every commit.
- Package a bundle with `./scripts/package_app.sh` (writes `build/DevmachineApp.app`);
  `./scripts/install.sh` builds, installs `/Applications/Devmachine.app` and relaunches.
- `scripts/check-real-data.sh` runs as a pre-push hook with the private pattern list
  in `~/.config/devmachine-app/private-patterns`.

## Git
- Conventional Commits, one line, ENGLISH. Sign via the 1Password agent socket:
  `export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"`.
- **NEVER add any Claude/AI attribution, trailer, or `Co-Authored-By` — anywhere.**
- Branch prefix `da-` when not committing straight to `main` locally.

## Updates
- The updater replaces this app only. It never runs, changes or upgrades the
  CLI, its configuration, packages, machines or `sync`. For the CLI it shows
  the command (`CLIUpdateAdvice`) in a `DMCommandBlock` and stops there: never
  run it, never type it into a session.
- **A newer CLI gets its own corner toast** (`CLIUpdateBanner`, under the
  app's; both stack). Update runs only `update --cli-only` and only when
  `canUpdateCLIInApp`; any other CLI gets the `CLIUpdateAdvice` command in a
  `DMCommandBlock`. Later is saved per CLI version
  (`UpdatePreferences.cliLaterVersion`) and hides that version and older
  ones (`CLIUpdateToast.shows`); a running or finished update shows
  whatever Later said, the finished one until Close. Details opens
  Settings → About. Demo shots `65`–`69` in the `cli-update` walk.
- Pure logic lives in `DevmachineCore/Updates` (versions, release JSON, ETag
  feed, schedule, install method, digest, bundle checks, swap); the app's
  `Updates/` folder holds `UpdateController` and the real system calls. Tests
  inject fakes; nothing in `swift test` reaches the network, except the
  opt-in `DEVMACHINE_UPDATE_E2E=1` test, which installs into a temp folder.
- Never test an install against `/Applications/Devmachine.app` or by running
  `brew upgrade`: both replace the owner's app. Use a temp folder.
- A disk image install trusts only a bundle signed by the running app's Team
  ID. A local ad-hoc build has none, so it links to the release page instead.
- `scripts/package_app.sh` takes the version from the newest `v*` tag when
  `DEVMACHINE_APP_VERSION` is unset, so a local build compares correctly.
- AppKit will not quit while any window has a sheet attached (the log says
  "App termination blocked by modal sheet"), and the update dialog is a
  sheet. `AppRelauncher` starts the helper first (`DetachedProcess`: its own
  session, none of the app's open files), ends every sheet, then terminates.
  The helper opens the app only once the old pid is gone, never a second copy
  beside a stuck one; if the app is still running 10 s later, the dialog, the
  toast and About ask to "Quit and Reopen".
- To watch a real relaunch, run a debug build from a temp `.app` with its own
  bundle id: `open --env DEVMACHINE_DEMO=1 --env
  DEVMACHINE_RELAUNCH_REHEARSAL=<another .app> <copy>.app`. It "updates" to
  the other bundle through the real dialog, swap and relaunch. Debug only.

## Publishing through another machine
- **A workspace on a machine without Caddy is published by one that has
  it** (`expose add --via`). The add sheet's "Published by" lists the
  non-self machines with caddy (`CaddyStore.publishPlaces`); the
  workspace's own machine wins when it has caddy, then the machine the
  Subdomains page shows, then the first. `via` is passed only when it
  differs from the workspace's machine, so nothing changes for a machine
  that serves its own sites. Nothing known about where things live means
  no `--via`, as before.
- The Subdomains page of a machine with caddy also offers the workspaces
  of machines without it. After a publish, the serving machine is the one
  read again, not the workspace's.
- An older CLI answers `unknown flag: --via`; the card says to run
  `devmachine update` instead of showing Cobra's usage text. A published
  site whose serving machine cannot reach the port is live with an
  attention step carrying the CLI's note.

## DNS provider setup
- **A server with caddy and no DNS provider that answers gets a card on
  the Subdomains page** (`DNSProviderSetupCard`, `DNSSetupStore`, state in
  Core `DNSProviderSetup.evaluate`). Without one, `expose add` saves the
  site and only prints the record to make by hand; the card says so.
  Only `dns providers` answering with a zone ends it: a finished sync that
  still sees none keeps the card on "Run sync". A machine that could not
  be asked shows no card (fails open).
- Declared providers come from `packages list` (`installed_on`). A CLI
  that reports `kind`/`credentials` (0.7.27+) is read by `kind == "dns"`
  alone; an older one by the summary "DNS zones on …". The token is stored
  under the package's declared secret credential, else the package name.
- Add = `packages add <p> --machine <m> --yes`, then the zones if typed,
  then `secrets set <secret> --stdin`: all local to this Mac, behind one
  confirm. The token goes on stdin only, never argv, logs or the job
  output. Run sync = `sync --machine <m> --tags <p> --yes` then
  `credentials push --machine <m> --yes`, behind a confirm, as a machine
  job in the corner (`MachineJobCenter`), which holds the log; the card
  only says where it stands. A failed job retried or dismissed in the
  corner moves the card with it. A CLI older than 0.7.24 gets the commands.
- Hostinger's `hostinger.zones` is set with `machines edit <m> --set
  hostinger.zones=[…] --yes` behind a confirm on CLI 0.7.27+, after the
  package is added (the CLI refuses a setting for a package not there).
  Zones are plain names only (`DNSProviderCatalog.zones`). An older CLI
  gets a `config.yml` snippet; the app never edits `config.yml`. Demo
  mode refuses every write.
- `DEVMACHINE_DEMO_WALK=dns-setup` captures every state; its sync runs on
  a demo center whose runner is `DemoDNSSyncRunner`, which starts no
  process. Outside the walk, demo mode's sync fails in the corner.

## Machines and the Add machine wizard
- **Settings → Machines lists the CLI's configuration** (`MachinesStore`:
  `config path`, `version`, then `machines list` and `packages list`). A
  machine's packages are its own `packages` from `machines list` (CLI
  0.7.27+), else the `installed_on` of `packages list`. Before `config.yml`
  exists an older CLI fails every one of those calls, so the store checks
  the file first and reads "no machine" without calling them; a CLI with
  `MachineUnattendedAdd` lists the latest release's packages then, for the
  first machine (a failure there is no error: essentials is still offered).
  Remove runs `machines rm --yes` behind a confirm and only forgets the
  machine. A load asked for while one runs reads once more after it, so
  the last change on disk is always the one shown.
- **The sidebar offers "Add a machine" above Local only once a read says
  there is none besides this Mac** (`AddMachinePrompt`). Nothing is gated
  on a machine: Home and local sessions work with zero. One rule in
  `AppSettings.validate` covers both this and onboarding: Public IP and Base
  domain are optional (checked only once typed, filled from the CLI when it
  knows them); the CLI's own folder passes before `devmachine setup` writes
  its `config.yml`; only a missing CLI or another folder without
  `config.yml` blocks Save, with the setup flow as its fix. That folder is
  never silent: `AppSettings.notices` gives a non-blocking "No machine
  yet" with Run setup (onboarding) and Add a machine (the wizard); a fresh
  Mac that landed on Settings had nowhere to go. Demo shot:
  `95-settings-no-machine.png` in the setup-flow walk.
- **The wizard (`AppPage.addMachine`) only builds `devmachine` commands**
  (`MachinePlan`, Core) and shows them before Create. Packages are
  `--no-essentials` or `packages add`, then `workspaces new <w> --machine
  <m> --yes` (optional here, required by default on the first run) and
  `sync`. A workspace name is its Linux account's: the CLI's
  `linuxUserName` rule, at most 32 characters, not a system account or
  the admin login, not a workspace the configuration has
  (`WorkspaceName.problem`, shared with the Workspaces page). Package cards are machine packages whose `platforms` hold `linux`
  or are empty (any): a server and a Lima machine are both Linux, so a
  `[macos]` package is never offered. Essentials is always installed
  (locked, its `needs` listed as included and not offered again on their
  own); docker is suggested and checked (`MachinePackageCatalog.suggested`).
- **The column beside the form is never empty.** Before the run it holds
  `AddMachineSummaryView`: the answers so far (`MachineWizard.summary`,
  read from the same plan that runs) and the commands they would run
  (`previewCommands`, none until the machine has a name; on the review
  the commands are the page, so only the summary). The kind step has
  nothing to summarise, so its two cards take that room. The run puts its
  log and steps in the same 340-point column (`AddMachineContent.sideWidth`).
- **CLI 0.7.27+ adds with no terminal at all**
  (`MachineUnattendedAdd.minimumCLIVersion`, read from `version` into the
  `MachinesSnapshot`). Every answer is a flag: `machines add --address
  --fingerprint` with `--key <file>`, `--key agent:SHA256:…` (keys listed
  with `ssh-add -l` against the socket the app hands the CLI) or
  `--password-stdin`; `--domain` only for the first machine, which `add`
  then writes the configuration for, as `setup` would; a Lima machine is
  one `create-local <name> --add`. The steps run in the background
  (`MachineStepRunner`, `runProcess`), output shown as it comes; `add` writes
  the machine only once its key is proved, so Try again simply runs the
  failed step again.
- **A Lima machine is sized from this Mac on CLI 0.7.28+**
  (`LocalMachineSizing`, `LocalMachineSizeLimits`): CPUs up to every core,
  memory up to the Mac's minus 2 GiB, disk up to the free space minus
  10 GiB (Lima's disk grows as it fills). The default is half the cores
  (2–4), a quarter of the memory (4–8 GiB) and 40 GiB, clamped. The size
  goes to `create-local --add --cpus --memory --disk` and the review
  says it; an older CLI shows no controls, gets no flags, and a note
  names its own default size. Demo and tests inject the limits
  (`DemoData.macLimits`), never this Mac's.
- **The password is a `SecretText`**: in a `SecureField`, on the add's
  stdin and nowhere else. The step carries only `input: .password`, never
  the value, so it is in no argument, step id, display line or log;
  printing the draft shows dots. It is written to the pipe before the
  process starts (no SIGPIPE if the CLI exits first). The draft drops it
  when a run starts, whatever the outcome, when the page goes away, and
  when the context is read again; a Try again that needs it opens the
  answers instead.
- **The fingerprint is read before anything trusts it** (`machines scan
  --format json`, logs in nowhere, writes nothing): the wizard shows the
  presented key beside the CLI's `verify` command for the provider's
  console. `--fingerprint` is the console output pasted, or the scan once
  the person ticks that the console shows the same key; a paste that
  disagrees with the scan trusts nothing. A scan of another address or
  port counts for nothing.
- **An older CLI keeps the terminal flow.** A server whose key already
  logs in is added unattended; a password-only server, a Lima machine
  (`create-local`, then `machines add`) and the very first machine (`setup`)
  go through the CLI's own questions, and the page lists the answers to
  type. The commands run in a local terminal pane (`MachineStepRunner`), so
  a password goes straight to the CLI. Only `sh <script>` is typed (any
  login shell, fish included); the script prints a per-step nonce marker
  the runner finds in the scrollback. A failed step shows
  `DMErrorStateView`; Try again skips the steps done. Tests inject
  `MachineStepRunner.Hooks`; nothing types into a real pane or starts a CLI.
- **No run waits forever.** Stop ends a run in either mode (Ctrl-C into
  the pane, or the background process is cancelled, which
  `StreamingProcess` turns into SIGTERM). A terminal step that ends
  without its marker is noticed when the pane's shell is its terminal's
  foreground group again, twice in a row (`ProcessTree.isAtPrompt`), and
  any step fails after `stepTimeout` (3 h: a first sync is slow) with
  what to do.
- **A failed run goes back to its answers.** "Edit answers" (and Close)
  return to the details with every answer but the password; steps done
  stay done, and the machine the run already wrote does not block its own
  name. Reopening after a success starts fresh. When the context is read
  again (a newer CLI found meanwhile), the wizard returns only as far as
  every step before is still valid (`MachineWizard.restore`), so a step
  that now needs a password or a fingerprint is where it stops.
- **No `config.yml` means no machine, not an unread list**: `machines
  list` fails before it exists, and `StatsStore` then checks the file and
  drops its cached cards, so Home never shows machines from an old
  configuration. Any other failed read keeps the cache.
- `DEVMACHINE_DEMO_ONLY=id,id` captures only those screens of a walk.
- `DEVMACHINE_DEMO_WALK=machines` captures Settings → Machines, every
  wizard step (key file, password, agent key, scan), a background run in
  each state, the first machine with its domain, the sidebar with no
  machine (Home with no machine cards), `legacy-` shots of an older
  CLI's terminal flow, and `cli-socket-` shots (Home and Stats on a CLI
  whose socket path is too long). Demo mode scans no server and reads no agent
  (`DemoData.addMachineScan`, `addMachineAgentKeys`) and refuses every run:
  `MachineStepRunner.run`, `MachinesStore.removeMachine`,
  `PackagesStore.apply` and `ProcessJobRunner` (every machine job: Prepare,
  DNS sync, Packages sync) each refuse before reaching a terminal or the CLI
  (`DemoRefusalTests`).

## Machine jobs
- **Every `devmachine` run against a machine is a machine job** (`MachineJobCenter`,
  `MachineJobToast` in the corner stack): Prepare, the DNS provider sync and the
  Packages page's sync. A screen never streams a sync into its own layout.
- **A sync is asked for, not started** (`requestSync`): the card asks "Sync
  <machine>?" and runs only on its button, which is the confirm the VPS-writes
  rule needs. Two asks for one machine merge into one card (tags join, full
  wins). One job runs per machine; the next waits as queued.
- **A tagged sync never records a removal** (the CLI's lock only updates tagged
  entries), so a request with a removal, or a CLI before 0.7.24, starts full.
- The log keeps the newest 5000 lines (`JobLog`) and arrives in batches
  (`JobOutputBuffer`): a hop per line carrying the whole log froze the window.
- `DMLogView` anchors its scroll at the bottom: `scrollTo` alone, on a lazy
  stack of wrapped lines, stopped a line or two short of the error.

## Packages page
- Settings → Packages reads `packages list`, `config show` and `packages.lock`.
  Declared is `installed_on`; applied is the lock (machines and workspaces).
  A package the lock has because another one `needs` it is "via <parent>",
  never "pending removal"; a workspace always has `workspace` (the CLI adds it).
- "Pending" is derived from config and lock, so a sync put off with Later is
  still offered ("Sync now") after a relaunch.
- Apply runs `packages add|rm … --yes` one by one; the first failure stops it and
  asks for no sync. Removing never uninstalls: the row and the confirm say so.
- `DEVMACHINE_DEMO_WALK=packages` (`DemoPackages`) seeds the store and the
  corner at each moment (every machine, `main` with two ticks, the confirm,
  the sync pending, running, done, failed); nothing runs.

## Workspaces page
- **`AppPage.workspaces` lists every workspace by machine** (`WorkspacesStore`:
  `workspaces list --format json` with its `settings`, and `packages.lock`).
  "Applied", "Waiting for sync" or "Not created yet" come from the lock's
  `workspaces` map (`WorkspaceSync`): every declared package in it is applied.
  A package taken off is not caught: the lock also lists what the declared
  ones pull in. No `config.yml` yet means no workspace, without a list call.
- **Reached from** the sidebar's + beside WORKSPACES ("New workspace…", under
  the new-session items), ⌘K "Workspaces…" and "New workspace…"
  (`requestNewWorkspace`, taken by the page through `pendingNewWorkspace`),
  and Settings → Workspaces "Manage workspaces…". Settings keeps only the
  sidebar visibility toggles; the page owns everything else.
- **Every flow is a `WorkspaceFlow` (Core) and runs through
  `MachineStepRunner` in the background**, with `MachineRunLayout`,
  `DMLogView` and `SetupFailurePanel` (Retry, Report a bug), like the wizard.
  New and Edit: form, review of the exact commands, a confirm, run. New is
  `workspaces new <w> --machine <m> --packages a,b --yes` (`--packages=` when
  every card is off) then `sync --machine <m> --yes`; Edit is `workspaces edit
  <w> --add/--rm/--set/--unset … --yes` then the same sync, never `--machine`
  (there it moves the workspace). "Apply it now" off skips the sync.
- The name uses the wizard's rule (`WorkspaceName`); the machine picker lists
  non-self machines only. Package cards are workspace packages for Linux,
  grouped by `category`, the account package `workspace` locked on.
- **CLI 0.7.29 reports what the page used to guess** (`WorkspaceJSON`, read
  from `version`; an older CLI keeps the fallbacks). `config show` gives
  `defaults.workspace`, which is the preselection and the DEFAULT badge
  (fallback: the setup's own `dev`, `zsh`, `mise`, and the form says it
  cannot read yours), and the top-level login answers. `packages list` gives
  each package's `variables`: Edit shows one typed field per declared
  variable of the packages kept (boolean as Default/On/Off, list and map as
  YAML text, a number checked before Continue), empty meaning the default;
  anything else stays in the free-text "Other settings". `workspaces list`
  gives each workspace's own `credentials`: Edit lists the logins its
  packages declare (`WorkspaceLogin`: the workspace's answer, then the
  configuration's, then the package's scope) with As configured / Shared /
  Own, written as `--share <login>=machine|own`, or `<login>=` to follow
  the configuration again. A login whose `credentials[].shareable` is
  false (CLI 0.7.29 with `shareable`; always false for a secret or a file)
  offers only As configured / Own, with the reason, and follows `own`
  whatever the configuration says, as `sync` does. A CLI that leaves
  `shareable` out keeps all three, and a Shared it refuses fails at the
  sync with its message.
- Edit mirrors the CLI's checks: a free-text setting is `<package>.<name>`
  for a package the workspace keeps, with a value (an empty `--set` would
  remove it). The machine and the account stay in the terminal.
- **Forget and Destroy are different on purpose.** Forget is `workspaces rm
  <w> --yes` behind a confirm: only this Mac's configuration changes. Destroy
  is `workspaces destroy <w> --confirm <w>` (+ `--keep-dns`, a checkbox) and
  runs only once the name is typed exactly. The CLI's refusals (a site
  published through another machine, an unreachable machine) are its
  `error:` line, shown as the failure's cause; nothing is guessed.
- Once a step changed the configuration, "Change answers" is gone (the name
  now exists); Retry runs only what failed. Any run that changed something
  reloads the sidebar, Settings → Machines, readiness and the cached
  workspace list.
- Demo mode reads `DemoData.workspacesSnapshot` and refuses every run ("Demo
  mode never changes a workspace."). `DEVMACHINE_DEMO_WALK=workspaces`
  captures `130`–`144`: list, new, a taken name, review, running, failed,
  done, edit, edit review, forget, a refused forget, destroy, Settings →
  Workspaces, a new workspace with no harness on, and Settings → Harnesses
  (every harness with a package has a switch). It turns on Claude, Codex
  and Pi, and Edit shows glab's login, which cannot be shared.

## VPS writes
Features that write to the VPS or public DNS run only on an explicit user action
in the app, behind a confirm, and never from tests. The app delegates publishing
to `devmachine expose`; it does not edit Caddy, DNS, or Ansible itself.
