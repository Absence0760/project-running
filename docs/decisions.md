# Architecture decisions

Short records of non-obvious choices that the code alone doesn't explain. Reach for this before proposing something that's already been considered and rejected.

This is not a strict ADR template — each entry is a few paragraphs: what we decided, why, and what we traded away. Append new entries to the bottom; don't rewrite history. Date them when you know the date.

---

## 1. Apple Watch is native Swift / SwiftUI; Wear OS is Flutter

**Decided:** Phase 2 planning (Q1 2026 · see [roadmap.md](roadmap.md))

Flutter's watchOS support is a non-starter for a first-class running computer — the build target isn't stable, the widget tree costs are too high for a small screen under a workout, and the native health frameworks (HealthKit, CoreLocation, WKWorkoutSession) are only reachable through channels we'd have to write ourselves. Swift / SwiftUI / WatchKit is the path everyone else takes and it's the only one that lets the watch run standalone GPS sessions without the phone. Flutter on Wear OS is fine — the Compose interop story is good enough, and the Android team already writes Dart, so we reuse core_models and api_client.

**Trade-off:** We now maintain a second codebase (`apps/watch_ios/`) with its own networking, auth, and Supabase client (`SupabaseService.swift`) that doesn't share anything with the Flutter stack. Acceptable because the watch scope is intentionally small (record + navigate) and the watch mostly relays to the phone.

**Don't re-litigate unless:** Flutter ships a production-ready watchOS target, or Wear OS drops Compose interop support.

---

## 2. GPS tracks live in Storage, not in `runs.track` jsonb

**Decided:** April 2026 · migration `20260410_001_runs_to_storage.sql`

A 10 km run has ~3,300 GPS points ≈ 265 KB of jsonb per row. At 10 K active users with 200 runs/year that's ~500 GB of database storage, and every dashboard query scans rows bloated with tracks that the dashboard never needs. Moving to object storage (`runs` bucket, path `{user_id}/{run_id}.json.gz`, gzipped) cut per-row size by ~99 %, eliminated jsonb column bloat on the dashboard query path, and let bulk importers (Strava, Health Connect) stay on the $25/month Supabase Pro tier instead of needing Team.

**Shape:** `runs.track_url` column points at the Storage object. Clients lazy-load the track on demand via `ApiClient.fetchTrack` (Dart) or `fetchTrack` in `apps/web/src/lib/data.ts` (TS). The dashboard list view never touches Storage.

**Trade-off:** One extra round trip per run detail view (download + gunzip + JSON parse). Acceptable — detail views are rare compared to dashboard loads.

**Known rough edges** (tracked in `roadmap.md` § "Known issues — runs storage + bulk import"): public `/share/run/{id}` pages can't read tracks because the bucket is private with owner-only RLS; `LocalRunStore.delete` leaks the Storage object; `saveRun` re-uploads the full track on metadata-only edits.

---

## 3. Custom Dart schema codegen instead of `supadart` / `supabase_codegen`

**Decided:** April 2026 · `scripts/gen_dart_models.dart`

The roadmap's Phase 1 parity-enforcement plan called for evaluating `supadart` or `supabase_codegen` from pub.dev before falling back to a custom script. We skipped the evaluation and went straight to the custom script for two reasons: (1) the schema is tiny (four tables at time of writing), (2) a pub.dev dependency evaluation is an unbounded multi-hour task that was out of proportion to the payoff. A ~260-line parser that handles `create table` / `alter table ... add column` / `alter table ... drop column` is enough for this codebase and adds zero runtime dependencies.

**Trade-off:** The generator's SQL subset is small — it silently ignores indexes, RLS, functions, storage bucket inserts, and `$$...$$` function bodies. Any future migration that relies on an unusual form (a column default calling a subquery, say) will need `gen_dart_models.dart` itself extended before it can be parsed. We get to keep the parser small but we own the failure modes.

**Don't re-litigate unless:** the schema grows past ~15 tables, or a future migration needs a SQL form that would be a non-trivial parser extension.

See [schema_codegen.md](schema_codegen.md) for the full workflow.

---

## 4. Auto-pause is computed from the saved track, not a live event stream

**Decided:** April 2026 · commit `049b5f5 refactor(android): replace live auto-pause with derived moving time`

The original auto-pause implementation ran during recording — the recorder would flip a "paused" bit when speed dropped below a threshold and stop accumulating distance and duration until movement resumed. That created two problems: (a) the live state was a hidden global that every consumer had to stay in sync with, and (b) the paused/unpaused decision couldn't be revised after the fact. Switching to a post-hoc computation — `movingTimeOf(run)` derives moving time by walking the saved track and dropping segments under the speed threshold — makes the recording pipeline simpler and lets us recompute moving time with different thresholds without re-recording.

**Trade-off:** Live "moving pace" during a run is now approximate — it uses the wall-clock elapsed time, not the eventual moving time, because moving time can't be computed until the track exists. This is acceptable because the runner sees "current pace" which is already a rolling window, not moving pace.

**Applies to:** `packages/run_recorder` and `apps/mobile_android`. The other platforms haven't implemented auto-pause yet.

---

## 5. Disk-backed tile cache on Android uses `flutter_map_cache` + `dio_cache_interceptor`, not Hive

**Decided:** April 2026 · commit `5fe9b56 feat(android): disk-backed tile cache and test suite`

