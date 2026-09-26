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
