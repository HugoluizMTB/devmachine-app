# Home: layout and widgets

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Home layout
- **The default Home board is laid out for the canvas it opens on**
  (`DefaultBoard.make(harnesses:canvasWidth:machines:)`). `HomeCanvasView`
  opens the board only once the canvas has a width, so a missing `home.yml`
  is written for the real window; 1280 is the fallback. Every machine sits
  side by side in one row at the top (sized from `MachineStatsCard.width` and
  `MachinesWidgetView`'s spacing, for the machine count `StatsStore` knows, 3
  when none), one `devmachine-app/usage` per enabled harness under it (two
  across from two harnesses, 336-480 wide), and on the right edge a 336-416
  column with the clock and the summary pill under it. Machines, usage and
  the summary are `size: auto` (no `h` in their frame): they are as tall as
  their content. `DefaultBoard.layout` also gives the height it reserved for
  each one (machines: its rows; usage: 600, because the full card with a
  typical snapshot measures 591 at any width; summary: 160) so the rows under
  them are spaced; those heights only space the stored `y`, and the push-down
  (below) fixes any overrun on screen. The clock stays fixed. The pill sits at
  the top of its widget so it reads as part of the clock.
  `DefaultHomeBoardTests` pins the frames; `DefaultHomeBoardFitTests` draws the
  real cards against the reserved heights. The `HomeLayout` notes below
  describe the pre-widget view.
- **`HomeLayout.plan` decides from Home's width alone**; showing or hiding
  the sidebar only changes that width. The clock sits in the middle of all of
  Home when, there, it still clears the cards column by the gap
  (`HomeClockPlacement`, Core, with the clock's width estimated at 2.8 times
  its scaled point size); otherwise in the middle of the column beside the
  cards. Its height never changes: it is laid across the same row.
- **The button that reopens a collapsed sidebar floats over the centre**, so
  Home moves its cards (stacked: everything) down until they start below it
  plus a gap (`FloatingButtonClearance`, Core). ContentView measures the
  button in its `window` coordinate space and hands it down as
  `\.collapsedSidebarButtonFrame` (nil while the sidebar shows); HomeView
  measures itself in the same space. It once covered the first card's name.

## Home widgets
- **Home is `<config>/boards/home.yml`, nothing else.** `<config>` is what
  `devmachine --format json config path` answers (`DevmachineCLI.configPath()`,
  called by `HomeBoardController.start()` off the main thread; it honours
  `DEVMACHINE_CONFIG`), never `AppSettings.opsRepoPath`.
  The app, `devmachine widgets add/remove` and agents edit the same file.
  `BoardStore` reloads it on every change. The app never creates the config
  folder: with no folder, nothing is written.
- **The CLI writes by rename, so `BoardFileWatcher` watches the `boards/`
  folder.** A watch on the file alone goes blind after the first CLI write,
  because the rename swaps the inode. The file is watched too, for editors that
  write in place. Bursts settle for 150 ms, so one save is one reload.
- **What is on disk wins.** A write waits 300 ms (`BoardStore.writeDelay`) and
  is dropped when the file changed since the store last read it: the CLI's
  edit replaces the app's pending one. An invalid file keeps the last good
  layout on screen, the banner names the line, and nothing is written until it
  is valid again: someone is fixing it by hand. An edit still waiting when the
  file turns invalid is dropped, and the last good layout comes back. Reset is
  the one write allowed then: it saves `home.yml.bak` first. With no config
  folder it writes nothing, keeps the placements and shows an error.
- **A failed `widget-placements.json` save is not silent.** The placement
  stays in memory, the error goes to the `widgets` log and to
  `HomeBoardController.placementsError`; the next good save clears it. If the
  CLI's config path is unknown at launch, the next reload asks again.
- **Yams reads, our code writes.** Three writers produce the file (the app, the
  CLI, a person or agent), so the reader must accept any YAML style. A
  hand-made parser would call valid files invalid, and that blocks every write.
  The writer (`BoardCodec.encode`) stays ours because the spec fixes the key
  order and the flow-style `frame`. It quotes text with the rules in
  `YAMLScalarStyle.swift`, kept compatible with the CLI's `yaml.v3`. Cross-writer
  tests guard that: change the quoting and they fail.
