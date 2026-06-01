---
name: Gap-closure follow-ups
description: Open follow-ups only. Shipped items are pruned as they land — their cutover recipes live in apps/*/deployment.md and the code is in git history. Mirrors roadmap.md in spirit.
---

# Open follow-ups

What's left after the gap-closure + persona-hunt sessions. Shipped work has been pruned: the operator cutover recipes for the Go-service migrations (live hub, Strava webhook, token refresh, data export, premium endpoints) live in [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) and [`apps/web/deployment.md`](../../apps/web/deployment.md); everything else is in git history. Pair this file with [`docs/testing/testing.md`](../testing/testing.md) "What's *not* covered" for the test view.

Every item below is one of: (a) blocked on an external credential / account, (b) an operator deploy step on code that's already merged, or (c) a sized-but-unstarted feature awaiting a product green-light.

## Testing gaps

- [ ] **RunScreen Finish + save UI test** — the widget-test scaffold doesn't fully initialise `RunRecorder`, so `_stop()` produces no `LocalRunStore` row; needs platform-channel mocks for the recorder's start-time deps. The data-pipeline path (`recording_integration_test.dart`) is covered — only the Finish-tap UI surface is open.
- [ ] **Device-instrumented `integration_test` harness** — none today; would cover tile-cache / foreground-service / background-sync on real Android primitives. New infrastructure.
- [ ] **OSRM smoke test in CI** — blocked on free-runner capacity (OSM PBF extract + osrm-extract memory). Options: a self-hosted runner, or a pre-built OSRM cache in S3 the workflow downloads.
- [ ] **Positive-path Edge Function tests** — the envelope suite covers auth-rejection only; 200-on-valid-HMAC / replay-dedupe / freshness-window tests need real secret values in the CI config.

## Mobile

- [ ] **Pro native RevenueCat purchase sheet + native donate** — scaffolding shipped (`revenuecat.dart`); the live sheet needs a RevenueCat project + a `pro_monthly` package + `REVENUECAT_API_KEY_ANDROID` / `_IOS` provisioned. Until then the Subscribe tile falls through to the web URL. (The store-localised Pro price — `settings_pro_screen.dart` showing `getOfferings()` instead of the hard-coded `$9.99/month` — is part of this same RevenueCat dependency. The interim "billed in USD" honesty note from the 2026-05-30 Medium audit has shipped; the live price waits on the RC project.)
- [ ] **Map-matched track display** — gated on the map-matching deploy (see Deploys).
- [ ] **Wear OS recording-service foreground type may need `health`** — `apps/watch_wear/.../RunRecordingService.kt` runs as `foregroundServiceType="location"` but instantiates `HeartRateMonitor` (BODY_SENSORS) while in the foreground. On `targetSdk=35` (Android 14+ FGS-type enforcement) a service that accesses body sensors should declare `foregroundServiceType="location|health"` and hold `FOREGROUND_SERVICE_HEALTH`. Needs a Wear build + device test to confirm the current code doesn't already throw (Health Services passive monitoring may not trip the requirement) before changing the manifest — an unvalidated FGS-type edit can crash the service on `startForeground()`. Surfaced by the 2026-05-30 app-store-privacy audit while verifying the BODY_SENSORS disclosure.

## Deploys (code merged, operator steps remain)

- [ ] **share-run Lambda og:image PNG — verify the arm64 @resvg binary ships in the zip** — code merged (persona round-5 very-social): the share-run Lambda now serves `/og/run/<id>.png` at request time, CloudFront routes `/og/run/*` to it, and `build.mjs` copies the `@resvg/resvg-js` loader + the `@resvg/resvg-js-linux-arm64-gnu` native package into the zip's `node_modules`. The Lambda runs on arm64, so that native package must be resolvable on the build host. On `ubuntu-latest` (CI) `npm ci` normally pulls all-platform optional deps, but if `build.mjs` fails fast with the missing-binary error, run `npm install --workspace=apps/web --cpu=arm64 --os=linux @resvg/resvg-js-linux-arm64-gnu` before the zip step. Operator action: confirm the first prod/preview deploy after this lands actually renders `/og/run/<known-id>.png` (200, valid PNG) and that a private/deleted id returns the generic branded card at 200, not a 404. The new `/og/run/*` CloudFront behaviour is a `terraform apply` on `infra/envs/{prod,preview}`. See `apps/web/lambda/share-run/README.md § og:image PNG`.
- [ ] **Live spectator hub → Fly.io** — `fly.toml` exposes the hub on `:443` with `LIVEHUB_ALLOWED_ORIGINS`; remaining: provision the Fly app + `flyctl deploy`, add the `live.threkir.com` DNS record (`flyctl certs add` + Route 53), set `PUBLIC_LIVE_HUB_URL` (web sops blob) + `LIVE_HUB_URL` (mobile release builds). Client wiring (mobile + web) already switches transport on the env flip; no further code change. Recipe: `apps/job_worker/deployment.md § Live spectator hub`.
- [ ] **Map matching deploy** — OSRM alongside Supabase, OSM-extract refresh pipeline, auth endpoint, matched-geom return + raw-vs-matched toggle, offline fallback. Engine choice + trigger wiring shipped; the deploy is what remains.
- [ ] **Protomaps self-hosted tiles** — all 4 items from `roadmap.md` "Future — Protomaps self-hosted tiles".

## Blocked on external credentials / accounts

- [ ] **Push notifications (FCM + APNs + web Push)** — operator: create a Firebase project, drop `google-services.json` (Android) / `GoogleService-Info.plist` (iOS), enable an APNs auth key in the Apple Developer portal + upload to Firebase, generate `VAPID_PRIVATE_KEY` for web. Then add `firebase_messaging`, register tokens to `user_devices.push_token`, write the workout-reminder + kudos receive handlers, and wire `apps/web/src/lib/util/push.ts`.
- [ ] **Garmin Connect** — blocked on the multi-day Garmin Developer Program application + OAuth client provisioning. Then follow the Strava pattern: a `garmin.dart` helper + a `garmin-import` Edge Function + a Settings tile wired to OAuth.
- [ ] **RunSignUp race-results** — needs a runsignup.com API key (free for non-commercial use). Then follow the parkrun pattern: a `runsignup-import` Edge Function + a Settings tile that ingests into `runs.metadata.event` / `position`.
- [ ] **iOS verification** — Mac-only. The byte-identical Dart codebase already supports every Android feature (decisions §39); `parity.md` cells stay ✗/Partial *by design* until simulator/device-verified. Gates: `Runner.entitlements` (HealthKit + Sign-in-with-Apple), `pod install`, the Apple Developer Sign-in-with-Apple Services ID + APNs setup. Info.plist is already complete.
- [ ] **Apple Watch** — Xcode / watchOS device required: route-nav visuals, ultra-length stress test, live race participant, complication target (Widget Extension), activity types, lap markers, hold-to-stop, TTS cues, pedometer, GPS self-heal, indoor mode, route picker, BLE pairing UI — each wired in Xcode + verified on a simulator or paired device.

## Internationalisation framework (sized project, not started)

Surfaced by the 2026-05-30 i18n-readiness audit. RTL *layout* is already complete web-wide (logical CSS properties + dir switch), and two standalone items shipped — the non-Latin font fallback (`app.css`) and the coach "reply in the runner's language" instruction. The remaining work is one coherent project, not piecemeal fixes:

- [ ] **Web string framework** (W-1, ~1-2 wk) — extract ~35 components + ~40 routes of English literals into a message catalog + a small runtime (e.g. an `m['key']` lookup keyed off a locale signal that also drives `<html dir>`), then translate. Currency: `/compare` competitor prices + `formatPrice` are hard-coded USD (W-2) — fold into the same locale pass.
- [ ] **Mobile (Flutter) localisation** (M-1/M-2/M-3) — add `flutter_localizations` + `intl` + ARB files; replace the ~473 `Text()` literals + English month-name lists; drive TTS language off the locale instead of `en-US`/`Locale.US`.
- [ ] **Watch localisation** (WR-1, WOS-1) — Wear Compose string resources + watchOS `Localizable.strings`.
- [ ] **Guided-run scripts** (S-1) — per-locale `GUIDED_RUN_LIBRARY` script sets.

## Watch (Wear OS) — sized features awaiting hardware + a product green-light

Surfaced by the persona round-5 samsung-watch hunt. Each needs the Wear build
toolchain plus on-watch verification (Galaxy Watch / Pixel Watch) — the watch
recording stack is not runtime-testable without a device, so these can't be
closed from a host JVM. The audio-focus ducking fix from the same hunt shipped
already (`TtsAnnouncer.kt` now requests `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`);
these three are genuine features, not bug fixes.

- [ ] **BLE chest-strap HR paired directly to the watch** (~1-1.5 wk + device) —
  today BLE chest-strap HR is **phone-only** (`apps/mobile_android/lib/ble_heart_rate.dart`);
  the watch records **optical** HR via Health Services `MeasureClient` only, and
  only when standalone. Supporting a strap paired to the *watch* means an
  on-watch Wear OS BLE GATT client: a scan/pair UI, the standard Heart Rate
  Service (`0x180D`) / Heart Rate Measurement (`0x2A37`) characteristic
  subscription, `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` runtime perms, and a
  source-preference so a connected strap overrides the optical stream into
  `metadata.avg_bpm`. Reconnect/dropout handling on the wrist is the fiddly part.
  A minority feature (watch-standalone runners who own a strap) — already noted
  as deferred in [`apps/watch_wear/CLAUDE.md` § "What's still deferred"](../../apps/watch_wear/CLAUDE.md).
  **Needs hardware**: a real strap + watch to validate GATT connect, sample
  cadence, and battery cost; not unit-testable.
- [ ] **Real body weight → calorie estimate** (~2-4 d + device) —
  `apps/watch_wear/.../recording/RunCalories.kt` reads `body_weight_kg` from the
  prefs bag but defaults to **70 kg** when unset, so a runner who never set a
  weight in the web/mobile settings gets a generic kcal figure on `PostRunScreen`.
  Pipe the user's *actual* weight into the estimate. Data-source options, in
  rough order of fidelity: (a) Samsung Health BIA body-composition (most accurate
  on a Galaxy Watch, but requires the Samsung Health SDK / Health Connect read
  permission + Samsung partner approval — heaviest integration); (b) Health
  Services / Health Connect `WeightRecord` (vendor-neutral, lighter, but the user
  must have logged a weight somewhere that syncs); (c) surface a weight field in
  the watch settings or rely on the existing universal-setting sync from
  web/mobile (cheapest, no new permission, but manual). The watch still won't
  apply the female calibration the phone/web cell uses (it reads
  `user_settings.prefs` only, not `user_profiles.gender` — decisions §77), so the
  watch summary stays an estimate that the synced run-detail page recomputes.
  **Needs a device** to confirm the chosen read path actually returns a value on
  a real Galaxy Watch.
- [ ] **Watch-face complication** (~1-1.5 wk + device) — only an **active-run
  tile** ships today (`tiles/ActiveRunTileService.kt`); a true watch-face
  *complication* (a glanceable slot the user adds directly to their watch face,
  vs. the swipe-to tile carousel) is unbuilt — `parity.md` was corrected to say
  tile-only. Building it means a `ComplicationDataSourceService` (androidx
  `wear-watchface-complications-data-source`), supported complication types
  (`SHORT_TEXT` for elapsed/distance, `RANGED_VALUE` for goal progress,
  `MONOCHROMATIC_IMAGE` for an idle glyph), a tap `PendingIntent` into
  `MainActivity`, the same `requestUpdate`-on-stage-transition wiring the tile
  uses, plus a preview + picker label. Pure formatters can be unit-tested
  (mirror `ActiveRunTileFormattersTest`); the data-source binding + render need a
  watch face that hosts the complication slot, so **on-device verification is
  required**.

## Competitor-parity backlog (needs product green-light)

From `roadmap.md § Competitor-parity backlog`; sizes are rough estimates carried from the roadmap table:

- [ ] **Heatmap / popular-route discovery** (#4, ~2 wk) — materialised tile table or a Go tile service; anonymised aggregation. Open decision: opt-in vs opt-out privacy default.
- [ ] **Trail / offline navigation** (#5, ~3-4 wk) — turn-by-turn on a loaded route + offline tile packs + condition reports. Needs a routing-engine choice (Valhalla vs GraphHopper).
- [ ] **Gear tracking** (#7, ~1 wk) — `gear` + `run_gear` link table, mileage per item, retirement reminders. Smallest open feature; v1 manual-only.
- [ ] **Audio-coached runs** (#9, ~3-4 wk) — pre-recorded workout library + TTS-narrated pace cues. Audio CDN strategy + voice-talent budget needed.
- [ ] **Race calendar + results import** (#10, ~2 wk) — event discovery + entry links + auto-match results on record. Gated on the RunSignUp key above.
- [ ] **Advanced analytics polish** (#11, ~2 wk) — no new tables; richer dashboard breakdowns + race-time predictor over what VDOT / training-load already ship.
- [ ] **Premium billing extensions** (#12, ~1-2 wk) — Stripe Checkout + customer portal + paywall enforcement across web + mobile.
- [ ] **Treadmill BLE FTMS** (#13, ~3-5 d, mobile-only) — real-time speed / distance / incline from a paired treadmill. Spec in `integrations.md § Treadmills (BLE FTMS)`. Needs hardware-in-the-loop testing.

## Safety-contact finish alerts (persona round-5 family-club)

The `run_completed` notification (migration `20261101_001`) correctly fans a
**public** run out to the runner's **followers**. The family-club persona wanted
a partner to be alerted that the runner finished *even on a private run* (a
safety use case). This is NOT a fix to the `is_public` gate — removing that gate
would broadcast every private run to all followers, a privacy regression. The
real need is a distinct, opt-in feature:

- [ ] **Safety contacts** (~1 wk) — a `safety_contacts` table (owner → contact
  user/email, opt-in both ways), and a `run_completed`-style trigger (or a
  branch in the live-hub finish path) that alerts ONLY the designated contact
  on a finish regardless of `is_public`. Pairs naturally with the live-spectator
  feature (a watching partner already sees the finish). Gated on the same
  deferred push/email sender as the rest of theme B. Until then the gate stays
  as-is by design.

## Auto-follow on club join (persona round-5 social-group) — product decision

`join_club_by_token` adds an active `club_members` row; it deliberately does
NOT create `user_follows` edges. The social-group persona wanted joining a club
to wire up the social graph. But club invite tokens are **generic** (one
`clubs.invite_token`, not per-inviter), so there is no specific person to
follow-back, and auto-following every active member on join is presumptuous +
spammy + a consent concern (you didn't choose to follow 50 strangers). The club
feed (`club_posts`, already fanned out via notifications) is the intended
in-club social surface. If we want member-to-member connection, the right shape
is a **"Follow members" suggestion list** on the club page (opt-in, one tap),
not an automatic fan-out — tracked here rather than shipped as a silent
follow-everyone trigger.

## Persona round-5 — feature-scale items (not bug fixes)

Surfaced by the round-5 persona hunt; each is a real feature or needs external
keys/product sign-off, so none were half-built. Sized for the roadmap:

- [ ] **Push / email notification delivery (theme B, ~1-2 wk + ops)** — DB triggers
  already fan out `event_cancel` / `run_completed` / `club_post` notification rows
  and the in-app bell renders them, but there is NO server-side sender, so a
  Saturday-morning race cancellation never reaches a locked phone. Needs an Edge
  Function / Go endpoint that reads new notification rows and pushes via FCM
  (Android) + APNs (iOS) + a web-push path (the `VAPID_PRIVATE_KEY` is already in
  backend env, unused), plus an email channel (no email sender exists anywhere).
  Blocked on operator-supplied Firebase/APNs credentials. Hit by parkrun-owner
  (Critical), event-organizer (High), family-club (Critical), social-group (Med).
- [ ] **Paid event registration (~2-3 wk)** — event creation has no paid-entry /
  ticketing path (event-organizer Critical). Needs a Stripe-backed registration
  flow (capacity cap + waitlist already partially modelled), refunds, and payout
  config — couples to the premium-billing work below. Product + payments decision.
- [ ] **Strava community segment import (~2-3 wk)** — strava-migration wants their
  Strava KOM/QOM segments imported. Strava's segment API requires per-segment
  OAuth scopes we don't request, and segment-leaderboard data has Strava ToS
  redistribution limits — needs a legal + API-scope decision before building.
- [ ] **Family / household Pro tier (~1 wk + pricing decision)** — family-club pays
  4× $9.99 for 4 accounts. A household plan (shared subscription across linked
  accounts) is a pricing/product decision (RevenueCat entitlement model + a
  household link table), not a code-only change.

## Persona round-5 — remaining dispositions

- [ ] **Consent-flow consistency for health-data fields (privacy, legal-adjacent)** —
  onboarding now writes the bare `date_of_birth` column unconditionally (minor-
  exclusion) while gating the prefs-bag mirror + gender + consent timestamp on the
  Art 9 checkbox. `/settings/account` + `/settings/preferences` still persist
  DOB/resting-HR/max-HR into `user_settings.prefs` without that same consent gate
  (round-5 privacy "Art 9 via /settings/account"). Align all three surfaces on one
  consent model — a legal-flow decision (is in-app entry implicit consent, or is an
  explicit toggle required?), so deliberately not bolted on without counsel input.
- [ ] **Health Connect import brings tracks (garmin/android, mobile + device)** —
  `health_connect_importer.dart` hard-codes `track: []`, so every HC-imported run is
  trackless/lapless/cadenceless. Reading the HC ExerciseRoute + sample series into a
  track needs the HC route API + on-device testing. Mobile feature.
- [ ] **Year-in-Running recap parity (strava-migration, ~1 wk)** — the recap omits
  photos / crowns / badges that Strava's Year in Sport shows. Additive recap
  enhancement (recap.ts + recap/[year]); product-styling decision on what to feature.
