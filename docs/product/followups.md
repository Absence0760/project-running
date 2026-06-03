---
name: Gap-closure follow-ups
description: Open follow-ups only. Shipped items are pruned as they land — their cutover recipes live in apps/*/deployment.md and the code is in git history. Mirrors roadmap.md in spirit.
---

# Open follow-ups

What's left after the gap-closure + persona-hunt sessions. Shipped work has been pruned: the operator cutover recipes for the Go-service migrations (live hub, Strava webhook, token refresh, data export, premium endpoints) live in [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) and [`apps/web/deployment.md`](../../apps/web/deployment.md); everything else is in git history. Pair this file with [`docs/testing/testing.md`](../testing/testing.md) "What's *not* covered" for the test view.

Every item below is one of: (a) blocked on an external credential / account, (b) an operator deploy step on code that's already merged, or (c) a sized-but-unstarted feature awaiting a product green-light.

## Testing gaps

- [ ] **Device-instrumented `integration_test` harness** — none today; would cover tile-cache / foreground-service / background-sync on real Android primitives. New infrastructure.
- [ ] **OSRM smoke test in CI** — blocked on free-runner capacity (OSM PBF extract + osrm-extract memory). Options: a self-hosted runner, or a pre-built OSRM cache in S3 the workflow downloads.
- [ ] **Positive-path Edge Function tests** — the envelope suite covers auth-rejection only; 200-on-valid-HMAC / replay-dedupe / freshness-window tests need real secret values in the CI config.

## Mobile

- [ ] **Pro native RevenueCat purchase sheet + native donate** — scaffolding shipped (`revenuecat.dart`); the live sheet needs a RevenueCat project + a `pro_monthly` package + `REVENUECAT_API_KEY_ANDROID` / `_IOS` provisioned. Until then the Subscribe tile falls through to the web URL. (The store-localised Pro price is now WIRED: `settings_pro_screen.dart` fetches `proMonthlyPriceString` from `getOfferings()` and shows it in the Subscribe tile, falling back to the `$9.99` USD list price + the "billed in USD" regional note only when RevenueCat is unconfigured or the offering hasn't loaded. So the Apple 3.1.1 / Play store-localised-price requirement is satisfied in code — it just needs the RC project provisioned for the localised amount to actually appear.)
- [ ] **Map-matched track display** — gated on the map-matching deploy (see Deploys).
- [ ] **Wear OS recording-service foreground type may need `health`** — `apps/watch_wear/.../RunRecordingService.kt` runs as `foregroundServiceType="location"` but instantiates `HeartRateMonitor` (BODY_SENSORS) while in the foreground. On `targetSdk=35` (Android 14+ FGS-type enforcement) a service that accesses body sensors should declare `foregroundServiceType="location|health"` and hold `FOREGROUND_SERVICE_HEALTH`. Needs a Wear build + device test to confirm the current code doesn't already throw (Health Services passive monitoring may not trip the requirement) before changing the manifest — an unvalidated FGS-type edit can crash the service on `startForeground()`. Surfaced by the 2026-05-30 app-store-privacy audit while verifying the BODY_SENSORS disclosure.

## Deploys (code merged, operator steps remain)

- [ ] **share-run Lambda og:image PNG — verify the arm64 @resvg binary ships in the zip** — code merged (persona round-5 very-social): the share-run Lambda now serves `/og/run/<id>.png` at request time, CloudFront routes `/og/run/*` to it, and `build.mjs` copies the `@resvg/resvg-js` loader + the `@resvg/resvg-js-linux-arm64-gnu` native package into the zip's `node_modules`. The Lambda runs on arm64, so that native package must be resolvable on the build host. On `ubuntu-latest` (CI) `npm ci` normally pulls all-platform optional deps, but if `build.mjs` fails fast with the missing-binary error, run `npm install --workspace=apps/web --cpu=arm64 --os=linux @resvg/resvg-js-linux-arm64-gnu` before the zip step. Operator action: confirm the first prod/preview deploy after this lands actually renders `/og/run/<known-id>.png` (200, valid PNG) and that a private/deleted id returns the generic branded card at 200, not a 404. The new `/og/run/*` CloudFront behaviour is a `terraform apply` on `infra/envs/{prod,preview}`. See `apps/web/lambda/share-run/README.md § og:image PNG`.
- [ ] **Live spectator hub → Fly.io** — `fly.toml` exposes the hub on `:443` with `LIVEHUB_ALLOWED_ORIGINS`; remaining: provision the Fly app + `flyctl deploy`, add the `live.threkir.com` DNS record (`flyctl certs add` + Route 53), set `PUBLIC_LIVE_HUB_URL` (web sops blob) + `LIVE_HUB_URL` (mobile release builds). Client wiring (mobile + web) already switches transport on the env flip; no further code change. Recipe: `apps/job_worker/deployment.md § Live spectator hub`.
- [ ] **Map matching deploy** — OSRM alongside Supabase, OSM-extract refresh pipeline, auth endpoint, matched-geom return + raw-vs-matched toggle, offline fallback. Engine choice + trigger wiring shipped; the deploy is what remains.
- [ ] **Protomaps self-hosted tiles** — all 4 items from `roadmap.md` "Future — Protomaps self-hosted tiles".

## Web SEO (sized, not started)

- [ ] **Request-time `share-route` Lambda (parity with `share-run`)** — `/share/route/[id]` + `/og/route/[id].png` are prerendered at build time (`entries()` from `public_routes`, capped at 5k). A route made public *after* a build — or beyond the cap — serves the SPA-shell fallback `<head>` (generic "Threkir" title, no per-route OG) and a 404 for the og:image until the next deploy; a public→private flip stays served from S3 until overwritten. `share-run` already solved exactly this with a request-time Lambda (persona Casual #4 + round-5 very-social — see `apps/web/lambda/share-run/`). Mirroring it for routes is the symmetric fix: a `share-route` Lambda reusing `buildRouteShareCanonical` / `buildRouteJsonLd` / `buildRouteOgSvg`, a `prerender = false` flip on the page + og endpoint, CloudFront behaviours for `/share/route/*` + `/og/route/*`, IAM in `infra/github-oidc`, and a CI release step. Sized, not started — the build-time prerender + sitemap + canonical/JSON-LD (shipped) cover the steady-state indexed surface; this is the freshness/robustness upgrade.

## Blocked on external credentials / accounts

- [ ] **Push notifications (FCM + APNs + web Push)** — operator: create a Firebase project, drop `google-services.json` (Android) / `GoogleService-Info.plist` (iOS), enable an APNs auth key in the Apple Developer portal + upload to Firebase, generate `VAPID_PRIVATE_KEY` for web. Then add `firebase_messaging`, register tokens to `user_devices.push_token`, write the workout-reminder + kudos receive handlers, and wire `apps/web/src/lib/util/push.ts`.
- [ ] **Garmin Connect** — blocked on the multi-day Garmin Developer Program application + OAuth client provisioning. Then follow the Strava pattern: a `garmin.dart` helper + a `garmin-import` Edge Function + a Settings tile wired to OAuth. (Distinct from the on-watch Connect IQ data field at `apps/watch_garmin/` — that runs *on* the watch in Monkey C and needs no Garmin approval; this is server-side cloud sync. See [decisions.md § 107](../architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app).)
- [x] **Grade-adjusted pace on web/mobile** — done 2026-06-02. The Minetti 2002 model is now a shared TS↔Dart parity pair (`apps/web/src/lib/runs/grade_adjusted_pace.ts` ↔ `apps/mobile_android/lib/grade_adjusted_pace.dart`), surfaced as a run-detail key-stat on web and a secondary stat on mobile (byte-identical iOS twin), 10-test mirror suite each side. See [decisions.md § 114](../architecture/decisions.md#114-grade-adjusted-pace-lands-on-webmobile-first-as-a-shared-minetti-parity-helper-computed-over-5-m-segments-and-shown-only-when-it-diverges-from-raw-pace). **This satisfies the web-first prerequisite** [§107](../architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app) placed on the `apps/watch_garmin/` Connect IQ GAP field; remaining work is operator/product (publishing that field via the Connect IQ Store), not code — the math now matches across web, both mobile twins, and the watch field.
- [ ] **RunSignUp race-results** — needs a runsignup.com API key (free for non-commercial use). Then follow the parkrun pattern: a `runsignup-import` Edge Function + a Settings tile that ingests into `runs.metadata.event` / `position`.
- [ ] **iOS verification** — Mac-only. The byte-identical Dart codebase already supports every Android feature (decisions §39); `parity.md` cells stay ✗/Partial *by design* until simulator/device-verified. Gates: `Runner.entitlements` (HealthKit + Sign-in-with-Apple), `pod install`, the Apple Developer Sign-in-with-Apple Services ID + APNs setup. Info.plist is already complete.
- [ ] **Apple Watch** — Xcode / watchOS device required: route-nav visuals, ultra-length stress test, live race participant, complication target (Widget Extension), activity types, lap markers, hold-to-stop, TTS cues, pedometer, GPS self-heal, indoor mode, route picker, BLE pairing UI — each wired in Xcode + verified on a simulator or paired device.

## Internationalisation framework (sized project, not started)

Surfaced by the 2026-05-30 i18n-readiness audit. RTL *layout* is already complete web-wide (logical CSS properties + dir switch), and two standalone items shipped — the non-Latin font fallback (`app.css`) and the coach "reply in the runner's language" instruction. The remaining work is one coherent project, not piecemeal fixes:

- [~] **Web string framework runtime** (W-1/W-2/W-3 foundation) — **landed 2026-06-01.** The i18n runtime lives at `apps/web/src/lib/i18n/`: a client-side locale signal (`store.svelte.ts`, `m(key, params)`), pure negotiation (`locale.ts`), a per-locale message catalogue (`locales/{en,de,fr,es,ja,pt-BR}.ts`, lazy-imported via `catalogues.ts`), and detection wired in `+layout.svelte` (`initLocale` → `<html lang/dir>`). W-2/W-3 are resolved **client-side**, not via an `Accept-Language` server hook — the web app is statically prerendered with no per-request SSR ([decisions.md § 108](../architecture/decisions.md#108-web-i18n-is-detected-client-side-with-a-lazy-loaded-message-catalogue--not-an-accept-language-ssr-framework)). Starter translations ship for de/fr/es/ja/pt-BR. The **settings language picker** shipped (Settings → Preferences, endonym options). The **locale-aware formatter pass** shipped: number formatting (`format/number.ts` → `units.svelte.ts`, **W-15**), relative time (`Intl.RelativeTimeFormat`, **W-7**), the weekly-mileage axis label (**W-10 label**); **W-11** (recap-image numbers) was already locale-aware. The **calendar pass** shipped: PlanCalendar month/weekday names + `week_start_day` reorder via `format/calendar.ts` (**W-5**), and the weekly-mileage chart now anchors on `week_start_day` (**W-14**); **W-6** (`CalendarHeatmap`) already supports `weekStartDay` + locale-aware labels and the component is not currently mounted anywhere; the run-list week filter already honours `week_start_day` (the rest of W-14). **W-12** is done: `time.ts` carries a runtime-synced active format locale (`setActiveFormatLocale`/`activeFormatLocale`), so `formatDate`/`formatDateShort`/`formatRelativeTime` follow the picker, and all 19 inline `toLocaleDateString(undefined,…)` surfaces were swept to `activeFormatLocale()`. **W-8/W-9** done: the Free-tier price routes through `formatPrice(0)` and the Strava competitor price is labelled a US reference that varies by region. **Remaining (the only open web i18n item): incremental extraction of the ~400 user-facing string literals** across the route/component tree into the catalogue — a large mechanical + per-locale-translation effort, best done cluster-by-cluster. **Done:** app-shell nav/profile/offline + `prefs.language` + the full `/login` page; **workflow batch 1** (+1067 keys): dashboard, runs + runs/[id], routes + routes/[id] + routes/new, onboarding, coach + CoachChat, plans + plans/[id], u/[id], settings/{account,devices,integrations}. **Workflow batch 2** (+1231 keys): clubs (home + event detail + new-event + join + ClubEditor + EventEditor), landing, the plan/workout/run/event/plan-meta editors, settings/{upgrade,gear}, recap, compare, coaching (+ accept + athletes), share (run + route), live (+ event), messages, social (feed/people/clubs/hub + RunSocial), RunPhotos, SegmentsPanel, ImportRoute, RouteExplorer, RouteHeatmap, DateRangePicker, PeriodSummary, plans/new, guided detail, auth/reset. **Workflow batch 3** (+239 keys): the final tail — NotificationBell/NotificationsList, CookieConsentBanner, LicenseList, ReportDialog, RaceDayPanel, RunMap, ElevationProfile, PersonalHeatmap, RouteBuilder, TrainingLoadChart, RunGearChips, runs/heatmap, settings/+layout, and the auth/{confirm-age,callback} + guided + clubs/new + runs/new page-chrome wrappers. **Post-batch fixes (2026-06-01):** (1) the **Settings → Preferences** page itself was still ~95% English — the batches skipped it because it already used `m('prefs.language')`, so a `+87`-key extraction pass finished it. (2) A **reactivity bug** class was found + fixed: labels built in top-level `const` arrays/objects (the /runs filter chips, run-detail activity/zone labels, settings/devices spec, settings nav sections, landing app cards, integrations descriptions) called `m()` once at init and never updated on a locale switch — each was moved to `$derived(...)` (or rendered reactively in-template). **Watch for this anti-pattern in future extraction: never `const x = [{ label: m(...) }]` at script scope — use `$derived` or call `m()` inline in the template.** **Web string extraction is now COMPLETE** — ~75 files / ~2682 keys × 6 locales across the three workflow batches plus the hand-done shell/login/preferences. The only English-by-design surface left is the **legal pages** (privacy/terms/cookie-notice) — counsel-pending draft copy, translating them is a legal decision. **Caveat:** the ~2540 machine-extracted translations want a **native review** before advertising full localisation (agents flagged the fitness-domain tooltips — CTL/ATL/TSB/VO₂max — and a few register/article-agreement/fragment-split spots, all noted in their per-file outputs). Next platforms: **mobile (Flutter)**, **Wear OS**, **watchOS**, and Supabase **email templates** (per the M-*/W-OS-*/iOS-W-1/SRV-1 audit items). Each cluster: pull the literals into `locales/{en,…}.ts`, swap to `m('key')`, translate ×5 (running-domain copy wants a native review). Then the mobile / watch / watchOS / email surfaces.
- [~] **Mobile (Flutter) localisation** (M-1/M-2/M-3) — **mostly done** (verified 2026-06-02; the old "unstarted, ~473 literals" estimate is stale). `flutter_localizations` + `intl` + gen-l10n are wired with six-locale ARB catalogues, committed gen output, a per-device locale picker, locale-aware `DateFormat`, and locale-driven TTS — see [decisions.md § 113](../architecture/decisions.md#113-mobile-i18n-uses-flutter-gen-l10n--arb-with-committed-non-synthetic-output-and-a-per-device-locale). 79 of ~158 `lib/` files already route through `AppLocalizations`. **Remaining (2026-06-03 pass):** the residual screen cleanup is essentially done — `people`, `trusted_contacts`, `club_invite`, `route_picker`, `recap`, `import`, `readiness_card`, and `missing_map_tiles_hint` were extracted (~107 keys ×6 locales + iOS twin mirror; the `import` pass also dropped a dual English/l10n shim in `buildImportStatus` plus two dead helpers). The last two files — `run_screen.dart` + `widgets/run_share_card.dart` — were localized on 2026-06-03 (run-start background-location + battery-optimisation dialog title/body, and the run-share caption; +5 keys ×6 locales, their now-orphaned English `k*` constants in `background_location_nudge.dart` / `battery_optimisation_hint.dart` deleted). A **wider follow-up sweep the same day** (a stricter grep than the `Text('[A-Z]` heuristic that had under-counted) caught the genuine remainder the earlier passes missed: the whole `settings_screen` landing (tile labels reuse existing `settingsAccountTitle`/`prefsTitle`/… keys, +7 new subtitle keys), `period_summary_screen` (`Week of`, `All time`, the share-text run-count plural + `Avg pace:` — pure helpers localized via context-free `lookupAppLocalizations`, +3 keys reusing `runsRangeAll`), the `verified_badge` tooltip (+1 key), and the dashboard + run-detail **best-effort distance names** (`Half Marathon`/`Marathon`/`5 km`/`10 km` — +4 keys via a `bestEffortDistanceLabel` resolver in `run_stats.dart`). Confirmed **not** gaps and left as-is: the `devices_screen` `overrideKeyRegistry` English `label`/`hint` (fallbacks behind a working `labelFor`/`hintFor` l10n switch, pinned non-empty by a test), `workout_review_section`'s `fromMap` labels (display uses `localizedLabel(l10n)` + the existing `workoutReviewLabel*` keys), `$e`-interpolated exception text in already-localized banners, the `"DELETE"` account-deletion challenge token (referenced literally in every locale's instruction string), and proper nouns (`Strava`/`GPX`/`Threkir`/parkrun `A123456` format hint). The mobile string-extraction pass is now **complete**; the only remaining mobile i18n work is RTL (`EdgeInsetsDirectional` sweep), still deferred until an RTL catalogue ships.
- [ ] **Watch localisation** (WR-1, WOS-1) — Wear Compose string resources + watchOS `Localizable.strings`.
- [ ] **Guided-run scripts** (S-1) — per-locale `GUIDED_RUN_LIBRARY` script sets (web `guided_runs.ts` is still a hard-coded English `const`; the mobile twin already localized via `guidedRunLibrary(AppLocalizations)`).
- [~] **2026-06-03 i18n residual closures** — re-verified the 2026-05-30 audit against current code; the bulk was already done. Closed this pass: **W-4** (workout-kind + plan-phase labels were still bare English in `training.ts`/`training.dart` — moved to presentation helpers `workout_labels.ts` / `training_labels.dart` that read the catalogues, +14 keys across all web locales and all 7 ARBs, both mobile twins); **W-12** (`PeriodSummary` week-range *end* date passed `undefined` instead of the active locale); **W-OS-3** (Android run-notification channel name + Resume/Pause/Stop action labels were hard-coded in `RunNotificationBridge.kt` — now string resources with 5 locale folders + a guard test). Note: the **watch** framing on the line above is stale — Wear already uses `stringResource` + `values-{de,fr,es,ja,b+pt+BR}` and watchOS ships `Localizable.xcstrings` with 5 locales (W-OS-1/W-OS-2/iOS-W-1 are closed). **Still genuinely open:** the **`routes/heatmap` web page** is fully English (0 `m()` calls — distinct from the already-localized `runs/heatmap`); guided-run scripts (line above); Supabase auth email templates (SRV-1 — GoTrue serves one template set per project with no per-recipient locale, so this is platform-limited, not a quick edit); and RTL (`EdgeInsetsDirectional`/`AlignmentDirectional`, deferred until an RTL locale ships).

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
- [x] **Gear tracking** (#7) — shipped end-to-end (migrations `20260827_001` + `20260901_001`; `/settings/gear` + `RunGearChips` on web, `GearScreen` + twin on mobile, auto-tag-default trigger, `gear_with_distance` mileage view). 2026-06-02 follow-up closed a latent RLS bug: the gear chip never rendered on the **public** run-share page for non-owners — the `run_gear` SELECT policy wrapped `is_run_visible_to` in a base-`runs` subquery that the public-read-policy drop (`20260701_001`) had silently defanged, and the `gear` join is owner-only so a non-owner read NULL anyway. Fixed by `20261126_001` (direct definer call + a `public_run_gear` SECURITY DEFINER RPC that projects only public columns), `RunGearChips` mounted on `RunShareView`, pgtap + anon e2e. **Remaining (mobile parity, small):** mobile `public_run_screen.dart` doesn't surface a gear chip yet — a web-ahead parity gap, not a bug (mobile only shows gear on the owner's own run-detail today).
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
  feature (a watching partner already sees the finish). The email leg of the
  theme-B sender now ships (`decisions.md § 117`), so a safety-contact alert
  could route through it; native push to a locked phone still waits on the
  FCM/APNs leg. Until that feature is built the gate stays as-is by design.

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

- [x] **Email notification delivery + event-day reminders (theme B, email leg)** —
  SHIPPED 2026-06-03 (migration `20261130_001`, `decisions.md § 117`). A
  `notification_email` job kind on the Go worker reads new notification rows and
  sends over SMTP, gated on `user_settings.prefs.email_notifications`
  (`all | important | off`, default `important`); `enqueue_event_reminders()`
  (hourly pg_cron) creates `event_reminder` rows for `going` RSVPs in the next
  24 h. Credential-free, end-to-end tested against local Mailpit. So the
  Saturday-morning race cancellation now reaches an inbox. Addresses the
  parkrun-owner / event-organizer / family-club / social-group findings for the
  email channel; admin-update fan-out rides the same path once that kind exists.
- [ ] **Native push delivery (theme B, FCM/APNs leg, ~1 wk + ops)** — the remaining
  leg: native push to a locked phone. The `notifications` row is already the source
  of truth and the email handler proves the consumer pattern; an FCM/APNs sender is
  a sibling consumer. Genuinely blocked on operator-supplied Firebase/APNs
  credentials + mobile client-side token registration (no `firebase_messaging`
  wiring exists). Web-push server-side delivery is a separate not-blocked slice (the
  `VAPID_PRIVATE_KEY` is self-generated; the client subscribe path already ships).
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
  onboarding still writes the bare `date_of_birth` column unconditionally (minor-
  exclusion) while gating the prefs-bag mirror + gender + consent timestamp on the
  Art 9 checkbox. `/settings/account` is now consent-gated (DOB writeback +
  `grant_health_data_consent` RPC, matching `/settings/preferences`), so the two
  settings surfaces are aligned; the remaining inconsistency is the onboarding
  unconditional-DOB-column write. Decide whether onboarding's minor-exclusion DOB
  capture counts as implicit consent or needs the explicit toggle too — a legal-flow
  decision, deliberately not bolted on without counsel input.
- [ ] **Age-grade calculator for non-parkrun races (older, MEDIUM)** — `age_grade`
  is only surfaced for parkrun imports (scraped value in `metadata.age_grade`).
  A manual / Strava / FIT race with a known distance, duration, and the runner's DOB
  gets no age grade. Computing it properly needs the official **WMA road age-factor
  tables** (per single-year-of-age × distance × sex) plus the open-class road
  standards — a sizeable, version-specific dataset (WMA 2023/2025). Deliberately NOT
  shipped as a from-memory approximation: a wrong age-grade % actively misleads the
  exact masters-runner audience that values the metric. Build as a shared TS↔Dart
  parity helper (web `age_grade.ts` ↔ mobile `age_grade.dart`) once the authoritative
  factor tables are sourced, then surface on run-detail when DOB + distance + duration
  are known and `metadata.age_grade` is absent.
- [~] **Treadmill / indoor per-point HR → HR-zone chart (garmin)** — **core shipped 2026-06-02.**
  Chose data model (b): a sibling `{user_id}/{run_id}.hr.json.gz` Storage object in the
  `runs` bucket + a `runs.hr_series_url` column (migration `20261127_001`, [decisions.md
  § 116](../architecture/decisions.md)). `garmin-fit.ts` collects HR from records with no
  GPS fix into `ParsedFitRun.hr_series`; `saveRun` uploads the sidecar when the track has
  no bpm; web run-detail + the mobile twin (`ApiClient.fetchHrSeries`) fall back to the
  sidecar so the HR-zone chart renders for trackless indoor runs. The coordinate pipeline
  (GPX export, clip RPC, map-match) is untouched — the sidecar carries no location and is
  owner-only (never in `public_runs` / clip). Tests: FIT-parser unit tests + an anon-safe
  HR-zone e2e (`hr-zones.spec.ts` indoor case) + the path-forgery pgtap; twins byte-identical.
  **Backup/restore done (2026-06-02):** both backup builders (Dart `writeBackupZipStreaming`
  + Go `BuildBackupZip`) archive the sidecar under `hr/{id}.hr.json.gz` and count it in the
  manifest; the Dart restore re-homes it and always re-stamps `hr_series_url` (the archived
  value is the old owner/run path, which the path-shape CHECK would reject). Per-point HR now
  survives a device-swap backup→restore. **Fully shipped** — no remaining sub-items. (Offline
  restore still doesn't reconstruct per-point HR, the same documented caveat the GPS track has
  on that path; the cloud copy + online restore are complete.)
- [ ] **Health Connect import brings tracks (garmin/android, mobile + device)** —
  `health_connect_importer.dart` hard-codes `track: []`, so every HC-imported run is
  trackless/lapless/cadenceless. Reading the HC ExerciseRoute + sample series into a
  track needs the HC route API + on-device testing. Mobile feature.
- [ ] **Segment-KOM "crowns" in the recap (deferred)** — the Year-in-Running recap now
  shows a derived **Trophies** badge grid + **Photos** and **Personal records** counts
  (`recap.ts#computeRecapBadges` + `fetchRecapExtras`). Strava-style segment KOM/QOM
  "crowns" specifically are still omitted: `segment_efforts` has no stored rank, so a
  per-segment global-min aggregation across all users would be needed — heavier than a
  recap card warrants, and segment leaderboards are a secondary surface here. Personal
  records stand in as the achievement metric.
