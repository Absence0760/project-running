# Wear OS deployment plan

How `apps/watch_wear/` (native Kotlin + Compose-for-Wear) ships to the Google Play Store.

Operational counterpart of [`apps/watch_wear/CLAUDE.md`](CLAUDE.md) and [`apps/watch_wear/local_testing.md`](local_testing.md). For tag-driven release mechanics see [`docs/releasing.md`](../../docs/releasing.md). For the cross-service overview see [`docs/deployment.md`](../../docs/deployment.md).

**Status: plan.** App compiles and runs on emulator + real watches; no Play listing yet.

---

## Why a separate Play listing

Wear OS apps **are** Android apps — the manifest declares `<uses-feature android:name="android.hardware.type.watch" />` and the Play Store routes installs to paired watches. They can ship in three ways:

1. **Bundled inside the phone app's APK** — Play installs the watch APK to the paired watch automatically. This is the legacy approach.
2. **Standalone APK in the same listing** — phone app and watch app share a `applicationId` and one Play listing.
3. **Separate listing entirely** — different `applicationId`, watch app discoverable from the watch's own Play Store.

We picked **#3** ([decisions.md § 15](../../docs/decisions.md#15-watch_wear-is-pure-kotlin--compose-for-wear-not-flutter)). The reasons:

- The watch app is native Kotlin while the phone app is Flutter. Bundling them would force the phone app's APK to ship a Kotlin runtime it doesn't need.
- The Wear OS user can install the watch app **without** the phone app — common for users on iPhone with a Wear OS smartwatch (yes, this exists).
- Independent release cadence — a watch UI tweak shouldn't require shipping a phone build.
- Independent crash + ANR metrics in the Play Console.

So: `com.threkir.app` (phone) and `app.threkir.watchwear` (Wear OS) are two Play listings under the same developer account.

---

## Provider — Google Play Console (separate listing)

Same Play Console developer account as `mobile_android`. Setup is largely identical to `apps/mobile_android/deployment.md` § One-time Play Console setup, with these differences:

- Application ID: `app.threkir.watchwear`
- Form factor: Wear OS (declare in the Console under "Form factors")
- Listing screenshots: Wear OS-specific (round + square watch face previews)
- The store listing description should call out "Wear OS standalone — no phone required"

The `PLAY_SERVICE_ACCOUNT_JSON` from the phone-app Play setup is reusable here — just grant the same service account "Release manager" role on this app too.

### Wear OS-specific store metadata

Play Console → Wear OS → Wear OS settings:

- **Wear OS standalone**: Yes — the app can run without the phone (post-pairing setup).
- **Wear OS form factor declaration**: Required to show in the Wear OS Play Store at all.
- **Watch face previews**: Round (Pixel Watch / Galaxy Watch) and square (legacy) — auto-generated from the screenshots if you check the box.

---

## Signing setup

Different upload key from the phone app — different `applicationId` requires different signing identity per Play's rules.

### Generate the upload keystore (one-time)

```bash
keytool -genkey -v -keystore wear-upload-keystore.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Runonward Wear, O=Runonward, L=London, ST=England, C=GB"

base64 -w0 -i wear-upload-keystore.jks | xclip -selection clipboard
```

Same 1Password + GitHub Secret discipline as the phone-app keystore (`apps/mobile_android/deployment.md` § Signing setup) — losing the keystore is a 2–7 day Play support recovery flow.

### GitHub Secrets required

| Secret | Source |
|---|---|
| `WATCH_WEAR_KEYSTORE_BASE64` | base64 of `wear-upload-keystore.jks` |
| `WATCH_WEAR_KEYSTORE_PASSWORD` | from `keytool` |
| `WATCH_WEAR_KEY_ALIAS` | `upload` |
| `WATCH_WEAR_KEY_PASSWORD` | from `keytool` |
| `PLAY_SERVICE_ACCOUNT_JSON` | reused from the phone-app setup |

Plus build-time secrets injected via Gradle properties:

| Secret | Source |
|---|---|
| `SUPABASE_URL` | `https://api.threkir.com` (production) |
| `SUPABASE_ANON_KEY` | publishable key |
| `PUBLIC_MAPTILER_KEY` | shared MapTiler key |

These are passed to Gradle via `-PSUPABASE_URL=...` and end up in `BuildConfig` constants the Kotlin code reads.

---

## Build configuration

### `applicationId`

`apps/watch_wear/android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        applicationId = "app.threkir.watchwear"
        minSdk = 30           // Wear OS 3+
        targetSdk = 35
        compileSdk = 36
        versionCode = ...     // derived from git rev-list --count HEAD
        versionName = ...     // derived from the tag
    }
}
```

### Build flavours

Same shape as the phone app: `dev` and `production`. The dev flavour reads from `apps/watch_wear/android/.env.local` (gitignored, has `BYPASS_LOGIN=true` for local testing). The production build reads only from Gradle properties (no `.env.local` on the CI runner).

### Manifest declarations to verify before launch

`apps/watch_wear/android/app/src/main/AndroidManifest.xml`:

