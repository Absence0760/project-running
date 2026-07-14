# Mobile iOS deployment plan

How `apps/mobile_ios/` ships to the Apple App Store, including the bundled `apps/watch_ios/` Apple Watch target.

Operational counterpart of [`apps/mobile_ios/CLAUDE.md`](CLAUDE.md) and the byte-identical-twin convention with `apps/mobile_android/` ([decisions.md § 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)). For the cross-service overview see [`docs/ops/deployment.md`](../../docs/ops/deployment.md). For tag-driven release mechanics see [`docs/ops/releasing.md`](../../docs/ops/releasing.md).

**Status: plan.** The Dart code is at parity with Android (same `lib/`, same `test/`); native iOS work + entitlements + a Mac runtime smoke run are the remaining gates.

---

## What this doc covers

The iOS app and the Apple Watch app are **one deployment**. The watchOS target is a Watch Extension bundled inside the iOS app's `.ipa`. There's no separate listing, no separate review, no separate upload. `apps/watch_ios/` exists as a sibling directory for organisational purposes only — the Xcode project lives at `apps/mobile_ios/ios/Runner.xcworkspace` and pulls in the watchOS target from there.

So: `mobile_ios@1.2.3` triggers one CI workflow that ships **both** apps.

---

## Provider — Apple App Store Connect

**Distribution:** App Store + TestFlight.

**TestFlight first.** Internal testers (up to 100 Apple IDs in the developer team) and external testers (up to 10,000 via a public TestFlight link) can install before the App Store rollout. Treat TestFlight as the equivalent of Play's Internal track.

**Bundle IDs:**

```
com.threkir.app            ← iOS phone app
com.threkir.app.watchkitapp ← Apple Watch app target
com.threkir.app.watchkitapp.WidgetsExtension  ← (when the complication ships)
```

**Country / region rollout:** Same shape as Android — start with UK + Australia + US, expand once stable.

---

## One-time Apple Developer Program setup

1. **Pay $99/year for the Apple Developer Program.** Use a long-lived team mailbox, not a personal Apple ID. Apple's account recovery is brutal — it's worth the extra ~5 minutes of setup to use a shared account.
2. **Create an organisational team** (Apple Developer → Membership). Personal accounts work but limit to 1 admin; an organisation lets multiple maintainers manage signing.
3. **Create the App ID** at developer.apple.com → Identifiers:
   - Bundle ID: `com.threkir.app` (Explicit)
   - Capabilities: HealthKit, Sign in with Apple, Push Notifications, Background Modes (Location updates), Maps, Associated Domains (for universal links — optional)
4. **Create the Watch App ID:**
   - Bundle ID: `com.threkir.app.watchkitapp`
   - Capabilities: HealthKit, Background Modes (Workout processing)
5. **Provisioning profiles.** Create App Store distribution profiles for both bundle IDs. Set the team to your Developer Program team. Download the `.mobileprovision` files.
6. **Create the App Store listing** at App Store Connect:
   - App information (name, primary category Health & Fitness, content rights)
   - App privacy (next section)
   - Pricing — Free, available worldwide minus the regions we're skipping
   - In-App Purchases — RevenueCat will populate this once SDK is wired

---

## Signing setup

### Generate the distribution certificate (one-time)

In Keychain Access on a Mac:

1. Certificate Assistant → Request a Certificate from a Certificate Authority. Email = the developer team mailbox. Choose "Saved to disk".
2. developer.apple.com → Certificates → "+" → iOS Distribution → upload the `.certSigningRequest` from step 1.
3. Download the issued `.cer`. Double-click to install in Keychain Access.
4. In Keychain Access, find the certificate. Expand to see the private key. Right-click → Export → save as `threkir-distribution.p12` with a password.
5. `base64 -i threkir-distribution.p12 | pbcopy` → paste into GitHub Secret `IOS_BUILD_CERTIFICATE_BASE64`.

### App Store Connect API key (one-time)

This is what lets CI upload to TestFlight without a maintainer's Apple ID password.

