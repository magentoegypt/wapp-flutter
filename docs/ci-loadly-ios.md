# Publishing iOS (Ad Hoc) to Loadly

[`.github/workflows/publish-ios-loadly.yml`](../.github/workflows/publish-ios-loadly.yml)
builds a signed **Ad Hoc** `.ipa` on a macOS runner and uploads it to Loadly.

It runs on every push to `main`, the same as the Android pipeline, so the two platforms stay
on the same commit. You can also run it from **Actions → iOS Ad Hoc to Loadly → Run
workflow** to choose a flavor and release notes, or push a `v*` tag to set the version
string from the tag. Every one of those publishes — this pipeline has no check-only mode.

> **The one rule that governs everything.** Ad Hoc builds install **only on devices whose
> UDID was registered in the provisioning profile before the build was signed**. Any other
> device fails with an unexplained *"Unable to Install"*. Adding one tester means
> registering their UDID, regenerating the profile, updating the secret and rebuilding.
> Apple's cap is **100 iPhones per membership year**, and the count only resets at renewal.
>
> If testers are customers, or you don't want to rebuild whenever someone joins, TestFlight
> is the right tool and this pipeline is the wrong one.

## No changes were needed to the Xcode project

The app still uses **automatic** signing, exactly as committed. CI overrides it entirely
through `FLUTTER_XCODE_*` environment variables, which Flutter forwards to `xcodebuild` as
command-line build settings — the highest-precedence layer in Xcode's hierarchy.

That was deliberate: the only developer here is on Windows, so a project switched to manual
signing would be broken with no Mac available to repair it. Nothing in `ios/` is modified,
by CI or by this setup.

## One-time setup

### 1. Apple Developer Program — $99/year

