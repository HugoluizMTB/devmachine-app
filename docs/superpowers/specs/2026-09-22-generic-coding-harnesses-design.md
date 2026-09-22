# Generic Coding Harnesses Design

## Goal

Make Devmachine support multiple coding harnesses without exposing provider-specific rules to SwiftUI. Claude Code and OpenAI Codex are the first adapters, but the app-facing APIs must remain generic.

The first delivery stays deliberately small: it generalizes session launch, settings, process detection, sidebar presentation, the context panel boundary, and usage surfaces. It prepares a central external-data boundary for the future `devmachine-cli` without adopting that CLI yet.

## Architectural Boundary

SwiftUI views consume presentation models and facades only. They must not know executable names, filesystem paths, command arguments, parser formats, provider-specific colors, or provider capabilities.

```text
SwiftUI views
    |
    +-- HarnessSettingsFacade
    +-- SessionHarnessFacade
    +-- UsageFacade
    +-- ContextFacade
            |
       HarnessRegistry
            |
            +-- ClaudeHarnessAdapter
            +-- CodexHarnessAdapter

Stores and facades
    |
    DevmachineServices
            |
            +-- WorkspaceSource
            +-- SessionSource
            +-- ContextSource
```

`DevmachineServices` is the injection point for information that comes from outside the app. The current implementation may continue to use SSH, `HostRunner`, and `devmachine-infer`. A future implementation can call `devmachine-cli` without changing views or presentation models.

This delivery introduces that boundary only for the flows already being changed: workspaces, sessions, context, and harnesses. Stats, Caddy, and Files remain on their current implementations until the future CLI serves them.

## Harness Model

`HarnessID` is a stable, codable identifier. Initial values are `claude` and `codex`.

Each registered adapter supplies:

- a presentation descriptor: title, short title, icon, color, and help text;
- the startup command typed into a new shell;
- local CLI availability validation;
- process names used by local and remote session detection;
- usage and context capabilities;
- provider implementations for the capabilities it supports;
- image storage and terminal-input policies when they differ by harness.

The app-facing model can carry multiple detected harnesses for future safety, even though a newly created session starts at most one harness. Views receive ready-to-render badges rather than switching on `HarnessID`.

## Settings

Settings has a top-level Harnesses section. Multiple harnesses may be active simultaneously.

Activating a harness validates its CLI on This Mac through its adapter. A failed validation does not mutate settings and produces an inline, user-facing error. The app never installs or repairs a CLI.

Session launch is configured independently:

- This Mac has one default: Terminal or one globally active harness.
- Each remote workspace/user has one default: Terminal or one globally active harness.
- New remote workspaces inherit a remote fallback.

The app does not probe remote users or manipulate VPS installations. Selecting a remote harness is declarative. When the session is created, the app types the adapter's startup command; the remote shell reports a missing command normally.

If a harness is disabled, defaults that reference it normalize to Terminal. The existing `newSessionProgram` setting is decoded into the new structure so current installations preserve their behavior.

## Session Detection and Presentation

Remote detection continues to use the existing `tmux list-panes` snapshot. `SessionHarnessFacade` asks active adapters to match each foreground command.

Local detection continues to use one `ps` snapshot for every `zmx` session. The process tree is parsed once, then active adapters match descendants. Supporting another harness must not add another process-list command.

Sidebar, command palette, Home, and context-panel visibility consume generic session presentation state. The existing hover-only badge behavior remains:

- Claude is initially orange.
- Codex is initially green.
- Tooltip text comes from the descriptor.

Colors and labels live in adapters or descriptors, never in views.

## Context Panel

The `Context / Files / Git` panel is a session tool, not a Claude-only view. It is mounted for any selected session, so Command-J works in Claude, Codex, and terminal-only sessions.

Files and Git retain their current behavior. The Context tab requests normalized data from `ContextFacade` and renders generic groups such as monitors, shells, agents, plans, pull requests, and links.

The existing Claude provider continues to use the current context source. Codex initially returns no provider-specific agent context, so the tab shows `No context`. The first delivery does not infer Codex subagents from internal files or choose a thread by working directory: multiple live conversations can share a directory, so that association is not reliable.

The context contract accepts a generic harness identifier while retaining backward-compatible decoding of the existing `isClaude` field. The future `devmachine-cli` can replace `ContextSource` and supply Codex thread/subagent information without changing the UI.

The global context shortcut remains Command-J. Control-J and Shift-Return remain terminal input owned by the running harness.

## Usage

The reusable Claude-only target becomes a generic usage module. Its app-facing state is `HarnessUsagePresentation`, containing optional sections:

- quota/rate-limit bars;
- daily token totals;
- per-model breakdown;
- summary metrics;
- plan name;
- loading, error, and refresh metadata.

Providers populate only supported sections. Generic views omit absent sections.

The Claude provider preserves its current behavior: `/usage`, `~/.claude.json`, and local JSONL statistics.

The Codex provider uses the official app-server JSON-RPC methods `account/rateLimits/read` and `account/usage/read`. These account reads do not start a model turn and do not consume inference tokens. The provider has a bounded timeout and always terminates any helper process it starts.

Usage polling runs only while at least one usage surface is visible. One shared facade/store prevents Home and the menu bar from duplicating work.

### Home

Home renders one generic usage card for each active, locally available harness. Cards are stacked; Codex appears below Claude when both are active. The unused Notifications card is removed.

### Menu Bar

The Pull Requests tab keeps its existing width and layout.

The Usage tab renders all active, locally available harnesses side by side using the same generic panel component:

- one harness uses the current narrow width;
- two harnesses use a wide two-column layout;
- the width is derived from the number of presentations and constrained to the visible screen.

Switching tabs continues to resize the popover. Widening Usage must not affect Pull Requests.

## Images and Terminal Policies

Image paste calls a harness-neutral facade. Each adapter can select a storage directory and cleanup policy. Claude may retain its managed cache directory; Codex may use an app-managed cache.

Harness-specific input behavior is expressed as adapter capabilities or policies. Generic SwiftTerm/tmux compatibility protections remain global when they are safe for every terminal program.

## Failure Handling

- One failed usage provider does not hide or stop another provider.
- A missing local CLI prevents activation and explains why.
- A missing remote CLI is reported naturally by the remote shell.
- Unsupported context returns an explicit empty state without guessing.
- Malformed provider output becomes a provider-scoped error.
- Polls and helper processes have timeouts and cannot overlap for the same provider.

## Testing

Tests use fake adapters, providers, and external sources. They never invoke real Claude, Codex, SSH, or VPS commands.

Coverage includes:

- migration from `newSessionProgram`;
- multiple simultaneously active harnesses;
- local activation validation;
- one launch default per local environment and remote workspace;
- normalization to Terminal after disabling a harness;
- remote tmux and local process-tree detection;
- generic sidebar and command-palette presentations;
- context-panel availability for every session;
- backward-compatible context decoding;
- Claude and Codex usage parsing;
- independent provider failures and observer-counted polling;
- stacked Home cards and removal of Notifications;
- narrow and wide menu-bar Usage layouts without changing Pull Requests.

Completion requires `swift build`, `swift test`, and `scripts/check-real-data.sh` to pass.
