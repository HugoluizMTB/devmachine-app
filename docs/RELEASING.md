# Releasing Devmachine.app

A tagged push builds a signed, notarized `.dmg` and publishes it as a GitHub
release in the public releases repo (`RELEASES_REPO`, default
`mydevmachine/app-releases`) — never in this private repo.

## One-time setup

1. **Developer ID Application certificate.** Xcode → Settings → Accounts →
   select the team → Manage Certificates → + → Developer ID Application.
   Export it from Keychain Access as a `.p12` file, with a password.

2. **App Store Connect API key.** At
   <https://appstoreconnect.apple.com/access/integrations/api>, create a key
   with role **Developer**. Download the `.p8` once (Apple does not offer it
   again) and note its Key ID and Issuer ID.

3. **Public releases repo.** Create `mydevmachine/app-releases` (or whatever
   `RELEASES_REPO` will point at) if it does not exist yet.

4. **Repo secrets**, in this repo's Settings → Secrets and variables →
   Actions:

   | Secret | Value |
   | --- | --- |
   | `MACOS_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperIDApplication.p12 \| pbcopy` |
   | `MACOS_CERTIFICATE_PASSWORD` | the password chosen when exporting the `.p12` |
   | `APPLE_API_KEY_P8` | the full contents of the `.p8` key file |
   | `APPLE_API_KEY_ID` | that key's Key ID |
   | `APPLE_API_ISSUER_ID` | that key's Issuer ID |
   | `RELEASES_TOKEN` | a fine-grained PAT (or GitHub App token) with `contents: write` on `RELEASES_REPO` |
   | `TAP_TOKEN` (optional) | a token with `contents: write` on `mydevmachine/homebrew-tap`; only needed to open the automated cask-bump PR |

   And one repo/org **variable**:

   | Variable | Value |
   | --- | --- |
   | `RELEASES_REPO` | `mydevmachine/app-releases` (only needed if it differs from the default) |

   Nothing identifying — team ID, certificate name, company name — lives in
   the workflow file. The workflow reads the Developer ID identity back from
   the imported certificate at run time (`security find-identity`), never
   from a literal.

## Per-release steps

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist` if the
   workflow's tag-derived version should also be the file's resting value
   (optional — the release workflow overrides it from the tag either way).
2. Tag the release commit: `git tag v1.2.3 && git push origin v1.2.3`.
3. Watch the `Release` workflow run. On success it publishes
   `Devmachine-1.2.3.dmg` as a GitHub release on `RELEASES_REPO`, and — if
   `TAP_TOKEN` is set — opens a PR against `mydevmachine/homebrew-tap` with
   the bumped cask.

## Local dry run

Nothing above is needed to check the packaging mechanics:

```
swift build && swift test
./scripts/package_app.sh                 # ad hoc signature
codesign --verify --deep --strict build/DevmachineApp.app
SKIP_NOTARIZE=1 ./scripts/make_dmg.sh     # builds & signs the dmg, skips Apple
```

Signing with a real Developer ID identity and notarizing both need the
secrets above; there is no way to exercise `spctl -a -vvv -t exec` or
`xcrun notarytool submit` without them.
