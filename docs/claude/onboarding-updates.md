# First run and updates

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## First run (onboarding)
- **Onboarding owns the window until the Mac is set up** (`AppModel.launchRoute`):
  Home needs the CLI and saved settings, every launch. There is no way to
  put the setup off: a skipped setup used to open Home with no CLI, which
  showed only the wallpaper and a raw "not found" error. The old
  `onboardingSkipped` default is deleted at launch, so a Mac that skipped
  goes back to the setup. A first run never lands on Settings.
- **Home is never empty when the setup is not done**
  (`HomeCatalogNotice.needsSetup`): a CLI that goes missing after launch
  (`WidgetCatalogStore.State.cliMissing`, from
  `DevmachineCLIError.executableNotFound`) while no catalog was read, or a
  CLI that names no configuration folder
  (`HomeBoardController.configurationUnknown`), shows "Devmachine is not
  set up on this Mac" with "Finish setup" (`AppModel.openOnboarding`) and
  the raw error under "Show details". A Mac with the CLI and no machine
  is not gated: Home draws the default board and the sidebar offers "Add
  a machine". A missing config folder also draws the default board.
- **The first run is the Add machine wizard, not a second implementation**
  (`OnboardingFlow`, a pure state machine driven by `OnboardingRunner`).
  The CLI is installed first, as a background step with its log
  (`MachinePlanStep.installCLI`: the release binary, never Homebrew),
  because the wizard reads keys and packages through it. Then
  `AddMachineWizardView` runs with `firstRun`: "Do you already have a
  server (VPS)?" (yes: address, login, key or password, `machines scan`
  fingerprint confirmed against the console; no: a Lima machine on this
  Mac, no address asked), packages, review of the exact commands, run.
  `firstRun` always syncs, always adds `devmachine-app` (essentials needs
  it, but `installed_on` lists only what a machine names itself), asks for
  the first workspace (`MachineWizard.requiresWorkspace`; a switch,
  `skipsWorkspace`, turns it off) so the app opens with one in the
  sidebar, and installs the skills (below). A Mac already connected
  but missing `devmachine-app` gets `packages add` + `sync` per machine,
  run the same way. A CLI older than `MachineUnattendedAdd` says so and
  offers the installer (`.cliTooOld`).
- **No agent setup.** The setup is deterministic and all in the UI: no
  "let your agent do it", no prompt, no "ask the agent". The owner's agent
  once hand-rolled a Lima VM with `limactl`, which the checklist can never
  see.
- **Every step is a background process with its log** (`MachineStepRunner`,
  `DMLogView`): no pane, nothing typed. Retry resumes from the failed step;
  the ones done are skipped (`machines add` is atomic on CLI 0.7.27+). A
  run that ends 0 but leaves the Mac as it was is `unresolved`, with Check
  again, never a loop. Demo mode refuses every run (`OnboardingDemoTests`).
- **The skills always install** when a harness is chosen: one
  `skills add --agent <h>… --yes` after the sync (`--agent` works for a
  harness not installed yet). The choices are the harness registry's
  harnesses that the CLI accepts (`SkillAgent.options`, which maps a
  `HarnessID` to its `--agent` name): claude, codex, pi and opencode on any
  CLI, antigravity, kimi and cline on 0.7.28+ (an older CLI refuses the
  whole command on an unknown agent). A new harness is offered once it is
  in `SkillAgent.cliAgents`. Preselected: Settings → Coding agents plus the
  harness folders this Mac has (`AddMachineModel.harnessesInUse`). In the
  first run a failed skills step is a failure like any other, with Retry:
  "You are all set" waits for it. Add machine from Settings keeps it a
  warning (`MachinePlanStep.blocksSetup`, `AddMachineModel.onlySkillsFailed`).
