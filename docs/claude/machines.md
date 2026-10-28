# Machines, workspaces, packages and scheduled tasks

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Machine readiness
- **A machine missing `devmachine-app` gets a card, never a gate over the
  whole window** (`MachineReadinessStore`). Declared comes from `packages
  list`, applied from `packages.lock` in the CLI's config folder
  (`PackagesLock`), and a failed package call (`PackageCallReports`, posted by
  `DevmachineCLI`) overrides both until the lock changes. Anything unread
  fails open: no card.
- **Prepare syncs with `--tags devmachine-app` only** and only on CLI 0.7.24+
  (`MachinePrepare.minimumCLIVersion`). A plain sync would apply every change
  waiting in the configuration behind a button that says Prepare, and an older
  CLI's tagged sync wrote the whole plan into the lock. Never move the
  packages pin from the app: it is shared by every machine.
- **A new workspace on a machine without `devmachine-app` is one sidebar
  card, not two** (`SessionProblem.mergesIntoFirstSync`): its account and the
  package both wait for the first sync, so the card says
  `devmachine sync --machine <m>` instead of offering Prepare, which would fix
  only the package. Home keeps the machine's own card. Demo shot `79`.
- **An SSH agent that will not sign is not a refused login**
  (`SSHFailure.agentRefused`, from `FailureCause.isSSHAgentFailure`: "agent
  refused operation", "communication with agent failed"). After a wake,
  1Password is locked and every machine fails this way at once; the machine
  accepted the key and saw no bad signature, and its sessions keep running.
  So: no `LoginHoldCenter` hold, no red, no problem under the name, no toast.
  One quiet `agentLocked` pause per machine (`PollPause.agentLockedSeconds`),
  drawn as one card for the whole sidebar, lifted when the app becomes
  active, the network returns, Refresh, or the timer. The hold with "Check
  the machine's key and user, then Retry" is for a login the server itself
  turned down. This once filled the sidebar with "The server refused the
  login" cards after every sleep, and the owner was right to be angry.
- **A session list never fails silently** (`SessionListProblem`): ssh looking
  the alias itself up as a hostname means no Host entry, exit 127 means no
  tmux. Neither stops the sweep or pauses polling; both show in the sidebar
  with the fix.
- The CLI's config folder is watched (`ConfigDirectoryWatcher`), so a machine
  or workspace added in a terminal shows up without a restart.

## Machines and the Add machine wizard
- **Settings → Machines lists the CLI's configuration** (`MachinesStore`:
  `config path`, `version`, then `machines list` and `packages list`). A
  machine's packages are its own `packages` from `machines list` (CLI
  0.7.27+), else the `installed_on` of `packages list`. Before `config.yml`
  exists an older CLI fails every one of those calls, so the store checks
  the file first and reads "no machine" without calling them; a CLI with
  `MachineUnattendedAdd` lists the latest release's packages then, for the
  first machine (a failure there is no error: essentials is still offered).
  Remove runs `machines rm --yes` behind a confirm and only forgets the
  machine. A load asked for while one runs reads once more after it, so
  the last change on disk is always the one shown.
- **The sidebar offers "Add a machine" above Local only once a read says
  there is none besides this Mac** (`AddMachinePrompt`). Nothing is gated
  on a machine: Home and local sessions work with zero. One rule in
  `AppSettings.validate` covers both this and onboarding: Public IP and Base
  domain are optional (checked only once typed, filled from the CLI when it
  knows them); the CLI's own folder passes before `devmachine setup` writes
  its `config.yml`; only a missing CLI or another folder without
  `config.yml` blocks Save, with the setup flow as its fix. That folder is
  never silent: `AppSettings.notices` gives a non-blocking "No machine
  yet" with Run setup (onboarding) and Add a machine (the wizard); a fresh
  Mac that landed on Settings had nowhere to go. Demo shot:
  `95-settings-no-machine.png` in the setup-flow walk.
