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

- [ ] **Pro native RevenueCat purchase sheet + native donate** — scaffolding shipped (`revenuecat.dart`); the live sheet needs a RevenueCat project + a `pro_monthly` package + `REVENUECAT_API_KEY_ANDROID` / `_IOS` provisioned. Until then the Subscribe tile falls through to the web URL.
- [ ] **Map-matched track display** — gated on the map-matching deploy (see Deploys).
- [ ] **Wear OS recording-service foreground type may need `health`** — `apps/watch_wear/.../RunRecordingService.kt` runs as `foregroundServiceType="location"` but instantiates `HeartRateMonitor` (BODY_SENSORS) while in the foreground. On `targetSdk=35` (Android 14+ FGS-type enforcement) a service that accesses body sensors should declare `foregroundServiceType="location|health"` and hold `FOREGROUND_SERVICE_HEALTH`. Needs a Wear build + device test to confirm the current code doesn't already throw (Health Services passive monitoring may not trip the requirement) before changing the manifest — an unvalidated FGS-type edit can crash the service on `startForeground()`. Surfaced by the 2026-05-30 app-store-privacy audit while verifying the BODY_SENSORS disclosure.

## Deploys (code merged, operator steps remain)

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
