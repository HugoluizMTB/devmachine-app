# Releasing Devmachine.app

This page is the full release process. Follow it and you need no other help.

## Distribution model

Devmachine.app ships outside the Mac App Store, signed with a Developer ID
certificate. It never goes through the App Store.

Apple notarizes every build. Notarization is Apple's automatic scan for
malware. Without it, Gatekeeper blocks the app when a user opens a downloaded
copy.

A tagged push builds a signed, notarized `.dmg` and publishes it as a GitHub
release in the public releases repo (`RELEASES_REPO`, default
`mydevmachine/app-releases`) — never in this private repo.

## One-time setup

Do these once, as the owner of the app's Apple Developer account. Skip this
section on every release after the first.

1. **Developer ID Application certificate.** In Xcode, go to Settings →
   Accounts → select the team → Manage Certificates → click **+** →
   **Developer ID Application**. Then open Keychain Access, find the new
   certificate, and export it as a `.p12` file. Set a password on export —
   you need it again later.

2. **App Store Connect API key.** Go to
   <https://appstoreconnect.apple.com/access/integrations/api> and create a
   key with role **Developer**. Apple lets you download the `.p8` file only
   once. Save a copy in a password manager right away. Note the key's Key ID
   and Issuer ID too — you need all three.

3. **Public releases repo.** The workflow publishes to `RELEASES_REPO`, which
   defaults to `mydevmachine/app-releases`. Make sure that repo exists (or
   set the `RELEASES_REPO` repo/org variable to point at a different one).

4. **A fine-grained GitHub token for the releases repo.** Go to
   <https://github.com/settings/personal-access-tokens/new>. Scope the token
   to only the releases repo (`mydevmachine/app-releases`, or whatever
   `RELEASES_REPO` points at). Grant it repository permission **Contents:
   Read and write**. Nothing more.

5. **Homebrew cask update — pick one.** The workflow updates
   `mydevmachine/homebrew-tap` on its own once one of these is set. Without
   either, this step is skipped and you update the tap by hand.

   - **Preferred: reuse the CLI repo's GitHub App.** The `devmachine-cli`
     repo already has a GitHub App (`devmachine-release`) installed on
     `homebrew-tap` with **Contents: Read and write** — see that repo's
     `docs/releasing.md`, "The credential in place today". Add the same App
     ID and a private key to **this** repo (a GitHub App's credentials work
     from any repo the app owner adds them to; the install on
     `homebrew-tap` is what grants the write, not which repo holds the
     secret):
     - `TAP_APP_ID` — the App's ID (same value as the CLI repo's
       `TAP_APP_ID`, visible on the App's settings page).
     - `TAP_APP_PRIVATE_KEY` — a private key for that App. Generate a new
       one on the App's settings page (**Generate a private key**) rather
       than reusing the CLI repo's downloaded `.pem` — Apple- and
       GitHub-style keys can only be downloaded once, so a fresh key avoids
       needing the original file. Add it with:
       ```
       gh secret set TAP_APP_PRIVATE_KEY --repo mydevmachine/devmachine-app < path/to/key.pem
       ```
     With this set, the release commits the cask straight to
     `homebrew-tap`'s `main` (message `feat: devmachine-app vX.Y.Z`, one
     line) — no PR to merge by hand. GitHub Apps cannot produce a GPG/SSH
     signed commit from Actions, so this commit is unsigned; that is
     expected.

   - **Fallback: a fine-grained token, opens a PR instead.** Only used when
     `TAP_APP_ID`/`TAP_APP_PRIVATE_KEY` are not set. Create a token scoped to
     `mydevmachine/homebrew-tap` with **Contents: Read and write** (and
     **Pull requests: Read and write** to open the PR), then:
     ```
     gh secret set TAP_TOKEN --repo mydevmachine/devmachine-app
     ```

## Secrets

Set these on this repo (Settings → Secrets and variables → Actions), or with
the `gh` CLI. Run every command below from a real machine, never by pasting
the secret value into chat.

### File-based secrets

