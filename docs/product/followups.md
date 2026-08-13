---
name: Gap-closure follow-ups
description: Open follow-ups only. Shipped items are pruned as they land — their cutover recipes live in apps/*/deployment.md and the code is in git history. Mirrors roadmap.md in spirit.
---

# Open follow-ups

Every item below is one of: (a) blocked on an external credential / account, (b) an operator deploy step on code that's already merged, or (c) a sized-but-unstarted feature / a deferred-with-reason finding awaiting a product or architecture call.

> **Completed work was pruned from this file on 2026-06-14.** The full pre-prune snapshot — every shipped `[x]` item and closed section with its implementation context — is preserved in [`followups_archive.md`](followups_archive.md). Pair this file with [`docs/testing/testing.md`](../testing/testing.md) "What's *not* covered" for the test view. Operator cutover recipes for the Go-service migrations live in [`apps/job_worker/deployment.md`](../../apps/job_worker/deployment.md) and [`apps/web/deployment.md`](../../apps/web/deployment.md).

## Deploys (code merged, operator steps remain)

- [ ] **share-run / share-route Lambda og:image PNG — verify the arm64 @resvg binary ships in the zip.** Both Lambdas serve their og:image PNG at request time and `build.mjs` copies the `@resvg/resvg-js` loader + `@resvg/resvg-js-linux-arm64-gnu` native package into the zip. The Lambdas run on arm64, so that native package must resolve on the build host. If `build.mjs` fails fast with the missing-binary error, run `npm install --workspace=apps/web --cpu=arm64 --os=linux @resvg/resvg-js-linux-arm64-gnu` before the zip step. Operator: confirm the first prod/preview deploy renders `/og/run/<id>.png` + `/og/route/<id>.png` (200, valid PNG) and that a private/deleted id returns the generic branded card at 200, not a 404. The new `/og/run/*` + `/og/route/*` + `/share/route/*` CloudFront behaviours are a `terraform apply` on `infra/envs/{prod,preview}`. See `apps/web/lambda/share-run/README.md` + `apps/web/lambda/share-route/README.md`.
- [ ] **Live spectator hub → Fly.io** — `fly.toml` exposes the hub on `:443` with `LIVEHUB_ALLOWED_ORIGINS`; remaining: provision the Fly app + `flyctl deploy`, add the `live.threkir.com` DNS record (`flyctl certs add` + Route 53), set `PUBLIC_LIVE_HUB_URL` (web sops blob) + `LIVE_HUB_URL` (mobile release builds). Client wiring already switches transport on the env flip; no further code change. Recipe: `apps/job_worker/deployment.md § Live spectator hub`.
- [ ] **Map matching deploy** — OSRM alongside Supabase, OSM-extract refresh pipeline, auth endpoint, matched-geom return + raw-vs-matched toggle, offline fallback. Engine choice + trigger wiring shipped; the deploy is what remains.
- [ ] **Route builder needs a reachable OSRM — design decision first, not just a deploy.** The shipped internal-track build (`mobile_android@1.0.5`, 2026-07-14) has `OSRM_URL` unset, so the route Build button throws on a phone. **Do NOT "just" expose `osrm.threkir.com`** — the previous wording of this item said that, and it contradicts a documented decision: `osrm-routed` is the upstream `osrm/osrm-backend` image with **no auth of any kind**, which is exactly why `apps/job_worker/osrm/fly.toml` attaches no public IP and `apps/job_worker/deployment.md` § DR states "OSRM has no auth; that's why it can never have a public route" (it declines to expose even `/health` directly). A naked public OSRM is an open, abusable `performance-2x`/8 GB compute service.

  The real blocker is **cross-cloud reachability + no auth**, and it has three parts:
  1. **OSRM is on Fly 6PN; its consumer is an AWS Lambda.** The `osrm-proxy` Lambda (`apps/web/lambda/osrm-proxy/`, issue #198 / decisions §242) is built, Terraformed (`infra/envs/{prod,preview}`) and bundled by `release-web.yml` — but it cannot reach `osrm.internal`. `var.osrm_url` defaults to `""`, and an empty value leaves the proxy at 501 with the **web** route builder degrading to straight-line segments. Confirm whether prod actually has it set before assuming web routing works.
  2. **Auth has to be added in front of OSRM, not to it.** The house precedent is `graph_cycle`: `[http_service]` + `force_https` + a required `GRAPH_CYCLE_API_KEY` header — but that works because `graph_cycle` is *our* Go code (`apps/graph_cycle/main.go`). OSRM is a third-party binary, so the equivalent needs a small auth reverse-proxy in front of it on Fly (or moving OSRM into AWS beside the Lambda, removing the cross-cloud hop entirely).
  3. **Mobile must go through the Lambda proxy, not straight at OSRM.** `routing.dart` currently builds `$OSRM_URL/nearest/v1/...` and `$OSRM_URL/route/v1/...` and calls them directly from the device — the precise exposure web *removed* in §242, where a user's pin coordinates (routinely their home) left the client with no server boundary. Pointing `MOBILE_OSRM_URL` at a public OSRM would re-open it on mobile. The proxy deliberately mirrors OSRM's own GET path shape, so mobile's URL building needs **no change** — set `MOBILE_OSRM_URL=https://threkir.com/api/routes/osrm` and send the Supabase JWT in the `x-supabase-authorization` header on the two fetch helpers — the standard `Authorization` header is owned by CloudFront's OAC sigv4 signing and never reaches the Lambda (`apps/web/lambda/osrm-proxy/src/index.ts`); the proxy 401s without a signed-in user.

  Until (1) and (2) are decided and provisioned, mobile route-building cannot ship past Internal, and the mobile code change in (3) is not worth landing (it would only move the failure). Operator-gated: needs `flyctl` + Fly/AWS credentials.
- [ ] **Graph-cycle loop generator (v3) — prod deploy only.** The Go graph sidecar (`apps/graph_cycle/`) + its integration as the first link in the generator chain (`apps/web/src/lib/routes/generate/graph_cycle.ts`) are shipped and gated on `GRAPH_CYCLE_URL`/`GRAPH_CYCLE_API_KEY` (falls back to `round_trip` then polygon). Operator: `flyctl deploy` the service per its `fly.toml`/`deployment.md`, then set `GRAPH_CYCLE_URL` + `GRAPH_CYCLE_API_KEY` in the web env. No further code required. Design in [graph_cycle_loop_generation.md](../features/graph_cycle_loop_generation.md).
- [ ] **Protomaps self-hosted tiles** — all 4 items from `roadmap.md` "Future — Protomaps self-hosted tiles".
- [ ] **Auth email — localized templates (Send Email Hook).** The signup/reset redirect fix + custom-SMTP sender are done (project custom SMTP → Resend fixes the `noreply@threkir.com` From). The `auth-email` function's six-locale templates are **not** live: prod uses GoTrue's built-in **English-only** templates until the send-email hook is enabled. Operator: deploy `auth-email` to prod, `supabase secrets set` its `SEND_EMAIL_HOOK_SECRET` + Resend `SMTP_*`, then enable the hook (Dashboard → Auth → Hooks → Send Email) — in that order (an enabled hook pointed at an absent function 404s all auth mail). Also set the hosted **Site URL** = `https://threkir.com` + add `/auth/callback`, `/auth/reset`, `com.threkir.app://login-callback` to the Redirect-URLs allow-list. Recipe: [email.md § Production ops 2d](../features/email.md).

## Blocked on external credentials / accounts

- [ ] **Push notifications (FCM + APNs + web Push)** — operator: create a Firebase project, drop `google-services.json` (Android) / `GoogleService-Info.plist` (iOS), enable an APNs auth key + upload to Firebase, generate `VAPID_PRIVATE_KEY` for web. Then add `firebase_messaging`, register tokens to `user_devices.push_token`, write the workout-reminder + kudos-receive handlers, and wire `apps/web/src/lib/util/push.ts`. (The server-side **web-push** leg already ships — see archive; this is the native FCM/APNs leg + the operator credentials.)
- [ ] **Garmin Connect** — blocked on the multi-day Garmin Developer Program application + OAuth client provisioning. Then follow the Strava pattern: a `garmin.dart` helper + a `garmin-import` Edge Function + a Settings tile wired to OAuth. (Distinct from the on-watch Connect IQ data field at `apps/watch_garmin/`, which needs no Garmin approval — see [decisions.md § 107](../architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app).)
- [ ] **RunSignUp race-results** — needs a runsignup.com API key (free for non-commercial use). Then follow the parkrun pattern: a `runsignup-import` Edge Function + a Settings tile that ingests into `runs.metadata.event` / `position`.
- [ ] **iOS verification** — Mac-only. The byte-identical Dart codebase already supports every Android feature ([decisions §39](../architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)); `parity.md` cells stay ✗/Partial *by design* until simulator/device-verified. Gates: `Runner.entitlements` (HealthKit + Sign-in-with-Apple), `pod install`, the Apple Developer Sign-in-with-Apple Services ID + APNs setup. Info.plist is already complete.
- [ ] **Apple Watch** — Xcode / watchOS device required: route-nav visuals, ultra-length stress test, live race participant, complication target (Widget Extension), activity types, lap markers, hold-to-stop, TTS cues, pedometer, GPS self-heal, indoor mode, route picker, BLE pairing UI — each wired in Xcode + verified on a simulator or paired device.

## Mobile

- [x] **Sign-up takes the password in a single field, so a typo locks the account out permanently.** Closed 2026-07-16 alongside the web fix: `auth_gates.dart` (the `checkPasswordPair` Dart twin, 17 mirror tests) + a confirm field on `sign_up_screen.dart` checked before `signUp`, ARB keys across all seven catalogues, four widget tests, mirrored to the iOS twin. Sign-up is the only password-minting surface on mobile, so the class is closed there. See [web_app_auth.md § Password confirmation](../features/web_app_auth.md#password-confirmation).
- [x] **Change password now has a current-password step-up (the mobile half of issue #381).** Landed 2026-07-20 in the same PR as the web fix: `settings_account_screen.dart`'s `_changePassword` dialog carries a current-password field and drives the pure `password_change.dart` twin of `lib/core/password_change.ts` (now a parity pair — `checkPasswordPair`, then `ApiClient.verifyCurrentPassword` over `signInWithPassword`, fail-closed, before `updatePassword`), plus an "email me a reset link" fallback for OAuth-only accounts (lands on web `/auth/reset`). ARB keys across all catalogues, unit + widget tests, and the byte-identical iOS mirror shipped alongside. See [decisions §278](../architecture/decisions.md).
- [x] **Undo has no mobile equivalent** — closed in round 13 (decisions § 523). `apps/mobile_android/lib/undo_queue.dart` is the Dart twin of web `core/undo_queue.ts` (a new parity pair, 14 mirror tests each); `widgets/undo_bar.dart` hosts the offer in a **root `Overlay` entry** rather than the `SnackBar` this entry originally proposed — a snack bar under a modal barrier is dropped from the semantics tree entirely, and `showSnackBar` was already banned in `lib/screens`/`lib/widgets` by an architecture guard. All seven of web's adopting deletes adopted, `undo_window_s` is read AND editable on the phone, and the deferred-commit contract is guarded per call site.
- [x] **Undo offered on every eligible web surface** — round 12 closed the four the U8 sweep enumerated ([decisions § 516](../architecture/decisions.md)): the **notification** dismiss (single row and a collapsed group — one intent, one undo slot, one batched delete), the **route review** delete (issue #664), the **route marker** delete, and the **gear wear-log** delete, which was the one blocked on design. That block is resolved rather than routed around: `Modal.svelte`'s Tab ring now admits a designated `[data-modal-trap-include]` host, so the bar is keyboard-reachable inside a dialog, guarded by `src/lib/undo_modal_trap_guard.test.ts` + a keyboard-only leg in `tests-e2e/settings/gear.spec.ts`. Everything still destructive keeps its confirm on purpose — see [conventions.md § Destructive actions](../architecture/conventions.md).
- [ ] **Pro native RevenueCat purchase sheet + native donate** — scaffolding shipped (`revenuecat.dart`); the live sheet needs a RevenueCat project + a `pro_monthly` package + `REVENUECAT_API_KEY_ANDROID` / `_IOS` provisioned. Until then the Subscribe tile falls through to the web URL. (The store-localised Pro price is already wired via `getOfferings()`; it just needs the RC project provisioned for the localised amount to appear.)
- [ ] **Health Connect import brings tracks (garmin/android, mobile + device)** — `health_connect_importer.dart` hard-codes `track: []`, so every HC-imported run is trackless/lapless/cadenceless. Reading the HC ExerciseRoute + sample series into a track needs the HC route API + on-device testing.
- [ ] **Background sync doesn't execute on an iOS device (BGAppRefreshTask vs `fetch`)** — `background_sync.dart`'s `registerPeriodicTask` maps to a `BGAppRefreshTaskRequest` on iOS, which requires the `fetch` `UIBackgroundMode`; Info.plist only declares `processing`. `AppDelegate.swift` registers the identifier so launch no longer crashes, but the app-refresh submit is rejected at runtime so background sync never runs in the background. Fix: add `fetch` to `UIBackgroundModes` and keep app-refresh, OR switch the Dart side to a `BGProcessingTask`. Needs on-device testing. iOS-only — Android uses `WorkManager` and is unaffected. See `apps/mobile_ios/CLAUDE.md § Catch-up status`.
- [ ] **Retire the vestigial `onStartRun` route-carrying callback plumbing** — since [decisions §298](../architecture/decisions.md#298-route-sharing-gets-a-mobile-share-link-starting-a-public-route-you-dont-own-is-a-first-class-action-and-both-ride-a-global-start-run-handoff) the route-detail Start FAB hands off through the global `pendingStartRunWithRoute` notifier and no longer pops a route back, so `routes_screen` / `explore_routes` / `fitness_hub` / `home_screen`'s `onStartRun` (`void Function(cm.Route)`) is never invoked with a non-null route (its `if (picked != null)` guards no-op). Harmless but dead. Cleanup = remove the field + its threading through those four screens + update the widget tests that construct them; low-risk but a 4-file + tests cascade, deferred so it doesn't ride in with the feature. (Distinct from `dashboard_screen`'s `VoidCallback onStartRun`, the idle plain-run button — that one stays.)
- [ ] **Course-marker drag-to-move on mobile** (needs device) — **snap-on-tap-placement SHIPPED 2026-07-02**: `route_markers_panel.dart` gained a default-on "Snap to route line" toggle that projects the tapped point onto the route polyline via `snapToPolyline` before placing (render-only; `position_m` still server-derived), mirroring web's `RouteMarkerEditor`, twin-mirrored to iOS, pinned by two widget tests. **Remaining:** the draggable-symbol affordance on `LiveRunMap` (maplibre-flutter `SymbolManager` drag) — needs on-device verification, deferred. See [route_markers.md § Surfaces](../features/route_markers.md#surfaces).
- [ ] **`activity_type` has no shared localized vocabulary, and the coach surface renders raw English.** `coaching_athlete_screen.dart`'s `_activityLabel` capitalises `runs.activity_type` by hand — round 14 localized its sibling `_workoutLabel` through the existing `workoutKindLabel` but could not do the same here, because no vocabulary covers the column. `ActivityType` is `run | walk | hike | cycle | stroller` (`types.ts`, CHECK in `20261207_001`), and the app carries **two** partial vocabularies, neither complete: `settings_preferences_screen._activityTypeLabel` has 4 (`prefsActivity*`, no `stroller`, falls through to a hand-rolled title-caser) and `feed_screen._activityLabel` has 5 but its fifth is `lift` and its fallback is "All". The durable fix is one `activityTypeLabel(l10n, raw)` beside `workoutKindLabel` in `training_labels.dart` (or its own `activity_labels.dart`) covering all five, a `stroller` key added to all 7 ARBs, and the three call sites migrated — a consolidation, not a per-site patch, which is why it was not bolted onto round 14.
- [ ] **Nutrition targets are not a peer of the mobile Nutrition surface** — web closed issue #666 M1's structural half on 2026-08-05 with `/nutrition/targets` (derivation + the two non-sensitive levers at its own URL, ungated from the `/nutrition` header; height/weight/DOB/sex stay in the Art 9 consent-gated Settings editor). On mobile, `nutrition_screen.dart` reaches `SettingsBodyMetricsScreen` from its **empty state only** ([decisions § 490](../architecture/decisions.md)) — once targets exist there is no route to the number the rings are measured against, and no derivation view exists on either twin. The mobile shape is a peer entry beside the rings card (or a row on the § 488 peer strip if Nutrition gains one), pushing a new `NutritionTargetsScreen` that composes the **existing** `nutrition_targets.dart` exports — the Dart twin already has every constant and `mifflinStJeorBmr`, so this needs no new pure logic and no parity-pair change. Web is canonical per § 24, so this is a follow-up, not drift to close first.

## Watch (Wear OS) — sized features awaiting hardware + a product green-light

Most need the Wear build toolchain plus on-watch verification (Galaxy Watch / Pixel Watch) — the recording stack isn't runtime-testable without a device.

- [x] **Honour the mi distance preference on the watch** — `preferredUnit` added to `UniversalSettings` (parsed from `prefs.preferred_unit`, validated against `{km, mi}`) and threaded onto `RunViewModel.UiState` as a `DistanceUnit` (same path as `bodyWeightKg`). `recording/UnitFormat.kt` gained `DistanceUnit` + `formatDistance` + `paceSecPerUnit`; `distance_mi` / `distance_mi_to_go` / `pace_per_mi` added to `values/strings.xml` + all five `values-*`. Applied at the running screen (distance + pace + ambient), the route "to go" badge, the route picker, the PostRun summary, and the active-run tile (unit carried on `RecordingRepository.Metrics`, set at `startRecording` via `EXTRA_PREFERRED_UNIT`). Pure parse/format pinned in `UnitFormatTest` + `ActiveRunTileFormattersTest` + `UniversalSettingsTest`. **TTS closed 2026-08-03** (issue #664, [decisions.md § 467](../architecture/decisions.md)): `UnitFormat.kt` gained `splitIntervalMetres` / `completedSplits` so the cue *fires* once per mile for a mi-mode runner rather than every kilometre, and every spoken resource split into a `_km` / `_mi` pair across all six locales with the pace scaled through `paceSecPerUnit`. Pinned in `UnitFormatTest` / `TtsPhrasesTest` plus a `TtsSplitUnitWiringTest` source guard (the announcer's resource lookup needs Robolectric, which this module doesn't carry). **Remaining:** the on-face visual flip and the audible read-out both need a device check.
- [ ] **BLE chest-strap HR paired directly to the watch** (~1-1.5 wk + device) — today watch HR is optical (Health Services `MeasureClient`) only. A strap paired to the *watch* means an on-watch Wear OS BLE GATT client: scan/pair UI, HR Service (`0x180D`)/HR Measurement (`0x2A37`) subscription, `BLUETOOTH_SCAN`+`BLUETOOTH_CONNECT` perms, source-preference override into `metadata.avg_bpm`. Reconnect/dropout on the wrist is the fiddly part. Minority feature; needs hardware to validate.
- [ ] **Real body weight → calorie estimate** (~2-4 d + device) — `recording/RunCalories.kt` defaults to 70 kg when `body_weight_kg` is unset. Pipe the actual weight in. Source options: (a) Samsung Health BIA (most accurate, heaviest — Samsung SDK/partner approval); (b) Health Services/Health Connect `WeightRecord` (vendor-neutral, lighter); (c) the existing universal-setting sync from web/mobile (cheapest, manual). Watch still won't apply the female calibration (reads `user_settings.prefs` only). Needs a device to confirm the read path returns a value.
- [ ] **Watch-face complication** (~1-1.5 wk + device) — only an active-run *tile* ships today; a true watch-face complication is unbuilt. Needs a `ComplicationDataSourceService` (`wear-watchface-complications-data-source`), `SHORT_TEXT`/`RANGED_VALUE`/`MONOCHROMATIC_IMAGE` types, a tap `PendingIntent` into `MainActivity`, the same `requestUpdate`-on-stage-transition wiring the tile uses, + preview/picker label. Pure formatters unit-testable; binding + render need a watch face that hosts the slot.

## Internationalisation

RTL *layout* is complete web-wide; web + mobile string extraction is complete (~2682 web keys ×6 locales; the mobile ARB pass is done). Remaining:

- [ ] **Native review of machine-extracted translations** — the de/es/fr/ja/pt-BR strings (web catalogue + mobile ARB + the nutrition/consent copy) are best-effort machine output. Agents flagged fitness-domain tooltips (CTL/ATL/TSB/VO₂max) and a few register / article-agreement / fragment-split spots. Wants a native-speaker pass before advertising full localisation.
- [ ] **`app_pt.arb` is not reachable at runtime, so its European-Portuguese content ships to nobody — decide whether pt-PT is a locale.** Measured on `main` (2026-08-05): `locale_support.dart`'s `supportedLocales` lists only `Locale('pt','BR')` for Portuguese and `_baseToLocale` maps `'pt'` → `Locale('pt','BR')`, so `negotiateLocale` returns `pt_BR` for a `pt-PT` device, a bare `pt` device, **and** a stored `pt` preference. `main.dart` passes that list to `MaterialApp`, not gen-l10n's (which does contain `pt`). `app_pt.arb` exists only because gen-l10n requires a base-language catalogue beside `app_pt_BR.arb` ([decisions § 113](../architecture/decisions.md#113-mobile-i18n-uses-flutter-gen-l10n--arb-with-committed-non-synthetic-output-and-a-per-device-locale)) — and **3,251 of its 3,477 keys are byte-identical to `app_pt_BR`**, i.e. it began as a copy. Successive rounds have Europeanised 226 of them (including the whole `profileNotif*` block, round 14), which is correct content going nowhere. Two honest ends, both decisions rather than translation work: (a) **ship pt-PT** — add `Locale('pt')` to `supportedLocales`, map `pt`/`pt-pt` to it, add the picker endonym, and finish Europeanising the remaining ~3,251 keys (wants the native review above); or (b) **admit it is a fallback** — keep it a mechanical copy of `app_pt_BR` and add a guard that the two stay identical, making every partial Europeanisation drift. Doing neither leaves a third catalogue nobody reads and nobody can trust.
- [ ] **Supabase auth email templates (SRV-1)** — GoTrue serves one template set per project with no per-recipient locale, so localising auth emails is platform-limited, not a quick edit.
- [ ] **RTL on mobile** — `EdgeInsetsDirectional`/`AlignmentDirectional` sweep, deferred until an RTL locale catalogue actually ships. (Web RTL is done; the legal pages stay English-by-design pending counsel.)

## Email / lifecycle

The notification-email, welcome, Pro-receipt/dunning, and server-side web-push legs all ship (see archive). Remaining:

- [ ] **Native push delivery (FCM/APNs leg, ~1 wk + ops)** — native push to a locked phone. Same `notifications` source-of-truth + sibling-consumer pattern the web-push leg demonstrates; an FCM/APNs sender is another sibling. Blocked on operator-supplied Firebase/APNs credentials + mobile client token registration (no `firebase_messaging` wiring exists). Also unblocks safety-contact finish alerts to a locked phone.
- [x] **Account-deletion receipt** — SHIPPED 2026-06-20 (migration `20270217_001`, `account_deleted` template). Built as enqueue-with-inline-address + a non-cascading send-once record (not a second SMTP transport in the EF): `delete-account` captures `user.email` + locale before the cascade, enqueues a `lifecycle_email` job carrying `{email, locale}` and **no `user_id`** AFTER `admin.deleteUser` succeeds (so the `payload->>user_id` drain leaves it untouched), and the worker dedups on a hash of the address via the non-cascading `account_deletion_receipts` table. GDPR Art 17 confirmation mail — no per-feature compliance gate; goes live with the shared `SMTP_HOST` worker gate (see `docs/features/email.md` § Production ops) and a CISO eyeball as a pre-prod deploy check, no new credential. `docs/features/email.md`, `decisions.md § 121`.
- [ ] **Security emails (password-changed, new-device sign-in)** — blocked on absent infrastructure: no GoTrue auth hooks configured and no sign-in/device tracking (`device_tokens` has no write path). Needs a password-change auth hook + a device/session table with new-device detection. `decisions.md § 121`.
- [x] **Weekly digest + lifecycle drip (engagement email)** — BUILT (digest foundation `20270108_001` + scheduler `20270220_001`; drip `20270223_001` + first-week template `20270331_001`; decisions §174 + §177). Shipped as dedicated `weekly_digest` / `lifecycle_drip` job kinds (not extra `lifecycle_email` templates — §177 records why): per-stream opt-IN prefs (`email_weekly_digest`, `email_lifecycle_drip`, both default off, toggles on web + mobile Preferences), stream-aware RFC 8058 one-click unsubscribe (`/unsubscribe/{weekly-digest,lifecycle-drip}` off one HMAC secret), the `email_suppressions` hard-block + bounce/complaint webhook (`POST /v1/email/bounce`), four localized drip templates (`drip_onboarding`, `drip_first_week`, `drip_reengagement`, `drip_streak`) with cohort selection in SQL (`enqueue_lifecycle_drip()` daily pg_cron). **Send is the fail-closed gate, not the code**: nothing mails until an operator provisions SMTP + the unsub/bounce secrets AND the CISO/counsel sign-off lands (bulk mail under CAN-SPAM + GDPR/ePrivacy) — pre-deploy checklist in `docs/features/email.md § Production ops` items 4-5.
- [ ] **Data-export-ready email** — NOT planned: the export endpoint is synchronous and returns a 10-minute signed URL inline, so an async "your export is ready" email would arrive stale. Revisit only if export moves to an async/job model.

## Feature-scale / product-gated

- [ ] **In-app "Send a route to a follower" (targeted DM send)** — the link-based send shipped ([decisions §298](../architecture/decisions.md#298-route-sharing-gets-a-mobile-share-link-starting-a-public-route-you-dont-own-is-a-first-class-action-and-both-ride-a-global-start-run-handoff)): mobile "Share link" → OS share sheet reaches any follower. The *in-app* targeted version (pick a follower, route lands in your DM thread without leaving the app) is specced web-first on the existing `direct_messages` rail — v1 sends the share link as a DM body (no schema change), v2 adds a typed route attachment that renders as a card. Full spec: [route_direct_share.md](../features/route_direct_share.md). Web-first per §24; the mobile leg is additionally gated on a mobile `/messages` twin existing.
- [ ] **Strava community segment import (~2-3 wk)** — Strava's segment API requires per-segment OAuth scopes we don't request, and segment-leaderboard data has Strava ToS redistribution limits. Needs a legal + API-scope decision before building.
- [ ] **Family / household Pro tier (~1 wk + pricing decision)** — a household plan (shared subscription across linked accounts) is a pricing/product decision (RevenueCat entitlement model + a household link table), not a code-only change.
- [ ] **Segment-KOM "crowns" in the recap (deferred)** — `segment_efforts` has no stored rank, so a per-segment global-min aggregation across all users would be needed — heavier than a recap card warrants. Personal records stand in as the achievement metric for now.
- [ ] **Auto-follow on club join — product decision (decided: NOT a silent fan-out)** — `join_club_by_token` deliberately does not create `user_follows` edges; club invite tokens are generic so there's no specific person to follow, and auto-following every member is presumptuous + a consent concern. The right shape, if wanted, is an opt-in "Follow members" suggestion list on the club page — tracked here so it isn't re-raised as a silent trigger.
- [ ] **Consent-flow consistency for health-data fields (legal-adjacent)** — onboarding still writes the bare `date_of_birth` column unconditionally (minor-exclusion) while gating the prefs-bag mirror + gender + consent timestamp on the Art 9 checkbox. `/settings/account` and `/settings/preferences` are aligned; the remaining inconsistency is onboarding's unconditional-DOB write. Decide whether minor-exclusion DOB capture counts as implicit consent or needs the explicit toggle — a legal-flow decision, not bolted on without counsel input.

## Compliance — DSAR export coverage (GDPR Art 20)

- [x] **DSAR export omits four personal-data tables — and the guard that should catch this is blind to them.** (Closed 2026-06-20.) `session_plans` (`author_id`), `event_orders` (`buyer_user_id`/`host_user_id`), `route_photos` (`owner_id`), and `event_pricing` (host data) were missing from **both** export paths — the Go worker `exportPersonalDataSpecs` (`apps/job_worker/internal/supabase.go`) and the `export-data` EF `buildBackupSpecs` (`apps/backend/supabase/functions/export-data/backup_spec.ts`). Erasure was always fine (all four cascade-delete from `auth.users`, so Art 17 held); the gap was the Art 20 **export**. **Durable fix shipped:** the export-completeness guard (`apps/job_worker/internal/personal_data_export_guard_test.go`) no longer keys on a literal `user_id` column — it now flags any table with *any* owner-style FK to `auth.users` (`user_id` / `author_id` / `owner_id` / `buyer_user_id` / `host_user_id` / `contact_user_id`) that isn't in the export specs or the reasoned-exclusion list (the `user_id` form by name; the other owner names only when the column declaration carries an inline `references auth.users`, so a non-user `owner_id` can't false-positive). All four tables are wired into both export paths (`event_orders` × 2 legs, `event_pricing` via embedded `events!inner` host-id join), the Deno export test asserts each, and widening the guard surfaced five more pre-existing plain-`user_id` gaps now wired in too (`achievements`, `challenge_participants`, `challenge_badges`, `public_recaps`, `route_conditions`). Documented in [`docs/compliance/data-subject-rights.md`](../compliance/data-subject-rights.md).

From `roadmap.md § Competitor-parity backlog`; sizes are rough estimates carried from the roadmap table:

- [ ] **Heatmap / popular-route discovery** (#4, ~2 wk) — materialised tile table or a Go tile service; anonymised aggregation. Open decision: opt-in vs opt-out privacy default.
- [ ] **Trail / offline navigation** (#5, ~3-4 wk) — turn-by-turn on a loaded route + offline tile packs + condition reports. Needs a routing-engine choice (Valhalla vs GraphHopper).
- [ ] **Audio-coached runs** (#9, ~3-4 wk) — pre-recorded workout library + TTS-narrated pace cues. Audio CDN strategy + voice-talent budget needed.
- [ ] **Race calendar + results import** (#10, ~2 wk) — event discovery + entry links + auto-match results on record. Gated on the RunSignUp key above.
- [ ] **Advanced analytics polish** (#11, ~2 wk) — no new tables; richer dashboard breakdowns + race-time predictor over what VDOT / training-load already ship. **Race-time predictor shipped** (2026-06-20): the multi-distance `race_predictor` TS↔Dart parity pair (`predictRaceLadder` — recency-weighted Riegel anchor, per-rung confidence reusing `predictionConfidence`) + the `RacePredictorCard` on web `/dashboard` AND the mobile `widgets/race_predictor_card.dart` on the Home dashboard (5K/10K/Half/Marathon ladder, self-hiding on the qualifying-run gate, both platforms). **Consistency card shipped** (2026-07-11): the web-only `training/consistency.ts` pure helper (`computeConsistency` — active weeks out of the last 12, current + best active-week streak with an in-progress-week grace, and a steady/variable weekly-volume CoV) + the self-hiding `ConsistencyCard` on web `/dashboard` (< 2 active weeks → hidden), scoped to `filteredRuns` so the source/activity-type filter carries through. 16 unit tests + a Playwright surface test. Web-only (no Dart twin, deliberately off the parity list). Remaining ideas: easy/hard intensity distribution, week/month trend deltas.
- [x] **Dashboard best-streak sub-label is windowed, not all-time.** Closed 2026-08-03 ([decisions § 471](../architecture/decisions.md)) — the last surviving half of the #332 follow-up (§ 470 closed the PeriodSummary drilldown). The `run_streaks_for_user(p_tz, p_source)` gaps-and-islands aggregate (migration `20270501_001`) serves `(current, best)` in one row on the paint path, bucketed by the runner's **local** day (client passes its IANA zone, matching `computeRunStreaks` rather than the awarder's UTC shortcut) and taking the dashboard's source filter so the sub-label's all-time claim stays true under a filter. Web `fetchRunStreaks` returns null — never zeros — on failure, and `streak_card.ts#streakCardState` then suppresses the numeric best claim instead of presenting the windowed number as all-time. 12 pgtap tests (pre-window island, 23:30-local/UTC-date edge, grace day, source filter, owner scoping) + 8 helper unit tests + source guards. **Mobile closed 2026-08-03 ([decisions § 475](../architecture/decisions.md))** — the § 471 note's open store-population question resolved the other way: the dashboard card reads the SAME RPC (`ApiClient.fetchRunStreaks`, device IANA zone via `flutter_timezone`, explicit `'UTC'` degrade) through the new `streak_card.ts` ↔ `streak_card.dart` parity pair, with a mobile-only pointwise-max fold so an unsynced local run is never walked back; no full-history backfill onto the device.
- [ ] **Premium billing extensions** (#12, ~1-2 wk) — Stripe Checkout + customer portal + paywall enforcement across web + mobile.
- [ ] **Treadmill BLE FTMS — live run-screen wiring** (#13, ~3-5 d, mobile-only) — the parser + model + pairing tile + `RunRecorder.setTreadmillSample` recorder seam all ship and are tested; remaining is the live run-screen wiring (a mode toggle that subscribes the belt stream and calls `setTreadmillSample` during recording, threading a shared `BleTreadmill` through `RunApp` → `run_screen`). Pure UI wiring on a proven seam; needs hardware-in-the-loop testing. Spec in `integrations.md § Treadmills (BLE FTMS)`.
- [ ] **Route-design preferences (scenic / elevation-aware / cul-de-sac half)** — the avoid-highways / prefer-residential half shipped (a "Quiet roads" toggle on `/routes/new` → GraphHopper `custom_model`). Remaining (~2-3 d, needs v3): scenic/park-adjacency, elevation-aware, cul-de-sac mode, and the multi-objective post-hoc ranking — the half that needs the graph search where we own the edges + scoring. Web-only (route generation is web-canonical). Design in [graph_cycle_loop_generation.md § Extension](../features/graph_cycle_loop_generation.md).

- [x] **Mobile mirror: session-derived Log-as-workout prefill on event detail** — done 2026-07-11. `event_detail_screen._logAsWorkout` now loads the attached session plan (`_maybeLoadSessionPlan`, best-effort L4) when a `class` event carries a `session_plan_id`, expands it via `expandSessionSteps`, and passes `seedSets` + `seedTitle` to `showGymComposeSheet` through the pure `logWorkoutSeed` helper (mirrors web's `logWorkoutPrefill`: discipline/plan title → flat title fallback, one seeded set per expanded step). Added `session_plan_id` to `_eventSelectCols` and carried `duration_s` through the composer's `seedSets` map so timed poses survive. Twin-mirrored; unit tests in `event_detail_screen_test.dart`.

- [x] **Mobile mirror: honour `show_calories` on run detail** — done 2026-07-11. `run_detail_screen`'s calorie tile now gates on `SettingsSyncService.service.effective<bool>('show_calories') != false` (default on), and Settings → Preferences → Units & Display carries a "Show calorie estimates" `SwitchListTile` writing the universal bag via `_putUniversal`. `SettingsKeys.showCalories` registered; ARB keys `prefsShowCalories`/`prefsShowCaloriesHint` in all six locales; widget tests in `run_detail_screen_test.dart` (tile hidden when false / shown by default) + `settings_show_calories_test.dart` (toggle write path); mirrored to the iOS twin.

## Testing gaps

- [ ] **Device-instrumented `integration_test` harness** — none today; would cover tile-cache / foreground-service / background-sync on real Android primitives. New infrastructure.
- [ ] **OSRM smoke test in CI** — blocked on free-runner capacity (OSM PBF extract + osrm-extract memory). Options: a self-hosted runner, or a pre-built OSRM cache in S3 the workflow downloads.
- [ ] **Positive-path Edge Function tests** — the envelope suite covers auth-rejection only; 200-on-valid-HMAC / replay-dedupe / freshness-window tests need real secret values in the CI config.

## Web bundle weight

- [x] **Externalise the RevenueCat web SDK behind hosted checkout** (done 2026-06-20) — `@revenuecat/purchases-js` was a top-level static import in `apps/web/src/lib/billing/revenuecat.ts`, shipping the full SDK (~178 KB gzipped) into the `/settings/upgrade` bundle. The web Pro flow now drives both checkout and management through RevenueCat's **hosted-checkout redirect**: `proCheckoutUrl()` redirects to the Web Paywall Link `https://pay.rev.cat/<token>/<userId>?redirect_url=…`, and `managementUrl()` opens the no-code customer portal — no embedded SDK, no API key in the bundle. The dependency was dropped from `apps/web/package.json` + the root lockfile, removing the ~178 KB from the summed bundle metric (no `purchases-js` import remains in `apps/web/src`). Env config renamed `PUBLIC_REVENUECAT_WEB_API_KEY` → `PUBLIC_REVENUECAT_WEB_CHECKOUT_URL` (+ optional `PUBLIC_REVENUECAT_WEB_PORTAL_URL`), with the production-env guard, CI workflows, and security_guards test updated in lockstep; the fail-closed configured-vs-unconfigured fallback is preserved. Pure URL builder unit-tested (`revenuecat_links.test.ts`, 6 cases); the unconfigured-fallback e2e covers the redirect-fail-closed path. **Mobile parity:** N/A by design — `apps/mobile_android/lib/revenuecat.dart` keeps `purchases_flutter` because iOS Guideline 3.1.1 / Play policy require native IAP for digital goods; the web hosted-redirect is a web-only optimisation, not a parity gap.

## watchOS deferred target

- [x] **CheckpointStore.loadTrackPoints buffers the whole track file at finish** — SHIPPED 2026-08-03 (issue #664, [decisions.md § 467](../architecture/decisions.md)). The read now mirrors the streaming save: `forEachTrackPoint` walks the NDJSON 64 KiB at a time, carries at most one partial line and yields a point at a time, still skipping an undecodable tail. `FinishedRun` stopped carrying `[TrackPoint]` — it holds the file URL + point count — so `writeTrackJSON` streams into a staged file it renames and the DEBUG upload maps that artefact rather than re-encoding; streaming the read alone would have moved the peak, not removed it. **The ~60 MB figure here was an undercount**: recomputed at the 100 h / ~360k-fix target it is ~73 MB *inside `loadTrackPoints` alone* (~27 MB file + ~11.5 MB `Substring` headers + ~17.3 MB records + ~17.3 MB of heap `ts` strings — the 20-byte ISO stamp is past Swift's 15-byte small-string cap, the term the old estimate missed), plus the resident array and its encoding. Pinned by new XCTest cases (chunk-boundary walk, truncated vs whole final line, flush-boundary JSON validity, file lifetime); the Swift is **Mac-CI-compiled only**, and an Instruments trace over a long recording is still a bench item.

## Live-tracking residual (wave-1 follow-ons, 2026-06-13)

The headline live-tracking bugs (staleness honesty, name-leak on the event leaderboard, retention, reconnect JWT, tie-order/cap, in-zone last-seen carve-out) all shipped. Residual scope edges:

- [x] **Label the coarse last-seen ping in the spectator/SAR UI (web + mobile).** Done 2026-06-20. The web `/live/[id]` page + mobile `live_spectator_screen.dart` (+ iOS twin) now read the `coarse` flag on the latest ping and render a distinct marker (web `.runner-dot.coarse` hollow amber ring; mobile `LiveRunMap.coarsePosition` → `_CoarseDot`) plus an "Approximate / last seen near here" badge + sub-line, gated on a live (non-terminal) `coarse=true` fix. i18n added to all six web locales + all mobile ARBs; Playwright (`tests-e2e/live/spectator.spec.ts`) + a Flutter widget test pin the badge. Note: the **event live pages** were NOT in scope after reading the code — they render `race_pings`, which has no `coarse` column (the `20270121_001` carve-out covers `live_run_pings` only). Extending the carve-out to `race_pings` is the separate follow-up below.
- [x] **Extend the privacy-zone last-seen carve-out to `race_pings`.** SHIPPED 2026-07-02 (migration `20270309_001`, [decisions.md § 196](../architecture/decisions.md)). The sibling `race_pings` BEFORE-INSERT trigger now retains an in-zone ping coarsened to a ~2-dp grid + flagged `coarse=true` (at most one per `event_id/instance_start/user_id`) instead of dropping it; only lat/lng are coarsened (distance/elapsed/bpm kept for ranking). The competitive-board-semantics concern resolved in favour of the same last-seen honesty the solo feed provides — the web event live page renders the coarse "last seen near here" chip + hollow-amber marker. Web-only (no mobile event-live spectator reads `race_pings`); pgtap + Playwright pinned.
- [x] **Mirror the next-cut-off "signal lost" vs "still connecting" copy split to mobile.** Done 2026-07-11. `live_spectator_screen.dart`'s `_CutoffCard` now takes the screen's `stale` flag and branches the suppressed (`unknown`) verdict like web `/live/[id]`: a stale fix reads the amber w700 `liveCutoffSignalLost` ("Signal lost — can't project arrival", matching the screen's existing Delayed/amber freshness treatment) while a fresh still-connecting fix keeps the neutral italic `liveCutoffWaitingSignal`. ARB key added to all seven mobile catalogues (six locales + base `pt`); pure UI, no helper change (the `live_freshness` + `live_cutoff_eta` twins already exposed the flag). Both branches pinned in `test/live_spectator_cutoff_test.dart`; mirrored to the iOS twin. See [predictive_live_tracking.md § Design](../features/predictive_live_tracking.md).
- [ ] **Validate the Strava-CSV-UTC + FIT-compressed-timestamp fixes against real files pre-prod.** Both landed (Strava `Activity Date` parsed as UTC; FIT compressed-timestamp records decoded) but only against the documented format + a synthetic fixture. Get a real Strava bulk export + a real older-Garmin/Wahoo compressed-timestamp FIT and confirm the format string(s) + field layout before relying on them in prod (the parse is fail-safe, so the risk is "no improvement", not corruption).

## Pure-logic-helper hunt deferrals (2026-06-14)

Low-reach TS↔Dart twin divergences found by the 2026-06-14 helper hunt; the higher-impact bugs from that round were fixed + pinned. Pick these up the next time the file is touched:

- [x] **`macroBudget` negative-tie rounding diverges TS↔Dart.** `nutrition_budget.ts` uses `Math.round` (rounds negative `.5` toward +∞); the Dart twin uses `.round()` (half away from zero). Latent in production (inputs are exact integers, so `.round()` is a no-op) — only reachable via direct fractional calls. Pick one convention and align both twins. **Done:** the Dart twin now rounds via `_roundHalfUp(value) => (value + 0.5).floor()` (matches JS `Math.round`); negative-half-tie parity test added both sides + mirrored to the iOS twin.
- [x] **`computeSessionAdherence` can report >100% adherence.** `session_steps.ts` (+ `.dart`) computed `completedSteps / totalSteps` without clamping or matching results to steps by `itemId`; a results array longer than the steps array yielded `>1` and still verdicted `'completed'`. Fixed: completed-result counting is keyed to the set of step `itemId`s (extra/duplicate/unmatched results no longer inflate), the count is capped at `totalSteps`, and the fraction is clamped to `[0,1]`. Mirror tests added on both sides (more-results-than-steps → 1.0; unmatched itemIds ignored).
- [x] **`gym_routine.prefillFromRoutine` RPE string diverges for whole-number doubles.** Done 2026-06-20. Web is canonical (`String(s.targetRpe)` → `"8"`); the Dart twin (`apps/mobile_android/lib/gym_routine.dart` + iOS) now formats RPE via a `_rpeString` helper that drops the trailing `.0` on a whole-number double (8.0 → `"8"`) and keeps the decimal on a half-step (7.5 → `"7.5"`), matching JS `String(number)` semantics. The TS file was not touched. Pinned by a mirror test on both sides (`prefillFromRoutine: whole-number RPE drops the trailing .0, half-step keeps it`); test counts stay in lockstep (23 each).

## Pure-logic-helper hunt deferrals (2026-06-15)

Verified-but-deferred findings from the 2026-06-15 five-worker bug hunt (the three clear bugs that round — checkpoint-board tie-break jitter, roadbook equal-clock 0s cutoff, plan-progress zero-distance long run — were fixed + pinned). Both parked on a product call were resolved + shipped 2026-07-02:

- [x] **`gym_adherence` fails a weighted-duration set on an unlogged weight even when the full duration was held.** RESOLVED 2026-07-02 ([decisions.md § 194](../architecture/decisions.md)). Product call: duration is the primary axis while the weight is unrecorded. The weight gate now fails a set only when a weight was actually logged and fell short, or when the set has no duration axis (weight-only, unchanged); a both-axes set with the weight unlogged is graded on duration. Twin-pinned (`gym_adherence.ts` ↔ `.dart`, 20 tests each).
- [x] **`gym_progression` percent_cycle labels a real prescription `'hold'` when there's no prior top weight.** RESOLVED 2026-07-02 ([decisions.md § 195](../architecture/decisions.md)). Product call: added a dedicated `establish_baseline` `ProgressionReason` for the first/bodyweight session (concrete 1RM-percentage weight, no prior top weight) instead of the misleading `'hold'`; the suggested weight is unchanged. Localized in all six web locales + all mobile ARBs, exhaustive `gym_detail_screen` switch extended, twin-pinned (20 tests each).

## Mobile bug hunt deferrals (2026-07-24)

Findings from the 2026-07-24 three-worker mobile hunt that were parked for a
product call, a schema change, or a coordinated web+mobile change. The nine bugs
fixed that round (route-progress floor poisoned by a rejected fix, treadmill
console reset, pace across a pause, silent turn cues on a second run, negative
splits, run-index ordering, DST week boundaries, backup-restore abort,
route-sidecar fail-open) are in git history on the same PR.

**All twelve were resolved on 2026-07-25**, on the same PR, each with the
decision it needed recorded in [decisions.md](../architecture/decisions.md)
§§ 299-305 and a pinning test confirmed to fail against the old behaviour. A
follow-up hunt the same day found that the § 303 route-store half had been
claimed but not shipped, plus seven further defects in the same subsystem; those
are folded into the list below and recorded as §§ 308-313 (and an amendment to
§ 301). Two
carry a judgement the owner may want to revisit rather than a defect: the
hydration ceiling's specific value (§ 300) and the run-store's
re-upload-rather-than-presume-synced asymmetry (§ 299). Kept here rather than
pruned so the reasoning stays next to the finding it answers.

- [x] **`OfflineSyncStore.markSynced` re-reads the live row instead of the pushed snapshot.** RESOLVED 2026-07-25 ([decisions.md § 302](../architecture/decisions.md)). The compare key is **identity**, not `lastModifiedAt`: entries are immutable and every mutation installs a new instance, so `identical` is exact, while a clock comparison would miss two mutations inside one tick. `markSynced` now takes the pushed entry and marks only while it is still resident; the `pendingDelete` branch applies the same test before `dropRow`, so a tombstone raised mid-push is no longer flipped to synced and left with a live server row. `syncWithServer` also gained the drain guard (a second concurrent call returns 0). All eight subclasses inherit both. Three pinning tests, each confirmed failing against the old behaviour.
- [x] **Two `LocalRunStore` / `LocalRouteStore` instances write the same whole-file sidecars from independent snapshots.** RESOLVED 2026-07-25 ([decisions.md § 303](../architecture/decisions.md)). **This entry was wrong when first written and is corrected here: only `LocalRunStore` was changed that day.** The merge and `_withSidecarLock` never reached `local_route_store.dart`, whose three sidecars (`synced_route_ids.json`, `route_owner_tags.json`, `offline_pinned_route_ids.json`) stayed unlocked whole-file replaces even though `background_sync.dart` builds a second `LocalRouteStore` over the same directory and calls `markManyRoutesSynced` + `tagRoutesOwner` from it. Both stores are now covered. Run sidecars: `synced_ids` keeps an unknown id only while its run file exists (the process-independent ghost prune); `pending_remote_deletes` lets additions win and carries removals in a cleared-ledger. Route sidecars: all three resolve a shared id the `pending_remote_deletes` way, because for routes the losing direction is a cross-account transfer (an un-tagged route is drainable by any account on the device) rather than a re-upload — § 299's asymmetry applied to the other store. Pinned by three two-stores-over-one-directory tests per store, each confirmed failing against the whole-file write.
- [x] **`LocalRunStore._persistIndex` is an unlocked whole-file replace, and the cold-load gate only compares the id set.** RESOLVED 2026-07-25 ([decisions.md § 309](../architecture/decisions.md)). Per-id content drift from the background isolate's stale snapshot passed the membership-only gate, loaded verbatim, and was re-persisted from memory forever — so every all-history consumer read a stale distance while run-detail (which reads the file) read the corrected one, and the stale `last_modified_at` let a delta fetch clobber the local row. `_persistIndex` now merges per id under `_withSidecarLock`, newest-wins on `_lastModifiedOf` with ties to this process, pruning by run-file existence rather than against `_summaries`.
- [x] **`LocalRunStore.update()` never persists the unsynced transition and never restores residency.** RESOLVED 2026-07-25 ([decisions.md § 308](../architecture/decisions.md)). `synced_ids.json` outranks the index on cold load (§ 299), so an offline edit was silently re-marked synced on the next launch and could never drain; separately, an edit to a windowed-out run was never inserted into `_runs`, which `unsyncedRuns` reads, so it was invisible to the drain even in-session. Both fixed, plus the same durability hole in `save()`'s re-save case. Run-detail now marks the run synced after a successful `updateRunFields`, or the newly-durable un-sync would schedule a full-track re-upload on every title edit.
- [x] **`LocalCrossingsStore.replaceFromServer` treats a single event+instance fetch as a complete set.** RESOLVED 2026-07-25 ([decisions.md § 310](../architecture/decisions.md)). The method takes the fetch's scope and preserves synced rows outside it, mirroring the gym / food window guard; retention still sweeps the preserved rows so the 90-day Art 9 mirror keeps working for other events.
- [x] **`createBackup` archives only server rows, so an undrained run is silently absent.** RESOLVED 2026-07-25 ([decisions.md § 311](../architecture/decisions.md)). The archive now carries the device's unsynced runs and their in-memory tracks, and the server-first path is skipped while anything is local-only. The offline restore also became genuinely additive (it was overwriting a same-id local run — including replacing a full GPS trace with the empty one a failed track download leaves in the archive). The documented-but-uncalled `iterateAllRuns` was deleted.
- [x] **`clearInProgress` does not await an in-flight `saveInProgress`.** RESOLVED 2026-07-25 ([decisions.md § 312](../architecture/decisions.md)). Reported as a suspected timing window; it reproduced on 32 of 60 iterations, so it is live. The append opens in `writeOnlyAppend` and recreated `in_progress.json` after the delete, offering Resume/Finish for a run already saved — either of which overwrites the completed run's file with the ~10-point partial. `clearInProgress` now drains the in-flight append first.
- [x] **`LocalRunStore` / `LocalRouteStore` / `WatchIngestQueue` never sweep `.tmp` orphans.** RESOLVED 2026-07-25 ([decisions.md § 313](../architecture/decisions.md)). The `OfflineSyncStore` sweep moved into `core_models/atomic_io.dart` next to the writer that creates the orphans, and all four cold-load paths now call it. The one-hour age gate stays — it is what keeps the sweep off a concurrent writer's in-flight temp file.
- [x] **A watch payload with no `id` decodes cleanly but can never upload.** RESOLVED 2026-07-25 ([decisions.md § 301](../architecture/decisions.md), amended). `raw['id'] as String? ?? ''` put a permanent failure on the transient side of § 301's split, so the entry retried on every sign-in forever. A missing or blank id is now a parse failure and lands in the existing quarantine. Neither shipped sender omits `id`, so no live sender changes behaviour. `setLastKnownOwner` also became atomic (a truncated stamp reads as "no owner" and lets the next account adopt the previous user's run), and `watch_ingest_queue.dart` joined the `noBareWriteStores` guard.

### Open follow-up from this round

- [ ] **One shaper for Run → raw `runs` row.** `BackupService.rawRunRowForBackup` duplicates `ApiClient._metadataWithoutPromotedColumns` / `_embeddedBestSeconds` so the archive's local-only rows match what `saveRun` would have written. Extract a single shaper into `core_models` and point both at it — kept out of the § 311 change because `packages/api_client` was outside its scope.
- [x] **`WatchIngestQueue` writes queue files non-atomically and retries an unparseable entry forever.** RESOLVED 2026-07-25 ([decisions.md § 301](../architecture/decisions.md)). `enqueue` now uses `writeStringAtomic`, and `drain` splits the parse class from the upload class: a decode or `runFromWatchPayload` failure quarantines the entry as `<uuid>.json.rejected` (out of the `.json` glob, so no retry loop and no phantom `pendingCount`), while an upload failure still retries. Rejected entries are swept at init past 30 days — renamed rather than deleted so a decoder bug cannot silently destroy a real run. Five new on-disk tests including both failure classes.
- [x] **`clear()` and `rewriteAll()` only delete `*.json`, so a `<id>.json.N.tmp` orphan survives sign-out.** RESOLVED 2026-07-25. `clear()` now deletes EVERY file in the store's directory rather than filtering by name — the store owns the directory and the contract is "nothing of the prior user survives", which a filename filter can only approximate. Orphans are also swept at cold load, behind a one-hour age gate so the sweep can't delete the temp file of a genuinely concurrent writer (the background-sync isolate holds its own instance over the same directory) — that is a safer home for the sweep than `rewriteAll`, which runs while writes are in flight. Guarded by a planted orphan in `offline_store_wipe_test.dart` plus a stale-vs-fresh pair in `local_gym_store_test.dart`.
- [x] **`generateNewIds` is not plumbed into the gym/food restore.** RESOLVED 2026-07-25. The flag now reaches `restoreFromBackup`, which re-mints the record's id before parsing it. Re-keying is generic — every subclass keeps its id at `row['id']` inside the same `{row, sync_state, last_modified_at}` envelope — and a record whose shape exposes no id is **refused with a log rather than queued**, which is the decision the item asked for: a foreign id becomes a `pendingCreate` whose INSERT can never succeed, and the swallowed failure means `hasPending` never clears and every refresh re-runs the drain. Pinned by two backup round-trip tests (a foreign archive lands under fresh ids; the same archive restores twice side by side).
- [x] **`saveInProgress`'s waypoint cursor is read before an `await` and written after.** RESOLVED 2026-07-25. An in-flight guard drops an overlapping call rather than queuing it: the cursor has not advanced, so the skipped waypoints go out with the next tick and nothing is lost. Pinned two ways — overlapping saves append each waypoint exactly once (confirmed failing without the guard), and a dropped save's backlog still reaches disk on the following tick.
- [x] **`gym_adherence` collapses two planned refs for the same exercise onto one logged set.** RESOLVED 2026-07-25 ([decisions.md § 304](../architecture/decisions.md)). Matching moved from the per-block `setIndex` to an explicit `stepIndex` — the ref's ordinal position in the expanded step list — on both twins, both runners, and the persisted `gym_step_results` row (which `gym_programming.md` had always specced as carrying `step_index`; only the implementation omitted it). An ordinal also survives a skipped set, which a consume-in-order match would not. `setIndex` stays on the ref for display. Mirror test each (27 apiece), confirmed failing under the old key.
- [x] **`computeElevationGain` has two different algorithms across the twin, and each suite pins the opposite answer.** RESOLVED 2026-07-25 ([decisions.md § 305](../architecture/decisions.md)). One contract on both platforms: gain over the RAW track, a dropout carries the last reading rather than breaking the chain, and a change counts only once it clears a 3 m hysteresis band. Web's `summarizeRouteFromTrack` no longer grades the 2-D-simplified polyline (a straight road over a summit collapsed to its endpoints and saved 50 m of climb as 0), and the third inline copy in `run_detail_screen` now calls the shared helper. `computeElevationLoss` moved into the same module with the same gate — mobile-only, but it had to move or a flat road would report 0 m of climb beside hundreds of metres of descent. `route_simplify` is now a declared parity pair in `CLAUDE.md` and in `shared-library-syncer`, which is what both doc comments had been claiming without enforcement. **Amended same day:** a fourth ungated copy — the live counter in `run_screen._onSnapshot`, which read ~1,200 m on a flat 10K against run-detail's ~38 m — now feeds the Dart-only `ElevationGainAccumulator`, the streaming form of the same gate that `computeElevationGain` itself is now built on.
- [x] **`mileage_trend` weekly back-fill drifts a week on a DST transition, and anchors on the last bucket *with data*.** RESOLVED 2026-07-25. Both halves. `_mondayOf` and `_previousBucketStart` now step days with the year/month/day constructor (the calendar arithmetic `goals.dart` adopted this round), so a transition week's bars keep their real labels and stop vanishing from the chart. The back-fill window now always ENDS at the bucket containing `now` — the card labels that bucket "this week", so an idle runner used to read an eight-day-old total as the current one. Pinned behaviourally in `mileage_trend_test.dart` (verified failing under `TZ=America/New_York`) and at the source in `architecture_guards_test.dart`, since a DST test cannot fail under CI's UTC.
- [x] **`exercise_history` truncates reps before the Epley estimate.** RESOLVED 2026-07-25. The Dart twin now passes `reps` through unmodified, matching the TS twin and the non-truncation contract `gym_prs` declares (`estimatedOneRepMax` already takes a `num`). A 5.5-rep set at 100 kg scores 118.3 on both sides instead of 116.7 on one. Pinned by a mirror test each (14 apiece).
- [x] **`LocalRunStore._readSyncedIdsSidecar` fails open to "everything unsynced".** RESOLVED 2026-07-25 ([decisions.md § 299](../architecture/decisions.md)). A damaged sidecar is now distinguished from an absent one and resolves through a fixed authority order (sidecar → `index.json`'s cached flag → the legacy per-run flag, the last only when no sidecar ever existed). Deliberately **not** the route store's presumed-synced default: for runs a skipped upload can strand the only copy of a recorded run, so they re-upload instead. Fixing it surfaced the ordering bug underneath — the slow-path repair called `_persistSyncedIds()` before `_summaries` was rebuilt, and that prunes against `_summaries`, so every recovered id was dropped and an empty sidecar written; the legacy migration path had therefore never worked. Pinned across five corruption shapes + the no-index and legacy-migration paths.
- [x] **`hydration`'s exercise add-on has no upper clamp.** RESOLVED 2026-07-25 ([decisions.md § 300](../architecture/decisions.md)). The add-on now stops scaling at 240 exercise minutes (1.92 L), so a 12 h ultra no longer asks for ~8.2 L and a 24 h effort ~14 L. Shipped rather than parked because a ceiling is the conservative direction — the unbounded term extrapolated a daily-baseline heuristic far past its range and printed a hyponatremia risk as a goal, and long-effort fluid is already modelled per leg by `fuel_plan`. **The specific cap is a product call the owner can tune**; a per-athlete sweat rate is the better long-term answer. Twin-pinned (11 tests each).

## Antimeridian planar frames outside the parity pairs (2026-08-03)

[decisions.md § 468](../architecture/decisions.md) routed every planar frame in
the five TS↔Dart route helpers named by issue #664 through the shared
`geo` longitude normalisation. Four more sites still differenced two raw
longitudes to produce a planar value. **ALL FOUR RESOLVED 2026-08-03**
([decisions.md § 473](../architecture/decisions.md)), each as its own
behaviour change with its own pinning tests, and — per § 468's bar — with
no existing pinned value moved:

- [x] **`apps/web/src/lib/routes/routing_quality.ts`** — the perpendicular-offset
  frame now takes its deltas through `lonDeltaDeg`. The raw frame read a
  waypoint just across the line as ~40,000 km off the snapped path (a spurious
  deviation warning on every antimeridian route) and a point ON a crossing
  segment as ~87 m off it. Web-only, as surveyed.
- [x] **`apps/web/src/lib/routes/nearest_track_point.ts`** — the spatial grid
  now unwraps longitudes onto the first coordinate's side. Worse than the
  degenerate-column the survey described: the broken frame also made the
  ring-termination bound unsound, so a tap beside the line could return the
  WRONG vertex (a ~430 m same-side decoy over the true ~53 m neighbour across
  the line), pinned by a deterministic test. Web-only, as surveyed.
- [x] **`apps/web/src/lib/routes/route_loop.ts`** — the synthetic-curve delta is
  folded and every emitted longitude wrapped back into range (the loop branch
  too — a radial ring seeded beside the line used to emit lng > 180). The
  survey's "web-only" was WRONG: `route_loop.dart` declares lockstep in its own
  header and carried the same defect — on mobile a debug build crashed outright
  on latlong2's longitude-range assert. Fixed on web + both mobile twins.
- [x] **`RunTrackPreview.svelte`'s 5 m span** — extracted to `isTrackRenderable`
  in `routes/track_projection.ts` (the Dart twin's name and placement beside
  `projectTrack`) and unwrapped on both platforms alongside the Dart
  `isTrackRenderable`. The survey's "benign" was backwards in the one case the
  gate exists for: ~2 m of stationary jitter AT the line read as a 359.99° span
  and PASSED the gate, drawing exactly the meaningless dot it suppresses.

Everything trigonometric is unaffected and needed no work: `sin`/`cos` are
periodic, so haversine distances and great-circle bearings were always right.

## Bug-hunt 2026-08-10 — verified but deferred

Found during the multi-agent bug hunt that landed the fixes on
`fix/bug-hunt-2026-08-10`. Each was reproduced by running the real module;
they are deferred because the correct fix is a design decision, not a
mechanical change. Do not "fix" any of these without deciding the rule first.

- [ ] **`turn_cues.ts` suppresses real turns on a densely-sampled route.**
  `generateTurnCues`' collapse pass advances the surviving vertex onto each
  merged point (`prev.wp = waypoints[i]`) while leaving `prev.cumM` behind, so
  on a corner sampled finer than `mergeWithinM` (15 m) it walks the kept vertex
  *through* the corner and measures the bearing pair across a chord that cuts
  it off. Measured at 5 m spacing: a 90° corner reports 71.6° and fires 20 m
  early; 45° reports 34.2°; **35° and below produce no cue at all**. At 40 m
  spacing the same bend is announced correctly, so cue behaviour depends on
  source-polyline density — and dense is the normal case (`route_save_polyline`
  persists the full OSRM polyline; GPX imports are 1 Hz; a power-hiked climb is
  ~1 m spacing). The live consumer is mobile: `run_screen.dart` builds
  `TurnCueAnnouncer` from `route.waypoints` and speaks these cues mid-run.
  **Deleting the offending line is NOT sufficient** — verified: it fixes the
  on-grid case but a 35° bend at 5 m spacing is still suppressed and an
  off-grid corner still reports 63.4° for a 90° turn, because the distance-based
  collapse discards the corner vertex itself. The real fix is choosing a
  corner-preserving rule (keep-max-turn within a cluster, or RDP — which
  preserves corners by construction — before cue generation) and porting it to
  all three implementations: `turn_cues.ts`, `turn_cues.dart`,
  `apps/custom_watch/core/src/turn_cues.rs`. Existing suites all sample at
  ~2.2 km spacing, so none of them exercises the merge branch at all.
  Route through `/safe-edit`.

- [ ] **`roadbook.ts` silently degrades `model: 'effort'` to even pace.**
  `walk()` zeroes the grade on any segment under `MIN_SEGMENT_M` (5 m) instead
  of accumulating horizontal distance until the segment clears the threshold —
  which is what the sibling `gradeAdjustedPaceSecPerKm` does with the same
  constant. On a densely-sampled course every segment is sub-5 m, so effort
  allocation becomes byte-identical to `'even'` while `hasElevation` and
  `totalGainM` still report the full climb, so nothing signals the degradation.
  Reported flip on a 4 km leg with a 25 % climb, goal 5400 s: at 20 m spacing
  the cut-off reads `tight` with +1043 s in hand; at 3 m spacing the same gate
  reads `miss` by 300 s. Blast radius includes `fuel_plan.ts` (scales
  carbs/fluid by leg duration) and `live_cutoff_eta.ts`. Twins share it:
  `roadbook.dart`, `apps/custom_watch/core/src/roadbook.rs`. The fix is
  mechanical but changes projected arrival times on every existing roadbook, so
  it wants its own change with the crew-sheet numbers re-verified.

- [ ] **Should `backoff` and `dropset` sets also be excluded from progression
  judging?** The warmup exclusion landed (a ramp-up set no longer reads as a
  failed working set), matching the rule `gym_adherence` already states. But a
  back-off or drop set is deliberately lighter too, so judging "did they hit
  the target reps at the target weight" over them can stall progression the
  same way. `gym_adherence` skips only `warmup`, so the fix followed that
  precedent rather than inventing semantics. Decide the rule once and apply it
  to both.

## Bug-hunt round 2, 2026-08-10 — verified but deferred

Found by the second multi-agent sweep (recording engine, Edge Functions, SQL,
Rust firmware, native watch apps), landed alongside the fixes on
`fix/bug-hunt-2026-08-10-r2`. Each was reproduced against the real module or
the live catalog. Deferred because the fix needs a schema decision, a product
call, or a three-way lockstep port — not because it is uncertain.

### Blocks a whole feature

- [ ] **`event_pricing` upsert can never succeed — 42P10 on every call.**
  The table has no primary key and only two *partial* unique indexes;
  `setEventPricing` upserts with `onConflict: 'event_id,instance_start'` (and
  an `'event_id'` branch). PostgREST emits no index predicate, so Postgres
  cannot infer a partial index as arbiter. Proved with a non-executing
  `EXPLAIN` on both branches: *"there is no unique or exclusion constraint
  matching the ON CONFLICT specification"*. An organiser can therefore never
  attach a price to an event. Note this is the *second* independent blocker on
  the same rail — the checkout response-key mismatch fixed in this branch was
  the first, so paid events stay unreachable until this one lands too. The
  durable fix is one non-partial unique on a normalised instance key replacing
  the two partial indexes, which is a schema change on a table that may hold
  prod rows: route through `/safe-migration` and the `migration_locks.md`
  playbook. No pgtap covers it (`paid_events_test.sql` only does plain
  inserts).

### Wrong data, fix needs a decision

- [ ] **Enabling treadmill mode mid-run zeroes the accumulated distance.**
  `setTreadmillSample` anchors its baseline at the belt's own total, so
  `_reportedDistanceMetres` drops the GPS kilometres the moment the belt
  engages — measured: 60 m of GPS distance becomes 0.0, and a later belt
  reading of 100 m reports 100, not 160. Mid-run is the *only* way to enable
  it (`treadmill_live_mode.md` § open questions), so every activation lands on
  an already-accumulating run, and `lapsToCanonicalJson` clamps the negative
  delta so `metadata.laps` records a silent 0 m lap. **But** `run_recorder_test.dart`'s
  *"clearTreadmillMode reverts to the GPS distance"* pins the same discard in
  the opposite direction (20 m GPS + belt 1000→1200 asserts 200, not 220), so
  the current behaviour is a deliberate "two independent accumulators, show
  the active source", not an oversight. Changing it is a product call about
  what distance means across a source switch — decide the rule for both
  directions at once, then fix and re-pin.

### Three-way lockstep port

- [ ] **`turn_cues` collapse deletes the corner vertex it exists to preserve.**
  Independently confirmed this round in the firmware core, which reproduced it
  numerically: a single 90° left corner at 100 m sampled at 10 m spacing
  announces `SlightLeft at 80.0` *and* `SlightLeft at 100.0` — one turn
  reported twice, both under-classified, the first 20 m early, and "turns
  remaining" reading 2 on a one-corner course. A shallower bend splits into
  two sub-`min_angle` halves and produces no cue at all. This is the round-1
  finding, now with a third confirmed implementation: `turn_cues.ts`,
  `turn_cues.dart`, `apps/custom_watch/core/src/turn_cues.rs`. Deleting the
  offending line remains insufficient (verified in round 1). Fix web-first per
  § 24 as a lockstep triple.

### Firmware (bench-gated trigger, host-tested logic)

- [ ] **Barometric altitude bypasses the `plausible_gps` gate.** Every
  GPS-sourced altitude is narrowed to `-500..9000 m`; the barometric one —
  preferred over GPS at every one of those sites — is gated nowhere. A stuck-
  high I²C burst yields `-8789.741 m` and books 10,389 m of false loss, and the
  sample survives every later profile thinning for the rest of the run. The
  same read also reduces to a ~300,000 hPa sea-level pressure that can raise a
  spurious Storm banner. Trigger is bench-gated (the sim models the driver's
  own belief), so this is *host-tested*, not *bench-verified*, per
  `quality_standards.md`.
- [ ] **`FixGate` has no re-anchor escape.** Above `MAX_SPEED_MPS` (10 m/s)
  displacement outruns the gate's ceiling forever. Measured: course pushed at
  home, 40 km driven at 80 km/h → 0 fixes accepted, 129 rejected, first
  acceptance 36 minutes after arrival — so no off-course latch if the gun goes
  in that window, while the map marker keeps moving from the raw fix. The
  recorder has exactly this escape hatch (`GPS_REANCHOR_AFTER_S`); the gate
  does not.
- [ ] **`backyard` reads any backward clock step as a corral bell**, including
  1 s. The value is an extrapolation off an anchor with no monotonicity check,
  which retreats ~7 times over a 100-hour backyard at 20 ppm. It also clears
  `closed_this_window`, so a return the runner already marked is forgotten and
  the real bell double-counts. Separately, bell-then-press counts one loop
  twice (`on_bell_lap` increments without setting `closed_this_window`);
  press-then-press and press-then-bell are tested, bell-then-press is not.

### Watch apps

- [ ] **Wear `drainQueue` has no re-entrancy guard** and cold start fires two
  (cached-session restore and phone-bridge restore both call it, neither gated
  by backoff at zero failures). Both take the same queue snapshot; `pushRun`
  deletes the track file last, so the loser either re-uploads a multi-MB ultra
  track over LTE or hits `FileNotFoundException` — which `classifyDrainError`
  does not match, so it surfaces a raw ENOENT as a sync failure for a run that
  uploaded fine. Same gap lets two `refreshAccessToken()` calls race a
  rotating refresh token.
- [ ] **Wear `LocalRunStore.save`/`remove` read-modify-write outside the
  DataStore transaction**, so an uploaded run can be resurrected after its
  track file is deleted — every later drain throws ENOENT and the entry never
  clears. Fix is to move the whole mutation inside one `edit` lambda.
- [ ] **iOS pace look-back spans a pause.** `resume()` clears
  `lastLocationForDistance` (the #371 fix) but not `track`, so `updatePace`
  divides a ~200 m look-back by a span containing the entire stop. A 12-minute
  aid stop makes the first ~200 m after resume read on the order of an hour per
  km, published to the complication and to `checkPaceAlert` — the same class of
  bug as the recorder pace-gap fix landed in this branch, on the other platform.
- [ ] **Both watch apps keep the only copy of an unsynced run's GPS track in
  the OS-purgeable cache directory** (Wear `context.cacheDir`, iOS
  `.cachesDirectory`). After a purge the queue still promises "Sync 3 runs"
  while every push throws ENOENT. A not-yet-synced payload is not a cache.
- [ ] **iOS `HKWorkoutSession` failure is swallowed** — `didFailWithError` is
  empty and nothing nils the session, so HR freezes on a plausible number and a
  partial `avg_bpm` is stamped as if it covered the whole run.

### Smaller, still real

- [ ] **A partial Stripe refund is processed as a full refund.**
  `charge.amount` / `amount_refunded` are never read, so a £5 goodwill refund
  on a £50 registration marks the order `refunded` and hands the seat to a
  waitlister; the `partially_refunded` state in lib.ts is never produced.
- [ ] **`events-checkout`'s stable idempotency key + now-derived `expires_at`**
  makes every retry a Stripe `idempotency_error` → 502 for ~24 h. The header
  comment's "a double-click reuses the same session" is inverted.
- [ ] **`export-data` backup truncates every table at PostgREST's 1000-row
  cap** (no Range/limit/paging), and `manifest.json` reports the truncated
  count as the true one — an Art 20 completeness problem. `strava-import`
  already pages correctly; the Go path has the same shape.
- [ ] **`search_public_events` derives `p_byday` in the session timezone**
  while the sibling `p_time` filter correctly uses the event's, so every
  evening event west of UTC is filed under the wrong weekday.
- [ ] **`clubs_member_count_trigger` double-counts** a combined
  `status` + `club_id` UPDATE (two non-exclusive `if` blocks); the sibling
  `routes_run_count_trigger` gets this right with was/is deltas. Note
  `derived_state.md` currently claims the pgtap "guards every branch" — it
  never changes `club_id`, so that claim is false.
- [ ] **`routes_run_count_trigger` skips the decrement when the route's
  visibility changed**, permanently overcounting. This is not the drift
  `derived_state.md` accepts (that covers the *run's* `is_public`), and
  `routes.run_count` is the only cache there with no "Pinned by" line.
- [ ] **Recorder `dispose()` is not terminal** the way `stop()` is, so an
  in-flight async retry callback can re-open the GPS stream after disposal —
  an uncancellable subscription holding the foreground service and GPS radio
  for the process's life, with every fix raising on a closed sink.
- [ ] **`resumeSession` resets the monotonic route floor**, so distance-
  remaining nearly doubles on a loop or out-and-back (measured 1298.5 m where
  a fresh run reads 699.2 m) and never self-corrects.

## Bug-hunt round 3, 2026-08-10 — verified but deferred

Two hunters (Dart data layer, production Lambdas). Fixes landed on
`fix/bug-hunt-2026-08-10-r3`; these are the verified remainder.

**Observability — a real outage currently pages nobody, and geography pages
everyone.** These are the inverse of the share-id bug fixed in this branch,
and worth doing together as one alarm-hygiene pass:

- [ ] `share_session_lookup` / `share_workout_lookup` never inspect `error` at
  all (unlike the other six), and `alarms.tf` registers no metric filter for
  either. A Supabase outage on those two paths is invisible: 404 HTML, no
  Lambda `Errors`, nobody paged.
- [ ] `osrm-proxy` collapses OSRM's own 4xx (`NoSegment` — a waypoint outside
  the loaded extract) into 502, and the Lambda logs `engine_unreachable` for
  every 502. A user dropping a pin outside the extract raises "the OSRM engine
  is unreachable, all users degraded".
- [ ] `generate-route` gives three distinct outcomes status 502 and logs
  `engine_unreachable` for all of them; only one is a real outage. A Pro user
  in a loop-poor neighbourhood pages someone, and a genuine GraphHopper outage
  can't be told apart from geography.
- [ ] `lambda/share-entity` 503s on a percent-malformed path (`/share/club/%zz`
  → `decodeURIComponent` throws `URIError` → outer catch), where every other
  missing entity returns the branded `noindex` 404. Bad client input surfaced
  as a server error, and a retry signal to crawlers.

**Mobile data layer** (all `packages/api_client/lib/src/api_client.dart`):

- [ ] `fetchRunRowsRaw()` has no paging and is consumed as the complete history
  by `backup.dart`, so an account with 1,400 runs archives the newest 1,000 and
  a restore silently loses the rest. Same shape, lower impact, in
  `fetchCheckpointCrossings`, `fetchEventAttendees`, `getRouteReviews`,
  `fetchExerciseCatalogue`.
- [ ] `_hydratePeopleSuggestions` counts public runs via the `runs` base table,
  whose non-owner SELECT policy `20260701_001` dropped — that migration states
  the outcome verbatim ("returns zero rows"). So `people_screen` shows
  "0 public runs" for everyone and `comparePeopleRank`'s primary sort key is a
  constant. Migration `20270118_001_public_run_counts.sql` exists to replace
  this exact query and web already migrated; mobile didn't.
- [ ] Four writes stamp local wall-clock into a `timestamptz` via
  `DateTime.now().toIso8601String()` with no `.toUtc()` (`:3019`, `:3031`,
  `:4216`, `:5658`) — the bug `saveRun`'s own comment documents. A Berlin user
  archiving a coach thread at 23:30 sees it dated the next day.
  `createCustomExercise`'s is worse in kind: it feeds newer-wins sync.

## Segment leaderboards vs the §206 shadow-hidden backstop (2026-08-13)

Raised while fixing the segment-rank divergence ([decisions § 594](../architecture/decisions.md),
migration `20270523_001`) and **closed the same day** by migration
`20270524_001` ([decisions § 596](../architecture/decisions.md)). Both entries
below are fixed; the sweep that closed them turned two reported leaks into
five, so they are kept here as the record of what the class looked like.

- [x] **`segment_leaderboard_tiered` served a moderation-hidden route's board.**
  Its route branch was `r.is_public = true or r.user_id = caller or (r.club_id
  is not null and is_club_member(r.club_id))`, where `private.is_route_visible_to`
  additionally demands `shadow_hidden = false` (§206) — so a caller holding a
  segment id on a hidden route read the whole board, after `20270329_001` had
  closed that route's waypoints, photos, reviews, segments and markers. Now
  delegates to `private.is_route_visible_to(s.route_id, caller)`, resolved once
  before the CTE (every effort on a segment shares one route), which removed
  the `routes` join outright.
- [x] **The boards disclosed a shadow-hidden athlete's name + avatar.** Fixed
  on all three: `segment_leaderboard_tiered`, `global_segment_leaderboard`, and
  `challenge_leaderboard`, which the sweep added. A hidden athlete is
  **redacted, not dropped** — the row and rank stand, `display_name` +
  `avatar_url` go null for everyone but themselves — because dropping the row
  would restate every slower athlete's position and would reopen the § 594
  chip-versus-board divergence.
- [x] **Sweep extras: `is_event_visible` + `claim_event_result`.** Both pasted
  the events club-visibility predicate and never received the shadow gate the
  events policy got in `20270328_001`; `is_event_visible` backs the
  `event_pricing` / `event_checkpoints` / `checkpoint_crossings` SELECT
  policies, so a hidden club's pricing, checkpoints and runner crossing times
  stayed readable. Both now delegate to `is_public_club_by_id`.

Left deliberately untouched, with reasoning in § 596: `coach_roster_summary`
(hiding an athlete from their own consented coach is a narrowing that breaks a
legitimate viewer) and `join_club_by_token` (never consults `is_public`;
whether a hidden club still accepts an invite is a product question about
freezing hidden entities, not a leak).
