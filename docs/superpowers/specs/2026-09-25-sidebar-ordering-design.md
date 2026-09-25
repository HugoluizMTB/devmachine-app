# Sidebar Ordering Design

## Goal

Let the user arrange the sidebar in the order that matches their work. Remote and Local workspaces can move as complete blocks, and sessions can move within their own workspace. A session never moves from one workspace to another.

Ordering is a native app behavior. It has no Settings UI and does not change infrastructure, tmux, zmx, session names, or workspace ownership.

## Interaction

The neutral area of a session row and workspace header is draggable with the normal macOS hold-and-drag interaction. The existing buttons, row click, multi-selection, and context menus keep their current behavior. No permanent drag handle or other visual affordance is added.

Dragging a workspace reorders the entire block, including its sessions. Local participates in the same order as remote workspaces and is no longer pinned to the end.

Dragging a session can reorder it only among sessions in its original workspace. Drop targets in another workspace reject the operation without changing either list. The native drag preview and insertion feedback are sufficient; the design adds no custom drag mode.

## Ordering Boundary

`SidebarOrderStore` owns persisted ordering and reconciliation. It stores stable identifiers in `UserDefaults` under keys dedicated to sidebar ordering; it is separate from `AppSettings` and has no Settings-page controls.

Stable identifiers are:

- remote workspace: SSH alias;
- Local workspace: its existing reserved alias;
- remote session: tmux session name within its workspace;
- local session: stable zmx handle.

`AppModel` is the application-facing ordering facade. It exposes ordered workspaces and ordered sessions, plus move operations that validate scope before asking the store to persist a change. SwiftUI renders those results and forwards drag intent; it does not implement reconciliation or mutate arrays itself.

All consumers that represent sidebar traversal use the same ordered lists. This includes the sidebar, Command-Shift-Up/Down session navigation, workspace stacks, flattened session references, and command-palette session results.

## Reconciliation and Lifecycle

An identifier already present in the saved order keeps its relative position. A newly discovered workspace or session is appended to the end of its respective list.

Hidden workspaces keep their saved position and return there when enabled again. A temporarily unavailable remote workspace also keeps its position because connectivity failure is not evidence that it was removed.

A session absent from an authoritative successful remote or local session scan is removed from its saved order. Explicit session deletion removes it immediately. If a session with the same name or handle is later created again, it is treated as new and appears at the end. This prevents stale identifiers from accumulating or interfering with future drag operations.

Workspace ordering reconciles against the complete discovered workspace set, including hidden workspaces, plus Local. A genuinely new workspace is appended. Workspace removal is handled when the authoritative workspace source no longer reports it.

## Persistence and Failure Handling

The store writes the workspace order and per-workspace session orders immediately after a valid move or authoritative reconciliation. Malformed or missing persisted data falls back to discovery order without blocking the sidebar. A rejected cross-workspace session drop performs no write.

Ordering is local to the macOS user profile, matching the app's other `UserDefaults` preferences. It is not synchronized to the VPS and does not require `devmachine-cli`.

## Testing and Verification

Pure tests cover:

- Local moving before, between, and after remote workspaces;
- workspace blocks preserving their sessions;
- session movement inside its source workspace;
- rejection of cross-workspace session movement;
- new workspaces and sessions appending at the end;
- hidden workspaces retaining their position;
- closed sessions being pruned after a successful authoritative scan;
- malformed stored data falling back safely;
- keyboard navigation, workspace stacks, and palette results following visual order.

Manual verification uses the installed production app to drag remote and Local workspace blocks, reorder sessions within one workspace, attempt a cross-workspace drop, relaunch the app, close a session, and confirm keyboard navigation follows the resulting order.

Completion requires `swift test`, `scripts/check-real-data.sh`, production installation, and visual interaction with the installed app.

## Out of Scope

- moving or migrating a session to another workspace;
- changing tmux or zmx ordering outside the app;
- syncing sidebar order between Macs or users;
- exposing ordering controls in Settings;
- adding permanent drag handles.
