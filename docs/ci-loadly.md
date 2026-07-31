# Publishing to Loadly from CI

[`.github/workflows/publish-loadly.yml`](../.github/workflows/publish-loadly.yml) builds a
signed release APK and uploads it to [Loadly](https://loadly.io), which returns an install
link testers can open on their phone.

It runs in two modes, so the build that gets checked is the same build that gets shipped:

| Trigger | What happens |
| --- | --- |
| **Push to `main`** | analyze, test, build the release APK, inspect it. **Nothing is uploaded.** |
| **Actions tab → Run workflow** | all of the above, then publish to Loadly |
| **Push a `v*` tag** | all of the above, then publish — with `versionName` taken from the tag |

Publishing on every push to `main` would put builds in front of testers that were never
meant to be tried, and burn a `versionCode` each time — so the upload stays deliberate.

Check runs on `main` do not need the signing secrets. Without them the build falls back to
the debug key and says so; the run still catches a broken build, which is what it is for,
and the signing key is not decrypted on every push. Publishing always requires them.

## One-time setup

### 1. Create an upload keystore — outside the repo

**Run this yourself** — it produces a private key, and whoever holds it controls all future
updates to this app. Losing it means never being able to update an installed app under
`click.magento2.clickalize` again; leaking it lets someone else ship as you.

Generate it **outside the working tree**. The surest ignore rule is a file that was never in
the repo:

```bash
mkdir -p ~/keys && cd ~/keys
keytool -genkeypair -v -keystore upload.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

PKCS12, not JKS: `keytool` warns that JKS is a proprietary format and tells you to migrate.

Back `~/keys/upload.jks` up somewhere durable and private.

### 2. Base64-encode it for the secret

```bash
cd ~/keys && openssl base64 -A -in upload.jks -out upload.jks.b64
```

`-A` writes one unwrapped line. Wrapping is actually harmless — the workflow decodes with
`base64 -di` — but **carriage returns are not**, so encode on Linux/macOS or in Git Bash,
never with `certutil` (which also prepends `BEGIN CERTIFICATE` lines).

The base64 is the key: anyone holding it can decode the keystore. Treat both files as the
same secret, and delete `upload.jks.b64` once the secret is saved.

> The repo's root `.gitignore` now excludes `*.jks`, `*.keystore`, `*.p12`, `*.b64` and
> `key.properties` as a backstop. It did not before — `android/.gitignore` only governs
> paths under `android/`, so a keystore created in the repo root was committable. Keeping
> the key outside the repo is still the real protection.

### 3. Add five repository secrets

Settings → Secrets and variables → Actions → *New repository secret*.

| Secret | Value |
| --- | --- |
| `LOADLY_API_KEY` | From your Loadly account settings |
| `ANDROID_KEYSTORE_BASE64` | The contents of `upload.jks.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | The store password from step 1 |
| `ANDROID_KEY_ALIAS` | `upload`, unless you changed `-alias` |
| `ANDROID_KEY_PASSWORD` | The key password (often the same as the store password) |

Add them through the GitHub UI. Nothing in this repo should ever contain their values.

## Why CI must sign with a real key

`android/app/build.gradle.kts` falls back to the debug key when no credentials are present,
so a fresh clone can still run `flutter build apk --release`. That fallback is fine locally
and wrong for distribution: **every machine and every hosted runner generates its own debug
keystore**, so consecutive CI builds would each carry a different signature and Android
would refuse to install one over another — testers would have to uninstall before every
update.

The workflow therefore fails fast when `ANDROID_KEYSTORE_BASE64` is missing, and separately
runs `apksigner verify --print-certs` on the finished APK and rejects it if the certificate
is `CN=Android Debug`. The build succeeding does not prove the right key was used; only
inspecting the artifact does.

## Versioning

`versionName` depends on how the run started:

- **Tag push** — derived from the tag, so `v1.2.0` ships `versionName 1.2.0`. Prerelease
  tags like `v1.2.0-rc1` are fine; a tag that is not a version (`release-1`) fails the run
  rather than quietly shipping the wrong number.
- **Manual run** — taken from `pubspec.yaml`. Bump `version:` there for a user-visible
  change.

`versionCode` is `github.run_number + VERSION_CODE_OFFSET` (currently `1000`), computed in
the workflow. Two things to know:

- `run_number` **restarts at 1 if the workflow file is renamed or deleted and recreated**,
  which would push `versionCode` backwards. If that ever happens, raise
  `VERSION_CODE_OFFSET` past the highest already-published code.
- Re-running a failed job reuses the same `run_number`, so it produces the same
  `versionCode`.

The build is driven through `flutter build`, never `gradlew` directly — only that path
writes `flutter.versionCode` into `android/local.properties`, which is gitignored and so
absent on a fresh checkout. Invoking Gradle directly silently produces `versionCode 1`.

## The Loadly failure mode worth knowing

**Loadly answers HTTP 200 even when the upload fails.** The real outcome is only in the
response body's numeric `code` field, and the build fields live under `.data`, not at the
top level:

```json
{ "code": 0, "message": "", "data": { "buildShortcutUrl": "...", "buildQRCodeURL": "..." } }
```

So the workflow does **not** use `curl -f` — that would report a failed upload as a
success. It checks `.code == 0` and matches on the number rather than the message, because
the live wording differs from the documented wording for at least code 1001.

Codes the workflow explains on failure: `1001`/`1002`/`1055` (API key), `1022` (file too
large), `1098` (hourly limit). The APK is ~59 MB against a 2 GB ceiling, so size is not a
practical concern.

The upload also does **not** retry. Curl retries on a 5xx that arrives *after* the body was
accepted, which for a resource-creating POST means re-sending all 59 MB and leaving Loadly
holding several builds for one `versionCode`. If the upload fails, re-run the job — that
uploads once, deliberately.

## Scope

This pipeline is **Android only, and APK only**. It does not build an AAB (what the Play
Store requires) and has no iOS path — Loadly can host an IPA, but that needs a macOS runner
and Apple signing credentials, neither of which is set up here.

`flutter analyze` and `flutter test` run on every push to `main` as well as on every
publish. There is no pull-request check workflow yet, so a PR is not verified until its
commits land on `main`.

## What the pipeline does

1. Checkout, JDK 17 (AGP 9.0.1's minimum *and* default), Flutter 3.44.4, Gradle cache
2. `flutter pub get` → `flutter analyze` → `flutter test` — gates, so a broken build never
   reaches a phone
3. Decode the keystore into `$RUNNER_TEMP` (never the workspace, so no later step can
   archive or commit it), then prove it opens with `keytool -list`
4. Compute and validate `versionCode`
5. `flutter build apk --release` with the chosen flavor's entrypoint and dart-defines
6. Verify the signature is not the debug key
7. Upload to Loadly, checking the body's `code`
8. Write the install link and QR to the job summary, and keep the APK as an artifact for
   30 days
