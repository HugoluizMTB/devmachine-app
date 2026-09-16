# CLAUDE.md — devmachine-app

Native macOS app (Swift 6 / SwiftUI / AppKit, SwiftPM) that operates the
`devmachine` VPS: tmux sessions per context-user, PRs, files, Caddy subdomains,
VPS stats, Claude usage. Sibling of `~/dev/devmachine` (the ops repo).

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
  persisted in `UserDefaults`) and the ops repo on disk. A feature that needs an
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
- Create a new `Window` ONLY when the owner explicitly asks for a separate window.
  Existing exception: the **Files** window is contextual per-workspace (opened
  from the sidebar folder button) and stays a window for now.

## Menubar
`MenuBarExtra` uses `.menuBarExtraStyle(.window)` — an interactive popover with a
tab bar (`MenuBarTab`), mouse-navigable like pr-menubar. Tabs render inline
(Pull Requests, Usage, …); no separate PR window. The popover should size itself
to the active tab. Tab styling should be elegant/custom, not the raw native
segmented control.

## Reusable structure
- `DevmachineCore` (library): pure logic, parsers, command builders — unit-tested,
  no UI, no AppKit where avoidable.
- `ClaudeUsageKit` (library): reusable Claude-usage data layer + views. Depends
  only on Foundation/SwiftUI/Charts. NEVER depends on the app target; the app
  depends on it. Reuse its views in the menubar tab, central pages, and Home.
- `DevmachineApp` (executable): the app shell + SwiftUI views.
- Shared UI in `Sources/DevmachineApp/Components/DMComponents.swift`
  (`DMRow`, `DMSection`, `DMPill`, `DMProgressBar`, `DMToastCard`, `DMStatBubble`)
  + `Theme.swift` (`Color.dm*`). Reuse these; match the dark palette.

## Hard UI rules
- **Never put a `Divider` inside a `ZStack`** — it becomes horizontal and greedy.
  Use `Rectangle().frame(width:1)` / `.frame(height:1)`.
- Numbers shown to the user go through `Text(verbatim:)` with explicit formatting.
  Never `Text("\(intValue)")` — SwiftUI localizes it (pt-BR renders `5.182`,
  `740,31M`). This bug already shipped once; don't repeat it.
- A central page must fill the center (`.frame(maxWidth:.infinity, maxHeight:.infinity)`),
  never float at intrinsic size.
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
- `TerminalRegistry` owns ONE live `LocalProcessTerminalView` (mosh → `tmux new-session -A`)
  per session for the app's lifetime. `TerminalPaneView` only attaches/detaches it;
  single pane and stack-grid cells re-parent the same view. Never mount the same
  session in two places: two tmux clients at different sizes make `window-size latest`
  flap and garble the screen. Detached views are LRU-capped (6); a dismantled pane
  never terminates the process (only delete/rename/quit do).
- Remote sessions run with `TERM=tmux-256color` (`RemoteCommands.remoteTerm`), never
  `xterm-256color`: the host's `/etc/tmux.conf` gives every `xterm*` client `extkeys`,
  tmux then forwards the kitty keyboard protocol Claude Code 2.1.269+ turns on, and
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
- **A translucent pane is painted by BOTH layers, each at `Appearance.layerOpacity`.**
  The terminal must paint its own background: handing it `.clear` so the container
  could paint instead leaves every cell the terminal does not redraw showing what
  was there before, which is a screen half old and half missing, and slow, since a
  large transparent layer is expensive to blend. Painting in both places at full
  alpha stacks them and the pane reads almost solid, so each gets the share that
  combines to the setting. A day went into this; don't collapse it back to one layer.
- **The terminal fills its card: no padding ring, no stroke.** A ring around the
  terminal carries only the container's share of the translucent colour, so it
  reads lighter than the text area — a second border. Masking the container to
  the ring is not the fix: a layer mask clips sublayers too, so it hid every
  terminal and the app came up with no panes at all.
- **A pane that returns unchanged gets no size change, so nothing redraws it.**
  Switching sessions, closing a page, coming back from the stack: the program was
  never told anything happened. The app asks explicitly — `tmux refresh-client` for
  a remote session, the window-changed signal to the foreground process group for a
  local one (`TerminalRegistry.requestRepaint`). Do not fake a resize instead: an
  earlier version shrank the pane a row and restored it, which left the last row
  unpainted, and another killed the local client and restarted it, which left the
  keyboard wired to the process that had just died.
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
- **Hiding a workspace is a list of what to hide, not of what to show**
  (`AppSettings.hiddenWorkspaces`, filtered by `WorkspaceVisibility`). A new
  alias in `~/.ssh/config` shows up without anyone opening Settings. Everything
  except Settings reads `AppModel.visibleWorkspaces`, so a hidden workspace
  costs no row, no poll and no ssh; hiding also closes its panes at once
  (`TerminalRegistry.closeWorkspace`), which is what ends the mosh it held.
- **The Local workspace lists what `zmx ls` reports**, merged with what the app
  remembers (`LocalSessionScan.merge`): a session started outside the app shows
  up, and a remembered one that has no shell yet shows without a client count.
  One `ps -axo pid=,ppid=,comm=` per poll says which sessions hold a Claude.
- **A local session is renamed in the sidebar only.** `zmx` has no rename and its
  socket is named after the session, so `LocalSession.handle` (the multiplexer
  name, and the registry key) never changes; `name` is what the sidebar shows.

## Performance rules (learned from a 2 GB footprint)
- Poll only while a view is visible (`onAppear`/`onDisappear` begin/end, refcount),
  one in-flight run per target, publish a `@Published` only when the value changed.
- Never decode an image or run a blur inside `body`; bake once (`WallpaperBackground`)
  and cache with a cap. Hidden `.opacity(0)` views still cost a full-window drawable —
  render only what is shown. No `.shadow` on full-window cards.
- Session polling is a sequential sweep that stops at the first ssh-level failure and
  pauses (5 min on `Permission denied`, 1 min unreachable): parallel auths against a
  locked agent got this Mac banned by fail2ban. Keep it that way.

## Tests never spawn ssh
`~/.ssh/config` maps `*-devmachine` to the real host, so a fixture alias such as
`acme-devmachine` logs into the VPS as the Mac user. `ProcessRunner` refuses
ssh/mosh/scp under XCTest; tests inject a fake `CommandRunner`.

## Verifying UI
- Screenshot flow: `./scripts/install.sh` (relaunches), `osascript` to front the app,
  `screencapture -x -R<x,y,w,h>` of the window, downscale with `sips` before reading.
- Never send keystrokes into the app while the owner's sessions are open: `⌘K` +
  typing has landed in his live Claude sessions twice. Verify with screenshots,
  `tmux list-clients`/`capture-pane` over ssh, or ask him to try.

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

## VPS writes
Features that write to the VPS or public DNS (e.g. Caddy add-subdomain) run only
on an explicit user action in the app, behind a confirm, and never from tests.
The `add-subdomain` flow lives in the `devmachine` repo skill; the app mirrors it.
