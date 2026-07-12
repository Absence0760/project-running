# Mobile Android deployment plan

How `apps/mobile_android/` ships to the Google Play Store.

Operational counterpart of [`apps/mobile_android/CLAUDE.md`](CLAUDE.md) (stack, what's real, file layout) and [`apps/mobile_android/local_testing.md`](local_testing.md) (running it locally). For tag-driven release mechanics see [`docs/ops/releasing.md`](../../docs/ops/releasing.md). For the cross-service overview see [`docs/ops/deployment.md`](../../docs/ops/deployment.md).

**Status: plan.** Local builds + tests pass; no Play listing exists yet.

---

## Provider — Google Play Console

**Track strategy:**

```
Internal track  → Closed alpha (10–100 testers)  → Closed beta (1k+ testers)  → Production
   ↑ workflow                                                                       ↑ manual
   tag-driven                                                                  Play Console
```

The release workflow always lands at the **Internal track**. Manual promotion to Beta / Production happens in the Play Console after a smoke test. This is intentional: tagging `mobile_android@1.2.3` should never reach unsuspecting users without a human checking the build first.

**Application ID:** `com.threkir.app` (or whatever the brand picks). Don't change this after the first published release — every existing install becomes orphaned.

**Country / region rollout:** start with **UK + Australia** (where most early users live). Once stable, widen to "all countries". Some regulated markets (China, Russia) require additional legal work — leave them off until that work is scoped.

---

## One-time Play Console setup

1. **Pay the $25 developer registration fee.** One time, per Google account. **The login identity is a dedicated Gmail** (e.g. `threkir.app@gmail.com`), **not** a branded `@threkir.com` address — see § Account identity below for why. Set the Play Console *contact* addresses to `google@` / `support@` / `privacy@threkir.com` so the domain still shows up on the operator-facing side.
2. **Create the app.** Play Console → Create app. Name, default language (en-GB), Type: App, Free.
3. **Fill the Store listing.** Short description, long description, screenshots (need at least 2 phone screenshots, 1 7"+ tablet, 1 10"+ tablet for newer Play guidelines), feature graphic (1024×500 PNG), app icon (512×512 PNG).
4. **Privacy policy URL.** Required for any app that touches location. Host at `threkir.com/privacy` — see § Privacy policy below.
5. **App content questionnaire.** Click through every "Privacy", "Ads", "Target audience", "Data safety" form. **Data safety is non-trivial** — see § Data safety below.
6. **App access.** Provide test credentials (`runner@test.com` / `testtest` against a *staging* Supabase project — never production seed). The Play review team uses these to access functionality behind sign-in.
7. **Content rating.** Complete the IARC questionnaire. Running app should land at "Everyone".
8. **Pricing & distribution.** Free, available in target countries.
9. **Set up the "Internal testing" track.** Add at least 1 internal tester email so the link is live.

---

## Account identity — dedicated Gmail login, threkir.com contact addresses

**Decided 2026-07-12.** The Google account that owns Play Console (and later the
linked GCP project for the release service account + Firebase for FCM push) uses
a **dedicated Gmail as the login identity** (e.g. `threkir.app@gmail.com`).
`@threkir.com` addresses are used only as the **contact / notification
addresses** configured inside each Google product.

Why not a branded `@threkir.com` login:

- A real `@threkir.com` Google *login* requires **paid Google Workspace**
  (~$7/user/mo). Google's "create account with existing email" path has been
  removed for personal accounts, and "For work or my business" funnels straight
  into the Workspace signup.
- Worse, the Workspace signup wants to **take over `threkir.com` email** (own the
  MX, route mail through Gmail) — which **collides with the Migadu inbound setup**
  (the apex MX/SPF/DKIM in `infra/dns/terraform.tfvars` `email_auth_records`).
  Adopting Workspace would mean migrating mail off Migadu. Not worth it just to
  own a Play Console account.
- A Gmail login is cosmetic-only: all operational contact + notification mail
  still flows to the Migadu inbox via the `@threkir.com` contact addresses,
  nothing touches the MX, and it's free. It also avoids gating account creation
  on `@threkir.com` receiving working (Gmail verifies against itself).

Treat the Gmail as a **role identity**, not a person: two admins on the Play
Console, 2FA enabled, and **2FA backup codes printed** (see § Disaster recovery
→ Lost Play Console access). If real `@threkir.com` Google logins are ever
wanted, that's a deliberate "adopt Workspace + migrate mail off Migadu" project,
not a default.

---

## Signing setup

The release workflow signs every `.aab` with an upload key stored as a GitHub Secret. The Play Console then re-signs with Play App Signing's distribution key — that key never leaves Google.

### Generate the upload keystore (one-time)

```bash
keytool -genkey -v -keystore upload-keystore.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Runonward, O=Runonward, L=London, ST=England, C=GB"

# Encode for GitHub Secret:
base64 -w0 -i upload-keystore.jks | xclip -selection clipboard

# Keep the original .jks in 1Password — losing it means losing the
# ability to push updates. The Play Console's "Reset upload key"
# flow exists but it's a multi-day process; treat the .jks as
# irreplaceable.
```

Keep the keystore in 1Password under `runonward / android-upload-keystore`. CI never reads it from there directly — it reads from the GitHub Secret, which is just a copy.

### GitHub Secrets required

| Secret | Source |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of `upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | from `keytool -genkey` |
| `ANDROID_KEY_ALIAS` | `upload` (matches `-alias` above) |
| `ANDROID_KEY_PASSWORD` | from `keytool -genkey` (often same as keystore password) |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play service account key JSON (next section) |

### Play service account (one-time)

Lets the workflow upload an `.aab` without a human in the loop:

1. Play Console → Setup → API access → "Choose a project to link" → create a Google Cloud project.
2. Create a service account in the Cloud Console (IAM & Admin → Service Accounts → Create).
3. Skip granting Cloud roles; we only need Play permissions.
4. Back in the Play Console → grant the service account "Release manager" role on **this app**.
5. Generate a JSON key for the service account (Service Accounts → … → Manage keys → Add key → JSON).
6. Paste the entire JSON into the GitHub Secret `PLAY_SERVICE_ACCOUNT_JSON`.

The same service account JSON is reusable for the Wear OS release ([`apps/watch_wear/deployment.md`](../watch_wear/deployment.md)) — just grant it Release manager on that app too.

---

## Build configuration

### Build flavours

Two product flavours, set up in `apps/mobile_android/android/app/build.gradle.kts`:

| Flavour | applicationId | Backend |
|---|---|---|
| `dev` | `com.threkir.app.dev` | Local Supabase or staging |
| `production` | `com.threkir.app` | Production Supabase |

Different `applicationId` lets dev + prod coexist on a single device. Useful for the "I want to test against staging without losing my production runs" flow.

### Production secrets injected at build time

The production flavour reads from `--dart-define`s (passed by the workflow):

| Define | Value |
|---|---|
| `SUPABASE_URL` | `https://api.threkir.com` |
| `SUPABASE_ANON_KEY` | publishable key from Supabase |
| `MAPTILER_KEY` | from MapTiler dashboard |
| `REVENUECAT_API_KEY` | RevenueCat Android key |
| `SENTRY_DSN` | Sentry mobile project DSN |

The dev flavour reads from `apps/mobile_android/.env.local` (gitignored), which carries staging or local URLs.

### Manifest declarations to verify before launch

- `android.permission.ACCESS_FINE_LOCATION` — required for GPS recording
- `android.permission.ACCESS_BACKGROUND_LOCATION` — required for background recording when the screen locks
- `android.permission.ACTIVITY_RECOGNITION` — pedometer (steps)
- `android.permission.FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` — for the recording notification
- `android.permission.POST_NOTIFICATIONS` — for the run-in-progress notification on Android 13+
- `android.permission.INTERNET` + `ACCESS_NETWORK_STATE` — sync
- Health Connect: handled at runtime via the `health` package
- `BluetoothScan` / `BluetoothConnect` (Android 12+) — BLE chest-strap HR

The `BACKGROUND_LOCATION` permission is the most scrutinized at review time. The Play Store requires a **prominent in-app disclosure** explaining why we need it before requesting; that lives on the `OnboardingScreen`. Don't remove that disclosure.

### targetSdk 36 (Android 16) — what to re-verify on-device

`targetSdk = 36` (Play requires it for updates from **2026-08-31**; `compileSdk` follows `flutter.compileSdkVersion`, currently 36). Android 16 behaviour changes that activate at this target and need a manual pass on an Android 16 device before release:

- **Edge-to-edge is mandatory** — `windowOptOutEdgeToEdgeEnforcement` is ignored on Android 16. Flutter's current stable handles insets, but verify the onboarding, recording (`run_screen`), and bottom-nav surfaces don't draw under the status/gesture bars.
- **Orientation / aspect-ratio restrictions ignored on ≥600 dp displays** — the app fills the window on tablets/foldables regardless of preferred orientation; check the recorder and map layouts at tablet widths.
- **Predictive back on by default** — verify back gestures from the recording screen still hit the in-app confirm flow rather than dismissing the activity.
- **Foreground-service recording** — no new FGS type is required (`FOREGROUND_SERVICE_LOCATION` stands), but soak-test a full background-locked recording on Android 16 for regressions in the tightened background-work quotas.
- **Notifications** — verify the live recording notification and push-notification taps; the app uses no full-screen intents, so `USE_FULL_SCREEN_INTENT` is not needed.

---

## Privacy policy

Required for the Play listing. Host at `https://threkir.com/privacy` — a static SvelteKit route in `apps/web/src/routes/privacy/+page.svelte`. Must cover, at minimum:

- What we collect (location, optional HR, optional photos, account email)
- How we use it (display in app, sync to user's account, optional sharing)
- Who we share with (third parties: Strava if connected, Garmin if connected, RevenueCat for subscriptions, Anthropic for Coach prompts)
- Retention (lifetime of account; export available; deletion via `/settings/account`)
- User rights (GDPR-ish — data export, deletion, correction)
- Contact (`privacy@threkir.com`)

Also link the same URL from the Play Console under "Data safety → Privacy policy URL". Mismatch between the two = automatic review rejection.

---

## Data safety questionnaire

Play Console → App content → Data safety. Be precise; mismatches between the questionnaire and what the app actually does are a sticky cause of review delays.

| Data type | Collected? | Shared? | Optional? | Encrypted in transit? |
|---|---|---|---|---|
| Approximate location | Yes | No | No (required for the core function) | Yes |
| Precise location | Yes | No | No | Yes |
| Health & fitness — heart rate, steps | Yes | No | Yes | Yes |
| Email address | Yes | No | No (account requirement) | Yes |
| Name | Yes (optional display name, setup wizard / profile) | No | Yes | Yes |
| User IDs | Yes | No | No | Yes |
| Device or other IDs | Yes (FCM push token → `device_tokens`, registered on sign-in when Firebase is configured) | No | No | Yes |
| Purchase history | Yes (Pro subscription state via RevenueCat / Play Billing) | No | Yes (only if the user subscribes) | Yes |
| Photos | Yes (if user uploads) | No | Yes | Yes |
| Other user-generated content | Yes (comments, club posts, route reviews, run notes, AI Coach chat messages) | No | Yes | Yes |
| App interactions / Diagnostics | Yes (Sentry crash reports) | No | Optional via opt-out | Yes |

"Shared" is **No** for everything we don't actively send to third-party servers. Strava / Garmin / RevenueCat / Anthropic are **only** invoked when the user signs in to those services or uses Coach, which counts as user-initiated rather than programmatic sharing. Phrasing in the questionnaire matters; if uncertain, default to the more conservative "Yes — Optional → user-initiated".

---

## Content rating — IARC interactive elements

The IARC questionnaire rates the *content* (a running app lands at "Everyone" / PEGI 3), but it also asks about **interactive elements**, which are displayed alongside the rating and must be declared truthfully:

- **Users Interact** — Yes: social feed, run comments, club posts, direct messages, coach chat.
- **Shares Location** — Yes: public run/route share pages and live spectator links expose (privacy-clipped) location.
- **Digital Purchases** — Yes: the Pro subscription in-app purchase.

A mismatch between these declarations and the binary is grounds for a rating recall or review rejection, same as the Data safety form.

---

## Release workflow — `mobile_android@*`

Triggered by tagging `mobile_android@1.2.3`. The workflow at `.github/workflows/release-android.yml`:

1. Checks out the tag.
2. Sets up Flutter SDK + JDK 17.
3. `melos bootstrap`.
4. Decodes `ANDROID_KEYSTORE_BASE64` to a temp file.
5. Reads version from the tag (`1.2.3`); derives `versionCode` from `git rev-list --count HEAD`.
6. `flutter build appbundle --flavor production --release \
     --dart-define-from-file=production-defines.json`.
7. Signs the AAB with the upload keystore.
8. Uploads to Play Internal track via `PLAY_SERVICE_ACCOUNT_JSON`.
9. Creates a GitHub Release with the AAB attached.

Promotion from Internal to Beta to Production is **manual** through the Play Console after smoke-testing the Internal build.

---

## Observability

| Surface | Tool | Cost |
|---|---|---|
| Crash reports | Sentry (mobile project) — bundled via `sentry_flutter` | $0 (free tier) → $26 (team) |
| Anomaly detection | Play Console → Statistics → Crashes & ANRs | included |
| User feedback | Play Console → User feedback | included |
| Vitals (excessive battery / wakeups / etc.) | Play Console → App quality → Android vitals | included |

**Sentry setup:** create a "mobile" project in Sentry. The DSN is a build-time `--dart-define`. `sentry_flutter` initialises in `lib/main.dart`'s `runZonedGuarded` boundary; releases are tagged with the `versionName` so a regression's release can be pinpointed.

**ANR alerts.** Sentry doesn't catch ANRs cleanly on Flutter. Watch the Play Console "Android vitals" panel weekly; an ANR rate >0.5% triggers warnings and eventually delisting from the Play Store's recommended lists.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Play Console developer fee | $25 one-time, not recurring | $0 |
| Sentry mobile | Free tier (50k events/mo across all projects) | $0 → $26 |
| **Subtotal** | | **$0–26** |

Marginal cost per install: $0.

---

## Rollback

The Play Store's release model is fundamentally roll-forward — every Play release ships a higher `versionCode` than the previous one. You can't re-deploy a lower `versionCode`.

**Halt rollout** is the closest thing to a rollback:

1. Play Console → Production → "Halt rollout" on the broken release.
2. Existing installs keep their version (whichever they auto-updated to).
3. New installs go back to receiving the previous release.
4. Tag a fix as `mobile_android@1.2.4` (higher than the broken `1.2.3`) and roll out.

If a release is so broken that "halt rollout" isn't fast enough, contact Play support for an "expedited review" of the next patch. Reserve this for genuine emergencies — abuse loses goodwill with reviewers.

---

## Disaster recovery

### Lost upload keystore

The single failure mode that's actually scary. The Play Store has a recovery flow:

1. File the "Reset upload key" support request from the Play Console.
2. Provide proof of identity + project ownership.
3. Google generates a new upload key; you swap it into GitHub Secrets.
4. Deploys resume.

This takes 2–7 days. **Keep the keystore in 1Password and in cold storage** (a printed QR code in a fireproof safe, an encrypted backup at a friend's house, etc.). The cost of redundancy is zero; the cost of losing the only copy is a week of zero releases.

### Lost Play Console access

The Google account itself becoming inaccessible. Mitigations:

1. The developer account login is a dedicated role Gmail (§ Account identity), not a person.
2. Two admins on the Console — if one's account is locked the other can recover.
3. The role Gmail has 2FA backup codes printed, and its recovery address points at the Migadu inbox.

### Account banned

Rare, but if it happens (usually for ToS violations the team didn't realise applied) the path is appeals process → if denied, the app and all reviews are gone. **Mitigation:** read the Developer Program Policies before launch; especially the location-data, financial-services, and family-friendly sections. If the appeal succeeds the app comes back intact.

---

## Production readiness checklist

- [ ] Play Console developer account paid + verified
- [ ] App created with target `applicationId`
- [ ] Store listing complete (short + long description, screenshots, icon, feature graphic)
- [ ] Privacy policy live at `threkir.com/privacy`
- [ ] Data safety questionnaire submitted, matches policy
- [ ] Content rating done
- [ ] App access test creds provided (staging, not prod seed)
- [ ] Internal testing track has ≥1 tester email
- [ ] Upload keystore generated, in 1Password and GitHub Secrets
- [ ] Keystore backup stored cold (off-machine)
- [ ] Play service account created, JSON in GitHub Secrets, granted Release manager on this app
- [ ] Production-flavour `--dart-define` values verified (URL, anon key, MapTiler, RevenueCat, Sentry DSN)
- [ ] Manifest reviewed; permissions list matches data-safety form
- [ ] BACKGROUND_LOCATION prominent in-app disclosure on OnboardingScreen verified
- [ ] First `mobile_android@*` tag built clean, AAB landed on Internal track
- [ ] Internal smoke test passed (sign-in, record a run, view in history, sync to backend)
- [ ] Sentry receiving events from a debug build
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) Android column updated when promotion to Production happens
