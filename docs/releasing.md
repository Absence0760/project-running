# Releasing

Per-app release workflows, triggered by git tags. Each app ships on its
own cadence — tagging `mobile_android@1.2.3` cuts an Android release and
does not touch web, backend, or any of the watches.

**CI-only.** Release builds happen on GitHub Actions runners, never on a
laptop. Signing keys live in GitHub Secrets; no developer ever holds a
copy. A release APK built with `flutter build apk` on your machine will
not install as an update over the Play Store build because the keys
don't match — use `flutter run` for local testing.

## Tag conventions

```
mobile_android@1.2.3   → .github/workflows/release-android.yml
mobile_ios@1.2.3       → .github/workflows/release-ios.yml
watch_wear@1.2.3       → .github/workflows/release-watch-wear.yml
watch_ios@1.2.3        → .github/workflows/release-watch.yml
web@1.2.3              → .github/workflows/release-web.yml
backend@1.2.3          → .github/workflows/release-backend.yml
```

The glob is `<app>@*`, so any suffix works — `1.2.3`, `1.2.3-rc.1`,
`2.0.0-beta.4`. The workflow parses the suffix as the `versionName` and
derives a monotonic `versionCode` from `git rev-list --count HEAD`.

**Apple Watch ships inside the iOS app.** `watch_ios@*` is a build
smoke-check that creates an audit record; the canonical user-facing
release is `mobile_ios@*`, which bundles the watchOS target.

## Cutting a release

```bash
# Make sure main is green.
git checkout main && git pull

# Create an annotated tag. The workflow reads the version from the tag
# name; don't edit pubspec.yaml or build.gradle.kts manually.
git tag -a mobile_android@1.2.3 -m "Android 1.2.3"
git push origin mobile_android@1.2.3
```

GitHub Actions catches the tag, runs the matching workflow, and — on
success — creates a GitHub Release with the built artifact(s) attached.

### What gets published where

| Tag prefix | Runs | Signs | Publishes to | Also attaches to GitHub Release |
|---|---|---|---|---|
| `mobile_android@*` | ubuntu-latest | release keystore from secrets | Play Internal track | `.aab` |
| `watch_wear@*` | ubuntu-latest | Wear release keystore | Play Internal track (`com.runapp.watchwear`) | `.aab` + `.apk` |
| `mobile_ios@*` | macos-latest | *unsigned today* (skeleton until app ships) | — | `.ipa` |
| `watch_ios@*` | macos-latest | — | — | build log |
| `web@*` | ubuntu-latest | — | GitHub Pages | build zip |
| `backend@*` | ubuntu-latest | — | Supabase (migrations + functions on linked project) | — |

Promoting Android + Wear from the Internal track to Beta or Production
is done manually in the Play Console after you've smoke-tested the
Internal build. The workflow deliberately stops at Internal so a tag
doesn't immediately reach users.

## Required GitHub Secrets

Configure at **Settings → Secrets and variables → Actions**.

### Android

| Secret | What |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks` output |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | alias inside the keystore |
| `ANDROID_KEY_PASSWORD` | key password (often same as store) |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play service-account JSON key |

Creating the keystore (one-time):
```bash
keytool -genkey -v -keystore upload-keystore.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -i upload-keystore.jks -o upload-keystore.jks.b64
# Paste the b64 contents into the secret.
```

Creating the Play service account (one-time): Play Console → Users and
permissions → Invite new users → "API access" → create a service
account in Google Cloud → download the JSON key → paste into
`PLAY_SERVICE_ACCOUNT_JSON`. Grant "Release manager" on the app.

### Wear OS

Same shape as Android, different keystore (the Wear app has its own
`applicationId`, `com.runapp.watchwear`, so it needs its own upload
identity):

| Secret | What |
|---|---|
| `WATCH_WEAR_KEYSTORE_BASE64` | base64-encoded Wear keystore |
| `WATCH_WEAR_KEYSTORE_PASSWORD` | |
| `WATCH_WEAR_KEY_ALIAS` | |
| `WATCH_WEAR_KEY_PASSWORD` | |
| `SUPABASE_URL` | production Supabase URL (injected at build time) |
| `SUPABASE_ANON_KEY` | production anon key |

`PLAY_SERVICE_ACCOUNT_JSON` can be shared with the Android release if
the service account has Release-manager on both apps.

### iOS (when ready to flip on signing)

| Secret | What |
|---|---|
| `IOS_BUILD_CERTIFICATE_BASE64` | Apple distribution `.p12` |
| `IOS_P12_PASSWORD` | `.p12` password |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile |
| `KEYCHAIN_PASSWORD` | throwaway — gate for the ephemeral keychain on the runner |
| `APP_STORE_CONNECT_API_KEY_ID` | |
| `APP_STORE_CONNECT_API_ISSUER_ID` | |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `.p8` from App Store Connect |

These blocks are commented out in `release-ios.yml` today — uncomment
when the Flutter iOS app is feature-complete (see `apps/mobile_ios/CLAUDE.md`).

### Backend

| Secret | What |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | CLI personal access token |
| `SUPABASE_PROJECT_REF` | target project's ref (e.g. `abcd1234xyz`) |
| `SUPABASE_DB_PASSWORD` | Postgres password for `supabase db push` |

## Rollback

- **Android / Wear OS:** the Play Console has a "Halt rollout" button on
  any release. Use it, then push a fresh patch tag (`mobile_android@1.2.4`)
  with the fix — you can't re-use a `versionCode`, so rolling back is
  always a roll-forward with higher numbers.
- **Web:** re-run the Pages deploy with the previous tag's build zip.
  The GitHub Release attached to the tag has the artifact; download it,
  unzip, and push to the `gh-pages` branch manually, or re-run the
  workflow pointing at the older tag.
- **Backend:** Edge Functions can be rolled back by re-deploying the
  previous tag's function code (`supabase functions deploy <name>
  --project-ref ... --tag <ref>` — or just push a new tag with the old
  code reverted). Migrations are one-way — don't try to "roll back" a
  migration; write a compensating forward migration.

## Local dev path (explicitly NOT release)

Everything below produces unsigned or debug-signed artifacts that
cannot be promoted to users. If a laptop gets a release keystore, the
whole "keys stay in one place" story breaks.

```bash
# Mobile Android — debug-signed, installs as an update to existing debug.
flutter run -d <device>

# Wear OS — debug-signed, installs to an emulator or connected watch.
cd apps/watch_wear/android && ./gradlew installDebug

# Web — served at :7777 for dev, :8888 for preview build.
npm run dev --workspace=apps/web

# Backend — runs entirely against the local Supabase stack.
cd apps/backend && supabase start
```

If you catch yourself running `flutter build apk` + `adb install`
against a physical device you use normally, stop. The release APK is
signed with a key your laptop doesn't have; it'll install as a *second*
app alongside the Play Store one and won't sync the same installation.
Use `flutter run` for testing, or pull the signed AAB/APK from the
latest GitHub Release and `adb install` that.

## Before cutting a release

- `main` is green in CI.
- The app compiles locally — don't rely on CI to catch build breakage.
- Schema changes: if you deployed `backend@X`, apps that depend on the
  new schema should tag after (or at least not ahead of) `backend@X`.
- No uncommitted secrets. `grep -r SUPABASE_SERVICE_ROLE_KEY apps/` and
  friends should return only `.env.example` hits.
- If this is a first release on a new device, the test plan section in
  `apps/<app>/local_testing.md` has been smoke-run.