- **The wizard (`AppPage.addMachine`) only builds `devmachine` commands**
  (`MachinePlan`, Core) and shows them before Create. Packages are
  `--no-essentials` or `packages add`, then `workspaces new <w> --machine
  <m> --yes` (optional here, required by default on the first run) and
  `sync`. A workspace name is its Linux account's: the CLI's
  `linuxUserName` rule, at most 32 characters, not a system account or
  the admin login, not a workspace the configuration has
  (`WorkspaceName.problem`, shared with Settings → Workspaces). Package cards are machine packages whose `platforms` hold `linux`
  or are empty (any): a server and a Lima machine are both Linux, so a
  `[macos]` package is never offered. Essentials is always installed
  (locked, its `needs` listed as included and not offered again on their
  own); docker is suggested and checked (`MachinePackageCatalog.suggested`).
- **The column beside the form is never empty.** Before the run it holds
  `AddMachineSummaryView`: the answers so far (`MachineWizard.summary`,
  read from the same plan that runs) and the commands they would run
  (`previewCommands`, none until the machine has a name; on the review
  the commands are the page, so only the summary). The kind step has
  nothing to summarise, so its two cards take that room. The run puts its
  log and steps in the same 340-point column (`AddMachineContent.sideWidth`).
- **CLI 0.7.27+ adds with no terminal at all**
  (`MachineUnattendedAdd.minimumCLIVersion`, read from `version` into the
  `MachinesSnapshot`). Every answer is a flag: `machines add --address
  --fingerprint` with `--key <file>`, `--key agent:SHA256:…` (keys listed
  with `ssh-add -l` against the socket the app hands the CLI) or
  `--password-stdin`; `--domain` only for the first machine, which `add`
  then writes the configuration for, as `setup` would; a Lima machine is
  one `create-local <name> --add`. The steps run in the background
  (`MachineStepRunner`, `runProcess`), output shown as it comes; `add` writes
  the machine only once its key is proved, so Try again simply runs the
  failed step again.
