# CLAUDE.md — devmachine-app

Native macOS app (Swift 6 / SwiftUI / AppKit, SwiftPM) that operates the
`devmachine` VPS: tmux sessions per context-user, PRs, files, Caddy subdomains,
VPS stats, and coding-harness usage. It reads the devmachine CLI's configuration
folder (`~/.config/devmachine`) and publishes through the CLI.

This file holds the rules that apply everywhere and an index of the rest. The
detailed rules live in `docs/claude/`, one file per area. **Before changing an
area, read its file.** Each file is binding for its area, as this one is.
A rule in one file that says "see X" names a section; the index below says
which file holds it.

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

## Index of the area rules (`docs/claude/`)

- `docs/claude/ui.md` — "Page" = a central panel, never a window; the command
  palette (⌘K); reusable structure (Core, HarnessUsageKit, Services); the
  component library (`DM*`, tokens, `DMMetrics`); hard UI rules (few lines,
  gestures, hit-testing, `Text(verbatim:)`, BGTask cards); window toolbar;
  scroll bars; the right panel. Read before any view or component change.
- `docs/claude/terminals.md` — Terminals (SwiftTerm, `TerminalRegistry`,
  `TERM`, selection, OSC 52, repaint, copy mode, uploads, worktree removal,
  local sessions, shell integration); remote terminals (mosh, falling back to
  ssh); the tab strip over the terminal (⌘W, ⇧⌘W).
- `docs/claude/previews.md` — the Preview tab, tunnels, the in-app browser
  (`WKWebView`, `PreviewPage`, popups, downloads, keys), the document split.
- `docs/claude/home.md` — Home layout (default board, clock, floating button)
  and Home widgets (`home.yml`, `BoardStore`, frames, auto height, push-down,
  approvals, `ArgvBuilder`, `devmachine run`, schedules, session and web
  widgets, catalog, placements).
- `docs/claude/widgets.md` — sidebar widget stacks (`sidebar.yml`,
  `context-sidebar.yml`, context keys, git probe, who runs when); the menubar
  boards; choosing and editing widgets (`choice` inputs, overrides, the
  editor, permission modes); package providers and third-party widgets
  (trust, catalog, hashes).
- `docs/claude/coding-agents.md` — coding agents (`harness`: detection vs
  activation, launch places, icons, Context readers, process matching);
  Chats (`devmachine chat`, warm sessions, MCP, quick panel, Ask); the
  Operator session.
- `docs/claude/polling.md` — performance rules (polling, the sequential ssh
  sweep, `PollPause`, `LoginHolds`, wake and the SSH agent, first sync,
  `StatsStore`); local-first machine data (`DataCache`); host keys
  (`HostKeySheet`, trust); logs (`AppLog`, `LogRedactor`).
- `docs/claude/onboarding-updates.md` — first run (`OnboardingFlow`, the Add
  machine wizard as first run, Lima install, retries, failure help, finishing
  steps); updates (`CLIUpdateCommand`, the unified update dialog, CLI and
  packages toasts, relaunch).
- `docs/claude/machines.md` — machine readiness (`devmachine-app` package,
  Prepare, agent refusal, session list problems); Machines and the Add machine
  wizard (`MachinePlan`, unattended add, scan, password, Lima sizing, older
  CLI flow); machine location and the network map (also Home's map
  wallpaper); SSH password login; machine jobs (`MachineJobCenter`); the
  Packages page; Settings → Workspaces (`WorkspaceFlow`, Forget vs Destroy);
  the Scheduled page.
- `docs/claude/publishing.md` — publishing feedback (`PublishProgress`);
  publishing through another machine (`--via`); DNS provider setup
  (`DNSSetupStore`, the shared form, Remove); VPS writes (explicit action,
  behind a confirm, never from tests).
- `docs/claude/testing.md` — tests never spawn ssh; a test that blocks must
  let go (`BlockingRunner`); verifying UI (screenshots, never keystrokes into
  the owner's sessions, `ImageRenderer` and `ScrollView`); website videos
  (`scripts/site_demo_videos.sh`, demo walks).

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

## Changelog
- **Every app release adds an `App vX.Y.Z — date` entry to
  `~/dev/devmachine-cli/docs/changelog.md`** (the public changelog the site
  publishes at https://mydevmachine.sh/changelog/). Push it to the CLI's
  `main`, then `gh workflow run deploy.yml -R mydevmachine/docs`. Only what a
  user can see changed; no tests, CI or internal work.

## Where a rule goes
A new rule for one area goes in that area's file under `docs/claude/`, and a
new area gets a new file plus one index line above. Only a rule that applies
to the whole repo goes in this file, which must stay well under 150k
characters.