A persistent tile cache was a "deferred from Phase 1" item. The first pass was in-memory only via `flutter_map_cache`. The disk-backed upgrade uses `dio_cache_interceptor` (already in the Flutter ecosystem, plays nice with `flutter_map`'s network provider) rather than rolling a Hive or sqflite cache from scratch.

**Trade-off:** We depend on `dio_cache_interceptor`'s cache-expiry model rather than owning it ourselves. Fine for now — if we need custom eviction rules (per-style, per-zoom, per-age), we can add a second layer on top.

---

## 6. `dev` is the working branch; `main` is the PR target

**Decided:** implicit from project setup

All day-to-day work happens on `dev`. PRs merge `dev → main`. Do not push directly to `main`; do not force-push anywhere without being told. Commits on `dev` are fair game; commits on `main` are not amended.

**Why dev?** Lets the user experiment and reset `dev` without disturbing the canonical history on `main`. See the pull-request skill for the PR template.

---

## 7. Two package managers on purpose: Melos for Flutter, npm workspaces for JS

**Decided:** implicit from project setup

Flutter has its own dependency resolution story and Melos is the idiomatic way to run a multi-package Flutter workspace with pubspec overrides. The web app and the Supabase backend scripts are plain Node / TypeScript and live in npm workspaces declared in the root `package.json` (`apps/web`, `apps/backend`). The two worlds don't share dependencies, so there's no reason to try to unify them.

**Gotcha:** `apps/web` was originally bootstrapped with pnpm (per `apps/web/CLAUDE.md` — still references `pnpm i` / `pnpm dev`). In practice we use npm because that's what the root workspace uses. If you see `pnpm` in an older doc and it doesn't match what CI does, CI is correct.

---

## 8. Mobile uses `flutter_map` + MapLibre, not native MapLibre SDKs

**Decided:** implicit from the architecture

The native MapLibre SDKs for iOS (maplibre-native) and Android (maplibre-gl-native) are not well-wrapped for Flutter — the existing Flutter bindings are inconsistent and don't support the full style spec. `flutter_map` + a MapLibre-compatible tile source gives us raster tiles today with a clean Flutter API. The web app uses MapLibre GL JS directly because the JS ecosystem is fully featured there.

**Trade-off:** Mobile tiles are raster, web tiles are vector. Mobile can't do the 3D terrain and smooth styling the web route builder has. Users aren't building routes on mobile in Phase 1 anyway (route builder is web-first), so the gap is mostly invisible.

**Don't re-litigate unless:** Flutter's native MapLibre bindings mature, or the mobile app starts needing vector features (pitch, bearing, dynamic styles).

---

## 9. "Fastest 5k" is a rolling-window scan of the track, not a scaled average

**Decided:** April 2026 · `lib/run_stats.dart#fastestWindowOf` + `dashboard_screen.dart#_best5k`

The original `_best5k` computed `Duration(seconds: (run.duration.inSeconds / run.distanceMetres * 5000).round())` — the overall average pace of any run ≥ 5 km projected onto 5 km. This is fast, deterministic, and completely wrong for any run that isn't paced perfectly evenly: a 10 km in 1:14:34 would display as "Fastest 5k: 37:17" even though the runner never covered 5 km in 37:17 continuously. Users saw a PB they had never actually run.

The fix is `fastestWindowOf(track, 5000)` — a two-pointer sliding-window scan over the waypoints that finds the quickest continuous 5 km anywhere in the track, with linear interpolation at the window boundary so the result isn't quantised to waypoint gaps on sparse tracks. O(n) per run. The dashboard memoises the result in `_best5kCache: Map<String, Duration?>` keyed by run id so a 200-run history only pays the scan cost once per run-store mutation, not once per rebuild.

**Trade-off:** Runs without a GPS track (manual entries, Health Connect summary imports) have no pace data to scan, so they're excluded from "Fastest 5k" entirely — if all your runs lack tracks, the card hides. Better than lying: the old code would silently "project" a 5k PB from a manual run's typed-in distance and duration, which is meaningless.

**Don't re-litigate unless:** a compelling case emerges for showing a PB on manual runs, in which case consider a separate "Best estimated 5k" card rather than mixing the two definitions.

See the regression tests in `apps/mobile_android/test/run_stats_test.dart` — the 37:17 case is checked explicitly.

---

## 10. Clubs MVP: club-owned events, enum recurrence, open-join

**Decided:** April 2026 · `apps/backend/supabase/migrations/20260416_001_clubs_and_events.sql`

Three branch points in the social-layer design, all resolved the simpler way on purpose:

1. **Club-owned events only** (not standalone meetups). Every event has a non-null `club_id`. Standalone "public meetup" events were considered and rejected for v1 — they'd require a second visibility/RLS path and we haven't seen the need. A user who wants a standalone event creates a solo club for it.
2. **Enum recurrence, not RRULE** (Phase 2, not yet shipped). `weekly` / `biweekly` / `monthly` + `byday[]` + `until_date` covers ~95% of running-club schedules ("Sunday long run", "Tuesday speed work") at about 10% of the implementation cost of RFC 5545. Materialised instances on read, not on write, so shifting a recurring event is a single row update.
3. **Open-join in v1**, with request-to-join deferred to Phase 2. A boolean `is_public` gates club visibility and discovery. Private clubs are reachable only by slug + membership — no invite link yet. `join_club` just inserts a `club_members` row; no approval surface.

**Trade-off:** Scope creep is the main risk the simple defaults protect against. If a future user really wants a standalone meetup, we can lift the `club_id` constraint and add a `visibility` column without breaking anything. If someone really needs RFC 5545 recurrence (e.g. "last Tuesday of every month except August"), we grow the parser or swap in an `rrule` column — again, additive.

**Don't re-litigate unless:** (a) users ask for meetups that aren't tied to any club (common enough to justify a second RLS path), or (b) a concrete club's schedule can't be expressed with the enum + `byday` + `until_date` model.

Schema + RLS details in `api_database.md`, surfaces in `clubs.md`, phased rollout in `roadmap.md § Clubs and events`.

---

## 11. Training paces are goal-pace multipliers, not Daniels table lookups

**Decided:** April 2026 · `apps/web/src/lib/training.ts#pacesFromGoalPace`

The full Daniels training-pace model derives pace for each intensity zone from VDOT via the same implicit equation used to *compute* VDOT — there's no closed-form inverse. Real implementations use a published table of ~60 VDOT values × 5 zones. For v1 we anchor the five zones (easy / marathon / tempo / interval / repetition) on the runner's goal pace with fixed multipliers (1.22, 1.06, 0.97, 0.9, 0.85). Across the 3:00-5:00/km goal band these land within ~5 s/km of the Daniels tables, which is well inside the tolerance band a plan runner expects — most runners cannot actually hit a 1-second pace window, and the target bands we emit carry `±5-30s` tolerances anyway.

**Trade-off:** For very fast (≤3:00/km 5K) or very slow (≥7:00/km 5K) runners the multiplier model drifts further from the table — easy pace becomes too slow for elites and too fast for beginners. Neither demographic is our current target user; if we add one, swap `pacesFromGoalPace` for a table lookup without touching any caller.

**Don't re-litigate unless:** user reports show pace targets are systematically off, or we expand into the elite / total-beginner segments.

VDOT is still computed and stored (`training_plans.vdot`) for display — it's a useful fitness number for the runner even if it doesn't drive pace derivation in v1. See `docs/training.md § Pace derivation`.

---

## 12. Coach chat is critique-only, not plan-generation

**Decided:** April 2026 · `apps/web/src/routes/api/coach/+server.ts` system prompt; `CoachChat.svelte`

The LLM coach reviews the user's plan and runs; it does **not** author plans, prescribe medical advice, or give specific nutrition recommendations. The system prompt enumerates this narrowly and the UI framing (placeholder text, onboarding suggestions) reinforces it.

**Why:** LLM-authored training plans look plausible but occasionally prescribe dangerous volume ramps or stacked hard days — users get injured and don't know the model was wrong. The generator (`training.ts`) is the source of truth for structure; the LLM only interprets adherence against it. Medical and nutrition advice carry real liability and are better left to licensed services. Leaving them out of scope is cheaper than disclaimers.

**Trade-off:** A slice of users will want "write me a plan" or "what should I eat before my long run" from the chat. The system prompt refuses politely and redirects — some of those users bounce. If a future product direction decides LLM-authored plans are in scope, the right move is to let the model propose a *delta* against a generator output, not a free-form plan, and to gate it on an explicit "I know this is AI-generated" confirmation.

**Don't re-litigate unless:** product explicitly decides to absorb the liability surface (at which point expect lawyers, disclaimers, and a content-moderation layer on inputs too).

**Caching note:** two cache breakpoints (system prompt + context dump) keep repeat turns cheap. Don't move the `plan + recent runs` JSON out of the first user message — inserting cachable content between the system prompt and the chat tail is what makes the cache viable at all.

---

## 13. iOS uses Swift Package Manager; `--dart-define-from-file` for secrets

**Decided:** April 2026 · commit regenerating `apps/mobile_ios/ios/`

`apps/mobile_ios` had no native iOS project for most of Phase 1 — `flutter create --platforms=ios .` was needed to generate one. The regenerated project enables Flutter's Swift Package Manager integration (`flutter config --enable-swift-package-manager`) because `maplibre_ios` (pulled in transitively by `flutter_map_maplibre`) uses the native-assets build hook which requires an SPM `Package.resolved`. CocoaPods still handles the plugins that haven't migrated (`health`). Podfile pins `platform :ios, '15.0'` because `health` refuses anything lower.

Secrets for `flutter run` pass through `apps/mobile_ios/dart_defines.json` (gitignored), not inline `--dart-define=` flags. Flutter's Xcode build script rejects values shaped like Supabase's new `sb_publishable_...` anon keys as "improperly formatted define flag"; the JSON file path sidesteps that entirely.

**Trade-off:** A hybrid SPM + CocoaPods project is slightly more moving parts than pure-Pods. We accept that because the two SDKs that dominate the dep graph (`maplibre_ios`, `supabase_flutter`'s deps) are moving to SPM and mixed mode is now the mainstream Flutter iOS story.

**Don't re-litigate unless:** a future plugin refuses to play in mixed mode, or Flutter drops SPM support.

---

## 14. Watch syncs runs via phone-as-proxy over `WCSession.transferFile`

**Decided:** April 2026

`watch_ios` originally talked directly to Supabase (see decision 1), with a hand-rolled REST client, gzip helper, and a token-handoff flow over Watch Connectivity so the phone could push `{access_token, user_id, base_url, anon_key}`. This kept colliding with schema drift: when migration `20260410_001_runs_to_storage.sql` moved the GPS trace out of a `runs.track` jsonb column and into Storage, the watch client still posted the old column and every sync silently failed. The parity-enforcement layer (`packages/core_models` codegen) doesn't reach Swift, so every schema change demanded a manual port.

The cleaner shape: watch never writes to Supabase. On run finish, `WorkoutManager.writeTrackJSON()` dumps the raw points array to a file in Caches and `WatchConnectivityManager.transferRun(fileURL:metadata:)` hands it to the iPhone via `WCSession.transferFile(_:metadata:)`. The phone gzips, uploads to the `runs` bucket, and inserts the row via the shared `packages/api_client`. `WCSession.transferFile` is the right API: it picks the transport automatically (Bluetooth when close, Wi-Fi P2P on the same network, iCloud relay when the phone is far away), queues across app launches, and retries on its own. The watch has no anon key, no token, no Supabase model code at all in the Release binary — the entire `SupabaseService.swift` is wrapped in `#if DEBUG` and compiles out.

**Trade-off:** The phone-side receiver (`apps/mobile_ios/ios/Runner/WatchIngestBridge.swift`) forwards files to Dart via method channel; `WatchIngest` in `apps/mobile_ios/lib/main.dart` constructs a `core_models.Run` and writes through `ApiClient.saveRun`. Before the user signs in, payloads land in `WatchIngestQueue` on disk and replay on the next sign-in — see §22. For watch-sim-alone dev we keep `SupabaseService.swift` alive under `#if DEBUG` and surface a "DEBUG: Sync Direct" button that signs in with seed creds — Release never compiles that file. The acknowledgment semantics are weaker than the old path: `session(_:didFinish:)` only confirms the phone received the file, not that Supabase accepted the write. Good enough to start; a future roundtrip ack can tighten it.

We rejected "any device via CoreBluetooth peripheral mode": watchOS restricts background advertising and there's no receiver on the other end of that pipe that isn't the phone anyway. WCSession covers every real pairing.

**Don't re-litigate unless:** the phone app moves off Flutter in a way that makes `WCSessionDelegate` hard to implement, or we find `WCSession.transferFile` is unreliable in practice for large runs (50KB JSON is trivial today).

---

## 15. `watch_wear` is pure Kotlin + Compose-for-Wear, not Flutter

**Decided:** April 2026 (reverses decision 1 for the Wear OS target only)

Decision 1 picked Flutter for Wear OS so we could reuse `packages/run_recorder` + `packages/api_client` + `packages/core_models`. Two sessions of dogfooding the Flutter-on-Wear build made the ergonomic gap obvious: no rotary-bezel input, no `TimeText` / `PositionIndicator` / `Vignette`, no ambient-mode integration, and channel-crossing would have been required to get any of them. Three options were laid out (hybrid Flutter-engine + Compose UI; pure Kotlin rewrite; cosmetic Flutter polish). We picked the pure Kotlin rewrite after ruling out the hybrid on "channel-based state plumbing" grounds — two async models, two error models, field-by-field serialisation contracts, and debugging traversals across the boundary.

Schema drift — the exact failure mode that bit `watch_ios` when `runs.track` moved into Storage — was the main risk. Mitigated by extending `scripts/gen_dart_models.dart` with a Kotlin emitter. `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/generated/DbRows.kt` is regenerated from the same parsed migrations that drive the Dart row classes; renaming a column regenerates both and breaks `SupabaseClient.saveRun` at compile time exactly like it breaks Dart callers.

Other consequences:
- `packages/run_recorder` is reimplemented in Kotlin (`GpsRecorder.kt` + the distance/pace logic inside `RunViewModel`). The original had lap markers, off-route detection, and a mature GPS filter chain we haven't yet ported — those are TODOs. Phase 1 ports the essentials: `FusedLocationProviderClient` at high accuracy, ≥2m movement gate, ≤100m jitter ceiling, haversine for distance.
- `packages/api_client.saveRun`'s byte-for-byte contract is replicated in `SupabaseClient.kt`: gzip the track, `POST /storage/v1/object/runs/{user_id}/{run_id}.json.gz`, insert row with `track_url`. Web / mobile / watch_wear runs are indistinguishable on the server.
- Health Services + DataStore + Compose-for-Wear replace the Flutter plugins we were using — `health-services-client` (HR), `datastore-preferences` (queue), `androidx.wear.compose` (UI).

**Trade-off:** we now maintain two backend languages (Dart for Android phone / iOS / web; Kotlin for Wear). The surface is narrow — one table, one Storage bucket, one auth endpoint — and the codegen keeps it from drifting, but it's a real ongoing tax. If we ever add a second Kotlin writer (e.g. if iOS moves to Swift Supabase in future), the codegen needs extending further; the parser already handles everything, only the emitter grows.

**Don't re-litigate unless:** (a) Jetpack Compose gets a Flutter interop story that lets us render Compose inside Flutter (doesn't exist today), (b) the Kotlin codegen gets so much drift-reporting overhead that extending it stops being cheap, or (c) someone on the team wants to maintain only one backend language and is willing to accept Flutter's Wear OS UX.

---

## 16. Wear OS auth comes from the phone via the Wearable Data Layer

**Decided:** April 2026

`watch_wear` originally used hardcoded seed creds (`runner@test.com` / `testtest`) — acceptable for Phase 1 dogfooding, unacceptable for anything real. Three options for replacing it: (a) email/password entry on the watch, (b) Google Sign-In on the watch via `RemoteActivityHelper`, (c) piggyback on the paired phone's existing session by pushing it over the Wearable Data Layer.

We picked (c). Rationale: `mobile_android` already has mature Google + email/password auth wired through `ApiClient`; rewriting that flow on a 46mm screen is a bad use of time, and Google's own Wear guidance recommends against credential entry on the watch anyway. The Data Layer push is cheap — `DataClient.putDataItem("/supabase_session", {...})` on the phone, `DataClient.DataChangedListener` on the watch, with a DataStore cache so the watch survives cold starts while the phone is out of range. Refresh tokens travel with the push; `SupabaseClient.refreshAccessToken` uses them locally when the cached access token expires, so a watch that hasn't seen the phone for hours can still sync.

Concretely the wiring is:
- Phone (`mobile_android`): `WearAuthBridge` (Dart) subscribes to `Supabase.instance.client.auth.onAuthStateChange` and pushes through a method channel to `WearAuthBridge.kt` (Kotlin), which writes the DataItem via `Wearable.getDataClient(context)`.
- Watch (`watch_wear`): `SessionBridge.kt` exposes a `Flow<SessionPayload>` of pushes and a `current()` one-shot read for cold starts. `RunViewModel.init` combines three sources: cached session from `SessionStore`, one-shot pull from `SessionBridge`, and live subscription. `drainQueue` retries once on HTTP 401 after a token refresh.

**Trade-off:** standalone Wear OS users (LTE watch, no Android phone) have no auth path today. We accept that gap for the common case (watch paired with phone, phone app installed) and defer the standalone flow — either Google Sign-In via `RemoteActivityHelper` (uses the phone as a dumb browser) or QR-code pairing. Both are separate builds. Users in the gap see "Offline" + an auth error message on the pre-run screen telling them to install the phone app.

A second trade-off: the refresh token lives in DataStore Preferences, not an encrypted store. DataStore's per-app sandbox is sufficient for Phase 1 — a rooted watch can read it, but a rooted watch can also read any other credential store we'd use. Upgrade to `androidx.security.crypto` EncryptedSharedPreferences if we ever store multi-user data or hold long-lived access to third-party services.

**Don't re-litigate unless:** Google restructures `play-services-wearable` in a way that breaks the DataClient contract, or we start wanting the watch to be the auth primary (e.g. for a watch-first product where a phone isn't assumed).

