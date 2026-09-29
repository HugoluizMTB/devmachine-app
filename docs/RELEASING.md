# Releasing Devmachine.app

Devmachine.app ships as a Developer ID build, downloaded from a GitHub
release. It never goes through the Mac App Store. Notarization is Apple's
automatic scan of the binary. Without it, macOS shows a Gatekeeper warning
when someone opens a downloaded app.

A tagged push builds a signed, notarized `.dmg` and publishes it as a GitHub
release in the public releases repo (`RELEASES_REPO`, default
`mydevmachine/app-releases`) — never in this private repo.

## One-time setup

Do this once per machine or account, not per release.

1. **Developer ID Application certificate.** In Xcode: Settings → Accounts →
   select the owner's Apple Developer account → Manage Certificates → + →
   Developer ID Application. Then, in Keychain Access, export that
   certificate as a `.p12` file with a password.

2. **App Store Connect API key.** At
   <https://appstoreconnect.apple.com/access/integrations/api>, create a key
   with role **Developer**. The `.p8` file downloads only once — Apple does
   not offer it again — so keep a copy in a password manager. Note the key's
   Key ID and Issuer ID too.

3. **Public releases repo.** The workflow publishes to `RELEASES_REPO`,
   which defaults to `mydevmachine/app-releases`. Create that repo (or set
   the `RELEASES_REPO` variable to point elsewhere) if it does not exist yet.

4. **Fine-grained GitHub token for the releases repo.** At
   <https://github.com/settings/personal-access-tokens/new>: resource owner
   set to the org that owns the releases repo, repository access scoped to
   just that repo, permission Contents: read and write.

### Setting the repo secrets

Set these in this repo's Settings → Secrets and variables → Actions. Never
paste a secret value into chat or a shell history entry.

**File-based secrets** hold their value in a file, so any terminal works —
the secret never appears as text you typed:

```
gh secret set MACOS_CERTIFICATE_P12_BASE64 -R <owner>/devmachine-app < <(base64 -i DeveloperIDApplication.p12)
gh secret set APPLE_API_KEY_P8 -R <owner>/devmachine-app < AuthKey_XXXX.p8
```

**A short value**, like a key ID, can go straight on the command line:

```
gh secret set APPLE_API_KEY_ID -R <owner>/devmachine-app --body <key id>
```

**Secrets you have to type** — `MACOS_CERTIFICATE_PASSWORD`,
`APPLE_API_ISSUER_ID`, `RELEASES_TOKEN` — need `gh secret set NAME -R repo`
run in a real interactive terminal, with a TTY attached, so it can prompt
you. Run that same command with no input piped in from a non-interactive
context (a script, a CI step, an agent shell) and `gh` reads an empty
stdin and silently stores an **empty secret**. There is no error, just a
secret that is empty. Always run these from a terminal you are typing into.

Set the same way: `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`,
`RELEASES_TOKEN` (a fine-grained PAT with `contents: write` on
`RELEASES_REPO`), and, only if you want the automated Homebrew cask PR,
`TAP_TOKEN` (a token with `contents: write` on `mydevmachine/homebrew-tap`).

Also set the repo/org **variable** `RELEASES_REPO`, only if it should differ
from the default `mydevmachine/app-releases`.

**After setting the secrets**, delete the `.p12` and `.p8` files from
wherever they landed (Downloads, or your working directory). The password
manager copy of the `.p8` is the only one that should survive.

Nothing identifying — team ID, certificate name, company name — lives in the
workflow file. It reads the Developer ID identity back from the imported
certificate at run time (`security find-identity`), never from a literal.

## Releasing

Bumping the version in `Resources/Info.plist` is optional. The release
workflow derives the version from the git tag and passes it to
`scripts/make_dmg.sh` as `DEVMACHINE_APP_VERSION`, which overrides whatever
is in `Info.plist`.

Tag the release commit and push the tag:

```
git tag -s v1.2.3 -m v1.2.3
git push origin v1.2.3
```

That push triggers the `Release` workflow.

### What the workflow does

1. Checks out the repo and selects the newest stable Xcode. The runner's
   default Xcode ships an older Swift; SwiftTerm needs Swift 6.2.
2. Builds and runs the test suite (`swift build`, `swift test`).
3. Imports the Developer ID certificate into a temporary keychain built for
   this run, then reads the "Developer ID Application" identity back out of
   it with `security find-identity` — the identity is never hardcoded.
4. Runs `scripts/make_dmg.sh`, which:
   - Runs `scripts/package_app.sh` to build the app bundle. That script
     code-signs the embedded `zmx` binary (it keeps local sessions alive
     after the app quits) before signing the `.app` itself with hardened
     runtime — a nested binary has to be signed before the bundle that
     contains it, or signing the bundle afterwards breaks its seal.
   - Notarizes and staples the `.app` (`scripts/notarize.sh`), so it still
     opens offline once someone copies it out of the disk image.
   - Builds the `.dmg` with `hdiutil`, signs it, notarizes and staples it
     too.
   - Only now runs the Gatekeeper check, `spctl -a -vvv -t exec` on the
     `.app` and the matching check on the `.dmg`. Gatekeeper rejects any
     Developer ID build until notarization is done, so this check has to
     come last, after signing, notarizing and stapling — not right after
     signing.
5. Publishes the `.dmg` as a GitHub release on `RELEASES_REPO`.
6. If `TAP_TOKEN` is set, renders `packaging/devmachine-app.rb.template`
   into a Homebrew cask and opens a PR against `mydevmachine/homebrew-tap`
   with the bumped version and sha256.
7. Cleans up the temporary keychain and the API key file, whatever the
   outcome.

### Retrying a failed release

Fix the problem, push the fix to `main`, then move the tag to the new
commit:

```
git push origin :refs/tags/v1.2.3
git tag -d v1.2.3
git tag -s v1.2.3 -m v1.2.3
git push origin v1.2.3
```

### A workflow run that fails in 0 seconds

If a run fails instantly, even on an ordinary push to `main`, suspect a
workflow YAML problem before anything else — the job never actually
started. One real example from this repo: GitHub Actions does not allow
`secrets` inside a step's `if:` condition. The fix reads the secret's
presence into a job-level `env` var first, then checks that var in `if:`:

```yaml
env:
  HAS_TAP_TOKEN: ${{ secrets.TAP_TOKEN != '' }}
steps:
  - name: Render Homebrew cask
    if: env.HAS_TAP_TOKEN == 'true'
```

### Cost note

macOS GitHub-hosted runners bill at roughly 10x the per-minute rate of Linux
runners on a private repo. Keep that in mind before iterating on workflow
fixes by pushing tags — a `.dmg` build and notarization round trip is not
cheap to repeat.

## Local dry run

Check the packaging mechanics without touching Apple's servers or any repo
secret:

```
swift build && swift test
./scripts/package_app.sh                 # ad hoc signature
codesign --verify --deep --strict build/DevmachineApp.app
SKIP_NOTARIZE=1 ./scripts/make_dmg.sh     # builds & signs the dmg, skips notarizing
```

`SKIP_NOTARIZE=1` tells `scripts/make_dmg.sh` to skip
`scripts/notarize.sh`. Signing with a real Developer ID identity and
notarizing both need the secrets from the one-time setup above; there is no
way to exercise `spctl -a -vvv -t exec` or `xcrun notarytool submit` without
them.

## Build and install locally

For day-to-day development, not for cutting a release:

```
swift build
swift test
./scripts/install.sh
```

`scripts/install.sh` builds the app, quits any running copy (through
AppleScript first, then a force kill if that does not work), replaces
`/Applications/Devmachine.app`, and relaunches it.