- **A Lima machine is sized from this Mac on CLI 0.7.28+**
  (`LocalMachineSizing`, `LocalMachineSizeLimits`): CPUs up to every core,
  memory up to the Mac's minus 2 GiB, disk up to the free space minus
  10 GiB (Lima's disk grows as it fills). The default is half the cores
  (2–4), a quarter of the memory (4–8 GiB) and 40 GiB, clamped. The size
  goes to `create-local --add --cpus --memory --disk` and the review
  says it; an older CLI shows no controls, gets no flags, and a note
  names its own default size. Demo and tests inject the limits
  (`DemoData.macLimits`), never this Mac's.
- **The password is a `SecretText`**: in a `SecureField`, on the add's
  stdin and nowhere else. The step carries only `input: .password`, never
  the value, so it is in no argument, step id, display line or log;
  printing the draft shows dots. It is written to the pipe before the
  process starts (no SIGPIPE if the CLI exits first). The draft drops it
  when a run starts, whatever the outcome, when the page goes away, and
  when the context is read again; a Try again that needs it opens the
  answers instead.
- **The host key is read by itself, never by a button** (`machines scan
  --format json`, logs in nowhere, writes nothing). Once the address and
  port could name a server, the details page reads it after typing pauses
  (`MachineScanSchedule`, `.task(id:)` cancels on the next keystroke) and
  again only when they change; it shows one line, "Server key: ED25519
  SHA256:…". `--fingerprint` is that scan, so the add refuses a server that
  presents another key and a fake one never gets the password. The
  provider-console check (verify command, paste, mismatch warning) is a
  collapsed "Check it against the provider console (optional)"; a paste
  wins over the scan, and one that disagrees trusts nothing. A failed scan
  says it in plain words (`MachineScanFailure`: refused, no answer, name
  does not resolve) with the CLI's error under Show details, and blocks
  nothing: Create reads the key again first, and with none the add goes
  without `--fingerprint` and the CLI refuses on its own. A scan of another
  address or port counts for nothing.
- **Log in with Password or SSH key** (agent keys, 1Password included,
  or a key file from `~/.ssh`). The password field shows for both: with a
  key it is optional and goes on stdin only when typed, to put the key on
  the server once. An add whose key does not log in yet and had no
  password (the CLI's "the key does not log in yet and no password was
  given") fails with the password field and "Try again with this
  password" on the failure itself (`MachineRetryField`), which runs that
  step again with it on stdin; a password login's failure asks the same
  way. An add's step id ignores `--password-stdin`, so a retry with or
  without the password finds the same step.
- **An older CLI keeps the terminal flow.** A server whose key already
  logs in is added unattended; a password-only server, a Lima machine
  (`create-local`, then `machines add`) and the very first machine (`setup`)
  go through the CLI's own questions, and the page lists the answers to
  type. The commands run in a local terminal pane (`MachineStepRunner`), so
  a password goes straight to the CLI. Only `sh <script>` is typed (any
  login shell, fish included); the script prints a per-step nonce marker
  the runner finds in the scrollback. A failed step shows
  `DMErrorStateView`; Try again skips the steps done. Tests inject
  `MachineStepRunner.Hooks`; nothing types into a real pane or starts a CLI.
- **No run waits forever.** Stop ends a run in either mode (Ctrl-C into
  the pane, or the background process is cancelled, which
  `StreamingProcess` turns into SIGTERM). A terminal step that ends
  without its marker is noticed when the pane's shell is its terminal's
  foreground group again, twice in a row (`ProcessTree.isAtPrompt`), and
  any step fails after `stepTimeout` (3 h: a first sync is slow) with
  what to do.
- **A failed run goes back to its answers.** "Edit answers" (and Close)
  return to the details with every answer but the password; steps done
  stay done, and the machine the run already wrote does not block its own
  name. Reopening after a success starts fresh. When the context is read
  again (a newer CLI found meanwhile), the wizard returns only as far as
  every step before is still valid (`MachineWizard.restore`), so a step
  that now needs a password or a fingerprint is where it stops.
- **No `config.yml` means no machine, not an unread list**: `machines
  list` fails before it exists, and `StatsStore` then checks the file and
  drops its cached cards, so Home never shows machines from an old
  configuration. Any other failed read keeps the cache.
- `DEVMACHINE_DEMO_ONLY=id,id` captures only those screens of a walk.
- `DEVMACHINE_DEMO_WALK=machines` captures Settings → Machines, every
  wizard step (key file, password, agent key, scan), a background run in
  each state, the first machine with its domain, the sidebar with no
  machine (Home with no machine cards), `legacy-` shots of an older
  CLI's terminal flow, and `cli-socket-` shots (Home and Stats on a CLI
  whose socket path is too long). Demo mode scans no server and reads no agent
  (`DemoData.addMachineScan`, `addMachineAgentKeys`) and refuses every run:
  `MachineStepRunner.run`, `MachinesStore.removeMachine`,
  `PackagesStore.apply` and `ProcessJobRunner` (every machine job: Prepare,
  DNS sync, Packages sync) each refuse before reaching a terminal or the CLI
  (`DemoRefusalTests`).

## Machine location and the network map
- **A machine's location is the CLI's** (`machines[].location`, CLI
  0.7.30+, `MachineLocation` in Core): trimmed, lower-cased,
  `[a-z0-9][a-z0-9 ._-]{0,39}`. A CLI that leaves the field out reads as
  `local` for this Mac and a Lima machine (only host `127.0.0.1`), else
  `external`; an empty value is `external`. The wizard always asks
  (`MachineLocationField`: free text plus chips; default `external` for a
  server, `local` for Lima) and passes `--location` to `machines add` /
  `create-local --add` only on 0.7.30+; older, it says the location is kept
  once the CLI is updated. "Edit location" runs `machines edit <m>
  --location <v> --yes` on Save (config only); an older CLI gets "Update the
  CLI" instead.
- **Settings → Machines opens on a network map** (`NetworkMap`,
  `NetworkMapGeometry` in Core; `NetworkMapView` draws it in a `Canvas`
  after the website hero's hairline plates, creases and coins). One row of
  tiles, zones by location (this Mac's first, then zones with a door, then
  by name), columns fixed by sorting, so the same configuration always
  draws the same map; the scale fits the width (0.9–3 pt per unit).
  Links are only what the configuration proves: internet → every non-self,
  non-Lima machine with caddy/essentials (`https`); each site from Caddy's
  listing (`CaddyStore.sitesByMachine`) from its door to the machine whose
  `workspaces` holds it (`expose --via` shows as a lane to another
  machine); this Mac → every machine (`ssh`, drawn even without a self
  machine, then not selectable); a dashed chain between machines with a
  tailnet host (`100.64.0.0/10` or `tailscale:`). This Mac is never put on
  the tailnet: nothing says it is. Lines rise straight up from a tile and
  run along a lane above the row, so nothing crosses on the ground; at most
  6 sites are drawn, the rest counted. A click on a tile selects its card.
- **The map is one view with two presentations** (`NetworkMapView`,
  `NetworkMapPresentation` in Core). `.interactive` is the page above.
  `.decorative` is Home's wallpaper in two sizes (`WallpaperChoice.networkMap(
  NetworkMapSize)`, saved as `{"kind":"networkMap","size":"large"|"compact"}`;
  a value saved before there were two sizes, or a size a newer build wrote,
  reads as compact; a build older than the map reads it as the bundled
  photo): no hit testing, no selection or hover, ink at 45%, no site hosts
  (they ran under the clock's digits) and no "+N more", and its site lanes
  sit closer (`NetworkMapBackdrop.siteRow`). The grid covers all of Home.
  - **Compact** goes only in Home's free area (`HomeMapArea.rect`, Core):
    right of the cards column and under the clock and date when they sit
    side by side, under everything when Home is stacked, always above the
    stats pill. HomeView measures the clock, the stacked content and the pill
    in its `home` coordinate space and the plan gives the cards column.
    The map is centred on the clock's middle, not the free column's
    (`NetworkMapBackdrop.compact`): the area is narrowed the same on both
    sides of the clock's x (`HomeMapArea.centred`), so it still keeps clear of
    the cards; only when that leaves the map below scale 0.5 does it centre
    in the free column. The clock centres in all of Home when it can, and a
    map centred in the column then sat off to its right. Inside its area
    `NetworkMapBackdrop` keeps 12% margins (16 pt at least there), at most
    scale 2, shrunk whole to fit; no area, or a map that would draw below
    scale 0.5, leaves the grid alone.
  - **Large** sits behind everything, cards and clock drawn over it
    (`HomeMapArea.large`, `NetworkMapPlacement.filling`,
    `NetworkMapBackdrop.Fit.large`): a rect centred in all of Home, 70% of its
    width, with the same room top and bottom so it clears the pill by the gap
    and stays centred. It is spread around the clock's measured frame (time,
    date and Mac name) so that band stays empty
    (`NetworkMapGeometry.spread`, `keepClear`): the internet tile at the top,
    the machines in a row at the bottom, placed on the two sides of the band
    with a wider pitch, and the lanes above the band (or between it and the
    machines, with the internet tile moved beside the band). The search goes
    from scale 3.5 down and takes the first layout that keeps machines off
    the band and no line through it; only when none fits may a thin vertical
    cross it; with no room at all it falls back to the map centred in the
    rect. Owner feedback: the clock sat on the map's middle, digits over the
    internet tile and the server. The Machines page never spreads (its
    snapshots are byte-identical to before).
- **Settings → Appearance opens on a Background picker** (`WallpaperKind`,
  Core): four `DMPictureChoice` cards, Photo, Gradient, Network map — large,
  Network map — compact, the chosen one ringed and checked. The map cards draw
  a miniature Home (`HomeSketch`: a 760-point-tall Home scaled down, so the
  map lands where Home puts it, spread around the sketch's clock, and is not
  dropped as too small). Picking Photo or
  Gradient comes back to the last photo or gradient picked (else the bundled
  photo, `midnight`), then shows that kind's own picks under the cards: the
  theme chips and photos, or the gradients. Every picture there is 150 pt tall
  and cropped, in a grid that wraps (200–300 pt columns), so it never turns
  into a strip; thumbnails are fetched at 640 px (`-thumb640.jpg`, so an old
  320 px file is not reused).
- **The wallpaper reads no data of its own** (`NetworkMapWallpaper`): on
  appear it loads `MachinesStore` only if nobody has, and asks
  `CaddyStore.appearForMap` for the sites (cache first, read again only past
  their TTL, never DNS). Before any data, and with no machine, only the
  ground shows; the machines fade in (no fade with Reduce Motion). Both
  canvases are `Equatable`, so a stats tick or usage refresh on Home does
  not repaint them, and there is no motion to keep them busy. Only the
  bottom is dimmed (`WallpaperBackground.dimming`); behind terminals the
  ambient backdrop is the ground without the grid. The Appearance cards draw
  the same view inside their miniature Home.
- `DEVMACHINE_DEMO_WALK=map-wallpaper` (`DemoMapWallpaper`) captures
  `180`–`190`: Home with the compact map over the demo configuration, over
  the five-machine fleet, with no machine; Appearance on the large map; Home
  with the large map over both; Appearance on a photo theme and on the
  gradients; and Home with the sidebar collapsed, with the compact map and
  with the large one over both configurations. Run it with
  `DEVMACHINE_DEMO_WINDOW=1280x800` and `1728x1080` to check laptop sizes.
- **Per machine**: Check (`doctor --machine`, `machine doctor` for this
  Mac), Addresses (`resolve`), Credentials (`credentials list`) open inline
  and are read only when opened (two of them log in); Sync asks
  `PackagesStore.syncPending` (disabled with nothing waiting), Full sync a
  full `SyncRequest`; a Lima machine gets Start / Stop and Delete the VM
  (`delete-local --yes` behind a confirm that it destroys the VM, apart
  from Remove which only forgets). All runs are machine jobs; their PATH
  has `~/.local/bin` first for an app-installed Lima. "Packages on this
  machine" opens Settings → Packages through `AppModel.openPackages`.
- `DEVMACHINE_DEMO_WALK=machines-map` (`DemoMachinesMap`) captures
  `160`–`172`: the fleet, a selection, each panel, a Lima start in the
  corner, one and eight machines, the location editor, the wizard's
  field on a current and an older CLI, the SSH password login panel, and
  the wizard keeping one account's password.
  Nothing runs.

## SSH password login
- SSH has one password setting for the whole machine, so turning it off
  reaches every account: on a Mac, the people who use it too. The wizard
  asks (`PasswordLoginChoice`): off for every account (no flag), off except
  some (`--keep-password-login`, CLI 0.8.2+, hidden on an older one), or
  left as it is (`--no-harden`).
- The machine's "SSH password login" panel reads `machines password-login
  --format json` and changes it with `--keep`/`--off`/`--on --yes`, then
  reads the machine again: what it shows is sshd's answer. "On for every
  account" is disabled while the machine has `ssh_hardening`, which turns
  it off again on every sync.

## Machine jobs
- **Every `devmachine` run against a machine is a machine job** (`MachineJobCenter`,
  `MachineJobToast` in the corner stack): Prepare, the DNS provider sync and the
  Packages page's sync. A screen never streams a sync into its own layout.
- **A sync is asked for, not started** (`requestSync`): the card asks "Sync
  <machine>?" and runs only on its button, which is the confirm the VPS-writes
  rule needs. Two asks for one machine merge into one card (tags join, full
  wins). One job runs per machine; the next waits as queued.
- **A tagged sync never records a removal** (the CLI's lock only updates tagged
  entries), so a request with a removal, or a CLI before 0.7.24, starts full.
- The log keeps the newest 5000 lines (`JobLog`) and arrives in batches
  (`JobOutputBuffer`): a hop per line carrying the whole log froze the window.
- `DMLogView` anchors its scroll at the bottom: `scrollTo` alone, on a lazy
  stack of wrapped lines, stopped a line or two short of the error.

## Packages page
- Settings → Packages reads `packages list`, `config show` and `packages.lock`.
  Declared is `installed_on`; applied is the lock (machines and workspaces).
  A package the lock has because another one `needs` it is "via <parent>",
  never "pending removal"; a workspace always has `workspace` (the CLI adds it).
- "Pending" is derived from config and lock, so a sync put off with Later is
  still offered ("Sync now") after a relaunch.
- Apply runs `packages add|rm … --yes` one by one; the first failure stops it and
  asks for no sync. Removing never uninstalls: the row and the confirm say so.
- `DEVMACHINE_DEMO_WALK=packages` (`DemoPackages`) seeds the store and the
  corner at each moment (every machine, `main` with two ticks, the confirm,
  the sync pending, running, done, failed); nothing runs.

## Settings → Workspaces
- **Settings → Workspaces lists every workspace under its machine**
  (`WorkspacesSettingsView`, `WorkspacesStore`: `workspaces list --format
  json` with its `settings`, and `packages.lock`; grouping in
  `WorkspaceSettingsList`, Core). Each machine has a title with its
  location; machines in the configuration's order. A sidebar workspace the
  CLI's list does not hold goes under "Other workspaces", so its switch is
  never lost. "Applied", "Waiting for sync" or "Not created yet" come from
  the lock's `workspaces` map (`WorkspaceSync`): every declared package in
  it is applied. A package taken off is not caught: the lock also lists
  what the declared ones pull in. No `config.yml` yet means no workspace,
  without a list call. There is no separate page (`AppPage` has no
  workspaces case) and no "Manage workspaces…" button: the list is the
  section, at the full width and height.
- **Each row's switch is the sidebar's on/off** (`AppSettings.hiddenWorkspaces`
  by ssh alias, `WorkspaceVisibility.setting`). It saves at once, with no
  Save (`AppModel.setHiddenWorkspaces` writes only the hidden list), and a
  workspace off is not reached: no ssh, mosh or poll, its panes closed.
  The section has no Save footer, like Packages.
- **Reached from** the sidebar's + beside WORKSPACES ("New workspace…", under
  the new-session items), ⌘K "Workspaces…" (`openSettings(.workspaces)`) and
  "New workspace…" (`requestNewWorkspace`: Settings → Workspaces plus
  `pendingNewWorkspace`, taken by the view).
- **A flow opens inside the section, under a breadcrumb** ("Workspaces ›
  Edit acme", "Workspaces › New workspace"), with the Settings rail beside
  it and its buttons at the bottom. "Workspaces" goes back to the list,
  except while a run is going (Stop first). Leaving the section or closing
  Settings drops any flow that is not running (`WorkspacesStore.leave`, from
  the view's `onDisappear`): the store lives for the app, and a flow kept
  there once left Settings stuck on the last workspace clicked. There is no
  side column: New and Edit show their commands on the review step, Forget
  and Destroy on their own screen.
- **Edit never changes packages**: they live in Settings → Packages.
  `WorkspaceFlow.togglePackage` does nothing for Edit, so its plan has no
  `--add`/`--rm`. Edit shows the packages as labels and "Packages for this
  workspace →" (`AppModel.openPackages(workspace:)`, which opens Packages
  with its Workspace dropdown set, `PackagesPageState.requested`), then
  the declared variables, other settings and logins. New keeps its package
  picker: a workspace has to start from some list (`defaults.workspace`
  and the harnesses turned on). Onboarding and Add machine make the first
  workspace through `MachinePlan` (`workspaces new … --yes`) and never use
  this section.
- **Every flow is a `WorkspaceFlow` (Core) and runs through
  `MachineStepRunner` in the background**, with `MachineRunLayout`,
  `DMLogView` and `SetupFailurePanel` (Retry, Report a bug), like the wizard.
  New and Edit: form, review of the exact commands, a confirm, run. New is
  `workspaces new <w> --machine <m> --packages a,b --yes` (`--packages=` when
  every card is off) then `sync --machine <m> --yes`; Edit is `workspaces edit
  <w> --add/--rm/--set/--unset … --yes` then the same sync, never `--machine`
  (there it moves the workspace). "Apply it now" off skips the sync.
- The name uses the wizard's rule (`WorkspaceName`); the machine picker lists
  non-self machines only. New's package cards are workspace packages for
  Linux, grouped by `category`, the account package `workspace` locked on.
- **CLI 0.7.29 reports what the page used to guess** (`WorkspaceJSON`, read
  from `version`; an older CLI keeps the fallbacks). `config show` gives
  `defaults.workspace`, which is the preselection and the DEFAULT badge
  (fallback: the setup's own `dev`, `zsh`, `mise`, and the form says it
  cannot read yours), and the top-level login answers. `packages list` gives
  each package's `variables`: Edit shows one typed field per declared
  variable of the workspace's packages (boolean as Default/On/Off, list and map as
  YAML text, a number checked before Continue), empty meaning the default;
  anything else stays in the free-text "Other settings". `workspaces list`
  gives each workspace's own `credentials`: Edit lists the logins its
  packages declare (`WorkspaceLogin`: the workspace's answer, then the
  configuration's, then the package's scope) with As configured / Shared /
  Own, written as `--share <login>=machine|own`, or `<login>=` to follow
  the configuration again. A login whose `credentials[].shareable` is
  false (CLI 0.7.29 with `shareable`; always false for a secret or a file)
  offers only As configured / Own, with the reason, and follows `own`
  whatever the configuration says, as `sync` does. A CLI that leaves
  `shareable` out keeps all three, and a Shared it refuses fails at the
  sync with its message.
- Edit mirrors the CLI's checks: a free-text setting is `<package>.<name>`
  for a package the workspace keeps, with a value (an empty `--set` would
  remove it). The machine and the account stay in the terminal.
- **Forget and Destroy are different on purpose.** Forget is `workspaces rm
  <w> --yes` behind a confirm: only this Mac's configuration changes. Destroy
  is `workspaces destroy <w> --confirm <w>` (+ `--keep-dns`, a checkbox) and
  runs only once the name is typed exactly. The CLI's refusals (a site
  published through another machine, an unreachable machine) are its
  `error:` line, shown as the failure's cause; nothing is guessed.
- Once a step changed the configuration, "Change answers" is gone (the name
  now exists); Retry runs only what failed. Any run that changed something
  reloads the sidebar, Settings → Machines, readiness and the cached
  workspace list.
- Demo mode reads `DemoData.workspacesSnapshot` and refuses every run ("Demo
  mode never changes a workspace."). `DEVMACHINE_DEMO_WALK=workspaces`
  captures `130`–`144`, all inside Settings: the list by machine (umbrella
  switched off), new, a taken name, review, running, failed, done, edit,
  edit review, forget, a refused forget, destroy, the list again after an
  edit was left (`142-workspaces-reopened`), a new workspace with no
  harness on, and Settings → Coding agents (every harness with a package has a
  switch). It turns on Claude, Codex and Pi, and Edit shows glab's login,
  which cannot be shared.

## Scheduled page
- Schedule is a mode (⌘3, the sidebar title, the menu bar footer's clock and
  ⌘K "Schedule"): `showPage(.scheduled)` switches to it. The sidebar lists the
  tasks by workspace (`ScheduleSidebar`) with "New task" on top, which asks
  the page for its sheet (`ScheduledStore.requestNewTask`); the page
  (`ScheduledView`) is unchanged beside it. It reads `scheduled list` (every
  workspace at once; one that is not set up is `installed: false` and is not
  asked) and `scheduled harnesses`.
- The agent, permission-mode and model pickers come from `scheduled
  harnesses`, never from a list in the app: a new agent in the CLI needs no
  app release. A mode in `dangerous` needs the sheet's "I understand" and goes
  as `--allow-dangerous`.
- Create on a workspace without the package asks first ("Set up and
  create"), then runs `scheduled add --yes`, which adds the package and syncs
  the machine before saving; it can take a minute or two. That setup is a
  global job card (`beginTask`, no count) while the Create button spins.
- A failed setup: the CLI prints the whole Ansible run on stderr before its
  `error:` line, so every scheduled call reports `CLIStderr.reason` (the last
  `error:` line). Showing the start of stderr once made a failed setup look
  like no error at all. The sheet keeps the form, shows the error with Try
  again, and the list is read again.
- A workspace whose list error is `setup-incomplete` (package in config, no
  binary) gets "Finish setup" on its banner: `sync --machine <m> --tags
  scheduled --yes`, shown with the same job card (`finishing: true`). A failed
  finish stays on the banner (`setupErrors`). Demo walk `scheduled`, screens
  143-146.
- Edit sends every field (`ScheduledDraft.arguments`), so an empty model
  clears it. Run now starts the run and polls `scheduled runs` every 2 s until
  it ends (10 min at most). A `missed`/`skipped` run has no output; its
  message is shown instead.
- Go writes times with nine fraction digits; `ScheduledJSON.parseDate` cuts
  them to milliseconds before Foundation reads them.
