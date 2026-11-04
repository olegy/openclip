# Code Signing, Hardened Runtime & Releases

How an OpenClip Lite build is signed, how a release reaches installed copies through Sparkle, and
what each step is defending against.

Inspect any build with [Apparency](https://mothersruin.com/software/Apparency/) or the commands in
[Checking a build by hand](#checking-a-build-by-hand).

---

## Build modes

Signing is **opt-in**: a fresh clone builds, tests and runs with no certificate at all.

| | Ad-hoc (default) | Apple Development (Lite's releases) |
|---|---|---|
| Apple Developer account | not needed | free Personal Team (Xcode → Settings → Accounts) |
| Hardened runtime | no (see below) | yes |
| Accessibility grant survives rebuilds | no | yes |
| Notarized | no | no |
| Used for | tests, PR CI | `install.sh` and `release.sh` on the release Mac |

The hardened runtime needs a Team ID. Its library validation only loads nested code signed by the
same team, and ad-hoc or self-signed code has none, so a hardened ad-hoc app is killed by dyld at
launch (`Library not loaded: @rpath/Core.framework … different Team IDs`). `sign_artifact.sh`
therefore omits `--options runtime` (and the secure timestamp) for any identity without a Team ID,
and `verify_signing.sh` only requires the hardened runtime when the signature carries one.

The Team ID is read from the certificate's `organizationalUnitName`
(`oc_team_from_identity`), never from the identity name: in
`Apple Development: you@mail.com (XXXXXXXXXX)` the parentheses hold the certificate's own id.

## Configuration

`scripts/signing_config.sh` resolves the identity, highest precedence first:

1. `--identity <name>` on `sign_artifact.sh` or `verify_signing.sh`
2. `OPENCLIP_SIGN_IDENTITY` in the environment
3. `keys/signing.env`, if it exists (gitignored, like the whole `keys/` directory)
4. `-` (ad-hoc)

On the release Mac `keys/signing.env` names the Apple Development certificate, so local installs
and releases share one designated requirement:

```bash
OPENCLIP_SIGN_IDENTITY="Apple Development: you@mail.com (XXXXXXXXXX)"
```

`security find-identity -v -p codesigning` lists it. If it reports `0 valid identities`, install
the [Apple WWDR G3 intermediate](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer)
into the login keychain. The certificate lasts a year; renew it in Xcode and update the name.

## Releases

```bash
./scripts/release.sh                     # build, sign, publish v<MARKETING_VERSION>
./scripts/release.sh --no-upload         # build into build/release only
./scripts/release.sh export-key <dir>    # back up the Sparkle private key
```

A release needs a clean tree, `HEAD` pushed to `origin/main`, a version not released before
(bump `OPENCLIP_LITE_REVISION` in `project.yml`), and a `## <version>` section in `CHANGELOG.md`:
it becomes the GitHub release notes and the notes in Sparkle's update window. `CFBundleVersion` is
`OPENCLIP_UPSTREAM_BUILD.OPENCLIP_LITE_REVISION` (e.g. `23.5`), which is what Sparkle compares, so
it grows with every revision and with every new upstream base. `release.sh`:

1. Checks the signing identity has a Team ID and that the Sparkle key in the login Keychain
   (account `openclip-lite`) matches `SUPublicEDKey` in `project.yml`.
2. Builds a universal Release app and re-signs it inside out (`sign_artifact.sh`).
3. Verifies architectures and signature (`verify_universal.sh`, `verify_signing.sh --require any`).
4. Zips the app, signs the zip with Sparkle's `sign_update`, and writes a one-item `appcast.xml`
   with the changelog section as its release notes.
5. Creates the GitHub Release `v<version>` at `HEAD` with the zip and `appcast.xml`.

Sparkle checks once a day (`SUScheduledCheckInterval`) and never downloads or installs on its own
(`SUAutomaticallyUpdate` and `SUAllowsAutomaticUpdates` are off): a found update shows its window
and a dot on the menu bar icon, and installs only from the user's click. The About page has a
**Check for Updates** link under the version. Installed copies read `SUFeedURL`
(`https://github.com/olegy/openclip/releases/latest/download/appcast.xml`), which GitHub redirects
to the newest release's appcast. Only the Release bundle (`com.olegy.openclip`) updates itself;
the Debug build (`com.olegy.openclip.dev`) never does.

**The Sparkle private key is the one thing that cannot be replaced.** Without it no installed copy
accepts another update, and every Mac needs a manual reinstall. Back it up with `export-key` and
restore it on another Mac with Sparkle's `generate_keys --account openclip-lite -f <file>`.

Releases are not notarized (that needs a paid Developer ID). A Mac that installs one by hand
clears the download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/OpenClip.app
```

`scripts/package_app.sh` still builds a `.zip` and a styled `.dmg` for local inspection, and
`scripts/notarize_artifact.sh` is kept for a Developer ID identity, but no release path uses them.

## Why the app is re-signed rather than signed by Xcode

The packaging scripts used to finish with `codesign --force --deep --sign -`. That single line
caused most of what needed fixing:

- `--deep` walks a bundle **outside in** and **discards the flags and entitlements** of everything
  it re-signs. project.yml had asked for `ENABLE_HARDENED_RUNTIME` for a long time, and Xcode
  honoured it — then this call replaced that hardened signature with a plain ad-hoc one. Apparency
  reported `Hardening: Not enabled` on a project whose settings said otherwise, and no check
  looked at the finished artifact.
- Apple's own guidance is to sign nested code individually, deepest first, so a container is
  sealed only once its contents are final. `scripts/sign_artifact.sh` does exactly that, using the
  one shared walk in `oc_nested_code_items` so the signer and the verifier can never disagree
  about what counts as nested code.

Handing the identity straight to `xcodebuild` instead is not sufficient either. A Release build
with `CODE_SIGN_IDENTITY` set to a Developer ID certificate produces:

- the app, `Core.framework`, and `Sparkle.framework` correctly signed, but
- **Sparkle's `Updater.app`, `Downloader.xpc`, `Installer.xpc`, and the `Autoupdate` helper still
  ad-hoc signed**, exactly as Sparkle ships them. Signing a framework seals its helper binaries as
  resources without re-signing them. One ad-hoc binary anywhere inside the bundle is enough for
  the notary service to reject the whole submission.
- **`com.apple.security.get-task-allow` injected into the entitlements.** Xcode adds this
  debugging entitlement to any non-archive build. It lets other processes attach a debugger to the
  app, and the notary service rejects submissions that request it.

Re-signing the finished bundle from a known state fixes both, and the verifier fails the build if
either ever comes back.

## Entitlements

`Sources/OpenClip/OpenClip.entitlements` grants exactly one thing:

```
com.apple.security.automation.apple-events
```

AppleScript actions drive other applications. `AppleScriptRunner` shells out to `/usr/bin/osascript`
rather than using `NSAppleScript`, and TCC attributes those Apple events to OpenClip as the
responsible process, so the app needs both this entitlement and the `NSAppleEventsUsageDescription`
string that `project.yml` puts in `Info.plist`.

Deliberately **not** granted:

| Entitlement | Why not |
|---|---|
| `com.apple.security.cs.allow-jit` | JavaScriptCore extensions run correctly under the hardened runtime without it. Measured: a hot three-million-iteration loop evaluates in the same time signed with `--options runtime` as unsigned. The W^X exception buys nothing here. |
| `com.apple.security.cs.disable-library-validation` | Nothing is `dlopen`'d. Extensions are JavaScript, shell, AppleScript, or URL templates — never native code. |
| `com.apple.security.cs.allow-dyld-environment-variables` | Script actions get their environment from `ShellProcessRunner`; nothing injects `DYLD_*` into OpenClip itself. |
| App Sandbox | Incompatible with Accessibility-based text capture, `CGEvent` key synthesis, `~/.openclip`, and arbitrary script actions. Notarization does not require it. |

Two rules when editing that file:

1. **No XML comments.** `codesign`'s entitlement parser (AMFI) rejects them outright with
   `AMFIUnserializeXML: syntax error`, and the build fails at the signing step. Rationale goes in
   this document, not in the plist.
2. `scripts/verify_signing.sh` compares the **signed** entitlements against this file and fails on
   any difference in either direction. Adding an entitlement is therefore a visible, reviewable
   diff rather than something that appears only in shipped binaries.

## What signing changes for users

- **The Accessibility grant survives updates.** An ad-hoc signature's designated requirement is a
  bare `cdhash`, which changes with every build, so TCC treats each one as a different
  application. The Apple Development signature pins the bundle identifier and the certificate:

  ```
  identifier "com.olegy.openclip" and anchor apple generic
    and certificate leaf[subject.CN] = "Apple Development: …" and certificate 1[field.…] exists
  ```

  Renewing the certificate changes that requirement, so Accessibility is
  granted once more after the first release signed with the new one.
- **The Team ID is a commitment.** Sparkle checks that an update is signed by the same team as the
  installed app. Changing teams means installed copies reject every future update.

## Checking a build by hand

`scripts/verify_signing.sh` runs all of this and fails the build. To reproduce it directly:

```bash
APP=build/DerivedData/Build/Products/Release/OpenClip.app

codesign --verify --deep --strict --verbose=2 "$APP"   # structurally valid
codesign -dvv "$APP"                                   # flags contain "runtime"; Timestamp present;
                                                       # TeamIdentifier set
codesign -d --entitlements - --xml "$APP"              # only the apple-events entitlement
codesign -d -r- "$APP"                                 # designated requirement pins identifier + certificate
spctl -a -vv -t exec "$APP"                            # rejected: not notarized (expected for Lite)
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| `AMFIUnserializeXML: syntax error near line N` | An XML comment in the entitlements file. Remove it. |
| `... is still ad-hoc signed while the app is not` | Something was signed outside `sign_artifact.sh`, or a new embedded helper is not covered by `oc_nested_code_items`. |
| `not declared in OpenClip.entitlements: com.apple.security.get-task-allow` | The artifact came straight from `xcodebuild` without the re-sign step. |
| `no secure timestamp` | Signed while offline. The timestamp needs Apple's timestamp server. |
| Notary status `Invalid` | The script prints Apple's log; it names the offending binary and reason. |
| `rejected ... source=Unnotarized Developer ID` | Signed correctly but not notarized yet. |
| `resource fork, Finder information, or similar detritus not allowed` | An extended attribute on the bundle. `com.apple.FinderInfo` is the usual culprit; dmgbuild's `hide_extensions` writes one, which is why `make_dmg.sh` does not use it. Clear with `xattr -cr`. |
| `The staple and validate action failed! Error 65` | No ticket for that exact build. Re-notarize; a ticket is tied to the cdhash. |

## No CI

There is no GitHub Actions workflow. Tests run locally (`scripts/test.sh`), and releases are built
locally by `release.sh`, because the signing certificate and the Sparkle key live in this Mac's
login Keychain.