- **The golden fixture is the CLI's file.**
  `Tests/DevmachineCoreTests/Fixtures/widget-contract-1.7.json` must stay
  byte-identical to `internal/widgets/testdata/contract.json` in the CLI repo.
  Change one, copy it to the other. `widgets schema --json` prints the same
  document re-indented, so the live test compares it as sorted-key JSON.
- **Frames are points at 100% text size** (`CanvasLayout`). The canvas
  multiplies by the text scale to draw and divides to store, so the file reads
  the same at any setting. A window smaller than the layout moves widgets in on
  screen only.
- **A widget is never lost** (`CanvasBounds`, Core). Every widget is drawn
  fully inside the canvas when it fits, else pinned top-left so its top
  shows; push-down stops where the top 44 pt (`CanvasBounds.grab`) is still
  on screen. A drag stays on the canvas, a resize stops at its edge. Every
  widget is drawn and resized at least to its declared minimum raised to
  160x80 (`CanvasBounds.floor`; a growing view only to 44 high), placeholders
  and failed cards included. Clamping is display only: the file changes only
  on a move or resize, so a window that shrinks and grows back shows the
  saved layout, and an old file with a widget far off screen draws it in view.
- **The top 44 pt of a card drags it** (`WidgetChromeLayout.moveStrip`), on
  any content, error and placeholder cards included; buttons in that strip
  still win their clicks. The hover handle's grip and ⋯ are 44 pt high too.
  A web page eats its own mouse events, so over a web widget only the handle
  drags.
- **A stored `x` is a place on Home with the sidebar open**
  (`CanvasLayout.aligned`). With the sidebar hidden the canvas is wider, and
  `HomeCanvasView` draws each widget from the sidebar-open width to the real
  one: widgets that touch (8 pt or less apart) move as one group, a group
  within the margin (24 pt) of an edge stays at that edge, any other keeps its
  share of the free space between the margins (a centred group stays centred).
  The rule is its own inverse when the groups are the same, so a drop with the
  sidebar hidden aligns back from where the widgets are drawn, before clamping
  and push-down, and stores the x of the dropped widget's whole group: a widget
  dropped beside a group joins it, and the group keeps its place on screen.
  With the sidebar open nothing moves.
  The file format did not change: the CLI rejects unknown keys in a board.