- `<uses-feature android:name="android.hardware.type.watch" />` — REQUIRED, makes the app eligible for Wear listing
- `android.permission.ACCESS_FINE_LOCATION` + `BACKGROUND_LOCATION`
- `android.permission.ACTIVITY_RECOGNITION`
- `android.permission.BODY_SENSORS` — Health Services HR
- `android.permission.FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — for the long-run battery whitelist UX
- `android.permission.WAKE_LOCK` — partial wake-lock during recording
- `<service android:name=".tiles.ActiveRunTileService">` with `BIND_TILE_PROVIDER` permission ([`apps/watch_wear/CLAUDE.md` § Active-run tile](CLAUDE.md))

The `meta-data` for `com.google.android.wearable.standalone` should be `true` — declares we work without a paired phone.

---

## Release workflow — `watch_wear@*`

Triggered by tagging `watch_wear@1.2.3`. The workflow at `.github/workflows/release-watch-wear.yml`:

1. Checks out the tag.
2. Sets up JDK 21 (matches the Android Studio JBR pin).
3. Decodes `WATCH_WEAR_KEYSTORE_BASE64` to a temp file.
4. Reads version from tag; derives `versionCode`.
5. `cd apps/watch_wear/android`
6. `./gradlew bundleProductionRelease -PSUPABASE_URL=$SUPABASE_URL ...`
7. Signs the AAB with the upload keystore.
8. Uploads to Play Internal track via `PLAY_SERVICE_ACCOUNT_JSON`.
9. Creates a GitHub Release with the AAB attached.

Promotion to Beta / Production is manual through the Play Console after smoke-testing on a real watch + emulator pair.

---

## Observability

| Surface | Tool | What |
|---|---|---|
| Crash reports | Sentry — separate "watch-wear" project under the same org | grouped Kotlin stacks, breadcrumb trail |
| Anomaly detection | Play Console → Statistics → Crashes & ANRs | per-device-model breakdowns |
| Battery usage | Play Console → Android vitals → Battery | excessive wakeups, partial-wake-lock leaks |
| Tile load latency | Play Console → Wear OS → Tile metrics | tile cold-start time, freshness warnings |

Wear OS crash rates are noisier than phone — emulator crashes from the device-model fragmentation can dominate for the first month. Watch real-device crashes specifically (filterable in the Console) and triage those.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Play Console developer fee | one-time, shared with phone app | $0 |
| Sentry watch-wear project | within the same Sentry org's free tier | $0 |
| **Subtotal** | | **$0** |

Marginal cost per install: $0. The watch app doesn't make additional API calls beyond what the phone app already does (sync, route fetch, race-mode pings) — so it doesn't push the Supabase tier.

---

## Rollback

Same Play Store roll-forward model as the phone app — see `apps/mobile_android/deployment.md` § Rollback. "Halt rollout" pauses propagation; tag a higher `versionCode` to fix forward.

A Wear OS-specific rollback consideration: when the phone app + watch app deploy together, a phone-app rollback that doesn't include a corresponding watch-app rollback can leave the two on incompatible payload schemas. The cross-platform fixture test (`apps/watch_wear/.../WatchRunPayloadFixtureTest.kt`) is the protection — both sides must agree on the canonical run-payload shape, and the fixture lives in version control. Rolling back one side without the other only breaks if the rollback crosses a payload-schema bump, which is rare.

---

## Disaster recovery

### Lost upload keystore

Same Play support recovery flow as the phone app. Keep `wear-upload-keystore.jks` in 1Password + cold storage.

### Lost Play Console access

Mitigated at the developer-account level (shared with the phone app — `apps/mobile_android/deployment.md` § Disaster recovery applies verbatim).

### Watch app delisting only

A Wear OS-specific edge: Google occasionally tightens Wear OS-specific guidelines and asks for compliance changes (Play Store stricter on tile freshness, complication API deprecations, etc.). These typically come with a 90-day window. Watch the Play Console messages, ship a compliance update before the window closes.

---

## Production readiness checklist

- [ ] Play Console listing for `app.threkir.watchwear` created
- [ ] Form factor: Wear OS declared
- [ ] Wear OS standalone meta-data set to `true`
- [ ] Store listing complete (description, screenshots — round + square watch faces, feature graphic)
- [ ] Privacy policy URL set (same one as the phone app — both apps are governed by the same policy)
- [ ] Data safety questionnaire submitted
- [ ] Upload keystore generated, in 1Password + cold storage + GitHub Secrets
- [ ] Play service account granted Release manager on this app
- [ ] Production Gradle properties verified (Supabase URL, anon key, MapTiler)
- [ ] Manifest reviewed against the permissions list
- [ ] Active-run tile service declared with the right permission
- [ ] First `watch_wear@*` tag built clean, AAB landed on Internal track
- [ ] Internal smoke test on real watch (Pixel Watch / Galaxy Watch — emulator-only is not sufficient for haptics, BLE HR, tile freshness)
- [ ] Sentry receiving events
- [ ] [`docs/parity.md`](../../docs/parity.md) Wear OS column reflects shipped state