- **Everything the app downloads on first run happens before "You are all
  set"** (`OnboardingPlan.finishSteps`): once the Mac reads complete, the
  flow runs `widgets list --format json` (the pinned packages release lands
  in the CLI's cache) and `run --machine <m> -- true` (the machine answers),
  then reads the Mac again. The success card shows only when the flow is
  complete and every finishing step is done (`OnboardingRunner.isAllSet`).
  The catalog and the config folder that step read are handed to Home
  (`HomeBoardController.handOff`), so Home is whole on its first frame
  instead of waiting minutes for a first `widgets list` with nothing drawn.
  A Mac already set up runs only these steps, without a click.
- **A step that downloads tries again on a network failure**
  (`RetryPolicy.downloads`, Core: 3 attempts, 2 s then 5 s, "Attempt 2 of 3"
  under the step, every attempt's output in the log). `NetworkFailure`
  decides from the output, and a refused login, a changed host key, a bad
  checksum or an unknown flag is never tried again. Which steps:
  `MachinePlanStep.retriesOnNetworkFailure` (CLI and Lima installs, the
  packages release, the readiness check, skills, `packages add`, sync).
  After the last attempt the step fails with the real error and the usual
  failure panel.
- **A machine on this Mac installs Lima when it is missing**
  (`LimaInstall`, `LimaInstaller`): GitHub's latest release tarball for
  the Mac's processor, checked against the release's `SHA256SUMS` before
  a byte is written, unpacked into `~/.local` (`bin`, `share`, `libexec`);
  the temporary tarball is deleted whether the unpack worked or not.
  The CLI runs `limactl` by name, so `~/.local/bin` goes first on the PATH
  it gets. A failed download offers `brew install lima` when Homebrew is
  there. Only an unattended run (CLI 0.7.27+) can do this; an older CLI
  still shows `brew install lima`.
- **Every failure says how to fix it** (`SetupFailurePanel`,
  `SetupFailureHelp`/`SetupFailureAdvice` in Core): a cause read from the
  log (an outdated Xcode, a download, Lima's checksum, a changed host key,
  a refused login, an unreachable server) gets its own steps and buttons;
  anything else gets what the step ran, the last lines, Retry and Change
  answers. Every failure also has Report a bug (`DMReportBugButton`): the
  browser opens a new GitHub issue filled in by `BugReport`, with secrets,
  addresses, paths, emails, fingerprints, the typed hosts and domains, and
  the user, machine and workspace names (whole words, any length) taken
  out, under 7000 characters. The app never posts it. The
  DNS setup's failure has the same button.
- Demo walk `DEVMACHINE_DEMO_WALK=setup-flow` (`DemoSetupFlow`): `80`–`91`
  are the setup (start, CLI install and its failure, choice, server and
  local details, packages, review, running, failed, ready, old CLI),
  `92`–`95` Settings → General.
- **It ends on "Start using Devmachine"**: `completeOnboarding` reads the CLI
  again, fills the empty General fields, saves them and opens Home, with
  no restart. Settings → General shows what the CLI reports read-only
  ("Change…", "Edit"), re-reads it each time it opens, and an issue the setup
  fixes (no CLI; a folder other than the CLI's own with no `config.yml`)
  carries a button back into onboarding.
- **Leaving onboarding reads the CLI once, off the main thread**, and hands
  that answer to the workspace load. Then `onLeftOnboarding` reloads the
  machine lists (Home's stats machines, `MachinesStore`, readiness) and
  Home's catalog and board (`HomeBoardController.reload`), so a
  machine the setup just added shows without a relaunch. The config
  folder watcher is made again on any check while the folder it watches
  did not exist when it was made (`isWatchingConfiguration`).
- The main window opens at 80% of the screen when AppKit has no saved frame
  for it (`MainWindowSizing`, read before any window exists), never smaller
  than 1280x800 and never larger than the screen's visible frame; the scene
  also has `.defaultSize(MainWindowSizing.preferred)`. A saved frame always
  wins. Demo walk: `DEVMACHINE_DEMO_WALK=setup-flow`.

## Updates
- The updater replaces this app. For the CLI it runs one of the
  `CLIUpdateCommand` forms and nothing else: `update --cli-only` (CLI
  0.7.23–0.7.30, the binary only), `update --no-machines --format json`
  (CLI 0.7.31+: the binary, then the new binary pins the newest packages
  release and updates the skills on this Mac) or `update --no-machines
  --skip-cli --format json` (the packages card). The packages pin and the
  skills are the only things beyond the binary it may change, on purpose:
  a CLI updated from the app or brew kept an old pin and old skills, and
  nothing said so. **It never changes machines**: never plain `update`,
  never `sync`, never `--yes` or `--machine` (`--no-machines` refuses
  both), never the configuration. A CLI too old for `--cli-only` gets the
  command (`CLIUpdateAdvice`) in a `DMCommandBlock`: never run it, never
  type it into a session.
- The JSON forms print the report on stdout and the log on stderr, so
  `ProcessCLIUpdater` keeps stdout apart (`StreamingProcess.run(separatesStdout:)`)
  and `CLIUpdateReport` reads it. The CLI prints the JSON even when a step
  failed, then exits non-zero; the app shows the stderr `error:` line.
- **The app card's Update and Relaunch updates the CLI and packages
  first.** `UpdateDialog` shows three steps (`UnifiedUpdateSteps`): CLI and
  packages, app, relaunch. Step 1 (`UpdateController.updateTools`) calls the
  cards' own `updateCLI` when the CLI is behind, then `updatePackages` when
  the pin still is; nothing behind is "Up to date", skipped. A failure or a
  CLI that needs the `CLIUpdateAdvice` command stops there: the app is not
  installed, and the dialog offers "Update only the app" and Cancel. Then
  the install runs as before (Homebrew, disk image, or the release page for
  an ad-hoc build). The reason: a new app whose widgets need a newer CLI or
  packages release must never start on a Mac that lacks them. While the app
  card shows, it covers the CLI and packages cards and names what it also
  updates (`AppUpdateCardContent`). Step 1 has no Cancel while it runs, as
  the app download has none. An unknown CLI state (no CLI, or the release
  feed unread) is "Could not check", never "Up to date"; a CLI updated with
  `--cli-only` is asked about packages again, so its pin moves before the
  app installs. The compatibility card's Run update also re-checks app
  updates. Demo shot `205` (`update-dialog-steps`) is the dialog.
- Every finished `updateCLI`/`updatePackages` calls
  `UpdateDependencies.afterToolsUpdate`, which re-runs
  `WidgetCompatibilityStore.check()`, so the "needs a newer CLI" card never
  stays stale.
- **A newer CLI gets its own corner toast** (`CLIUpdateBanner`) while no app
  update is shown. Update runs `CLIUpdateCommand.forCLI(installed:)` and
  only when `canUpdateCLIInApp`; any other CLI gets the `CLIUpdateAdvice`
  command in a `DMCommandBlock`. On 0.7.31+ the done card reads "CLI updated
  to X · packages pinned vN · skills updated" (the version from `devmachine
  version`, the rest from the report), and a pin it reached clears the
  packages card. Later is saved per CLI version
  (`UpdatePreferences.cliLaterVersion`) and hides that version and older
  ones (`CLIUpdateToast.shows`); a running or finished update shows
  whatever Later said, the finished one until Close. Details opens
  Settings → About. Demo shots `65`–`69` and `57` (a 0.7.31 CLI) in the
  `cli-update` walk, built without an app update so the CLI card shows.
- **A newer packages release gets its own corner card**
  (`PackagesUpdateBanner`, under the CLI's) while no app update is shown. On CLI 0.7.31+
  `check` also runs `packages outdated --format json` (the CLI caches it a
  day and falls back to its last answer offline). It fails only when it never
  had an answer: that is "unknown", so no card and only a log line
  (`Logger` category `updates`), never an error on screen. `pinned` "" with
  `newer` false means nothing is pinned: no card. Update runs `--skip-cli`;
  a report whose pin did not reach the release is a failure. Done says what
  moved and points at Settings → Machines ("Open Machines"); it never syncs.
  Later is saved per release (`UpdatePreferences.packagesLaterVersion`) and
  hides it and older ones (`PackagesUpdateToast`, compared by
  `PackagesVersion`); Details opens `notes_url`. Demo shots `53`–`56`, also
  without an app update.
- Pure logic lives in `DevmachineCore/Updates` (versions, release JSON, ETag
  feed, schedule, install method, digest, bundle checks, swap, the update
  commands, their JSON and the packages card rules); the app's
  `Updates/` folder holds `UpdateController` and the real system calls. Tests
  inject fakes; nothing in `swift test` reaches the network, except the
  opt-in `DEVMACHINE_UPDATE_E2E=1` test, which installs into a temp folder.
- Never test an install against `/Applications/Devmachine.app` or by running
  `brew upgrade`: both replace the owner's app. Use a temp folder.
- A disk image install trusts only a bundle signed by the running app's Team
  ID. A local ad-hoc build has none, so it links to the release page instead.
- `scripts/package_app.sh` takes the version from the newest `v*` tag when
  `DEVMACHINE_APP_VERSION` is unset, so a local build compares correctly.
- AppKit will not quit while any window has a sheet attached (the log says
  "App termination blocked by modal sheet"), and the update dialog is a
  sheet. `AppRelauncher` starts the helper first (`DetachedProcess`: its own
  session, none of the app's open files), ends every sheet, then terminates.
  The helper opens the app only once the old pid is gone, never a second copy
  beside a stuck one; if the app is still running 10 s later, the dialog, the
  toast and About ask to "Quit and Reopen".
- To watch a real relaunch, run a debug build from a temp `.app` with its own
  bundle id: `open --env DEVMACHINE_DEMO=1 --env
  DEVMACHINE_RELAUNCH_REHEARSAL=<another .app> <copy>.app`. It "updates" to
  the other bundle through the real dialog, swap and relaunch. Debug only.
