# Devmachine

A native macOS app (Swift 6, SwiftUI + AppKit) that operates your dev machines
(Debian, Ubuntu, Arch Linux or macOS) over ssh: tmux sessions per context user
as floating terminals, a session grid per workspace, a context panel fed by the
host, published apps (Caddy subdomains), host stats, PRs, and coding agent usage
in the menu bar.

The host itself is provisioned by the [devmachine CLI](https://github.com/adevmachine/cli).
The app only needs an ssh alias to it and the CLI's configuration folder on this
Mac, usually `~/.config/devmachine`.

## Requirements

- macOS 14+ and the Xcode Command Line Tools (`swift build` is the build).
- `~/.ssh/config` with one `Host <alias>` for the machine (root) and one
  `Host <user>-<alias>` per context user. The workspace list itself comes from
  the devmachine CLI's `workspaces list`; the ssh config supplies the alias
  each workspace connects through.
- Optional: the 1Password ssh agent for signing. Nothing else: the app
  carries its own `mosh-client` (see Remote terminals).

## Build and install

```
./scripts/install.sh
```

Builds a release bundle and installs `/Applications/Devmachine.app`. The first
launch shows a Setup card: configuration folder, host ssh alias, public IP, base
domain, wallpaper. Change them later with `⌘,`.

Settings → Coding agents can enable multiple coding agents installed on this Mac: Claude
Code, OpenAI Codex, Pi, Antigravity CLI, opencode, Kimi Code and Cline. Each
local or remote workspace chooses one default launch program, while remote
choices remain declarative: the app does not install, inspect, or repair tools
on the host. A session running any of them gets its badge and the Context
panel. A session running Herdr gets its icon too.

Enabled coding agents that report usage (Claude Code, Codex) receive usage cards on Home and
in the menu bar. With Claude Code and OpenAI Codex enabled, Home stacks both
cards and the menu-bar Usage tab shows them side by side. Codex account limits
and activity come from `codex app-server` account reads; they do not start a
model turn or consume inference tokens.

## Sidebar order

Drag a workspace's header to move the whole workspace, Local included. Drag a
session to move it inside its own workspace; a session never moves to another
workspace, and dropping it on one does nothing. The order is kept for your
macOS user and survives a relaunch. A new workspace or session goes to the
end. Hiding a workspace in Settings → Workspaces forgets its place, so it
comes back at the end. ⌘⇧↑/↓, the command palette and session grids follow
the same order.

## Color picker

The eyedropper in the menu bar's footer, or ⌘K → Pick a color from the
screen, shows the system loupe. Move it anywhere on any screen and click: the
color under it goes to the clipboard as sRGB hex (`#1A334D`). Esc cancels.

## Remote terminals

A remote pane uses mosh when it gets through and ssh when it does not.
Settings → Appearance → Terminal → Remote terminals: Automatic (default), Always ssh, or
Always mosh. A pane shows which one it runs: `mosh` or `ssh` in the session grid
header and the context panel.

- The app carries `mosh-client` in `Contents/Helpers`, built from source by
  `scripts/fetch_mosh.sh` (pinned mosh and protobuf, checksums checked,
  protobuf linked in, universal). A local build without it uses Homebrew's
  from `/opt/homebrew/bin` or `/usr/local/bin`.
- The app starts the server itself over ssh (`mosh-server new -s -c 256 -l
  LANG=C.UTF-8 -- tmux new-session -A -s <session>`), reads `MOSH CONNECT`,
  and starts `mosh-client <ip> <port>` with the key in `MOSH_KEY`. The Perl
  `mosh` wrapper is not used.
- The address: `devmachine resolve --machine <m> --format json` when the
  installed CLI has it, otherwise the host `ssh -G <alias>` reports, looked
  up here.
- Falling back, so a pane never hangs: no `mosh-server` on the machine →
  ssh at once. No reply over UDP within 5 seconds (the `firewall` package
  keeps 60000–61000 closed until `firewall.mosh_interface` is set) → the pane
  switches to ssh, ends the unreachable server, and says so with a Details
  popover. The machine then goes straight to ssh for 30 minutes, or until
  "Try mosh again".

## Machine readiness

The app runs its stats, logs and session context on each machine through the
`devmachine-app` package. It checks every configured machine at launch, when
the CLI's configuration folder changes (a machine or workspace added, a sync
recorded in `packages.lock`), when you come back to the app, and when a call
into the package fails because it is missing or too old. The configuration
says whether a machine asks for the package; the lock says whether a sync
applied it. A read that fails says nothing, so no card shows.