Pipe the file straight into `gh secret set`. This never types the secret and
never puts it in shell history:

```
gh secret set MACOS_CERTIFICATE_P12_BASE64 < <(base64 -i devmachine.p12)
gh secret set APPLE_API_KEY_P8 < AuthKey_XXXX.p8
```

Run these from inside a clone of this repo, so `gh` picks the repo up on its
own.

### Prompted secrets

These have no file to pipe in, so `gh secret set NAME` prompts for the value:

- `MACOS_CERTIFICATE_PASSWORD` — the password you set when you exported the
  `.p12`.
- `APPLE_API_KEY_ID` — the Key ID from the App Store Connect key. You can also
  pass it directly: `gh secret set APPLE_API_KEY_ID --body <key id>`.
- `APPLE_API_ISSUER_ID` — the Issuer ID from the same key.
- `RELEASES_TOKEN` — the fine-grained PAT from step 4 above.
- `TAP_APP_ID` (optional, preferred) — from step 5, if reusing the CLI
  repo's GitHub App. You can also pass it directly:
  `gh secret set TAP_APP_ID --body <app id>`.
- `TAP_TOKEN` (optional, fallback) — the token from step 5, only if you are
  not using the GitHub App.

**Warning:** `gh secret set NAME` reads the value from standard input. Run it
in a real interactive terminal, one with a TTY. If you run it from a script or
an agent without a TTY, it reads empty input and silently stores an EMPTY
secret. There is no error and no warning — check the secret's "Updated" date
in the GitHub UI if you are ever unsure.

### Clean up

Once every secret is set, delete the `.p12` and `.p8` files from wherever you
downloaded them (usually `~/Downloads`). They have no reason to stay on disk.

## Doing a release

1. **Version number.** You do not need to bump anything in source.
   `Resources/Info.plist` can keep a stale `CFBundleShortVersionString` — the
   release workflow always overrides it from the git tag
   (`DEVMACHINE_APP_VERSION`, passed to `scripts/make_dmg.sh`).

2. **Preflight:** `scripts/preflight.sh` runs the tests, a release build and
   the real-data check. The release build matters on its own: the optimizer
   runs only there, and a compiler crash in it once reached CI only after a
   tag was pushed.

3. **Tag and push:**

   ```
   git tag -s v1.2.3 -m v1.2.3
   git push origin v1.2.3
   ```

4. **Watch the `Release` workflow.** It runs on `macos-15` and does, in
   order:

   - Selects the newest stable Xcode. The default Xcode on the runner ships
     an older Swift than SwiftTerm (a dependency) needs; `latest-stable`
     picks one with Swift 6.2.
   - Builds and runs the test suite (`swift build`, `swift test`).
   - Imports the Developer ID certificate into a temporary keychain, then
     reads the signing identity back out of it with `security find-identity`
     (never from a literal in the workflow).
   - Runs `scripts/make_dmg.sh`, which:
     - Builds the app and code-signs it (`scripts/package_app.sh`): first the
       embedded `zmx` binary, then `DevmachineApp.app` itself, with hardened
       runtime (`--options runtime --timestamp`) and its entitlements file.
     - Notarizes and staples the `.app` (`scripts/notarize.sh`).
     - Builds the `.dmg` with `hdiutil`.
     - Signs the `.dmg` (hardened runtime, no entitlements — a disk image
       does not need them).
     - Notarizes and staples the `.dmg`.
     - Runs Gatekeeper's check last: `spctl -a -vvv -t exec` on the `.app` and
       `spctl -a -vvv -t open` on the `.dmg`. This has to come last because
       Gatekeeper refuses any Developer ID build that is not notarized yet —
       checking earlier would always fail.
   - Publishes the `.dmg` as a GitHub release on `RELEASES_REPO`, using the
     `RELEASES_TOKEN` secret — twice, once as `Devmachine-X.Y.Z.dmg` (the
     asset of record) and once as a stable-named copy `Devmachine.dmg`, so
     `.../releases/latest/download/Devmachine.dmg` always serves the newest
     build without anyone having to know the version. Beside them it uploads
     `Devmachine-X.Y.Z.dmg.sha256` (`shasum -a 256` output). The app's
     updater downloads it and refuses a disk image whose digest differs; a
     release without it falls back to the `sha256:` line in the notes.
   - Renders `packaging/devmachine-app.rb.template` into a Homebrew cask,
     then updates `mydevmachine/homebrew-tap`:
     - If `TAP_APP_ID`/`TAP_APP_PRIVATE_KEY` are set, mints a short-lived
       GitHub App token and commits the cask straight to the tap's `main`
       (`feat: devmachine-app vX.Y.Z`).
     - Else, if `TAP_TOKEN` is set, opens a PR against
       `mydevmachine/homebrew-tap` with the bump instead.
     - If neither is set, this step is skipped.

