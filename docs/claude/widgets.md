# Widget boards: sidebar stacks, menu bar, editing, package providers

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Sidebar widget stacks
- **The sidebar and the Context tab are boards.** `<config>/boards/sidebar.yml`
  and `<config>/boards/context-sidebar.yml`, same envelope and store rules as
  `home.yml` (`StackBoardStore` = `BoardFileStore<StackBoard>`: disk wins,
  300 ms write, an invalid file is never written over, reset keeps `.bak`).
  `surface:` must match the file. A stack entry has no `frame` and no `z`;
  its place is its index. Optional `size` is a preset (its rows × `stack_row`
  40 pt) or `auto` for a view that grows (since engine 1.7 that includes the
  generic views text, number, status, list and markdown and the canvas app
  views summary, machines and harness usage; on `auto` a source widget or a
  canvas app view draws with `hugs: true`, as tall as its content, the same
  rule as on Home); with no `size` it draws `auto` when
  the view grows, else the widget's `default_size`, its first size, or
  `medium` (`StackLayout.effectiveSize`). A widget the app adds (gallery or
  placement, `StackPlacer.newEntry`) is written with that size, `auto` or
  the preset, as `devmachine widgets add --board` writes it, so the YAML is
  the same whoever added it. `collapsed: true` draws the header
  only and runs nothing. Key order on write: typed `id, type, with, size,
  collapsed`; inline `id, title, source, view, sizes, fits, size, collapsed`;
  `size` only when set, `collapsed` only when true. Inline `source` and
  `view` are written back as they were read, byte for byte.
- **A row's width is the scroll view's content width, never the scroll
  view's own** (`StackBoardView` measures the `VStack` inside the
  `ScrollView`). A row pinned to the scroll view's width is wider than its
  content area by the scroller; a row with a fixed height hid that, but one
  that hugs its height (`auto`) made the panel 15 pt wider on every layout
  pass and hung the main thread.
- **The default boards are today's UI** (`DefaultStackBoard`): `[workspaces]`
  and `[shortcuts, publish-port, monitors, shells, sub-agents, todo,
  pull-requests, links]`, every entry `type: devmachine-app/<id>`,
  `size: auto`. The CLI starts from the same boards when a file is missing.
- **Wrap, never rewrite.** The nine app views (`WorkspacesWidgetView`,
  `PublishPortWidgetView`, `ContextSectionWidgets`, `StackAppWidgetView`) hold the old SidebarView and ContextPanel code,
  moved as it was. Change them as you would have changed the old code; never
  "clean them up" into new layouts: selection, ⌘/⇧-click, `SidebarOrder`
  drag, host-key and readiness cards, row menus and the add-machine button
  live there. Shortcuts and Publish a port scroll with the rest; at offset 0
  the panel looks as it did.
- **The sidebar never empties.** The nine `devmachine-app/*` widgets resolve
  built in (`AppStackWidgets`) when the catalog lacks them; a catalog entry of
  the same name wins, and the stack gallery lists them even while the
  catalog loads or failed (`WidgetGalleryContent`, failure line above the
  list). With no config path the default board draws in memory,
  read-only. An invalid file on first read draws the default read-only under
  a `DMBanner` naming the file and line (the last good layout once one was
  read); nothing is written until it is valid.
- **The chrome stays out of the way** (`StackRowModel.showsControls`). A
  widget with its own section header (shortcuts, monitors, shells,
  sub-agents, todo, pull-requests, links) shows grip, chevron and ⋯ in that
  header's trailing slot (`StackHeaderControls()`) on hover. The workspace
  list and Publish a port have no header, and a pill there would cover the
  first workspace's buttons, so their pill shows only while the pointer is
  over them **and ⌥ is held**. Any other widget gets a `StackTitleHeader` with
  the controls always shown. The "Add widget" row is always in the layout, at
  the end, drawn (and hit-testable) only while the pointer is over the panel.
  An app widget with nothing to show (no pull requests, no links, a section
  before the first read, Shortcuts with no session, Publish a port with no
  Caddy) takes no space at rest or on a plain hover, as before; only while
  ⌥ is held over the panel (the `.bare` rule) does it draw
  `StackEmptyWidgetHeader`, its title row with the controls, so it can still
  be collapsed, moved or removed (`StackRowModel.showsEmptyHeader`).
- **One session-context section leads** (`ContextSectionLead`): before the
  first read, the board's first expanded one draws the status view; after
  it, the first that draws something carries the age label.