---

## 17. `RunRecordingService` foreground service owns the Wear recording lifecycle

**Decided:** April 2026

Early `watch_wear` builds ran GPS + HR + timer in `viewModelScope`. That died the moment Android backgrounded or Doze-throttled the activity — the run silently stopped a minute after the wrist dropped. Three realistic options: (a) stay in the ViewModel and lose runs, (b) a bound `Service`, (c) a foreground service with `foregroundServiceType="location"` + ongoing notification + wake lock.

We picked (c). The architecture is:
- `RecordingRepository` is a process-singleton `StateFlow` that the service writes to and the `RunViewModel` reads from. Activity lifecycle becomes irrelevant to the recording loop.
- `RunRecordingService` holds a `PARTIAL_WAKE_LOCK` and posts an `OngoingActivity` so Wear treats it as user-visible work, not background activity to be throttled.
- `CheckpointStore` snapshots track + distance to a side DataStore every 15s; the next launch offers a recovery prompt if it finds one, so a mid-run process kill loses at most 15s of data.
- Network retries are classified into permanent (400/404/409/422 — skip row), transient (5xx/timeout — stop loop, next network edge retries), and auth (401 — refresh + one retry).

**Trade-off:** the foreground service holds a wake lock for the entire recording, which fights some OEM battery policies more aggressively than a `JobScheduler`-based design would. At 10-hour-ultra scale there are also O(n²) allocation patterns in the current code (the full track list is rewritten to the repo on every GPS sample, and re-snapshotted to the checkpoint every 15s) that haven't been engineered for. Marathon-scale is comfortable; ultra needs a streaming refactor before trusting it.

**Don't re-litigate unless:** Google ships a stable Health-Services-based streaming API that supersedes `FusedLocationProviderClient` for workout-class apps (the pattern is converging toward `ExerciseClient` on Wear OS 4+), or OEM policies tighten foreground-service rules further and a `JobScheduler` design becomes the only reliable path.

---

## 18. Free-with-donations instead of paid subscription

**Decided:** April 2026 · commits `7cbcc45` through `94eb6d4`

The roadmap originally described a $6/month Pro tier via RevenueCat gating premium features (AI Coach, priority sync, training plans, advanced analytics). Before shipping any paid tier, we pivoted to a "free with donations" model: every feature is free, and a transparent funding page at `/settings/upgrade` shows the real monthly costs (Supabase, Claude API, MapTiler, domain, etc.) alongside a progress bar tracking how much of the monthly target is covered by donations.

The gate infrastructure stays in place — `GATED_FEATURES` registry, `ProGate` component, `isLocked()` function, `subscription_tier` column, `is_pro()` SQL helper, and the RevenueCat webhook. But `isLocked()` always returns `false` so nothing is actually locked. The AI Coach's cost is managed via a daily usage limit (10 messages/user/day, enforced by `increment_coach_usage` RPC) instead of a paywall.

**Why:** A paid tier before product-market fit creates friction that slows user acquisition. Donation funding lets early adopters use everything while signalling what the app costs to run. If the user base grows large enough that donation income can't cover API costs, re-gating specific features is a one-line change in `isLocked()`.

**Trade-off:** No revenue guarantee. Donations are unpredictable and the Claude API bill scales with usage. The 10-message daily cap on the coach is the cost-control mechanism — if it proves insufficient, either lower the cap or re-gate the coach behind Pro.

**Don't re-litigate unless:** (a) monthly API costs consistently exceed donation income by >2x, or (b) the user base is large enough that even a small conversion rate would meaningfully outperform donations.

---

## 19. Custom dialogs and toast system replace browser confirm/alert/prompt

**Decided:** April 2026 · commit `7cbcc45`