- **A widget is as tall as what it shows (engine 1.7).** A view with
  `"grows": true` in the contract (summary, machines, harness usage, text,
  number, status, list, markdown) has a natural height; the others (clock,
  gauge, sparkline, web, terminal, pull-requests panel, usage panel) do not.
  The rules are `CanvasLayout`, pure and tested:
  - `size: auto` on Home, with `frame: {x, y, w}` and no `h` (`BoardWidget.isAuto`;
    `frame.h` is 0 in memory, and the encoder writes nothing). A written `h` next
    to `auto` is read and dropped. Without `auto`, `h` is required
    (`<id>: frame needs h unless size is auto`); `auto` on a view that does not
    grow is refused with the sidebar's own message (`BoardCodec` for an inline
    widget, `WidgetResolution` for a typed one).
  - Drawn height = `auto ? content : min(content, max(h, 40))`
    (`drawnHeight`). A stored `h` on a growing view is a **cap**, never a
    floor: an old `custom` 160 pt summary draws at its pill. A growing view has
    no preset height minimum (one `stack_row`, 40 pt, when set by hand); its
    minimum width is the smallest preset width. Other views keep today's minimum.
  - The content height is measured by the view, not guessed. `WidgetChromeView`
    draws an `auto` widget with `hugs: true` (every growing view then reports
    its natural height: no `maxHeight: .infinity`, no `ScrollView`, no
    `GeometryReader`; machines draw every card, list every row) and reads its
    size with `onGeometryChange`. A widget with a cap draws in its box as
    before and keeps an invisible hugging copy only to learn the content
    height. `HomeCanvasView` stores the measure per id in board points; it is
    never written to the file. **Never give a hugging view `size.height`:** it
    would feed the last height back as the next offer and the widget could
    never grow.
  - **Push-down is display only** (`CanvasLayout.pushedDown`). Widgets are
    taken by stored `y`, then `x`; a widget's drawn `y` is `max(stored y,
    drawn bottom + 8 of every earlier widget whose columns overlap)`. It never
    pulls up, and stored frames do not change until the person moves the
    widget. A widget dragged is not pushed while it is held.
  - **Resize**: width as before; for a growing view the stored `h` is the
    height drawn at release, `min(dragged, content)`; within one snap (8 pt) of
    the content the entry becomes `size: auto` (`resizedGrowing`).
    The "..." Size picker lists Auto first for a growing view.
  - **Reset size** ("..." menu, and a double-click on the resize corner)
    returns a growing widget to `auto` at the width of its `default_size`, a
    fixed one to its `default_size` preset (`CanvasLayout.reset`,
    `HomeBoardController.resetSize`).
  - New widgets (gallery, `WidgetPlacer.newInstance`, inline
    `InlineEntryPlacement`) and the default board are `auto` for a growing
    view. The spot search cannot measure, so an `auto` widget occupies the
    height of its `default_size` (inline: 160), as the CLI's `widgets add`
    does.
  - `ImageRenderer` does not lay out a `ScrollView`, so the natural-height
    tests (`WidgetAutoHeightFitTests`, `DMFitCheck`) draw the `hugs: true`
    views, which have none.
- **Home is never blank while it has no catalog** (`HomeCatalogNotice`): a
  first read shows "Fetching the packages release…" (`DMStatusView`), and a
  network failure is read again on `RetryPolicy.downloads` while it stays
  `.loading`, even when no board waits for the catalog. Only then the
  "Could not fetch packages" card with Retry. A failure that is not the
  network's (no CLI) shows the card at once and is not retried, so an app
  without the CLI stays quiet.
- **A widget's meaning comes from the CLI catalog** (`widgets list --format
  json`, `WidgetCatalogStore`). The app ships no `widget.yml`. An entry the
  catalog cannot resolve keeps its place as a placeholder, so a missing
  package never loses a layout. `DemoData.widgetCatalog` is for demo
  screenshots only.
- **`places` adds a widget once.** `widget-placements.json` in Application
  Support (`WidgetPlacementsFile`) remembers it, so a removed widget does not
  come back. Placement is generic (`WidgetPlacer.place`): a widget that
  places itself and has one single-value `choice` input is placed once per
  option of its source, and the placements file keys each copy
  `<type>#<option>` (for usage: `devmachine-app/usage#claude`). A usage
  widget is placed only for a harness turned on in Settings, and never for a
  harness the board already shows (the default board's `devmachine-app/usage`
  entries, or an older `claude-code/usage` or `codex/usage` entry).
- **Stats keep their own schedule.** A widget never starts its own `stats`
  ssh; it reads `StatsStore`. Usage refreshes per harness on the widget's
  interval. A minimized widget, or one scrolled out of sight, refreshes
  nothing.
- **Compatibility fails open.** `WidgetAppManifest.current` names the CLI and
  packages release this build needs. The corner card shows only when one is
  readable and older. A `dev` CLI is never "behind". Newer releases are the
  update toasts' job, not this card's.
- Test hooks: `DEVMACHINE_CLI=<binary>` runs another CLI,
  `DEVMACHINE_WIDGET_PLACEMENTS=<file>` moves the placements file, and
  `DEVMACHINE_DEMO_BOARDS=<folder>` keeps a demo board across restarts.