A machine without it gets a card on Home and in the sidebar: "<machine> isn't
ready for the app yet" and **Prepare**. Prepare runs, in the background with
its log on the card, `devmachine packages add devmachine-app --machine <m>
--yes` when the configuration does not ask for it yet, then `devmachine sync
--machine <m> --tags devmachine-app --yes`, which applies only that package
and nothing else waiting in the configuration. It needs CLI 0.7.24 or newer,
the first whose tagged sync records only what it applied in the lock; an older
CLI gets the commands to copy and a link to update the CLI. A package from an
older release than the app needs is not fixed by a button: the packages pin is
shared by every machine, so the card explains it and shows `devmachine
packages pin` and `devmachine sync --machine <m>`.

A workspace whose sessions cannot be listed says why in the sidebar instead of
showing an empty list: no SSH alias yet (with `devmachine aliases --write`),
no tmux on the machine, a refused login, or a machine that does not answer.

To run the real Prepare against a throwaway `devmachine-accept-*` Lima VM
whose configuration does not ask for devmachine-app yet:

```
DEVMACHINE_KEYCHAIN=off DEVMACHINE_CONFIG=<temp config> DEVMACHINE_PREPARE_E2E=<devmachine 0.7.24+> \
  swift test --filter MachinePrepareEndToEndTests
```

When the CLI is missing, onboarding's **Install CLI** installs it in the
background with its log: `brew install mydevmachine/tap/devmachine` when this
Mac has Homebrew, otherwise the installer from
`https://mydevmachine.sh/install.sh`, which puts it in `~/.local/bin` without
a password. The command to copy stays beside the button.

## Updates

The app checks the latest release of `mydevmachine/app-releases` 30 seconds
after launch and every 6 hours (Settings → About → "Check for updates
automatically", on by default), or when you pick **Check for Updates…** in
the Devmachine menu or ⌘K. It asks GitHub with the last `ETag`, so a check
that finds nothing new does not count against the API's rate limit. Drafts
and prereleases are ignored. Nothing installs until you click **Update and
Relaunch**; **Skip This Version** hides that version until a newer one ships.

An update replaces only the app. It never touches the CLI, its configuration,
packages, machines or `sync`, and sessions keep running (they live in `zmx`
and `tmux`, not in the app).

- **Installed with Homebrew** (the app is `/Applications/Devmachine.app` and
  the `devmachine-app` cask is installed): the app runs
  `brew upgrade --cask mydevmachine/tap/devmachine-app` in the background,
  shows its output, and relaunches. You can also run
  `brew upgrade --cask devmachine-app` yourself.
- **Installed from the disk image**: the app downloads
  `Devmachine-X.Y.Z.dmg`, checks its sha256 against the
  `Devmachine-X.Y.Z.dmg.sha256` asset (or the `sha256:` line in the release
  notes of older releases), mounts it read-only, and checks the app inside:
  `codesign --verify --deep --strict`, the same Team ID as the running app,
  `spctl --assess --type execute`, the same bundle ID, and the promised
  version. It then copies the app beside the current one and swaps the two
  with renames, putting the old one back if the second rename fails. When
  the app's folder is not writable, it shows the verified copy in Finder to
  move by hand.
- **A local build** (`scripts/install.sh`, signed ad hoc) has no Team ID to
  compare against, so it only links to the release page.

The app also compares `devmachine version` with the latest
`mydevmachine/devmachine` release and, when the CLI is behind, shows the
command to run in Settings → About and ⌘K: `brew upgrade devmachine` for a
Homebrew install, the install script otherwise. From CLI 0.7.23 on, the
**Update CLI** button there runs `devmachine update --cli-only` in the
background and shows its log: it replaces the binary only. From CLI 0.7.31 on
it runs `devmachine update --no-machines --format json` instead: the CLI
replaces itself, then the new binary pins the newest packages release and
updates the skills on this Mac. Neither form runs doctor or sync, reaches a
machine, or types into a session. An older CLI does not know `--cli-only`, and
plain `devmachine update` would touch machines, so the app only shows the
command for that one manual update.

From CLI 0.7.31 on the app also asks `devmachine packages outdated` on the
same schedule. A newer packages release gets its own corner card: Update runs
`devmachine update --no-machines --skip-cli`, which moves the packages pin and
the skills only. Your machines change when you sync them from Settings →
Machines; the app never syncs for you.

To try the whole disk image path against the published release, into a
temporary folder:

```
DEVMACHINE_UPDATE_E2E=1 swift test --filter UpdateInstallerEndToEndTests
```

## Development

```
swift build
swift test
```

Read `CLAUDE.md` before changing anything: it holds the rules of this repo,
including the one that no real infrastructure data ever enters the tree.

## Credits

Wallpaper: photo by [Reed Naliboff](https://unsplash.com/@reednaliboff) on
[Unsplash](https://unsplash.com/photos/a-person-sitting-in-the-water-with-a-surfboard-92KySh7wzl8).

Wallpapers: photos from [Unsplash](https://unsplash.com) by their respective
photographers; each photo shows its credit in Settings.