1. App Store Connect → Users and Access → Keys → "+" → name "GitHub Actions", access "App Manager".
2. Download the `.p8` file. **You can only download it once** — save to 1Password.
3. Note the **Key ID** and **Issuer ID** shown on the same page.

### GitHub Secrets required

| Secret | Source |
|---|---|
| `IOS_BUILD_CERTIFICATE_BASE64` | base64 of `threkir-distribution.p12` |
| `IOS_P12_PASSWORD` | the password from the export step |
| `IOS_PROVISIONING_PROFILE_BASE64` | base64 of the iOS app's `.mobileprovision` |
| `IOS_WATCH_PROVISIONING_PROFILE_BASE64` | base64 of the Watch app's `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | a throwaway, gates the ephemeral keychain on the runner |
| `APP_STORE_CONNECT_API_KEY_ID` | the Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | the Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | base64 of the `.p8` |

---

## Build configuration

### Build flavours

Same shape as Android: `dev` and `production` build configurations, gated on `xcconfig` files.

| Configuration | Bundle ID | Backend |
|---|---|---|
| `Debug-Dev` | `com.threkir.app.dev` | Local Supabase |
| `Release-Dev` | `com.threkir.app.dev` | Staging Supabase |
| `Release-Production` | `com.threkir.app` | Production Supabase |

### Production secrets via `dart_defines.json`