### Retrying a failed release

Fix the problem on `main`, then move the tag to the new commit:

```
git push origin :refs/tags/v1.2.3
git tag -d v1.2.3
git tag -s v1.2.3 -m v1.2.3
git push origin v1.2.3
```

### A run that fails in 0 seconds

If the workflow run fails instantly, even on an ordinary push to `main`
(which does not trigger a release, but still parses the workflow file), the
cause is usually a YAML syntax or config error, not your code. A `validate`
job (Ruby's YAML parser, plus a grep that a step's `if:` never reads
`secrets` directly) runs first on `ubuntu-latest` and catches this before
the expensive `macos-15` job starts. One gotcha this workflow already works
around: GitHub Actions will not let a step's `if:` read the `secrets`
context directly. That is why `HAS_TAP_TOKEN` and `HAS_TAP_APP` are computed
once, in the job's `env:`, and steps check `env.HAS_TAP_TOKEN` /
`env.HAS_TAP_APP` instead of `secrets.TAP_TOKEN` / `secrets.TAP_APP_ID`
directly. Keep that pattern if you add a similar conditional step.

### Cost

macOS GitHub-hosted runners bill at roughly 10x the per-minute rate of a
Linux runner, on a private repo. Keep that in mind if you iterate on this
workflow with real tag pushes — prefer the local dry run below first.

## Local dry run

Check the packaging mechanics without touching Apple's servers:

```
swift build && swift test
./scripts/package_app.sh                 # ad hoc signature
codesign --verify --deep --strict build/DevmachineApp.app
SKIP_NOTARIZE=1 ./scripts/make_dmg.sh     # builds & signs the dmg, skips notarizing
```

Signing with a real Developer ID identity, and notarizing, both need the
secrets from the "Secrets" section above. There is no way to exercise
`spctl -a -vvv -t exec` or `xcrun notarytool submit` for real without them.

## Homebrew cask

The cask template lives at `packaging/devmachine-app.rb.template`. The
release workflow fills in `{{VERSION}}`, `{{SHA256}}` (of the versioned
`.dmg`), and `{{RELEASES_REPO}}`, checks the rendered file with `ruby -c`,
then updates `mydevmachine/homebrew-tap`:

- **`TAP_APP_ID` + `TAP_APP_PRIVATE_KEY` set (preferred):** mints a token
  scoped to `homebrew-tap` through the GitHub App and commits the cask
  straight to the tap's `main`, one line, `feat: devmachine-app vX.Y.Z`. No
  PR to merge — the release is done once the workflow finishes. See
  "One-time setup" above for where to get the App ID and private key.
- **Only `TAP_TOKEN` set (fallback):** opens a PR against
  `mydevmachine/homebrew-tap` with the bump instead; merge it by hand.
- **Neither set:** this step is skipped and the cask does not update
  automatically; update `mydevmachine/homebrew-tap` by hand.

## Build and install locally

To try a change without going through a release:

```
swift build
swift test
./scripts/install.sh
```

`scripts/install.sh` builds the app, quits any running copy, and replaces
`/Applications/Devmachine.app` with the new build, then relaunches it.
Sessions run in a separate `zmx` process, not inside the app itself, and
`install.sh` only quits `DevmachineApp` — so relaunching does not lose your
open sessions.