Every `window.confirm()`, `window.alert()`, and `window.prompt()` call in the web app was replaced with custom inline UI: `ConfirmDialog.svelte` for destructive-action confirmations, and `ToastContainer.svelte` + `toast.svelte.ts` for transient feedback. Browser dialogs are unstyled, block the main thread, and look alien in a dark-themed SPA.

`ConfirmDialog` is a styled modal with configurable title, message, and button labels. It resolves a promise so callers can `await` it the same way they would `confirm()`. `showToast()` from `$lib/stores/toast.svelte` pushes success/error/info messages to a corner stack with auto-dismiss.

**Trade-off:** More code than the one-liner browser APIs. Acceptable because the app now has a consistent UI language for confirmations and notifications, and the dialogs are accessible (focus trap, escape-to-dismiss).

**Don't re-litigate unless:** the custom dialog system becomes a maintenance burden, which it won't at this scale.

---

## 20. Lock-screen notification reuses geolocator's foreground-service channel

**Decided:** April 2026

`RunNotificationBridge` (native Kotlin + Dart client) replaces geolocator's static "Run in progress" notification with live time / distance / pace by reposting on the **same** channel id (`geolocator_channel_01`) and notification id (`75415`) that `GeolocatorLocationService.startForeground` uses. Android treats identical `(channel, id)` as an update, so our content overwrites the visible row without detaching the foreground service.

Two constraints forced this shape:

1. Geolocator 5.x exposes no public API to update the foreground notification text after the stream is opened. `changeNotificationOptions` exists in its Java internals but isn't routed through the Dart method channel.
2. The channel geolocator creates has `lockscreenVisibility = VISIBILITY_PRIVATE` and `IMPORTANCE_NONE`, and `lockscreenVisibility` is immutable after channel creation. We pre-create the channel with `VISIBILITY_PUBLIC` + `IMPORTANCE_LOW` at bridge init so the user actually sees the content on the lock screen.

