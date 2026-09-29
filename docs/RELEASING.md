# Releasing Devmachine.app

Devmachine.app ships as **Developer ID** distribution outside the Mac App
Store — never through the App Store. A tagged push builds a signed, notarized
`.dmg` and publishes it as a GitHub release in the public releases repo
(`RELEASES_REPO`, default `mydevmachine/app-releases`), never in this private
repo.

Notarization is Apple's automatic malware scan. A downloaded Developer ID app
needs it to launch without Gatekeeper blocking it.

## One-time setup

1. **Developer ID Application certificate.** Xcode → Settings → Accounts →
   select the team → Manage Certificates → + → Developer ID Application.
   Export it from Keychain Access as a `.p12` file, with a password. The
   account behind this certificate is referred to here only as "the owner's
   Apple Developer account" — nothing about it (email, Team ID) belongs in
   this repo.

2. **App Store Connect API key.** At
   <https://appstoreconnect.apple.com/access/integrations/api>, create a key
   with role **Developer**. The `.p8` file only downloads once — save a copy
   in a password manager right away, along with its Key ID and Issuer ID.

3. **Public releases repo.** Built DMGs go to `mydevmachine/app-releases`
   (the `RELEASES_REPO` default). Create it first if it does not exist yet.

4. **Fine-grained GitHub token for that repo.** At
   <https://github.com/settings/personal-access-tokens/new>, create a token
   with resource owner set to that org, repository access limited to just the
   releases repo, and permission **Contents: read and write**. This becomes
   `RELEASES_TOKEN`.

## Setting secrets without the value passing through chat or shell history

Set these in this repo's Settings → Secrets and variables → Actions.

**File-based secrets** can be piped in from any terminal, so the value never
sits in shell history or a chat window:

```
gh secret set MACOS_CERTIFICATE_P12_BASE64 -R <app repo> < <(base64 -i devmachine.p12)
gh secret set APPLE_API_KEY_P8 -R <app repo> < AuthKey_XXXX.p8
gh secret set APPLE_API_KEY_ID -R <app repo> --body <key id>
```

**Prompted secrets** — `MACOS_CERTIFICATE_PASSWORD`, `APPLE_API_ISSUER_ID`,
`RELEASES_TOKEN` — must be set in a real interactive terminal with a TTY:

```
gh secret set MACOS_CERTIFICATE_PASSWORD -R <app repo>
gh secret set APPLE_API_ISSUER_ID -R <app repo>
gh secret set RELEASES_TOKEN -R <app repo>
```

Without a TTY, `gh secret set` reads empty stdin and silently stores an
**empty** secret — no error, no warning.

Optional: `TAP_TOKEN`, a token with `contents: write` on
`mydevmachine/homebrew-tap`. It only enables the automated cask-bump PR; the
release itself works without it.

One repo/org **variable**, only if it should differ from the default:

| Variable | Value |
| --- | --- |
| `RELEASES_REPO` | `mydevmachine/app-releases` |

Nothing identifying — team ID, certificate name, company name — lives in the
workflow file. It reads the Developer ID identity back from the imported
certificate at run time (`security find-identity`), never from a literal.

**Afterwards, delete the `.p12` and `.p8` files from Downloads.**

## Releasing

Bumping `CFBundleShortVersionString` in `Resources/Info.plist` is optional —
the workflow always sets the app version from the git tag.

```
git tag -s vX.Y.Z -m vX.Y.Z
git push origin vX.Y.Z
```

The `Release` workflow then:

1. Picks the newest available stable Xcode on the runner (needed because
   SwiftTerm requires Swift 6.2, newer than the runner's default Xcode).
2. Builds and runs tests (`swift build`, `swift test`).
3. Imports the certificate into a temporary keychain and finds the Developer
   ID identity itself — no identity name is ever written into the workflow.
4. Signs the embedded `zmx` binary, then the app bundle, with the hardened
   runtime (inside out: the nested binary is signed first, since signing the
   bundle seals what is already inside it).
5. Notarizes and staples the `.app`, so it still opens offline once someone
   copies it out of the disk image.
6. Builds the `.dmg`, signs it, notarizes and staples it too.
7. Only then runs Gatekeeper's `spctl` check. Gatekeeper rejects any
   Developer ID build before it is notarized ("Unnotarized Developer ID"
   error) — running `spctl` last, after notarizing, is correct behavior, not
   a bug to fix.
8. Publishes the `.dmg` as a GitHub release on `RELEASES_REPO`.
9. If `TAP_TOKEN` is set: renders `packaging/devmachine-app.rb.template` into
   a cask with the new version and sha256, pushes a branch to
   `mydevmachine/homebrew-tap`, and opens a PR there with the bumped cask.

## Retrying a failed release

Fix the issue, push it to `main`, then move the tag:

```
git push origin :refs/tags/vX.Y.Z
git tag -d vX.Y.Z
git tag -s vX.Y.Z -m vX.Y.Z
git push origin vX.Y.Z
```

## Troubleshooting

A workflow YAML syntax or config error can show up as a **0-second failed
run**, even on an ordinary push to `main`. One known cause: `secrets` cannot
be referenced directly inside a step's `if:` condition. Read the secret into
a job-level `env:` var first (as `release.yml` does with `HAS_TAP_TOKEN`),
then reference that env var in `if:`.

**Cost note:** macOS GitHub-hosted runners bill at 10x the normal per-minute
rate on a private repo. Worth knowing before iterating on the workflow — this
is also why the release workflow only runs on a pushed tag, not on every push.

## Local dry run

Nothing above is needed to check the packaging mechanics:

```
swift build && swift test
./scripts/package_app.sh                 # ad hoc signature
codesign --verify --deep --strict build/DevmachineApp.app
SKIP_NOTARIZE=1 scripts/make_dmg.sh       # builds & signs the dmg, skips Apple
```

Signing with a real Developer ID identity and notarizing both need the
secrets above; there is no way to exercise `spctl -a -vvv -t exec` or
`xcrun notarytool submit` without them.

## Build and install locally

```
swift build
swift test
scripts/install.sh
```

`scripts/install.sh` builds a release bundle, quits the running app, and
relaunches the installed copy. Terminal sessions live on the remote host
(tmux over ssh), not in the app process, so they survive the relaunch.