- **A widget written in the board runs only after "Allow".** An inline
  `command`, `prompt` or `session` widget (the contract's `approval: true`)
  shows `WidgetApprovalCard` until the owner allows it. The decision is kept
  by SHA-256 (hex) of the canonical JSON (keys sorted, no spaces) of what
  runs, taken at run time with the area's real context
  (`ApprovalSubject.hash(for:context:)`): kind, run/script/args, shell,
  target, harness, prompt, permission mode (only when set, so older approvals stay valid), session, and for `shell: true` the `DM_` values it
  reads (only the `$DM_CONTEXT_<KEY>` the line names is exported and hashed) — never `every`, `timeout`, `mode`, `keep` or `parse`. The card and
  the stored summary read `ApprovalPrompt`, built from that same filled
  source and `DM_` values, so the owner approves exactly what the hash
  covers, never the raw templates. The runner
  checks the hash again right before every run (`SourceApprovalGate`). It
  lives in `Application Support/Devmachine/widget-approvals.json`, never in
  the config folder: whoever can write a board must not be able to approve
  it. Any change to what runs asks again; Deny pauses and keeps the widget,
  with "Allow" to change your mind. Every area keeps its own copy of the
  decisions, so a decision is merged onto what the file holds now
  (`WidgetApprovalsFile.record`, read, change, atomic write), never saved
  from the stale copy, and then announced (`WidgetApprovalsFile.didChange`,
  object = the file URL); every `WidgetSourceController` on that file
  reloads and runs what was allowed. An unreadable file means everything
  waits again. A package widget asks only when its package is third-party
  (see Package providers and third-party widgets); `url` and app providers
  never ask.
- **A value is never part of a shell line** (`ArgvBuilder`, the one place a
  widget argv or shell line is built; templates are filled once, at run
  time, with the area's real context). `shell: true` takes no templates in `run` and
  no `args`: the line reads its values as `$DM_INPUT_<NAME>` and
  `$DM_CONTEXT_<KEY>` environment variables. Without `shell`, templates go
  only in `args`, never in `run`: the program is named in `run`, found on the
  PATH here and started directly — never through `/usr/bin/env` or a shell,
  which would read a value-like word as an option or as code. Prompts run
  `claude -p -- <prompt>` and `codex exec --skip-git-repo-check -- <prompt>`
  (the `--` keeps a prompt that starts with `-` from being a flag).
- **A widget on a machine or workspace runs only through `devmachine run`**,
  with the argv of the CLI plan's Appendix B: `--machine` before `run`,
  `--workspace` after it, `--no-log`, then `--argv -- <words>` (a shell line
  is `--argv -- /usr/bin/env NAME=value … /bin/sh -c <line>`, each pair one
  word) or `--package <p> --script <s> -- <args>`, or, for a package
  provider, `--package <p> -- <command> --<key> <value> …`. `--config` is never passed:
  the process inherits `DEVMACHINE_CONFIG`. The app never opens its own ssh
  for a widget. stdin is `/dev/null`; exit 255 is "never ran" with the CLI's
  last `error:` line; exit 1 with `unknown flag` and no stdout asks for a
  newer CLI. `target: local` runs on this Mac in the home folder, with the
  known tool folders added to PATH (`LocalPATH`), `/bin/sh -c` for
  `shell: true`.
- **One run in flight per widget; polls only while Home is on screen.**
  `SourceSchedule` runs a poll on its interval (floors: command and url 5s,
  session 2s, prompt 15m; prompt defaults to manual), a manual widget only on
  ▶, and a stream only while it is on screen and not minimized. Hiding,
  minimizing or removing it, or leaving Home (`onDisappear` →
  `WidgetSourceController.stop()`), sends SIGTERM, and that exit is never
  shown. A stream that ends on its own waits for ▶. A timeout or more than
  1 MB of output ends the process; the last good value stays with the error
  beside it. Demo mode never runs a source.
- **A widget poll is not a machine job.** It draws in its own card and never
  registers a `BGTask` or a `MachineJobCenter` job (unlike sync, Prepare and
  the other runs against a machine).
- **Session widgets read, never type.** A remote session is
  `tmux capture-pane -p -e`, a local one `zmx history <session> --vt`; the
  terminal view is a parsed `AttributedString`, not a SwiftTerm view. A click
  selects the session (workspace or local); a machine's admin session is not
  clickable.
- **Web widgets** share one non-persistent `WKWebsiteDataStore` for the app
  run (not the preview browser's), allow http(s) in the main frame only, open
  no popups, and reload on `every` only while the view exists. The address
  comes from `URLSourceRunner.address(of:context:)`, the fill a `url` fetch
  uses; one that is not http(s) shows its error in the card, never a blank page.
- **Inline entries are written back as they were read** (`YAMLTree`: flow or
  block, quoting kept), in the order `id, title, source, view, sizes, fits,
  frame, size, minimized, z`, byte-identical to the CLI's writer; a
  cross-writer test (`testAnInlineWidgetSurvivesARewriteByteForByte`) guards it.
- **Unit tests never run a widget for real**: no real CLI, no ssh, no
  network, no real config folder, Application Support or keychain — fakes
  and temp folders. The one exception is opt-in:
  `DEVMACHINE_WIDGETS_E2E=<binary>` runs `WidgetSourceLiveTests` through that
  CLI against a temp config whose only machine is `here` (`self: true`, this
  Mac), with `DEVMACHINE_KEYCHAIN=off`. It never targets a remote machine.
  The same variable runs `StackBoardLiveTests`, `MenubarBoardLiveTests` and
  `WidgetEditLiveTests`.