- **A header drag freezes the list.** While the grip's drag is held the rows
  come from a snapshot (`StackBoardView`'s `StackDrag`), the dragged row
  lifted by `.zIndex` and offset; it lands by the neighbour it crossed
  (`StackDragMath`, `StackDropTarget`) and the order is written once, on
  release. Never reorder or remove the view holding a live drag.
- **Context keys, every one set, empty when unknown.** Sidebar: `selected`
  (the selected workspace, `SidebarContext`). Context tab (board\n  `context-sidebar`): `machine,
  session, workspace, path, repo, branch, harness` (`SessionContextFacts`,
  built by `ContextBridge` from the selection, `ContextState`, readiness and
  the self machine). `session` is the tmux session or the local session's
  name; `machine` is the workspace's machine, or the self machine for a local
  session; `path` is `ContextState.cwd`, else the local session's folder.
- **`repo` and `branch` cost a probe, so they run only when read.**
  `ContextGitProbe` (`git rev-parse --abbrev-ref HEAD` and
  `remote.origin.url`) runs through `HostRunner.runCapturingWithFolderArgument`
  (the folder is `$1` after `cd --`, never spliced into the line), only
  while an expanded widget reads `repo` or `branch`
  (`StackBoardController.needsGitContext`). It probes on a new session or
  folder, on each new session-context read (`ContextState.updatedAt`, so a
  `git checkout` shows), and when the Context tab appears, keeping the last
  answer meanwhile. A new read probes at most once per 30 s for the same
  session and folder (`GitProbeThrottle`); a new session or folder, or the
  tab appearing, probes at once. A failure is retried on the first read
  30 s later, not sooner. No timer of its own (`ContextGitStatusStore`).
- **A session switch hands over its context once per widget**
  (`ContextPushGate`). While the new session's first context read is out,
  the board keeps the old keys. While only the git probe is out (judged by
  the key about to be probed, not the store's last one), every other key
  goes at once with `repo`/`branch` pending
  (`WidgetSourceController.setContext(_:pending:)`): a widget that reads a
  pending key (`ResolvedSource.reads`) keeps its last context and output and
  does not run until the probe answers; the rest run at once. So no widget
  runs on an empty `path` or `branch` first, no approval card flashes, and a
  hung ssh holds only the widgets that need git.
- **A context change stops what it touches.** A widget whose read values
  change is stopped, what it showed is cleared (it belonged to the other
  session; sparkline history stays) and its approval hash is taken again: an
  inline widget asks again for each new set of resolved values, by design. A
  widget reads only the keys its templates or `$DM_CONTEXT_<KEY>` variables
  name (`ResolvedSource.reads(contextKey:)`); an inline `shell: true` line
  gets and hashes only the `DM_CONTEXT_` values it names; an inline `script`,
  whose text the app never sees, reads them all. A package widget reads the
  keys it declares.
- **Allow and Deny count only for the hash the card showed**
  (`WidgetSourceController.approve(_:hash:)`): if the context moved on, the
  card redraws with the new values and asks again. A source widget waiting
  for approval or denied takes at least `StackLayout.approvalRows` (5) rows so
  the card's buttons fit.
- **Who runs when.** Sidebar widgets run while the sidebar is open
  (`isVisible: !sidebarCollapsed`; SidebarView stays mounted at width 0);
  the context board's while the Context tab is on screen. A collapsed widget
  runs nothing. `ContextStore` keeps its 5 s poll only under
  `ContextPollRule` (panel shown, not collapsed, Context tab, a target, and
  an expanded widget reading `app/session-context`, or an expanded source
  widget reading `path` or `harness`, which come from the same poll:
  `StackBoardController.needsSessionContext`).
- **Placements are saved per surface** (`WidgetPlacementsFile.save(_:surface:)`):
  Home and each sidebar rewrite only their own set. A placements file that
  does not decode moves to `widget-placements.json.broken`, the move is
  logged, and the save goes on with a fresh file. If that write then fails,
  the error itself names where the broken file went
  (`cannotWriteAfterSettingAside`), so the move is never lost.
- **Controllers start from `ContentView.onAppear`**
  (`StackBoardController.startAll()`), never from a view a test can render,
  so rendering `ContextPanel` in a test never asks the CLI anything. No test
  reads `StackBoardController.sidebar` or `.contextSidebar`.
- Test hook: `DEVMACHINE_WIDGETS_E2E=<binary>` runs `StackBoardLiveTests`
  against a temp config the test makes itself: the schema equals the
  fixture, and the CLI's `validate`, `move` and `remove` on an app-written
  `context-sidebar.yml` keep an inline entry byte for byte and refuse a
  `frame`.

## Menubar
`MenuBarExtra` uses `.menuBarExtraStyle(.window)`: an interactive popover. The
title and the popover are widget boards (engine 1.4), owned by one
app-scoped `MenubarController.shared`:

- **Two files.** `<config>/boards/menubar.yml` (surface `menubar`, layout
  `slot`) and `<config>/boards/menubar-panel.yml` (surface `menubar-panel`,
  layout `tabs`). Same envelope and store rules as the sidebars
  (`StackBoardStore`, `StackBoardController`): disk wins, 300 ms write, an
  invalid file is never written over (the popover shows the banner), reset
  keeps `.bak`. A slot entry has no `frame`, `size`, `collapsed`, `z` or
  `minimized`; at most 3, left to right. A tab has no `frame`, `z`,
  `minimized` or `collapsed`; its `size` is kept on write and ignored.
- **Defaults are today** (`DefaultStackBoard`): `[brand, open-pull-requests]`
  and `[pull-requests-panel, usage-panel]`, no `size`. They resolve built in
  (`AppMenubarWidgets`), so a missing CLI or packages release never changes
  the title or the tabs. `MenuBarLabelTests` pins today's label pixels; keep
  it green.
- **The title is text plus one SF Symbol per slot** (`MenubarLabelModel`),
  so macOS can template it. A slot draws `text` (first non-empty line, cut
  at 24 characters counting the "…"), `number`, `status` (a symbol per
  level: colour is lost in the menu bar) or `app.brand` ("❯_"). Any other
  view is refused. A `number` view with `hide_zero: true` draws nothing at 0
  (the built-in open pull request count sets it); without it, 0 shows. With
  nothing to draw, the title shows "❯_", so the item never vanishes.
- **Who runs when.** The title's widgets run from launch, window or not
  (`DevmachineApp.init` starts the controller; never a view, never a test).
  A slot source's `every` is raised to 30 s, and a stream is refused. The
  popover's widgets run only while it is open, and only the selected tab
  (`StackBoardController.setVisibleEntries`); Edit mode shows no tab, so
  none runs. Open and close come from `onAppear`/`onDisappear` and also
  from the menu bar window's `didBecomeKey`/`didResignKey`
  (`MenubarPanelWindowWatch`), because a `MenuBarExtra` window kept alive
  between opens may skip them. `MenubarPanelPresence` lets only the first
  signal of an open or a close act; a window that gives up key but stays
  on screen stays open. The title's ticks never redraw the popover: the
  controller publishes only what the popover reads (`approvals`).
  `PRStore` and `HarnessUsageStore` keep their own schedules; the providers
  `app/open-pull-requests`, `app/pull-requests-panel` and `app/usage-panel`
  only read them. The 30 s floor and the 24-character cut are the app's;
  the CLI only carries the numbers in the contract.
- **Wrap, never rewrite.** The Pull Requests tab is `PRsView` as it is; the
  Usage tab is `MenuBarUsageColumns`, the old block moved as it was. Width
  776 and height 640 for every tab (`MenuBarSizing`, `UsageLayoutTests`).
- **Approval.** A title widget waiting for approval draws "!" in its slot;
  a denied one draws nothing. Both are listed, as their `SourceWidgetCard`,
  in an "Approvals" tab that comes first and is selected when the popover
  opens. An answer given in any area (Home, the sidebar, the Context tab, the popover)
  reaches the title at once: see "A widget written in the board runs only
  after Allow" for how every area shares the approvals file.
- **Edit mode** (pencil in the footer) lists both boards with up, down and
  remove, and "Add widget" opens `WidgetGalleryView` in place, filtered to
  that surface. A full menu bar disables "Add widget" and says why ("The
  menu bar holds 3 widgets", `StackGallery.fullReason`), and a placed
  widget never makes a fourth slot.
- **Settings → Appearance** resets the menu bar and the menu bar popover
  ("Reset menu bar", "Reset menu bar popover") under their own "Menu bar"
  heading, after "Sidebar and Context tab"
  (`StackBoardController.reset()`, `.bak` kept).
- Test hook: `DEVMACHINE_WIDGETS_E2E=<binary>` runs `MenubarBoardLiveTests`
  against a temp config: the CLI validates the app's default boards,
  refuses a fourth slot and a slot `size`, and moves a tab keeping an
  inline entry byte for byte. No test reads `MenubarController.shared`.

The footer's eyedropper and ⌘K's "Pick a color from the screen" share
`ScreenColorPicker` (the system `NSColorSampler`); the clipboard text is
`ScreenColor.hex` (Core), converted to sRGB first so the hex matches what a
web page or design tool means by it.

## Choosing and editing widgets
Engine 1.7. One mechanism for every widget, on Home, the sidebars and the
menu bar; the app has no code for a particular widget's choices.

- **A `choice` input declares its list.** `inputs.<name>: {type: choice,
  from: machines|workspaces|harnesses, many: bool}`. The widget menu shows
  "Choose ..." for each one (`ChoiceInput.all(of:)`, title from its summary),
  and `WidgetChoiceView` draws a checklist (many) or a picker (one). Options
  come from `WidgetOptionSources` (`StatsStore.machines`,
  `AppModel.visibleWorkspaces`, `HarnessUsageStore.states`), the one place
  that knows the sources; tests hand it closures. Never add a menu item or
  a view that names a widget or an input.
- **Saving a choice.** `WidgetChoiceModel.save` returns a
  `WidgetChoiceOutcome`: `.saved` closes the chooser, `.refused(message)`
  keeps it open and shows the message. It asks the board first
  (`WidgetEditTarget.problem(with:for:)`), then applies.
- **Many: empty means all.** No value, `[]` or every option ticked writes
  no `with` key, so a machine added later shows too. A chosen name the
  source no longer has stays in the chooser as "(not found)" to untick; the
  widget just draws nothing for it. One: no value means the first option,
  decided by the view (`UsageHarnessChoice`).
- **Lists in `with`.** `BoardScalar.list`, written flow (`[main, here]`). A
  template reads it joined with commas; an app provider gets the list in
  `ResolvedWidget.listArguments`. The codec reads the shape; resolution
  refuses a list for a single input and a scalar for a many input, with the
  CLI's words (`InputShapes`).
- **Overrides.** A typed entry may carry `title` and `every`
  (`EntryOverrideRules`): `every` never goes below the provider's, source
  kind's or package provider floor, a stream takes none, and a widget that
  reads an app provider takes no `manual` (it runs on a schedule). Inline
  entries own their title and source, so `every` there is refused. Key
  order: `id, type, title, with, every`.
- **Every edit replaces one entry.** The chooser and the editor build an
  `EntryEdit` and hand it to the board's controller (`WidgetEditTarget`:
  Home and every `StackBoardController`), which writes through the store:
  the 300 ms rule, disk wins, nothing while the file is invalid. Other
  entries stay byte for byte, and an inline source or view the edit did not
  change keeps its YAML tree.
- **An edit is refused only for a problem it adds.**
  `problem(with:for:)` compares the entry's resolution before and after the
  edit. A widget that was already refused (a missing package, say) can still
  change its title; the edit is blocked only when it makes the entry worse
  or names an input the widget does not declare.
- **The editor writes YAML and reads it back.** `InlineWidgetForm` (Command,
  URL status, Web page, Prompt, Session; only Command and URL status in the
  menu bar) writes a one-entry board with one field per line, reads it with
  `BoardCodec` and the area's resolver, and puts each problem under its
  field. An inline widget the templates cannot show edits its title only.
  `TypedEntryForm` edits a package widget's title, inputs and `every`.
- **Approval is unchanged.** An edit that changes what runs (command,
  arguments, target, prompt, session) asks again; title and `every` never
  do (`WidgetEditApprovalTests`).
- **A prompt's permission mode comes from the contract.**
  `PromptSource.permissionMode` holds the harness's own name, nil for its
  default; `PermissionModes` is the only code that reads the contract's
  `permission_mode` field (names per harness, the `dangerous` list, the
  CLI's two messages). `ArgvBuilder.prompt` turns it into the harness's
  flag (Claude `--permission-mode <m>`; Codex `--sandbox <m>`, or
  `--approve-for-me` / `--dangerously-bypass-approvals-and-sandbox`), and
  no mode keeps the old argv byte for byte. The mode is in the approval
  hash, the card names it, and a mode with no checks shows a red line.
  Such a mode never runs on a timer: the reader refuses it, an `every`
  override refuses it, and the Prompt form sets Every to manual and
  locks it. Never write a mode list in Swift: the picker reads
  `InlineWidgetForm.permissionModes()`.
- **Sheets on Home and in the sidebars, in place in the menu bar.** A
  sheet or nested popover from the `MenuBarExtra` window is not reliable, so
  the menubar Edit mode swaps its body for the chooser or the editor.

## Package providers and third-party widgets
- **A package provider is `<pkg>/<command>`** (`PackageProviderName`; `app/*`
  stays the app's). It is `WidgetSource.packageProvider`, kind `provider`,
  output token `json`: any view that takes `json` draws it with
  `{{json.<path>}}`. App providers keep `.provider` and `AppWidgetProviders`;
  a package provider runs through `WidgetSourceController` like a command.
- **It runs only on a machine or workspace, only through `devmachine run`**:
  `--machine <m> run --no-log` or `run --workspace <w> --no-log`, then
  `--package <pkg> -- <command> --<key> <value> …`. `target: local` is refused
  by the reader and again by `PackageProviderRunner`. The CLI's `commands`
  gate applies (the `Call` path, not `--script`).
- **`ArgvBuilder.packageProvider` is the only builder.** `with` pairs go in
  sorted key order; a key must match `[a-z][a-z0-9_-]*`; a value is always one
  argv item, even empty, starting with `-` or holding shell syntax. A value
  holding NUL is refused. The name holds no template. Never route it through
  the shell-line builders, which drop empty words.
  `ArgvBuilderTests.testAPackageProviderValueIsAlwaysOneWordAfterItsFlag`
  guards it.
- **Output is one JSON object** holding every `returns` field without `?`.
  Anything else (a list, two documents, nothing, a missing field) is an error
  and the last good value stays. `every` is ≥ the provider's `min_every`
  (floor 5s) or `manual`; `timeout` defaults to 30s, at most 10m.
- **A package widget reads only its own package's providers.** A catalog
  widget of `acme-tools` naming `mine/load` is refused, whatever the CLI let
  through.
- **Trust comes from the catalog** (`widgets list` `trust`): `official` and
  `local` run as before; `third-party` (a package with
  `.devmachine-source.yml`) asks before any code-running widget (`command`,
  `prompt`, `session`, package provider) runs. An older catalog without
  `trust` reads `release` as official, anything else as local. Each of these
  reads as third-party: an unknown or unreadable `trust` word, a
  `package_source` with no `trust`, and a widget `provider` key that does not
  read as a provider spec. An inline package-provider widget always asks.
- **No package-provider widget written in a board runs before a catalog
  loads.** Until then it resolves to `.waitingForCatalog` ("Waiting for the
  widget catalog…"): no job and no Allow button, so no approval without the
  package commit can be stored. Once the catalog loads it gets its trust and
  commit from the top-level `providers` map.
- **A failed catalog reload marks the kept catalog stale** (`isStale`).
  Third-party catalog widgets that run code, and every inline package-provider
  widget whatever its trust (a stale catalog cannot vouch for it), then wait
  as above until a read works, as the commits it holds may be older than what
  `packages update` installed. Official and local catalog widgets and `url`
  widgets keep running.
  While it is stale, the shared `WidgetCatalogStore` reads `widgets list`
  again on `CatalogRetrySchedule` (30s, 60s, 120s, then every 5 min): one
  pending retry for Home and both sidebars, stopped by a good read, a seed
  or app quit (`stopForQuit` also drops the quit observer, as `deinit` does;
  nothing retries after it). A failed first read (no catalog yet) is retried
  the same way, but only while some board holds a `.waitingForCatalog` widget:
  each controller reports it (`setWaitsForCatalog`) when it syncs its jobs, and
  the retry stops once no board does. Only with no catalog does a board report
  start a retry, so a board sync during a stale spell never moves the backoff
  ahead. With no CLI it settles at every 5 min.
- **The provider index is complete only when a packages release was read**
  and `providers` is there, as `widgets validate` decides it. Without a
  release an unknown package is left to `devmachine run`; a package the
  catalog lists still refuses a provider it does not declare.
- **A third-party hash carries the package commit** (`package_commit` in the
  canonical JSON, even when empty), so `packages update` to a new commit asks
  again for every such widget. That holds for a catalog widget (its
  `package_source`) and for an inline widget naming a third-party provider
  (the commit comes from the catalog's top-level `providers` map). Inline
  widgets of other providers and official/local hashes are unchanged from
  engine 1.2, so no stored approval was lost.
- **Never pass a complete provider index into `BoardCodec`.** The board
  reader checks only shape, target and the 5s floor (`PackageProviderIndex
  .unknown`); the catalog check runs later, in `WidgetResolution`, and refuses
  only that one widget. In the reader, a provider the catalog does not know
  is a `BoardProblem`: the whole board falls back to its last good layout and
  nothing on it can be written until the provider appears.
- **The card says where the code comes from**: "From a third-party package:
  <url>" (selectable) replaces the "written into <surface>.yml" warning, at
  every density.
- `DEVMACHINE_WIDGETS_E2E=<binary>` also runs `PackageProviderLiveTests`: the
  real CLI must take the argv against a temp config (self machine `here`,
  nothing synced) and answer "not installed", never "unknown flag".
