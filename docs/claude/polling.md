# Polling, caching, SSH failures and logs

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Performance rules (learned from a 2 GB footprint)
- Poll only while a view is visible (`onAppear`/`onDisappear` begin/end, refcount),
  one in-flight run per target, publish a `@Published` only when the value changed.
- Never decode an image or run a blur inside `body`; bake once (`WallpaperBackground`)
  and cache with a cap. The network map wallpaper is drawn, not baked: its
  canvases are `Equatable` views, repainted only when the map or the size changes. Hidden `.opacity(0)` views still cost a full-window drawable —
  render only what is shown. No `.shadow` on full-window cards.
- Session polling is a sequential sweep, one ssh at a time: parallel auths against a
  locked agent got this Mac banned by fail2ban. Keep it that way. A failure pauses
  only what it is about (`PollPause`, `AppModel.pollPauses`), so one broken workspace
  never stalls the others.
- **A refused login holds its whole machine until Retry** (`LoginHolds` in Core,
  `LoginHoldCenter` in the app). A new user's machine whose key was not authorized
  yet got this Mac banned: stats, doctor and sessions kept logging in with the refused
  key. Any caller that logs into a machine (session sweep and selection poll,
  Context, Files, Git, copy mode check, session share, Stats, doctor, Subdomains,
  widgets with a machine or workspace target) asks the center first and reports each
  failure. A refused login (`LoginFailure`: ssh's own words, the CLI's "does not log
  in", the sessions JSON `login-refused`) holds the machine with no timer; a
  `connection refused` after a refused login reads as the server probably blocking
  this Mac. Only Retry (exactly one attempt: one workspace's session list, or Stats
  for a machine with no workspace), a change to the machine's entry in the CLI's
  configuration (address, user, port, key; `ReadinessSnapshot.machineLogins`), or a
  relaunch ends it; a success from any other call does not. The sidebar shows
  `LoginHoldView` once per machine and Stats shows it in place of the numbers.
  The timed refused-login pause below is only for a workspace whose machine the
  configuration does not name: 5 min, doubled for each refusal in a row up to 30
  min. An unreachable machine pauses its own workspaces for
  1 min (only that workspace when the machine is unknown), a refused host key pauses
  nothing. A paused
  workspace gets no automatic login at all: sweep, selection poll, context, Git, copy
  mode check, the mosh watchdog's ssh. Try again and opening a session try once; the
  sidebar's refresh button (`refreshAllNow`) lifts every unreachable pause and sweeps,
  but leaves refused logins paused; a
  refusal pauses again (a refused mosh-server login skips the ssh fallback, which would
  be a second refusal). The sidebar shows each pause under the workspace
  (`PollPauseSidebarCard`, one per machine when the machine is paused) and it clears on
  the next answer; a corner toast says it once, when the pause starts, not again while
  it only goes on.
- **Waking and the SSH agent.** Waking lifts every pause but does not sweep at once:
  Wi-Fi and Tailscale are not up yet, and every machine failed and turned red. The
  sweep waits for `NetworkReturnWatch` (system path updates, no polling) or
  `wakeSweepDelay` at most; a path that comes back or gains an interface lifts
  unreachable pauses and sweeps (`networkReturned`), never refused ones. For 2 min
  after a wake or a network change, and whenever a remote terminal on that machine
  printed in the last 2 min (`TerminalActivity`, fed by SwiftTerm's output handler;
  a mosh pane redraws as soon as it reaches its machine), an unreachable machine is
  `PollPause.Reason.reconnecting`: grey card, no red dot, no toast, 30 s pause (not
  less: an older CLI counts a login waiting for the agent as unreachable after 30 s).
  The CLI answers `login-waiting` (`SSHFailure.loginWaiting`) when the machine
  accepted the key and only the agent's signature is missing; it keeps that one login
  open and touches the network no more while it waits, so the app pauses nothing,
  shows no red dot, and puts one `LoginWaitingSidebarCard` per machine. In the
  background the sweep runs every 30 s, not 5 s; coming back to the app sweeps at once.
- **A workspace no sync has created is never asked.** `packages.lock` names every
  workspace a sync applied; one it does not name has no account yet, and every login
  to it is a failed one (`AppModel.awaitsFirstSync`). It shows "isn't set up on its
  machine yet" and is asked again when the lock names it, or on Try again. A lock
  that names no workspace (an older CLI) and a workspace that has answered before
  hold nothing back. The CLI reports a refused login as `login-refused`, which is
  `SSHFailure.authDenied` here, never `unreachable`.

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

## Host keys
- **ssh refusing a host key is its own problem** (`SSHFailure.hostKeyRejected`,
  from ssh's own words on exit 255). No login was tried, so it counts toward
  no ban: the sweep goes on, polling is not paused, and the workspace is not
  painted offline. The sidebar shows one `HostKeySidebarCard` per machine,
  whether or not old sessions are still listed, and a click on one of those
  sessions opens the review. The 5s selection poll skips the alias; the 60s
  sweep still tries it. Only ssh's abort line ("Host key verification
  failed") counts: the CHANGED banner alone can precede a real login.
- **Review → `AppModel.showHostKey(machine)`, a sheet (`HostKeySheet`)** over
  whatever screen asked for it (sidebar card, a refused session's click,
  Settings → Machines' Host key, ⌘K), never a page: the screen under it stays
  as it was, and Close (Esc) or Done goes back to it. It cannot close while
  the trust is writing. `HostKeyStore` runs `devmachine
  machines trust <m> --check --format json` (CLI 0.7.24+; an older CLI
  refuses a changed key without JSON and gets the update advice) on every
  visit, never from a remembered answer: a Lima VM writes a new key on every
  restart. The sheet
  shows both fingerprints and the CLI's `verify` command for the machine's
  own console, never over SSH. Demo walk: `DEVMACHINE_DEMO_WALK=host-key`
  (`DemoHostKey`, `150`–`153`).
- **The trust button stays off until the pasted console output holds the
  exact presented fingerprint** (`HostKeyTrust.confirms`), and the write
  passes `--expect <fingerprint>`, so the CLI refuses if a second scan meets
  a different key. It writes only the CLI's local `known_hosts`, never the
  machine.

## Logs
- The app always writes `~/Library/Logs/Devmachine/app.log` (`AppLog.shared`,
  an `AppLogger` from Core): folder 0700, file 0600, rotated at 5 MB keeping
  `.1`–`.3`, written on its own queue; a failed write is dropped. Under
  XCTest it goes to a temp folder, never the real one.
- Every line goes through `LogRedactor` (Core): tokens, keys, passwords,
  `NAME=value` and JSON values with a secret's name, `.env` lines, private
  key blocks become `***`. Addresses, host, machine, workspace and user names
  and paths stay: they are what an install problem is read from. The rules
  match the CLI's own log.
- `DevmachineCLI` wraps its runner in `LoggingCommandRunner`: argv
  (redacted), exit code, duration, the stderr tail on failure; stdin is never
  logged. A read the app repeats (`CLICall.isPolledRead`) is written only when
  it starts failing or works again; Settings → Debug logging writes every
  run and the debug lines. The same line is written once per 5 minutes.
- Log through `AppLogChannel(category:)`, not `os.Logger`: it writes both.
- Help > Logs and the ⌘K log commands share `LogActionRunner`; "Save All
  Logs…" zips the app's, the CLI's logs and `history.log` with an
  `about.txt` (`LogBundle`) to the Desktop. The CLI's log is where
  `devmachine --format json logs path` says; an older CLI without that
  command falls back to `<config>/logs/devmachine.log`.