**Alternatives considered and rejected:**
- **A separate notification on our own channel.** User ends up with two persistent notifications (geolocator's static one + ours). Ugly and defeats the purpose.
- **A native foreground service we own, replacing geolocator's.** ~200 lines of Kotlin plus Dart glue to proxy fixes back through a method / event channel, and we'd be re-implementing what geolocator already does well. Worth revisiting if we ever need richer controls (buttons, media-style layout) that channel-sharing can't support.

**Trade-off:** hard coupling to geolocator internals. If a future release changes `CHANNEL_ID` or `ONGOING_NOTIFICATION_ID`, our replacement stops applying — the user sees a second row instead of the live stats, and the constants in `RunNotificationBridge.kt` need to be bumped to match. The constants are named and commented specifically so this is obvious when it breaks.

**Don't re-litigate unless:** geolocator changes its notification plumbing (watch the `geolocator_android` changelog on bumps), OR we want custom action buttons / media-style layout that require our own channel.

---

## 21. Advanced GPS keeps the default 20 m accuracy gate

**Decided:** April 2026 · reverts the per-Advanced-mode override from `4b6dc1b`

The original Advanced GPS feature passed `accuracyGateMetres: 10` to `RunRecorder.prepare` on the assumption that requesting `LocationAccuracy.best` would produce fixes with sub-10 m reported accuracy and the tighter gate would reject the noisy outliers. It doesn't work that way: `Position.accuracy` is the OS's real-world uncertainty estimate (cell + GNSS fusion, sky view, multipath), not a knob the OS scales down when you ask for `best`. Consumer phones routinely report 15–30 m outdoors even on open sky — exactly the conditions Advanced GPS targets. With the 10 m gate, `_onPosition` silently dropped almost every fix, the blue dot froze, and distance stayed at 0. The bug was invisible because the drop happens before `_currentWaypoint` is touched and nothing logged the rejection.

We kept `accuracyGateMetres` as a prepare parameter (some future caller may want a custom value) but the only live caller — `run_screen.dart:_preload` — no longer overrides it in Advanced mode. The real "advanced" levers remain: `LocationAccuracy.best`, `distanceFilterMetres: 2`, `minMovementMetres: 1`. We also added a rate-limited `debugPrint` at the accuracy-drop site so a future regression like this is visible from logs instead of presenting as "the app just doesn't record."

**Trade-off:** none — the old gate was purely a bug. Advanced GPS still gives denser tracks and asks the hardware for a better fix; we just no longer throw away the hardware's honest uncertainty estimates.

**Don't re-litigate unless:** a future device ecosystem (or ARCore-style dual-frequency GNSS becoming standard) makes sub-10 m reported accuracy routine outdoors. At that point the gate could be dropped, not tightened — the floor is "what real phones actually produce," not what we'd like them to.

---

## 22. Unauthed watch-run payloads persist to disk and replay on sign-in

**Decided:** April 2026 · `apps/mobile_ios/lib/watch_ingest_queue.dart`

When the Apple Watch sends a completed run via `WCSession.transferFile` and the paired iPhone user is not signed in, the previous behaviour was to return `false` from the Dart method channel handler, which caused `WatchIngestBridge.swift` to re-queue the payload in an in-process `pending` array. On app restart that array was empty and the run was permanently lost. Any run recorded before the user first signed in, or during a session where credentials expired, was silently discarded.

The fix is `WatchIngestQueue`: when `WatchIngest.attach` receives a run payload and `api.userId == null`, the payload is written as JSON to `<documents>/watch_ingest_queue/<uuid>.json` instead of being forwarded to Supabase. On the next `AuthChangeEvent.signedIn` event (both cold launch with a stored session and explicit sign-in), `WatchIngestQueue.drain` replays every queued file via `api.saveRun` and deletes each file on success. Files that fail to upload are left on disk and retried on the next sign-in, making the queue eventually consistent.

**Trade-off:** Disk space is bounded by the number of watch runs that arrive before first sign-in — negligible in practice. The duplicate-return-false to `WatchIngestBridge.swift` means the native side also keeps a reference until the app tells it `true`; in the brief window between writing the queue file and restarting, both the native and Dart queues hold the run, but deduplication via `api.saveRun` (upsert by id) means only one row is written.

**Don't re-litigate unless:** the queue grows unbounded (add a cap) or the upsert deduplication stops working (add an explicit existence check before drain).

---

## 23. Pro tier reintroduced at $9.99/mo alongside one-off donations

**Decided:** April 2026 · supersedes [§ 18](#18-free-with-donations-instead-of-paid-subscription)

Decision #18 pivoted the app to "everything free, funded by donations" with a transparent cost-breakdown page. Donations are unpredictable and the Claude API bill is the only cost that scales with active usage, so the 10-message daily cap on the coach was the sole cost-control lever. That cap hits heavy users before it hits casual users — exactly the opposite of what we want — and gives nothing back to people willing to pay.

The new model is a **Pro tier at $9.99 / month** that unlocks two things:

- **Unlimited AI Coach.** The 10 / day cap still applies to the free tier (cost control); Pro users bypass it. Server-side enforcement lives in `/api/coach/+server.ts` via the `is_user_pro(uid)` RPC.
- **Priority processing.** Pro requests are routed ahead of the free queue at rate-limit boundaries. Today this is a marketing claim with no enforcement beyond the unlimited-coach bypass; concrete enforcement (Edge Function queue priority, client throttle hints) lands as needed.

The `/settings/upgrade` page replaces the transparent funding page with a two-card layout: a Pro plan card ($9.99/mo, feature bullets, "Get Pro" CTA) and a single "Donate" card linking to an external one-off payment provider. Cost breakdown, per-month progress bars, donor count, and the tiered donation buttons are gone — those stats were a nice-to-have that didn't move conversion.

Infrastructure from #18 is largely reusable: the `GATED_FEATURES` registry, `is_user_pro` / `is_pro` SQL helpers, the `subscription_tier` column, the RevenueCat webhook, and the `user_coach_usage` table all stay. The only registry change is renaming `priority_sync` → `priority_processing` with broader copy. The `monthly_funding` table stays in place (orphaned but not dropped); if transparency becomes a differentiator later it's a one-migration revival.

**Why:** A clear, price-anchored value proposition ("$9.99 for unlimited chat and priority handling") converts better than an open-ended donation ask, and it aligns cost with usage — heavy coach users are exactly who benefits, and they're the ones generating the API spend.

**Trade-off:** Re-adds the subscription friction that #18 explicitly avoided. The one-off Donate button is retained so users who don't want a subscription still have a path to support the project. RevenueCat's web SDK is not yet wired; the "Get Pro" button is a placeholder toast until it lands.

**Don't re-litigate unless:** conversion is <0.5% after 3 months of marketing the tier, or Pro users complain that "priority processing" isn't observable (at which point we either enforce it concretely or rename the bullet).

---

## 24. Web is the canonical feature surface; mobile and watches are platform-additive

**Decided:** April 2026 · supersedes the informal "parity per platform" default

Every user-facing feature lives on the web app unless it is physically impossible there. Mobile (Android / iOS Flutter) and watch (watch_ios Swift / watch_wear Kotlin) clients are expected to **mirror the web's feature surface** and then **add things only a device in the pocket or on the wrist can do** (live GPS recording, sensor access, on-device crash recovery, ambient-mode rendering, haptics, OS share sheets, etc.). The web is the reference; the other clients are extensions.

**Why:** for a solo-dev, small-team product, maintaining full feature parity across five clients scales poorly. Concentrating net-new product surface on one platform — the one with the fastest iteration loop, the richest input devices, the best tooling, and the broadest discoverability — keeps the monorepo honest. Parity work becomes "mirror to mobile" rather than "pick a feature and find out which of five platforms it's missing on." The [cross-platform parity enforcement initiative](roadmap.md#future--cross-platform-parity-enforcement) stops being an N-way problem and becomes a one-way flow.

**Physical exceptions** (stay platform-led; web row stays `N/A` in `parity.md`):

| Feature | Why web can't lead |
|---|---|
| Live GPS recording | Browsers can't do reliable background location over a multi-hour run |
| Pedometer / cadence | No browser step-counter sensor |
| Heart rate via device sensor | HealthKit / Health Connect / BLE GATT are OS-level APIs |
| Haptic alerts during a run | Vibration API is unreliable and has no background access |
| OS share sheets | Platform-specific by definition |
| Watch complications / tiles | Platform-native |
| Crash-safe recording | Needs a foreground service (Android) / workout session (watchOS) |
| Offline-only mode | Every web route is online by design |
| Import via OS share target (GPX / KML files) | Mobile intents; web uses drag-and-drop instead |

**How to apply it:**

1. **New features.** Build on web first. Port to mobile only after the web surface is real. The exception is features that *start* in one of the rows above — those are designed on the platform that owns them.
2. **Bug fixes / polish.** When the divergence is a gap in web's coverage of an otherwise-mirrored feature (e.g. "Android has X but web doesn't"), close it on web first. That inverts the drift pressure: instead of "is mobile up to date?", the question becomes "is web covering everything?"
3. **The matrix.** `parity.md` rows where web is `✗` or `Partial` on a non-physical-exception feature are now flagged as **"gap vs web-canonical principle"** in the Notes column — they're the backlog to close, in order of impact.

**Trade-off:** mobile users who open the app before the web mirror lands will see fewer features than a user who lands on the web first. Historically this happened in the reverse direction — Android led on recording, history, sync, clubs, plans; web caught up. We're explicitly flipping the order for *new* work from this decision onward; *existing* drift in the other direction (Android ahead of web on, e.g., multi-goal editor, browsable period summary) gets closed the same way — by building the web version first and letting mobile stay where it is until the web lands.

**Don't re-litigate unless:** a non-trivial segment of active users uses the mobile app without ever touching the web (analytics check), or a genuinely web-hostile feature category emerges (ARKit-style AR, deep watch-complication work, etc.) where the web-first rule would hold the category back.

---

## 25. Live spectator tracking uses Supabase Realtime, not a custom WebSocket service

**Decided:** April 2026 · supersedes the original "Go service behind `/live/*`" plan.

The spectator page at `/live/{run_id}` streams a runner's in-progress GPS trace to anyone with the link. The earlier plan was to stand up a dedicated Go WebSocket service that held per-run channels. We shipped it instead as a new `live_run_pings` table (migration `20260509_001`) on the realtime publication, subscribed from the browser via `supabase.channel(...).on('postgres_changes', ...)`.

**Why:** a custom Go service adds a whole deployable (container, scaling, health checks, certs) for a feature where the read pattern is trivial — "stream rows inserted for `run_id = X`". Supabase Realtime already offers that over logical replication; piggybacking on it keeps the feature at zero operational cost and lets the mobile recorder write to the same table it would write any other row into.

**Trade-off:** Postgres WAL isn't a free lunch at scale — very high-frequency broadcasters (sub-second ping cadence × many concurrent runners) can pressure the replication slot. The recorder contract is one ping every 3–10 s, which is fine, and the `cleanup_stale_live_run_pings()` helper (callable from the service role) sweeps anything older than 4 hours so orphan rows don't pile up. If usage ever moves us past the realtime limits we revisit; until then we avoid a Go service we don't need.

**Don't re-litigate unless:** realtime throughput becomes the bottleneck, or we need server-authoritative coordination (a race starter gun that must fan out to N participants with < 250 ms jitter, for example) that belongs in an in-process hub.

---

## 26. Web formatters split: pure-TS modules can't import `*.svelte.ts`

**Decided:** April 2026 · captured after the `fmtKm` / `fmtPace` move.

`apps/web/src/lib/training.ts` is unit-tested under `tsx --test` (see [testing.md](testing.md)). The runtime is plain Node — Svelte's runes (`$state`, `$derived`, `$effect`) are compile-time syntax provided by the Vite plugin, so importing any `*.svelte.ts` module from a tested file blows up at module-load with `ReferenceError: $state is not defined`. We hit this when the unit-aware `fmtKm` / `fmtPace` formatters were first added to `training.ts` and re-imported `getUnit()` from `units.svelte.ts`.

**Decision:** unit-aware formatters live in `units.svelte.ts` (alongside the reactive `unit` signal); pure-TS modules don't import them. Svelte components that need them write a second import line. The two clusters never cross.

**Trade-off:** an extra import line in every Svelte component that wants `fmtKm` instead of one tidy "everything from `$lib/training`". Worth it — keeps the pure logic file testable without pulling in vitest + the Svelte plugin just to test two formatters.

**Don't re-litigate unless:** we adopt vitest with `@sveltejs/vite-plugin-svelte` (which natively transforms runes for tests), at which point the constraint disappears and a single export point is fine again.

---

## 27. Product renamed from "Better Runner" to "Run Onward"; bundle IDs stay

**Decided:** April 2026.

The user-visible product name is now **Run Onward** (URL: `runonward.com`). All display strings — Android `android:label`, iOS `CFBundleDisplayName` / `CFBundleName`, watchOS health-permission usage strings, web `<title>` + meta + share-card chrome, GPX `creator=` attribute — were updated. Internal identifiers were deliberately *not* changed: the Android `applicationId` / Kotlin package directory remain `com.betterrunner.app`, the WorkManager task name remains `com.betterrunner.backgroundSync`, and `BACKUP_FORMAT` remains `'run-app-backup'`.

**Why:** "Better Runner" was running-only branding for a multi-modal app (run + walk + hike + cycle). "Run Onward" reframes the verb as forward movement rather than jogging, and `runonward.com` was the rare clean `.com` left in the running-adjacent namespace (most short slang `.com`s are squatted on Afternic).

**Trade-off:** keeping the bundle ID tied to the old name means the Play Store / App Store internal identity, on-device install identity, signing key association, and existing-user upgrade path are all preserved — at the cost of some lasting "betterrunner" strings inside the codebase that are jarring to read but never user-visible. Changing the bundle ID would create a new app listing with no upgrade path and break deep links / signing. Twitter→X did the same (kept `com.atebits.Tweetie2` long after the rebrand). Similarly, the WorkManager task name and backup format are stable identifiers — changing them would orphan scheduled tasks on existing devices and break restore of old backups respectively.

**Don't re-litigate unless:** we're prepared to accept a clean-break new app listing (new Play Store / App Store entries, deep-link migration, user re-install, signing-key reassociation). At that point we'd also revisit the WorkManager and backup-format identifiers in the same migration.

---

## 28. Coach chat persists server-side; archive-not-delete; SSE streaming

**Decided:** April 2026 · captured after the coach-chat v2 work.

The Claude coach surface gained four shape changes that, together, look like ChatGPT/Grok:

- **Cross-device persistence.** Threads live in `coach_messages` (RLS owner-only, scoped per `user × plan`) instead of localStorage. Pre-existing localStorage threads migrate once on first read.
- **Archive, don't delete.** "Start new conversation" sets `archived_at = now()` on every active row in the (user, plan); rows sharing one timestamp form an archive. The sidebar lists archives auto-titled by their first user message; runners can view (read-only) or delete an archive. Per-archive delete is RLS-scoped.
- **Server-Sent Events streaming.** The endpoint emits events of `meta` (user_message_id + tier + limits), N × `token` (text deltas), and `done` (assistant_message_id + cache + usage). Pre-stream errors (auth, rate-limit) still come back as JSON so the client picks the path off `content-type`. Reload-mid-stream is handled by a Realtime subscription on `coach_messages`: the in-flight server request still completes and writes the assistant row; the realtime listener picks it up and the typing indicator (which the client shows whenever the last message is a user message without an assistant follow-up) clears.
- **Inline bubble actions.** Copy / regenerate / edit-and-resend / thumbs are all anchored on `coach_messages.id`. The server accepts `mode` (`send` / `regenerate` / `edit`) + `anchor_message_id`; regenerate / edit truncate the active thread from the anchor onward and re-run without inserting a duplicate user message.

**Why each:**
- Persistence: previous localStorage shape didn't survive a different browser. Switching to `coach_messages` was straightforward once we accepted RLS as the isolation primitive.
- Archive vs delete: runners told us they wanted to keep useful conversations. The simplest model that doesn't require a new `coach_threads` table is `archived_at` as a grouping timestamp. We can normalise to a real threads table later if titles, renames, or thread-level metadata appear.
- SSE: streaming makes a 5–15 s response feel instant. Buffer-then-respond is the correct shape only if you don't have the bandwidth for incremental rendering — we already have it via `marked` + `DOMPurify`.
- Inline actions: the right product is "every Grok / ChatGPT affordance" rather than picking the cheapest subset. The server-side truncate-and-rerun pattern means the data model never accumulates duplicates.

**Trade-off:** `coach_messages` uses an `archived_at` grouping convention rather than a real threads table. Renames, multi-thread-per-plan, or thread-level metadata are not expressible without schema work. Acceptable today — the cost of a real threads table is a migration that backfills `thread_id` onto existing messages, which we'll do if and when product needs it.

**Don't re-litigate unless:** runners ask for renamed threads, or a model-evaluation feature wants to query at the thread level.

---

## 29. Security patterns from the data-isolation audit

**Decided:** April 2026 · captured after the post-coach data-isolation audit (`/tmp/data-isolation-audit/`).

A fan-out audit across DB, server endpoints, and client surfaced a recurring class of bug — `security definer` functions that take a `p_user_id uuid` argument with no caller-identity guard, callable by any authenticated user. We close it with three patterns going forward:

- **Guard or drop.** `security definer` functions that take a user-id argument either (a) raise `not authorized` when `auth.uid() is not null and auth.uid() != p_user_id`, or (b) get dropped in favour of a no-arg variant that gates internally on `auth.uid()`. Convention: callers passing only their own id should always use the no-arg variant; functions that *need* a different `user_id` (e.g. trigger paths) keep the guard. Concrete actions: `is_user_pro(uuid)` dropped (`is_pro()` is the no-arg variant); `refresh_personal_records_for_user(uuid)` guarded.
- **Defence-in-depth filters on the client.** Personal-data list queries from the browser always include an explicit `.eq('user_id', auth.user.id)` predicate, even when RLS would scope the query anyway. The audit found two `runs` queries that relied solely on RLS — `fetchPersonalRecords` and `fetchRuns`/`fetchRunById`. The cost of the explicit filter is one line; it's a hedge against a future RLS regression silently widening visibility.
- **Column-level GRANTs for write immutability.** When some columns of a table should be read-only to clients (e.g. `coach_messages.content` after insert), enforce it at the GRANT layer, not via a `WITH CHECK` self-subquery. Concrete: `coach_messages` UPDATE was reduced to `(archived_at, reaction)` only — PostgREST honours per-column UPDATE grants and rejects mutations that touch other columns at the gateway.

Two third-party-imposed patterns also fell out of the audit:

- **Strava webhook secret in the URL query string.** Strava doesn't HMAC-sign POST payloads — their security model is "the callback URL is secret." That's not enough on its own (a leak of the function URL is unrotatable), so the configured callback URL embeds `?secret=<STRAVA_WEBHOOK_SECRET>`. Strava preserves URL query strings on both GET and POST, so the secret guards both. Constant-time string compare to avoid timing side-channels. (RevenueCat's HMAC pattern is the right thing where the third party offers it; Strava simply doesn't.)
- **Auth before parse.** Edge functions check `Authorization` and `auth.getUser(token)` before `req.json()`. A malformed-JSON probe from an unauthenticated caller would otherwise produce a 500 distinguishable from a 401, and any future code added between the parse and the auth check would run unauth'd.

**Trade-off:** the explicit-filter rule means redundant predicates that RLS already enforces. The column-level GRANT means PostgREST will return `permission denied` rather than the silent ignore that some `with check` shapes give. Both are deliberate: a noisy failure is better than a silent leak.

**Don't re-litigate unless:** Postgres adds first-class column-level RLS (then column-level GRANTs become redundant), or Strava ships a payload-signing scheme (then the URL secret can rotate to header-based HMAC).

---

## 30. Routes can be club-owned; "save to library" is a reference, not a copy

**Decided:** April 2026 · captured before the migration that adds `routes.club_id` and the `saved_routes` join table.

The original `routes` model has a single `user_id` owner column and a boolean `is_public` discoverability flag. That works for a runner uploading their Sunday loop, but breaks for the "club hosts a recurring race" scenario: when a race director uploads the official course, only they can attach it to events, the next admin can't edit it, and any user who taps the bookmark icon on Explore creates a duplicate row of the same course. Strava has the same gap — their long-running [Saving Routes to a Club](https://communityhub.strava.com/t5/strava-features-chat/saving-routes-to-a-club/m-p/1342) thread asks for exactly this and they haven't shipped it.

We solve it with two schema additions, deliberately small:

- **`routes.club_id` (nullable FK to `clubs`).** When set, the route is *club-owned*: any club admin can edit it, any club member can read it (regardless of `is_public`), and it survives the original uploader leaving the role. When null, behaviour is unchanged. `user_id` stays non-null and now means *uploader* — an audit trail, not authority. Two new RLS policies layer on top of the existing user-owned and public-readable policies: club members can SELECT, club admins can write.
- **`saved_routes` (user_id, route_id) join table.** "Save to library" inserts a reference, not a clone. `/routes` "My routes" tab UNIONs personal `routes` with `saved_routes`. The bookmarked canonical row gains `run_count`, the org keeps a single source of truth, and the explore listing stops accumulating parallel copies of the same course.

**Why this shape and not alternatives:**

- *Many-to-many `route_clubs`* — flexible but premature. The mental model is "this club's official course," singular. If real demand for cross-club routes appears, add a join table later; the single `club_id` migration is forward-compatible.
- *A `verified` / `is_official` flag* — separate concern. The existing `featured` flag already covers admin curation, and we don't want a second axis until users actually argue about which copy is canonical.
- *Geometric dedup of duplicates* — fuzzy edges, research-grade problem (start/end tolerance, path similarity, parkrun-style multi-lap loops). Out of scope. The reference-not-clone pattern eats the most common duplicate source for free.
- *Drop `user_id` when `club_id` is set* — kept for audit. Knowing who originally uploaded the course matters for moderation and for crediting community contributions.

**Trade-off:** A single `club_id` means a course used by three different clubs is either three rows or one row + two `saved_routes` references. We accept that in exchange for a much simpler permission model. Also: `saved_routes` doesn't dedup *legitimately separate* uploads of the same course (two different runners both upload the Richmond marathon course) — only the bookmark path. Editorial `featured` curation is the answer there until volume forces a smarter dedup.

**Don't re-litigate unless:** runners report regularly attaching the wrong copy to events because three near-identical rows show in Explore (then geometric dedup or an `official_for_club_id` verified flag becomes worth the engineering cost), or clubs federate (a route belonging to multiple parent clubs becomes a real product concept).

---

## 31. Following graph is its own social layer; profiles are public-by-default

**Decided:** April 2026 · captured before the migration that adds `user_follows` and the `/feed` + `/u/[id]` surfaces.

The clubs/events social layer (decisions §0–§28) is a *group* abstraction — useful for race directors and weekly-meetup organisers, but the wrong shape for the runner who just wants to see what their three running friends did this week. That's the surface every consumer running app (Strava, Nike Run Club, Garmin Connect) builds first. We add it as a parallel social layer rather than reusing club_members because the audience model is different: club membership is bidirectional and gated; following is asymmetric and instant.

We ship three things together:

- **`user_follows (follower_id, followee_id, followed_at)`** — composite-PK join table, self-follow blocked by CHECK, on-delete cascade for both sides. RLS: anyone can INSERT where `follower_id = auth.uid()`; anyone can SELECT (the follow graph is public — visible on profile pages); only the follower can DELETE their own row. Deliberately no row hiding by either side: if you don't want to be followed, the right answer is a future "private profile" flag, not a hidden graph.
- **Public user profile pages at `/u/[id]`** — render `display_name`, `avatar_url`, follower / following counts, recent public runs, and a Follow button. The identifier is `auth.users.id` (UUID) for v1; URL-safe handles (`/u/jared`) get added later as a `user_profiles.handle` column once we decide on a reservation/uniqueness/normalisation scheme. Until then, the URL is uglier but the schema is forward-compatible.
- **`/feed` route** — recent public runs from people the caller follows. Cursor-paginated on `(runs.started_at desc, id desc)` to stay stable as new runs arrive. Pull-based (no realtime) — the engagement value of "instant" on a feed is low and adding `runs` to the realtime publication has a fan-out cost we don't need yet.

**Public-profile read access requires a schema-level shift.** Today `user_profiles` has one RLS policy: `auth.uid() = id`. That's been silently breaking cross-user enrichment (`enrichPosts`, `fetchClubMembers`, etc. — they query `user_profiles` for other users' display_name and get empty rows back). The follow feature *requires* cross-user reads, so we add a public-read policy and accept that `subscription_tier` and `parkrun_number` become world-readable to authenticated users. `subscription_tier` is already effectively public via the "Pro" badge any UI would show; `parkrun_number` is a public ID people share themselves. If a future user objects, the right fix is a column-level GRANT REVOKE pattern (decision §29's "column-level GRANTs for write immutability" applied to reads) — not row-level RLS.

**Why these and not alternatives:**

- *Follower approval (Twitter "private account")* — meaningful UX cost (request flow, pending state, privacy UI) for a problem we don't have yet. Default to open and add private profiles later as a single-row toggle.
- *Mutual-follow / friendship model* — collapses two relationships into one and forces both parties' consent. Wrong for "I want to see this elite runner's training" — Strava's asymmetric follow is correct here.
- *Reuse `club_members` for follows* — a club is a *thing*; following another runner is not. Overloading the table forces awkward synthetic clubs ("Jared's followers") and ties the feed query to club-permission RLS.
- *Server-side push on new runs from followed users* — engagement-positive but blocked on `VAPID_PRIVATE_KEY` (parity.md notes the gap). Out of scope for the v1 ship.

**Trade-offs:** (1) UUID URLs are uglier than handles; we accept that for v1 because handle reservation is a non-trivial design choice (case sensitivity, reserved words, length, change history). (2) The feed is purely pull-based — a runner who opens it twenty seconds after a friend uploads gets nothing until they refresh; we accept that because realtime on `runs` would fan out widely and we have no engagement signal that justifies the cost. (3) `user_profiles` is now world-readable to authenticated users; that's a small privacy widening accepted in exchange for fixing the existing enrichment bug.

**Don't re-litigate unless:** users start asking for handles (then add `user_profiles.handle` with a normalisation function), private profiles become a real ask (single-column toggle plus an RLS predicate on the public-read policy), or someone needs the feed instant (then enable realtime on `runs` with a `is_public` filter). Each of those is a forward-additive change — none requires undoing what we ship now.

---

## 32. Kudos + comments on runs; visibility tracks runs' own RLS

**Decided:** April 2026 · captured before the migration that adds `run_kudos` and `run_comments`.

The activity feed shipped in §31 needs an engagement loop. Strava's pattern — kudos (one-tap heart), then comments (free-form text with one level of threading) — is the canonical answer; copying it directly is the right call. We resist two adjacent product temptations:

- *Rich reactions (👏 / 🔥 / ⚡)* — Slack-style multi-emoji reactions look fun but every additional emoji dilutes the signal. Strava ships only kudos because "did you appreciate this run, yes/no" is the only question that scales. Multi-emoji is also a strict superset of kudos and can be added later by widening the `run_kudos` table with a `reaction text` column; we don't pre-build for it.
- *Multi-level threading* — replies-to-replies-to-replies is a moderation nightmare and the one-level cap (Reddit calls this "shallow threading") matches the existing `club_posts` precedent (`parent_post_id` only, no recursion in the data model). UI enforces it by hiding the reply affordance on already-replied comments.

**Schema:**

- **`run_kudos (user_id, run_id, given_at)`** — composite PK so a user can only kudos a run once. ON DELETE CASCADE on both sides. No `id` column; the natural key is the relationship itself.
- **`run_comments (id, run_id, author_id, parent_comment_id, body, created_at, updated_at)`** — `parent_comment_id` is a self-FK (nullable). One level of nesting is enforced in the policy: `with check (parent_comment_id is null or (select parent_comment_id is null from run_comments where id = parent_comment_id))`. `body` is CHECK-constrained to 1..2000 chars to keep an `<input maxlength>` honest.

**RLS — visibility tracks runs.** The lever-pulling decision is making kudos / comments inherit the parent run's visibility, not setting a new policy from scratch:

```sql
create policy "kudos readable when run is readable" on run_kudos
  for select using (exists (select 1 from runs where runs.id = run_kudos.run_id));
```

The EXISTS subquery is itself subject to runs' RLS (`auth.uid() = user_id` OR `is_public = true`), so kudos on a private run are invisible to anyone but the owner. Same shape for comments. This is the same pattern `club_posts` and `event_attendees` use to inherit clubs / events visibility, so it's not a new technique.

**Moderation rights:** the comment author can edit / delete their own comment; **the run owner can also delete any comment on their own run** (separate DELETE policy with `exists (...) where runs.id = run_comments.run_id and runs.user_id = auth.uid()`). No edit-by-run-owner — that's tampering, not moderation.

**Why these and not alternatives:**

- *Quoted replies* — Strava's "Reply to @user" affordance is rendered client-side from the reply tree; we get it for free from the existing parent_comment_id without storing a quote.
- *Comment likes* (heart on a comment) — additive surface; defer until people ask.
- *@mention notifications* — requires the push delivery path that `device_tokens` is staged for but isn't wired (parity.md). We keep `body` plain text for now; @mention parsing can layer on later without a schema change.
- *Single `run_engagements` polymorphic table covering both kudos and comments* — saves a migration, costs every consumer a `kind` filter forever. Two tables with the same cascade pattern is clearer.

**Trade-off:** A run owner can silently delete inconvenient comments — that's classic Strava behaviour and we accept it as the moderation primitive. If we ever want a public moderation log ("comment hidden by run owner") that's a future schema add.

**Don't re-litigate unless:** people start asking for emoji reactions and we have a usage signal (then widen `run_kudos` with `reaction text default 'kudos'` and enforce uniqueness on `(user_id, run_id, reaction)`), or comment counts on highly-engaged runs become a perf hotspot (then add a denormalised `runs.comment_count` maintained by trigger, mirroring `routes.run_count`).

---

## 33. Privacy zones live in user_settings; clipping is client-side; nearby leak is a known v1 gap

**Decided:** April 2026 · captured before the privacy-zones settings UI lands.

Strava and Garmin both let you blur a radius around home / work. We ship a v1 of the same idea with the smallest possible footprint: zones are stored as a JSON list on `user_settings.prefs.privacy_zones`, clipping is done client-side, and we accept one v2-ish gap (the `routes.start_point` PostGIS column still leaks the unclipped first waypoint into the nearby-routes RPC).

**Storage shape:**

```json
{ "privacy_zones": [{ "lat": 40.7128, "lng": -74.0060, "radius_m": 250 }] }
```

A list is the right shape because every realistic user has exactly 0–3 zones (home, work, gym), and `user_settings.prefs` is already a jsonb bag with no schema policing — no migration cost. RLS on `user_settings` already gates the row to the owner, so the zones themselves are *private to the owner*; only the *clipped output* is public.

**Algorithm:** for any list of points and the owner's zones, walk forward from index 0 and drop points whose haversine distance to any zone center is ≤ `radius_m`. Walk backward from the end with the same predicate. Keep the contiguous middle. This means a track that starts at home, runs away, comes back, runs out again, comes back home shows as a single un-broken middle — we deliberately don't slice out interior loops, because (a) the leak Strava is solving is "where you live," not "where you've ever been," and (b) gapping the polyline mid-run looks broken.

**Where clipping happens:**

- *`/share/run/[id]`* — the public share page. Always clipped; the page is publicly addressable and the run owner is the user we're protecting.
- *`/share/route/[id]`* — same.
- *`/runs/[id]`* and *`/routes/[id]`* — owner-only views; never clipped.
- *`/feed`* — entries link to `/share/run/[id]`, so clipping happens there.
- *`/u/[id]/...`* — the profile page surfaces a list of public runs but each one's detail page handles its own clipping.

**Why a SECURITY DEFINER RPC, not pure-client clipping:**

The naive shape ("just fetch the owner's `privacy_zones` and clip on the client") leaks the zones — defeating the whole point. Public viewers can't be trusted with the zone polygons. So the actual implementation is a `clip_track_for_user(target_user_id, points jsonb)` SECURITY DEFINER RPC that reads zones internally and returns only the clipped output. Zones never cross the wire to a non-owner.

- *Server-side clipping at insert / update time* is destructive — the owner can't get their full track back after toggling a zone off. RPC at render time is reversible by definition.
- *Pre-storing two Storage objects per run* (full-fidelity owner-only + pre-clipped public) is the right v3 architecture, but doubles storage and forces the recorder/uploader to know about zones. Future work.
- *Modifying the `routes_set_start_point` trigger to read user_settings* is the right v2 fix for the nearby-routes leak (see below) — same `security definer` pattern, just different call site.

There's a residual attack: a determined caller can pass a dense synthetic point grid to the RPC and recover zone geometry from the clip output. Mitigations: input length bounded to a reasonable track size; the RPC is auth-required (anonymous shares stay unclipped today, which is a separate v2 follow-up to add anon-callable + rate-limited variant). For a casual-privacy threat model — which is what `privacy_zones` is for, distinct from a stalking threat model — this is acceptable.

**Trade-offs we're explicitly accepting:**

1. **`routes.start_point` leak.** The `routes_set_start_point` trigger populates a PostGIS `geography(Point)` column from the first waypoint, indexed for the `nearby_routes` RPC. A route built from home will surface in proximity searches centered near home — the polyline is clipped, but the dot on the map isn't. v2 fix: trigger reads `user_settings.prefs.privacy_zones` (security-definer indirection) and snaps `start_point` to the first non-zone waypoint, or to `null` if every waypoint is in a zone. We document the gap rather than ship a half-fix.
2. **Owner-self-share visibility.** When the run owner opens their own `/share/run/[id]` (e.g. testing a share link), they see the clipped version. Strava behaves the same way — the share page is "what your followers see," and being able to verify that is the whole point.
3. **Elevation profile retains in-zone points.** The profile is per-distance, not per-coordinate, so it leaks no location info; we keep it complete to avoid a confusing "elevation drops off cliff at end" rendering artifact.

**Don't re-litigate unless:** users report routes built from home leaking through nearby search (then ship the trigger update), zones-per-user grows past ~5 in real usage (then promote to a `privacy_zones` table with its own RLS), or a third-party integration (Strava export, etc.) needs the *unclipped* track for sync purposes (then add a "Sync without privacy zones" toggle on the integration settings).

---

## 34. Training-load curves: client-side compute, server-side persistence, opportunistic stress score

**Decided:** April 2026 · captured before the dashboard widget lands.

TrainingPeaks invented the Fitness / Fatigue / Form trio (CTL / ATL / TSB) on top of a per-workout training stress score. The math is well-known and Strava Premium copies it. We have `fitness_snapshots` already (migration `20260507_001`), but no UI and no server-side recompute job. Shipping the widget today doesn't require either piece — we compute on the client from `runs`, render a chart, and *opportunistically* persist a snapshot so the trend builds up at the right pace even when the recompute job lands later.

**Stress score:** the canonical inputs are HR (Banister TRIMP) and power (Coggan TSS); runners without a power meter and often without HR straps need a fallback. We use a three-tier ladder:

1. **Banister TRIMP** when `runs.metadata.avg_bpm` is set *and* the user has `resting_hr_bpm` + `max_hr_bpm` in `user_settings.prefs`. Standard formula with the male-default 1.92 weighting; close enough for v1.
2. **GAP-adjusted distance proxy** when there's no HR. `stress = distance_km × 10` — calibrated so an easy 5k ≈ 50 (one ATL/CTL "unit"). Tempo/threshold runs would score higher under TRIMP, but in the absence of HR we'd be guessing intensity from pace alone, which over-rewards short fast sessions and under-rewards long easy ones in opposite directions. The flat distance proxy is honest about the missing input.
3. **Skip** when neither distance nor duration is set — synthesis-only rows (`activity_type: 'manual'` with `0` distance) shouldn't move the curves.

**EWMA shape:** alpha = `1 − exp(−1/halflife_days)`, halflife = 7 days for ATL, 42 days for CTL, TSB = CTL − ATL. We compute *daily* aggregated stress (sum of stresses on each calendar day in the user's local tz) and run the EWMA over 90 days of history. Days with no run still tick — the EWMA naturally decays without an entry. Calendar-day aggregation is the right unit because the chart renders at daily resolution; running the EWMA on raw runs would just double-apply same-day workouts.

**Why client-compute and not the recompute job:**

- *Server-side recompute on every run insert* is the right architecture but blocked on the Edge Function infra we don't have wired (the same blocker as the push notification path in parity.md). The migration `20260507_001` already provisions the table; the job is forward-compatible.
- *Pre-aggregating daily stress in a table* is a useful optimisation when N gets large, but at 1 run/day for 90 days the client computation is ~90 EWMA steps — under a millisecond. Premature.
- *Reading the existing snapshots and only computing the gap* is tempting but means a fresh user with no snapshots gets nothing; computing from runs always works.

**Opportunistic persistence:** on each dashboard load we call `insertFitnessSnapshot` with today's computed numbers. The existing guard ("only persist when qualifying_run_count ≥ 3") prevents noise spam. Once the recompute job ships, it can keep writing to the same table on the same shape; the client-write becomes a "fallback if the server hasn't run today yet."

**Why these and not alternatives:**

- *Power-based TSS only* — irrelevant; runners almost never have power meters.
- *Pure pace-based intensity factor* — too noisy in practice (a 5k race is ~95% IF, but a hill rep on a steep grade can score higher than threshold pace would imply). HR-based or distance-based is more honest.
- *Show the three numbers without the chart* — kills the value. The shape of the curve over a build / taper cycle is the whole insight. Numbers without trend are noise.

**Trade-offs:**

1. **Without HR data, the score is distance-only.** A 10k race scores the same as a 10k easy run. Users with HR straps get a more accurate picture; users without get a "training volume" curve which is still useful for spotting overreach. We label the chart with a hint when no TRIMP-eligible runs exist in the window.
2. **Client-side recompute means the chart can disagree with persisted snapshots.** When the algorithm changes (e.g. swap Banister for Edwards), today's chart won't match yesterday's stored snapshot. We accept that — `fitness_snapshots.source = 'client'` is already a known-honest column.
3. **No back-fill of historical days.** We only insert a snapshot for *today* on dashboard load. Reconstructing the curve at any past date requires re-running the math from `runs`, which is what the chart does anyway.

**Don't re-litigate unless:** the recompute job lands (then the client should defer to the server's snapshots when fresh), users start needing the curve on mobile (port `training_load.ts` to Dart), or someone in the cohort gets a power meter (add a `metadata.power_avg_w` branch ahead of HR in the stress ladder).

---

## 35. Plan templates: same shape as club-owned routes; clone-on-adopt, not subscribe

**Decided:** April 2026 · captured before the templates migration.

A plan today is owned by exactly one user. A coach managing 50 athletes ends up either editing 50 copies by hand or living in their head. The right shape is a *template* — a canonical plan that backs many user instances. We use the same pattern decisions §30 (club-owned routes) ships, transposed onto `training_plans`.

**Schema:**

- `training_plans.is_template boolean default false` — flips a row from "instance owned by `user_id`" to "template authored by `user_id`."
- `training_plans.parent_template_id uuid references training_plans on delete set null` — populated on instances that were cloned from a template. ON DELETE SET NULL because we don't want to delete a runner's executed plan history just because their coach tidied up the template.
- `training_plans.club_id uuid references clubs on delete cascade` — when set, the template is club-owned (any club admin can edit, any member can read and clone).

**RLS additions** layer onto the existing self-only policies:

- *Club members read club templates*: `for select using (is_template = true and club_id is not null and is_club_member(club_id))`.
- *Club admins write club templates*: `for all using (is_template = true and club_id is not null and is_club_admin(club_id))`.

The dependent tables (`plan_weeks`, `plan_workouts`) had `user_id = auth.uid()` in their EXISTS subqueries; we relax those to plain `exists (select 1 from training_plans p where p.id = ...)` so the parent's RLS evaluates correctly. A subquery against another table respects that table's RLS, so a user who can SELECT the parent template can transitively SELECT its weeks and workouts.

**Adopt = clone, not subscribe.** A `clone_plan_template(template_id uuid, start_date date) returns uuid` SECURITY DEFINER RPC duplicates the template's `training_plans` + `plan_weeks` + `plan_workouts` into a new instance owned by the caller, anchored to a chosen `start_date`. We pick clone-not-subscribe deliberately:

- *Subscribe* (athletes share the same row, see edits live) tangles authorship: the coach edits Tuesday's workout, every athlete's history mutates, schedules already past get re-written.
- *Clone* freezes a copy at adoption time. The coach can keep evolving the template; existing instances are unaffected. New athletes who clone *now* get the latest version. Same model GitHub forks use, and the same model `saved_routes` uses (one canonical row, many references).

**Where templates surface:**

- `/clubs/[slug]` gains a Templates section under the existing Routes tab pattern. Admins create / edit / delete templates here.
- `/plans/new` gets a "Start from a template" picker showing the user's club templates (and eventually public ones — out of scope for v1). Selecting a template + a start_date calls the clone RPC, then redirects to `/plans/[id]` of the new instance.
- The `instance.parent_template_id` link is exposed on the plan-detail page as a small chip ("Cloned from Aliens Marathon Build" linking back to the source) — context for the runner, with no live coupling.

**Why these and not alternatives:**

- *Subscribe model with live edits* — wrong shape. See above.
- *Templates as a separate `plan_templates` table* — duplicates the entire plan_weeks / plan_workouts shape. Same maintenance burden as the routes problem we already solved with a single `is_template` flag on the existing table.
- *Public template library (no club required)* — additive and shippable later; the column shape (`is_template + is_public`) is forward-compatible. Not in v1.

**Trade-offs:**

1. **No live updates from template to instance.** A coach who fixes a typo in week 5 has to ask runners to "re-clone" or fix it in their copies. Acceptable: the alternative is debugging "the schedule changed under me" support tickets.
2. **A template counts toward the user's plan list** unless we filter on `is_template = false` everywhere. We do — every existing fetcher and the `/plans` page get an `is_template = false` filter. Templates are reachable only through their owning club's surface.
3. **`training_plans_one_active` partial unique index** is on `where status = 'active'`. Templates don't get `status = 'active'` (they're inert authoring rows), so the index naturally excludes them. We add a CHECK to be explicit: `is_template = false OR status <> 'active'`.

**Don't re-litigate unless:** users ask for live propagation of template edits (then add an opt-in subscribe path that turns on a trigger), public templates become a real ask (add `is_public` and a `/templates` discovery surface), or coaches start needing per-athlete pace overrides on a template (then `parent_template_id` graduates to a "fork-with-overrides" model — a much bigger change).

---

## How to add an entry

1. Append below, numbered in sequence.
2. Lead with what was decided, then *why*, then the *trade-off*, then when not to re-litigate.
3. Cite the migration, commit, or PR that captures it if there is one.
4. Keep it short — one screen or less. If it's longer than that, it probably belongs in `architecture.md` or its own deep-dive doc, with a pointer from here.
