# Publishing, DNS providers and VPS writes

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Publishing feedback
- `expose add` / `expose rm` run with `--format json` (CLI 0.7.21+): the
  result (`applied`, `status`, `note`) and the exact stderr drive
  `PublishProgress` (Core). The card (`PublishJobCard` on `DMJobCard`) sits
  in the corner stack: steps, then Live with Open/Copy, Saved with the
  reason, or `DMErrorStateView` with the CLI's stderr and Retry. An older CLI
  without JSON reads as Saved, saying it cannot tell.

## Publishing through another machine
- **A workspace on a machine without Caddy is published by one that has
  it** (`expose add --via`). The add sheet's "Published by" lists the
  non-self machines with caddy (`CaddyStore.publishPlaces`); the
  workspace's own machine wins when it has caddy, then the machine the
  Publish page shows, then the first. `via` is passed only when it
  differs from the workspace's machine, so nothing changes for a machine
  that serves its own sites. Nothing known about where things live means
  no `--via`, as before.
- The Publish page of a machine with caddy also offers the workspaces
  of machines without it. After a publish, the serving machine is the one
  read again, not the workspace's.
- An older CLI answers `unknown flag: --via`; the card says to run
  `devmachine update` instead of showing Cobra's usage text. A published
  site whose serving machine cannot reach the port is live with an
  attention step carrying the CLI's note.

## DNS provider setup
- **A server with caddy, no DNS provider that answers and no sites on the
  Publish page shows the chooser page** (`DNSProviderChooserPage`): one
  card per provider package, and the form of the chosen one below. With
  sites, a bar says records are made by hand and its "Set up DNS" opens the
  chooser; "Back to Publish" leaves it. State is `DNSSetupStore`, from Core
  `DNSProviderSetup.evaluate`. Without a provider, `expose add` saves the
  site and only prints the record to make by hand; the page says so. Only
  `dns providers` answering with a zone ends it: a finished sync that still
  sees none leaves the provider's form showing the problem, with Save token,
  Push again and Remove. A provider that answers keeps the machine ready
  while a job runs on it or on another provider. A sync's end waits for a
  `dns providers` read already running (`DataCache.waitForRunningFetch`),
  then asks again: a forced read joins the running one, which may predate
  the sync. Add and save syncs on the install's own outcome. Nothing read
  at all (`unknown`) shows the table, with no chooser and no bar.
- **One form, two places.** `DNSProviderForm` is shared by the chooser page
  and Settings → DNS providers (`DNSProvidersSettingsView`), which lists
  every provider package with where it stands on the picked machine.
- **Remove** (`DNSSetupStore.remove`) drops the package from the machine's
  configuration, runs a full sync as a corner job, then forgets its token.
  Only a full sync rewrites the lock `dns providers` reads. A plain secret
  is one per Mac, so the token stays when another machine still has the
  package; the confirm names that machine. A package no longer declared
  that still answers is a removal whose sync failed: its form offers only
  Remove, which skips `packages rm` and goes on from the sync. Save token
  and Push again each confirm before they sync.
- Declared providers come from `packages list` (`installed_on`). A CLI
  that reports `kind`/`credentials` (0.7.27+) is read by `kind == "dns"`
  alone; an older one by the summary "DNS zones on …". The token is stored
  under the package's declared secret credential, else the package name.
- Add = `packages add <p> --machine <m> --yes`, then the zones if typed,
  then `secrets set <secret> --stdin`: all local to this Mac, behind one
  confirm. The token goes on stdin only, never argv, logs or the job
  output. Run sync = `sync --machine <m> --tags <p> --yes` then
  `credentials push --machine <m> --yes`, behind a confirm, as a machine
  job in the corner (`MachineJobCenter`), which holds the log; the form
  only says where it stands. A failed job retried or dismissed in the
  corner moves the form with it. A CLI older than 0.7.24 gets the commands.
- Hostinger's `hostinger.zones` is set with `machines edit <m> --set
  hostinger.zones=[…] --yes` behind a confirm on CLI 0.7.27+, after the
  package is added (the CLI refuses a setting for a package not there).
  Zones are plain names only (`DNSProviderCatalog.zones`). An older CLI
  gets a `config.yml` snippet; the app never edits `config.yml`. Demo
  mode refuses every write.
- `DEVMACHINE_DEMO_WALK=dns-setup` captures every state; its sync runs on
  a demo center whose runner is `DemoDNSSyncRunner`, which starts no
  process. Outside the walk, demo mode's sync fails in the corner.

## VPS writes
Features that write to the VPS or public DNS run only on an explicit user action
in the app, behind a confirm, and never from tests. The app delegates publishing
to `devmachine expose`; it does not edit Caddy, DNS, or Ansible itself.