Enrol at [developer.apple.com/programs](https://developer.apple.com/programs/). Note your
**Team ID** (Membership details), a 10-character string like `A1B2C3D4E5`.

### 2. Register every tester device

**Devices → +**, one UDID each. Testers get theirs from [get.udid.io](https://get.udid.io)
or by connecting to a Mac and copying it from Finder.

Do this **before** creating the profile — a profile only contains the devices that existed
when it was generated.

### 3. App ID

**Identifiers → + → App IDs → App.** Description `Clickalize`, Bundle ID **Explicit** =
`click.magento2.clickalize`, and **tick no capabilities** — the app needs none (no push, no
iCloud, no Sign in with Apple; `flutter_secure_storage` uses the default keychain access
group, and camera/photo access is an `Info.plist` usage string, not an entitlement).

The Bundle ID must match `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj` exactly. It
is already set to `click.magento2.clickalize`, so use that string verbatim.

Add capabilities only when a feature actually needs one: an entitlement the profile grants
but the binary never uses invites review questions, and a profile/binary mismatch fails
installs with a generic "unable to install".

### 4. Distribution certificate

**Certificates → + → Apple Distribution.** You'll need a Certificate Signing Request from
Keychain Access on a Mac (*Certificate Assistant → Request a Certificate From a Certificate
Authority*, "Saved to disk").

Download the resulting `.cer`, double-click to install, then in Keychain Access find it
under **My Certificates**, right-click → **Export** → `.p12`, and set a password.

Export from **My Certificates**, not *Certificates* — the latter exports the certificate
without its private key, which cannot sign anything and fails on the runner.

An **Apple Distribution** certificate is required. A Development certificate cannot sign an
Ad Hoc build; the workflow checks for this and fails early with a clear message.

### 5. Ad Hoc provisioning profile

**Profiles → + → Distribution → Ad Hoc.** Pick the App ID, the distribution certificate, and
**tick every device**. Name it something recognisable — `Clickalize AdHoc` — and download the
`.mobileprovision`.

### 6. Encode both files

```bash
base64 -i Certificates.p12 -o cert.b64
base64 -i Clickalize_AdHoc.mobileprovision -o profile.b64
```

On macOS `base64 -i/-o` writes a single unwrapped line. Do this outside the repo; the root
`.gitignore` covers `*.p12` and `*.b64` as a backstop, but the safest file is one that was
never in the working tree.

### 7. Add four secrets

Settings → Secrets and variables → Actions.

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | contents of `cert.b64` |
| `IOS_CERTIFICATE_PASSWORD` | the password you set on the `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | contents of `profile.b64` |
| `IOS_TEAM_ID` | your 10-character Team ID |

`LOADLY_API_KEY` is shared with the Android pipeline and is already set.

There is deliberately **no** secret for the profile name — the workflow reads the name, UUID,
team, App ID, expiry and device list out of the profile itself. A secret can disagree with
the file; the file cannot disagree with itself.

## What the workflow checks before it builds

Each of these otherwise surfaces much later as an unhelpful native error:

- both files decode to something non-empty
- the keychain accepts the `.p12` (wrong password, or an export with no private key)
- an **Apple Distribution** identity is actually present
- the profile's team matches `IOS_TEAM_ID`
- the profile covers `click.magento2.clickalize`
- the profile is Ad Hoc, not Development (`get-task-allow` is false)
- the profile registers at least one device — zero means it is an App Store or Enterprise
  profile, which passes every other check and then fails deep inside `exportArchive`

## Versioning differs from Android, on purpose

`CFBundleVersion` is `github.run_number + 1000`, same as Android's `versionCode`.

`CFBundleShortVersionString` comes from the tag — but **iOS accepts only digits and dots**.
Flutter silently strips anything else and pads to three segments, reporting the change only
at trace verbosity. Android passes the same string through untouched. So one tag can mean two
different things:

| Tag | iOS | Android |
| --- | --- | --- |
| `v1.2.0` | 1.2.0 | 1.2.0 |
| `v1.2` | 1.2.0 | 1.2 |
| `v1.2.0-rc1` | 1.2.0 | 1.2.0-rc1 |

The workflow cuts the prerelease suffix before sanitising and **warns in the log** when the
two diverge. Left to Flutter's raw behaviour, `v1.2.0-rc1` would become `1.2.01` — a *higher*
version than the `1.2.0` that follows it.

## When it breaks

| Error | Cause |
| --- | --- |
| `No signing certificate "iOS Development" found` | the project's hardcoded `CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` won over the override — delete those three lines in `project.pbxproj` |
| `No profiles for 'click.magento2.clickalize' were found` | profile not discoverable, or team/specifier didn't reach xcodebuild |
| `No Account for Team "XXXX"` | manual signing settings didn't apply, so xcodebuild tried to contact Apple |
| `exportArchive: "Runner.app" requires a provisioning profile` | profile lookup fell back to a minimal export plist |
| Job hangs, then times out | `set-key-partition-list` didn't run and codesign is waiting on a GUI prompt |
| Build green, no `.ipa` | `flutter build ipa` exits 0 when the archive succeeds but the export fails — the workflow asserts the file exists for this reason |
| `Unable to Install` on a tester's phone | that device's UDID is not in the profile |

Run with the log open: the build passes `-v` so Flutter's profile-lookup traces are visible,
which is the only way to see a silent fallback.

## Scope

Ad Hoc only. Not the App Store — that needs an `app-store-connect` export, an App Store
Connect API key, and `xcrun altool`/`notarytool` upload, none of which is set up here.

`ios/Podfile` and `ios/Podfile.lock` don't exist in the repo and don't need to: the project
is Swift Package Manager–integrated, so a missing Podfile is not fatal, and Flutter generates
one on the first macOS build if CocoaPods turns out to be needed.

They are **untracked, not ignored** — `ios/.gitignore` covers `Pods/` but says nothing about
`Podfile`. That's harmless on an ephemeral runner, which never commits. If anyone ever builds
iOS on a Mac, committing the generated `Podfile.lock` is the right move — it pins the pod
versions so CI and local builds resolve identically.
