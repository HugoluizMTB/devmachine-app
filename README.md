# Devmachine

A native macOS app (Swift 6, SwiftUI + AppKit) that operates one Linux dev host
over ssh: tmux sessions per context user as floating terminals, stack grids per
workspace, a context panel fed by the host, Caddy subdomains, host stats, PRs,
and coding-harness usage in the menu bar.

The host itself is provisioned by the [devmachine CLI](https://github.com/adevmachine/cli).
The app only needs an ssh alias to it and the CLI's configuration folder on this
Mac, usually `~/.config/devmachine`.

## Requirements

- macOS 14+ and the Xcode Command Line Tools (`swift build` is the build).
- `~/.ssh/config` with one `Host <alias>` for the machine (root) and one
  `Host <user>-<alias>` per context user. The workspace list itself comes from
  the devmachine CLI's `workspaces list`; the ssh config supplies the alias
  each workspace connects through.
- Optional: `mosh` (`brew install mosh`) — terminals use it when present and
  fall back to `ssh`. Optional: the 1Password ssh agent for signing.

## Build and install

```
./scripts/install.sh
```

Builds a release bundle and installs `/Applications/Devmachine.app`. The first
launch shows a Setup card: configuration folder, host ssh alias, public IP, base
domain, wallpaper. Change them later with `⌘,`.

Settings can enable multiple coding harnesses installed on this Mac. Each local
or remote workspace chooses one default launch program, while remote choices
remain declarative: the app does not install, inspect, or repair tools on the
host.

Enabled harnesses that are locally available receive usage cards on Home and
in the menu bar. With Claude Code and OpenAI Codex enabled, Home stacks both
cards and the menu-bar Usage tab shows them side by side. Codex account limits
and activity come from `codex app-server` account reads; they do not start a
model turn or consume inference tokens.

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
Homebrew install, the install script otherwise. It never runs it.

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