The iOS toolchain doesn't accept Supabase's `sb_publishable_...` keys via inline `--dart-define=` — the underscores break Xcode's argument parsing ([decisions.md § 13](../../docs/architecture/decisions.md)). Instead the workflow writes a temporary `dart_defines.json`:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_...",
  "MAPTILER_KEY": "...",
  "REVENUECAT_API_KEY": "appl_...",
  "SENTRY_DSN": "https://...@sentry.io/..."
}
```

Then `flutter build ipa --release --dart-define-from-file=dart_defines.json`. The file is gitignored; the workflow generates it from secrets, builds, then deletes.

### Info.plist keys to verify before launch

Required strings (Apple rejects without a meaningful description):

- `NSLocationWhenInUseUsageDescription` — "We use your location to record your runs."
- `NSLocationAlwaysAndWhenInUseUsageDescription` — explains why we need background access
- `NSMotionUsageDescription` — pedometer (steps + cadence)
- `NSHealthShareUsageDescription` — HealthKit reads
- `NSHealthUpdateUsageDescription` — HealthKit writes
- `NSBluetoothAlwaysUsageDescription` — BLE chest-strap HR
- `NSPhotoLibraryUsageDescription` — run photos
- `NSCameraUsageDescription` — taking a photo on the run

Required keys:

- `UIBackgroundModes` array containing `location` (background GPS) and `workout-processing` (Apple Watch session)
- `WKWatchKitApp` (in the watch target's Info.plist) — true
- `WKCompanionAppBundleIdentifier` — `com.threkir.app`

### Capabilities to enable in Signing & Capabilities

- HealthKit
- Sign in with Apple
- Push Notifications (APNs)
- Background Modes → Location updates + Audio (for TTS) + Background fetch
- App Groups → `group.com.threkir.app` (shared between iOS app, watch app, and the future complication target — see [`apps/watch_ios/Complications/README.md`](../watch_ios/Complications/README.md))

---

## Privacy nutrition label

App Store Connect → App Privacy. Same data classes as the Play Data Safety form, but Apple uses different language:

| Data type | Used to track? | Linked to user? | Purpose |
|---|---|---|---|
| Location (precise + coarse) | No | Yes | App functionality |
| Health & Fitness — heart rate, steps | No | Yes | App functionality |
| Email | No | Yes | App functionality |
| Name (optional display name) | No | Yes | App functionality |
| User ID | No | Yes | App functionality |
| Device ID (APNs/FCM push token) | No | Yes | App functionality |
| Purchase history (subscription state via RevenueCat) | No | Yes | App functionality |
| Photos | No | Yes (when the user uploads) | App functionality |
| Other user content (comments, posts, reviews, notes, Coach chat) | No | Yes | App functionality |
| Crash data, performance data | No | No | App functionality (analytics) |

These rows must stay consistent with `ios/Runner/PrivacyInfo.xcprivacy` (the privacy manifest declares the same collected-data types) and with the Android Data Safety table in [`apps/mobile_android/deployment.md`](../mobile_android/deployment.md).

"Used to track" = correlated with data from other companies for ads. We don't do this; answer "No" everywhere.

Apple cross-checks the App Privacy declarations against actual API usage during review. Declaring "no precise location" while the binary calls `CLLocationManager` requestAlwaysAuthorization is an instant rejection.

### Age rating — capability declarations

App Store Connect's age-rating questionnaire (revised 2025: 4+/9+/13+/16+/18+ tiers) asks about app capabilities, not just content. Declare truthfully:

- **User-generated content / social features** — Yes: social feed, run comments, club posts, direct messages.
- **Location sharing** — Yes: public run/route shares and live spectator links expose (privacy-clipped) location.
- **In-app purchases** — Yes: the Pro subscription (the "In-App Purchases" badge is also derived automatically from the IAP configuration).

The base content rating stays low for a running app; these capability flags are what raise the effective tier, and misdeclaring them is a review rejection. Keep the answers consistent with the Play IARC interactive elements in [`apps/mobile_android/deployment.md`](../mobile_android/deployment.md).

---

## Release workflow — `mobile_ios@*`

Triggered by tagging `mobile_ios@1.2.3`. The workflow at `.github/workflows/release-ios.yml`:

1. Checks out the tag on a `macos-latest` runner.
2. Sets up Flutter SDK + CocoaPods.
3. Decodes the `.p12` cert into an ephemeral keychain (gated by `KEYCHAIN_PASSWORD`).
4. Decodes both `.mobileprovision` files into `~/Library/MobileDevice/Provisioning Profiles/`.
5. Reads version from tag, derives build number from `git rev-list --count HEAD`.
6. Writes the production `dart_defines.json`.
7. `flutter build ipa --release --export-options-plist=export-options.plist`.
8. Uploads to App Store Connect via `xcrun altool` using the API key.
9. Creates a GitHub Release with the IPA attached.

Lands the build in **TestFlight** (the equivalent of Play's Internal track). Promotion to App Store is manual through App Store Connect after a smoke test.

The `release-ios.yml` workflow is currently a skeleton ([releasing.md](../../docs/ops/releasing.md) notes the secrets are commented out). Uncomment once the Apple Developer team is set up + the certs exist.

---

## Apple Watch specifics

### What ships in the IPA

The Apple Watch target is a separate scheme in the same Xcode project. `flutter build ipa` compiles it as a Watch Extension and embeds it in the IPA. Users who install the iOS app see the Watch app appear in the iOS Watch app's "Available apps" list, where they can install it on their paired watch.

There's no separate review for the Watch app. App Store review covers both targets in one pass; the reviewers test on a paired watch + phone simulator.

### HealthKit entitlements (Watch)

The Watch target needs its own HealthKit entitlement (separate from the iOS one). Set up at developer.apple.com → Identifiers → `com.threkir.app.watchkitapp` → enable HealthKit.

### Watch Connectivity

The phone-watch transport is `WCSession.transferFile(_:metadata:)` (decisions.md § 40). The phone-side `WatchIngestBridge.swift` is **live**; the queue persists pre-auth payloads to disk via `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` so a phone restart between watch transfer and sign-in doesn't lose the run. No additional setup at deploy time — entitlements travel with the App Group.

### Active-run complication

The Complications target ([`apps/watch_ios/Complications/README.md`](../watch_ios/Complications/README.md)) requires its own bundle ID + provisioning profile if/when it ships. Currently scaffolded but not built — `parity.md` shows it as `Partial`. When the complication target lands, add a `IOS_COMPLICATION_PROVISIONING_PROFILE_BASE64` secret and update the workflow.

---

## Observability

Same Sentry mobile project as Android — different DSN platform tag, same dashboard. Apple-specific surfaces:

| What | Where |
|---|---|
| Crash reports | Sentry mobile project + Xcode Organizer (post-launch) |
| Energy / power metrics | Xcode Organizer → Energy / Hangs |
| Adoption rate | App Store Connect → Analytics |
| User reviews | App Store Connect → Ratings and Reviews |

**Sentry on iOS gotcha.** `sentry_flutter` requires a build-phase script in the Runner target (`scripts/sentry-upload.sh`) that uploads dSYMs after every release build. Without it, crashes appear as raw memory addresses instead of symbolicated stacks. Adding this is part of the "uncomment the iOS release workflow" milestone.

---

## Cost projection

| Component | Tier | Monthly |
|---|---|---|
| Apple Developer Program | $99/year | $8.25 |
| Sentry mobile | shared with Android | $0 (covered already) |
| App Store ranking promotions | optional, not planned | $0 |
| **Subtotal** | | **~$8** |

Marginal cost per install: $0. Apple takes 15–30% of in-app purchase revenue (handled via RevenueCat); not directly an "Apple charge" but factor into pricing.

---

## Rollback

App Store has a similar "halt rollout" called **Phased Release** + **Stop Phased Release**:

- New releases ship via Phased Release by default — 1% of auto-update users on day 1, ramping to 100% over 7 days.
- If a regression surfaces during phasing, **Stop Phased Release** in App Store Connect freezes new auto-updates at the current %. Existing installs keep their version.
- Tag a fix as `mobile_ios@1.2.4` and submit. Expedited reviews are available for emergencies but should be reserved for genuine outages — abuse loses goodwill with reviewers.

There is **no rollback to a previous version** in the App Store. Releases are roll-forward only.

---

## Disaster recovery

### Lost distribution certificate / `.p12`

Generate a new one. Apple lets you have multiple distribution certs active simultaneously (max 2), so the failure mode here is an inconvenience, not a months-long blocker. Update the GitHub Secrets, commit a release. The previous cert keeps working until it expires — no impact on installed apps.

### Lost App Store Connect access

Same shape as Android Play Console. Mitigations:

1. Developer team mailbox, not a personal Apple ID.
2. Two **Account Holder** equivalents — actually App Store Connect supports one Account Holder + multiple Admins; ensure at least two team members are Admins.
3. The team mailbox itself has 2FA backup codes printed.

### Account terminated

Apple's appeal process is faster than Google's but still painful. Mitigations:

1. Read the App Store Review Guidelines before launch.
2. Stay clear of the headline pitfalls: misleading descriptions, hidden in-app purchases, copyright issues, location-data abuse, accessibility regressions.
3. If terminated, the appeal goes through the standard channel; expect 1–2 weeks. The app and reviews come back if successful.

---

## Production readiness checklist

- [ ] Apple Developer Program $99 paid + organisation team approved
- [ ] Bundle IDs registered at developer.apple.com (iOS + Watch)
- [ ] Capabilities enabled on both bundle IDs (HealthKit, Sign in with Apple, Push, Background Modes, App Groups)
- [ ] App Store Connect listing created (description, keywords, support URL, screenshots — required at iPhone 6.7", iPhone 5.5", iPad 12.9", Apple Watch screen sizes)
- [ ] Privacy policy live at `threkir.com/privacy`
- [ ] App Privacy nutrition label completed, matches policy
- [ ] Distribution certificate generated, in 1Password and GitHub Secrets
- [ ] Provisioning profiles for both bundle IDs in GitHub Secrets
- [ ] App Store Connect API key created, in GitHub Secrets
- [ ] Production `dart_defines.json` values verified
- [ ] Info.plist usage descriptions all written
- [ ] Watch target builds clean from `mobile_ios` scheme
- [ ] First TestFlight build smoke-tested on a real device + a real Apple Watch
- [ ] Sentry receiving symbolicated crash reports (dSYM upload script live)
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) iOS column flips from Partial to ✓ once Mac-runtime parity is verified
- [ ] [`docs/product/parity.md`](../../docs/product/parity.md) Apple Watch column updated as features pass review
