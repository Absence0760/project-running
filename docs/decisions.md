# Architecture decisions

Short records of non-obvious choices that the code alone doesn't explain. Reach for this before proposing something that's already been considered and rejected.

This is not a strict ADR template — each entry is a few paragraphs: what we decided, why, and what we traded away. Append new entries to the bottom; don't rewrite history. Date them when you know the date.

---

## 1. Both watches are native: Apple Watch is Swift / SwiftUI, Wear OS is Kotlin / Compose-for-Wear

**Decided:** Phase 2 planning (Q1 2026 · see [roadmap.md](roadmap.md)). The Wear OS half was originally Flutter; reversed in §15 below — keeping this entry to record the original framing and what changed.

Apple Watch was always going to be native Swift. Flutter's watchOS support is a non-starter for a first-class running computer — the build target isn't stable, widget-tree costs are too high under a workout, and the native health frameworks (HealthKit, CoreLocation, WKWorkoutSession) are only reachable through channels we'd have to write ourselves. SwiftUI / WatchKit is the path everyone else takes and it's the only one that lets the watch run standalone GPS sessions without the phone.

Wear OS originally shipped as Flutter on the assumption that Compose interop was good enough and that we'd reuse `core_models` + `api_client`. In practice the Flutter-on-Wear surface dragged on framework upgrades, made tile / complication work awkward, and the schema-typed Dart `RunRow` had to be re-derived in Kotlin anyway. **§15 reversed this** — Wear OS is now pure Kotlin + Compose-for-Wear, with `RunRow` regenerated from the same Supabase migrations as Dart's `db_rows.dart` via `scripts/gen_dart_models.dart`. Read §15 for the move and the trade-offs.

**Trade-off:** Two native codebases now (`apps/watch_ios/` Swift, `apps/watch_wear/` Kotlin) with their own networking, auth, and Supabase clients. Acceptable because the watch scope is intentionally small (record + navigate + sync) and the schema codegen keeps the row-shape contract enforced at compile time on both sides.

**Don't re-litigate unless:** Flutter ships a production-ready watchOS target *and* a similarly stable Wear OS target *and* the schema-codegen story works across both — at which point unifying back into Dart could be reconsidered. None of those are imminent.

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

The gate infrastructure stays in place — `GATED_FEATURES` registry, `ProGate` component, `isLocked()` function, `subscription_tier` column, `is_pro()` SQL helper, and the RevenueCat webhook. But `isLocked()` always returns `false` so nothing is actually locked. The AI Coach's cost is managed via a daily usage limit (5 messages/user/day, enforced by `increment_coach_usage` RPC) instead of a paywall.

**Why:** A paid tier before product-market fit creates friction that slows user acquisition. Donation funding lets early adopters use everything while signalling what the app costs to run. If the user base grows large enough that donation income can't cover API costs, re-gating specific features is a one-line change in `isLocked()`.

**Trade-off:** No revenue guarantee. Donations are unpredictable and the Claude API bill scales with usage. The 5-message daily cap on the coach is the cost-control mechanism — if it proves insufficient, either lower the cap or re-gate the coach behind Pro.

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

- **Unlimited AI Coach.** The 5 / day cap still applies to the free tier (cost control); Pro users bypass it. Server-side enforcement lives in `/api/coach/+server.ts` via the no-arg `is_pro()` RPC (the predecessor `is_user_pro(uuid)` was dropped in `20260516_001` because it took a user-id argument and let any authenticated caller probe another user's tier).
- **Priority processing.** Pro requests are routed ahead of the free queue at rate-limit boundaries. Today this is a marketing claim with no enforcement beyond the unlimited-coach bypass; concrete enforcement (Edge Function queue priority, client throttle hints) lands as needed.

The `/settings/upgrade` page replaces the transparent funding page with a two-card layout: a Pro plan card ($9.99/mo, feature bullets, "Get Pro" CTA) and a single "Donate" card linking to an external one-off payment provider. Cost breakdown, per-month progress bars, donor count, and the tiered donation buttons are gone — those stats were a nice-to-have that didn't move conversion.

Infrastructure from #18 is largely reusable: the `GATED_FEATURES` registry, the `is_pro()` SQL helper, the `subscription_tier` column, the RevenueCat webhook, and the `user_coach_usage` table all stay. The only registry change is renaming `priority_sync` → `priority_processing` with broader copy. The `monthly_funding` table stays in place (orphaned but not dropped); if transparency becomes a differentiator later it's a one-migration revival.

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

## 27. Product renamed from "Better Runner" to "Run Onward"; bundle IDs follow

**Decided:** April 2026 (display rebrand). **Revised:** May 2026 (bundle IDs aligned).

The user-visible product name is **Run Onward** (URL: `runonward.com`). All display strings — Android `android:label`, iOS `CFBundleDisplayName` / `CFBundleName`, watchOS health-permission usage strings, web `<title>` + meta + share-card chrome, GPX `creator=` attribute — match. The Android `applicationId` + Kotlin package directory + iOS `PRODUCT_BUNDLE_IDENTIFIER` are now also `com.runonward.com`, and the WorkManager task name is `com.runonward.backgroundSync`. `BACKUP_FORMAT` stays `'run-app-backup'` since changing it would break restore of any local backup blobs already exported during the dev cycle.

**Why:** "Better Runner" was running-only branding for a multi-modal app (run + walk + hike + cycle). "Run Onward" reframes the verb as forward movement rather than jogging, and `runonward.com` was the rare clean `.com` left in the running-adjacent namespace (most short slang `.com`s are squatted on Afternic).

**Why the revision:** the original April 2026 decision deliberately kept the bundle ID at `com.betterrunner.app` to preserve the Play Store / App Store upgrade path. We later confirmed there are no published builds yet — pre-launch was the free window to align internal identifiers with the rebrand. Once published, the rule from the original ADR holds: **never change the bundle ID afterwards**, since that creates a new app listing with no upgrade path, breaks deep links, and forces signing-key reassociation. Twitter→X kept `com.atebits.Tweetie2` long after their rebrand for exactly this reason.

**If we re-rebrand later:** changing the bundle ID post-launch is a clean-break new app listing — new Play Store / App Store entries, deep-link migration, user re-install, signing-key reassociation. The WorkManager task name and backup format would need a coordinated migration (orphaning old scheduled tasks and breaking old backups respectively).

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
- **SECURITY DEFINER `current_setting('request.jwt.claim.role', true)` ≠ effective role.** When a trigger function tells "is the caller a service-role bearer?" apart from "is the caller a regular user?", the safe signal is `current_setting('request.jwt.claim.role', true)`, not the session's `current_user`. SECURITY DEFINER swaps the executing role to the function owner regardless of who triggered the SQL, so `current_user` would always say `postgres` and the gate would always open. The empty-string fallback (`coalesce(..., '')`) covers the direct-SQL / pgtap path where no JWT claim is set; both are trusted because they come in via the service-role connection or `psql -U postgres`. The pattern is in `lock_subscription_columns()` (migration `20260624_001`) — copy that shape, not a `current_user` check, when adding any future column-immutability trigger that needs to thread the service-role exception through SECURITY DEFINER.

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
- **`/feed` route** — recent public runs from people the caller follows, time-windowed to the last `FEED_WINDOW_DAYS` (14) days so the feed reads as "what's new lately" rather than a chronological backlog dump. Cursor-paginated on `(runs.started_at desc, id desc)` to stay stable as new runs arrive. Pull-based (no realtime) — the engagement value of "instant" on a feed is low and adding `runs` to the realtime publication has a fan-out cost we don't need yet. The window cutoff also means following someone with a long history doesn't fire-hose your feed; older runs remain accessible via the runner's `/u/[id]` profile.

**Public-profile read access requires a schema-level shift.** Today `user_profiles` has one RLS policy: `auth.uid() = id`. That's been silently breaking cross-user enrichment (`enrichPosts`, `fetchClubMembers`, etc. — they query `user_profiles` for other users' display_name and get empty rows back). The follow feature *requires* cross-user reads, so we add a public-read policy and accept that `subscription_tier` and `parkrun_number` become world-readable to authenticated users. `subscription_tier` is already effectively public via the "Pro" badge any UI would show; `parkrun_number` is a public ID people share themselves. If a future user objects, the right fix is a column-level GRANT REVOKE pattern (decision §29's "column-level GRANTs for write immutability" applied to reads) — not row-level RLS.

**Why these and not alternatives:**

- *Follower approval (Twitter "private account")* — meaningful UX cost (request flow, pending state, privacy UI) for a problem we don't have yet. Default to open and add private profiles later as a single-row toggle.
- *Mutual-follow / friendship model* — collapses two relationships into one and forces both parties' consent. Wrong for "I want to see this elite runner's training" — Strava's asymmetric follow is correct here.
- *Reuse `club_members` for follows* — a club is a *thing*; following another runner is not. Overloading the table forces awkward synthetic clubs ("Jared's followers") and ties the feed query to club-permission RLS.
- *Server-side push on new runs from followed users* — engagement-positive but blocked on `VAPID_PRIVATE_KEY` (parity.md notes the gap). Out of scope for the v1 ship.

**Trade-offs:** (1) UUID URLs are uglier than handles; we accept that for v1 because handle reservation is a non-trivial design choice (case sensitivity, reserved words, length, change history). (2) The feed is purely pull-based — a runner who opens it twenty seconds after a friend uploads gets nothing until they refresh; we accept that because realtime on `runs` would fan out widely and we have no engagement signal that justifies the cost. (3) `user_profiles` is now world-readable to authenticated users; that's a small privacy widening accepted in exchange for fixing the existing enrichment bug.

**Don't re-litigate unless:** users start asking for handles (then add `user_profiles.handle` with a normalisation function), private profiles become a real ask (single-column toggle plus an RLS predicate on the public-read policy), or someone needs the feed instant (then enable realtime on `runs` with a `is_public` filter). Each of those is a forward-additive change — none requires undoing what we ship now.

**`user_follows` SELECT scope (re-affirmed 2026-05-07).** /audit/all flagged that the SELECT policy `auth.role() = 'authenticated'` makes the entire follow graph + every `followed_at` timestamp readable by any signed-in user. This is **intentional** and matches how Strava / Nike Run Club / Garmin Connect ship the same surface — followers / following lists on a profile page are the canonical "who is this runner" affordance. The trade-off cost is that someone harvesting the graph can reconstruct social-formation timelines (when X followed Y); the benefit is the entire `/u/[id]` follower-list UI works without a SECURITY DEFINER fan-out RPC. **First gate to flip if private profiles are ever added** — the new RLS predicate on the SELECT policy is `using (auth.role() = 'authenticated' and not is_private(followee_id))` plus the symmetric branch for the follower. Until then, leave it open.

---

## 32. Kudos + comments on runs; visibility tracks runs' own RLS

**Decided:** April 2026 · captured before the migration that adds `run_kudos` and `run_comments`.

The activity feed shipped in §31 needs an engagement loop. Strava's pattern — kudos (one-tap heart), then comments (free-form text with one level of threading) — is the canonical answer; copying it directly is the right call. We resist two adjacent product temptations:

- *Rich reactions (👏 / 🔥 / ⚡)* — Slack-style multi-emoji reactions look fun but every additional emoji dilutes the signal. Strava ships only kudos because "did you appreciate this run, yes/no" is the only question that scales. Multi-emoji is also a strict superset of kudos and can be added later by widening the `run_kudos` table with a `reaction text` column; we don't pre-build for it.
- *Multi-level threading* — replies-to-replies-to-replies is a moderation nightmare and the one-level cap (Reddit calls this "shallow threading") matches the existing `club_posts` precedent (`parent_post_id` only, no recursion in the data model). UI enforces it by hiding the reply affordance on already-replied comments.

**Schema:**

- **`run_kudos (user_id, run_id, given_at)`** — composite PK so a user can only kudos a run once. ON DELETE CASCADE on both sides. No `id` column; the natural key is the relationship itself.
- **`run_comments (id, run_id, author_id, parent_comment_id, body, created_at, updated_at)`** — `parent_comment_id` is a self-FK (nullable). One level of nesting is enforced in the INSERT policy. The original `with check (parent_comment_id is null or (select parent_comment_id is null from run_comments where id = parent_comment_id))` shape produced `infinite recursion detected in policy for relation "run_comments"` on every authenticated insert: PostgreSQL's RLS planner flags any policy that selects from its own table as recursive even when the runtime graph is acyclic. Migration `20260529_001` lifts the depth check into a SECURITY DEFINER helper (`_run_comment_parent_is_top_level(uuid)`) so the policy graph no longer self-references. `body` is CHECK-constrained to 1..2000 chars to keep an `<input maxlength>` honest.

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
- *Mobile `public_run_screen` and `public_route_screen`* — Flutter mirrors of `/share/run/[id]` + `/share/route/[id]`. Same gate: viewer id read from `api.userId`, anon (`null`) treated as non-owner. The RPC is shared (`clipTrackForUser` in `packages/api_client`), so a future change to the SECURITY DEFINER body covers web and mobile in lockstep.
- *Feed thumbnails* (web `RunTrackPreview.svelte`, mobile `widgets/run_track_preview.dart`) — the per-card preview always clips for non-owners. Cache key is prefixed `raw:` vs `clip:` so an owner viewing their own card and a follower viewing the same card don't pollute each other's session cache.
- *`/live/{run_id}`* — the live-spectator surface streams `live_run_pings` over Realtime to anonymous viewers. Pings can't be clipped at render time the way the durable track is, because the table fires Realtime on `INSERT` and a client-side filter would still leak the unclipped point through the broadcast envelope. Instead, a `BEFORE INSERT` trigger on `live_run_pings` (`live_run_pings_drop_in_zone`, migration `20260618_001`) calls `privacy_in_any_zone` against the runner's zones and returns `null` for any in-zone ping — the row never lands, so Realtime never broadcasts it. The trigger is `SECURITY DEFINER` with `search_path = public, extensions` so it can read the runner's `user_settings` and reach the PostGIS `geography` type that `privacy_distance_m` uses. Trade-off: the runner watching their own `/live/{run_id}` also won't see in-zone pings, which is acceptable — the surface is for spectators and the durable track is recorded unclipped to Storage for the runner's own `/runs/[id]` view.

**Why a SECURITY DEFINER RPC, not pure-client clipping:**

The naive shape ("just fetch the owner's `privacy_zones` and clip on the client") leaks the zones — defeating the whole point. Public viewers can't be trusted with the zone polygons. So the actual implementation is a `clip_track_for_user(target_user_id, points jsonb)` SECURITY DEFINER RPC that reads zones internally and returns only the clipped output. Zones never cross the wire to a non-owner.

- *Server-side clipping at insert / update time* is destructive — the owner can't get their full track back after toggling a zone off. RPC at render time is reversible by definition.
- *Pre-storing two Storage objects per run* (full-fidelity owner-only + pre-clipped public) is the right v3 architecture, but doubles storage and forces the recorder/uploader to know about zones. Future work.
- *Modifying the `routes_set_start_point` trigger to read user_settings* is the right v2 fix for the nearby-routes leak (see below) — same `security definer` pattern, just different call site.

**The Storage download path: an Edge Function for non-owners (added retroactively).** The original ADR sketched clip_track_for_user as a single SECURITY DEFINER RPC and assumed every render site would call it on the points it received. The 2026-04 wave of clients (web `RunShareView`, mobile `public_run_screen`, the thumbnail components, the route share page) followed that pattern: fetch the gzipped blob from Storage via `fetchTrackByPath`, then pass the resulting points through `clip_track_for_user`. An `audit/storage` sweep (June 2026) found this leaked the unclipped blob: anyone reading `runs.track_url` from the public-runs SELECT policy could replicate just the Storage download (`supabase.storage.from('runs').download(path)`) and skip the RPC, getting every point inside the owner's privacy zones. Migration `20260619_001` dropped the `Anyone can read tracks of public runs` Storage policy, and a new `clip-public-track` Edge Function handles non-owner reads server-side: it downloads the blob via service-role, runs `clip_track_for_user` inside the function, and returns clipped points. Owner downloads keep the original direct path because the per-user-folder Storage policy from `20260410_001` still grants `(storage.foldername(name))[1] = auth.uid()::text`. Every client surface that previously did "fetchTrackByPath then clipTrackForUser" now does "owner: fetchTrackByPath; non-owner: fetchClippedTrackForRun" — the clip step never runs on the client side, and the unclipped bytes never cross the wire to a non-owner.

**The wire-leak follow-up: the `public_runs` view (added 2026-06).** A pre-prod public-rows audit caught a class of leaks the `is_public = true` SELECT policy on `runs` opens by default: `external_id` (which for imported runs encodes `strava:<activity_id>` / `parkrun:<event>:<date>` / `garmin:<file_id>` and links the share link to the runner's third-party account permanently), the entire `metadata` jsonb bag (which carries audit-only `imported_from` / `*_id` / `*_activity_type`, sync-state `last_modified_at`, recorder internals like `recovered_from_crash`, and — most consequentially — training-plan-linkage keys `plan_workout_id` / `workout_step_results` / `workout_adherence` that expose the runner's structured-workout paces and adherence to anyone with a share link), plus link-existence leaks via `route_id` / `event_id` (a public run linked to a private route or private-club event proves attendance/ownership even though RLS hides the joined row). Migration `20260626_001_public_runs_view.sql` adds a `public_runs` view that omits `external_id` entirely, applies a denylist over `metadata`, and nulls `route_id` / `event_id` when the joined target isn't itself public (via two SECURITY DEFINER helpers `is_public_route_by_id` / `is_public_event_by_id`). The view is granted to `anon` + `authenticated` and is the canonical client read path for public runs — every web `fetchPublic*` helper and the mobile `api_client.fetchPublicRunById` / `fetchPublicRunsByUser` / `fetchFollowingFeed` switched in the same change. Architecture-guard tests on both web and mobile assert no public-runs reader regresses to the bare table. The base-table `public runs are readable by anyone` policy was dropped in `20260701_001_drop_runs_public_select_policy.sql` once every public-runs reader was confirmed on the view: the migration adds a SECURITY DEFINER `is_run_visible_to(run_id, user_id)` helper (mirrors `is_route_visible_to`) and rewires the five dependent policies (`run_kudos` SELECT/INSERT, `run_comments` SELECT/INSERT, `run_photos` SELECT, `segment_efforts` SELECT, `live_run_pings` SELECT) to call the helper instead of the runs-EXISTS subquery, then drops the policy. Direct PostgREST `from('runs')` reads of public rows now return zero — the view is the only public path. Owner reads, owner writes, and the public_runs view continue to work unchanged.

**Routes use a parallel RPC, not the EF (added 2026-06).** Routes carry `waypoints` inline as a jsonb column on the `routes` row, unlike runs whose tracks live in Storage. So the same "render-site clip" pattern needed a different shape: a SECURITY DEFINER `clip_route_for_viewer(p_route_id)` RPC that visibility-gates internally (mirroring the routes RLS — owner / public / club member, raises 42501 otherwise) and returns either unclipped waypoints (owner) or clipped output (non-owner, delegated to `clip_track_for_user` so the zone walk has one implementation). Migration `20260625_001_clip_route_for_viewer.sql`. Pre-prod privacy-zones audit caught six leak surfaces — three on web (`/routes/[id]`, `/routes` My-routes tab, `/clubs/[slug]` Routes tab) and four on mobile (`route_detail_screen`, `routes_screen`, `club_detail_screen` Routes tab, `explore_routes_screen`); web's `RouteTrackPreview` and mobile's `route_track_preview.dart` are the new lazy-fetch wrappers (analogous to the runs `RunTrackPreview` shape with the same `raw:` vs `clip:` cache prefix). Wire-leak caveat: `select * from routes` from a non-owner perspective still returns the row with `waypoints` populated. Closing that requires either a `public_routes` view-projection or column-level grants — tracked as a follow-up alongside the public-rows audit findings; the visible-render leak the privacy-zones audit flagged is what these RPCs close. The migration also fixed a forward-compat hole on the original 20260523_001 helpers: `privacy_distance_m` and `privacy_in_any_zone` were declared `set search_path = public` only, which works in production because the calling role's default path includes `extensions` (PostGIS) but breaks under direct-SQL callers like seed.sql; the helpers are now `set search_path = public, extensions`.

There's a residual attack: a determined caller can pass a dense synthetic point grid to the RPC and recover zone geometry from the clip output. Mitigations: input length bounded to 50 000 points (caps the work for the residual probe). The RPC is granted to `anon` and `authenticated` — anonymous public-share callers are clipped via the same path. Every render site treats `viewerId == null` as non-owner so unauthenticated traffic gets the same clip pass authenticated traffic does. The earlier ADR draft contemplated keeping the RPC auth-only and shipping an anon-callable + rate-limited variant later; we collapsed that into the single grant + the `audit/rls` caller gates. For a casual-privacy threat model — which is what `privacy_zones` is for, distinct from a stalking threat model — this is acceptable.

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

## 36. Photos on runs: own table + Storage bucket; visibility tracks the parent run

**Decided:** April 2026 · captured before the photos migration.

A run is more than the GPX — Strava's "attach a photo" is core to how runners tell the story of a workout. We add it as a separate `run_photos` table (id, run_id, owner_id, storage_path, caption, position_idx) plus a dedicated `run-photos` Storage bucket. RLS layers the same way as kudos and comments (§32): visibility tracks the parent run via an EXISTS subquery on `runs`.

**Two-table shape (DB metadata + Storage bytes):** the `run_photos` row stores everything queryable (caption, ordering, ownership) and a `storage_path` pointer; the bytes live at `run-photos/{user_id}/{photo_id}.{ext}` in Storage. This separation matches `runs.track_url` + the gzipped JSON in the `runs` bucket. We deliberately don't put bytes in the DB and we don't store URLs (which would expire on signed-URL rotation) — clients call `getPublicUrl` or `createSignedUrl` against the path at render time.

**Bucket policy:** the `run-photos` bucket is public-read so the share page works for anonymous visitors. Writes are gated by Storage RLS to `auth.uid()::text = (storage.foldername(name))[1]` — the same per-user-folder pattern the existing `runs` bucket uses. There's no "is this run actually public" check at the bucket layer because the photo URL contains the photo UUID; non-enumerability is the same security primitive that already protects the `runs` Storage bucket.

**Why these and not alternatives:**

- *Embed the photo path in `runs.metadata`* — fine for one photo, terrible for many. We'd lose ordering, captions, per-photo author (a future "anyone in the club can attach a photo to a public race run" feature), and the ability to delete a photo without rewriting the runs row.
- *Photos in `runs.metadata` + thumbnails in Storage* — partial-information shape; same problem.
- *Use the existing `runs` Storage bucket* — has the right per-user-folder RLS but its objects are private (signed URL only). Photos want fast public render, which means a separate bucket configured public-read.
- *Polymorphic `media (parent_table, parent_id, storage_path)`* — premature; we don't have other media surfaces yet. Promote the moment we add club_photos, route_photos, etc.

**Trade-offs:**

1. **No automatic thumbnail generation.** Clients render the original. We size the upload to 4 MB max and document that as the price of skipping a thumbnail pipeline. Storage egress is the only meaningful cost; on a public bucket through Supabase's CDN it's negligible at our scale.
2. **No EXIF stripping.** Phones may embed GPS coordinates in EXIF that survive upload. We document this in the upload UI ("photos may include location data — strip in your camera app first if a privacy zone matters") and accept the gap. v2 fix: a server-side Edge Function that re-encodes on upload.
3. **`owner_id` always equals `runs.user_id`** in v1. The schema separates them so a future "anyone in the club can attach a photo to a club event's race run" feature is forward-compatible without a migration.

**Don't re-litigate unless:** photo bandwidth becomes the dominant Storage cost (then add server-side thumbnail generation), users ask for video clips (different bucket, different MIME policy, probably a separate `run_videos` table), or someone reports an EXIF leak (then ship the EXIF-strip Edge Function).

---

## 37. Segments v1 are slices of a saved route, not arbitrary geometry

**Decided:** April 2026 · captured before the segments migration. A deliberate radical scope cut from the Strava-class shape.

The full Strava model is hard: an arbitrary polyline anywhere on Earth becomes a segment, and every uploaded run gets matched against every nearby segment via a server-side geometric scan (Hidden Markov path matching, or Hausdorff distance, or both). That's months of work and a real R&D problem. Most of the *user value* shows up the first time you can race your own past time on a defined stretch of road — so we ship that with a much smaller mechanism, and keep the door open for arbitrary-geometry segments as v2.

**v1 scope:** a segment is a named slice of a *saved route* — `(route_id, start_distance_m, end_distance_m)`. An effort is auto-created when a `runs` row is inserted with the matching `route_id`. The effort time is extracted by walking the run's track once: cumulative distance is computed point-to-point, and the timestamps at the start_distance_m and end_distance_m crossings are recorded. Leaderboard is `select * from segment_efforts where segment_id = X order by time_seconds asc`.

**Schema:**

- `segments (id, route_id, name, start_distance_m, end_distance_m, length_m, created_by, created_at)` — `length_m` is a `generated always as (end_distance_m - start_distance_m) stored` column so the leaderboard query saves a subtraction without risking drift. There's no `is_public` flag — visibility is inherited from the parent route via RLS (an EXISTS subquery), so a segment on a public route is public-readable and a segment on a private route stays private.
- `segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)` with `unique (segment_id, run_id)` so a re-import doesn't double-count.

**RLS:** segments inherit visibility from the parent route (EXISTS-on-routes — same shape as kudos, comments, club routes). Efforts inherit from the segment + the underlying run, joined: `select 1 from segments s join runs r on r.id = segment_efforts.run_id where s.id = segment_efforts.segment_id`. Public route → segment is public-readable; private route → only the owner sees it.

**Auto-effort generation:** an `AFTER INSERT` trigger on `runs` calls a SECURITY DEFINER function `compute_segment_efforts_for_run(run_id)` which (a) finds segments matching the new run's `route_id`, (b) downloads the track from Storage *server-side via pg_net* — except we don't have pg_net wired and downloading from Postgres is gross — so instead, the trigger does nothing. The client computes efforts after a successful run upload and INSERTs them via the regular RLS-gated path. **Auto-effort generation is client-side in v1**, called from `saveRun` after the row + track are persisted. Document the gap: "if a user inserts runs via SQL bypass or a third party syncs a run, efforts won't auto-create until the user opens the run detail page once, which triggers a compute."

**What's deliberately not in v1:**

- *Arbitrary-geometry segments* (segment polyline, not tied to a route). Postpones the matching problem.
- *KOM / QOM / leaderboard tiering* (sex / age-group buckets). Single linear leaderboard.
- *Real-time effort during a run* — execution requires the recorder to know about segments mid-run. Out of scope.
- *Star / favourite a segment* — additive whenever it's worth shipping.
- *Premium gating.* Strava puts segment leaderboards behind Strava Pro; we don't gate v1 because we don't have the volume yet.

**Trade-offs:**

1. **Two runs of the "same" course on different `routes` rows don't share a leaderboard.** That's the dual of the `saved_routes` reference pattern from §30 — the leaderboard is per-route, and route-deduplication is a separate problem. If two clubs each upload "the Richmond Marathon course" as their own route, each gets its own segment leaderboard. The bookmark mechanism mitigates this for casual users (most will save-not-clone the canonical row); for race-org runs the canonical-route concept from §30 already points the right way.
2. **Effort time is only as accurate as track sampling.** A run with 1Hz GPS gives sub-second segment resolution; a 10s sampling rate makes a 30s segment nearly unmeasurable. We document this and skip auto-effort if `length_m / median_sample_distance_m < 5`.
3. **Client-computed efforts mean a stale browser tab can't refresh someone else's leaderboard live.** Acceptable — pull-based leaderboard refresh on tab focus is fine.

**Don't re-litigate unless:** users start asking for arbitrary-track segments (then this gets the "real" geometric matching engineering investment), KOM-style age/sex leaderboards become a real ask (segment_efforts already has `user_id` and a profile lookup; just split the query), or volume on a popular segment makes the linear leaderboard slow (paginate).

---

## 38. Notifications inbox is a `notifications` table fed by SECURITY DEFINER triggers

**Decided:** April 2026 · captured before the migration.

The social loop (kudos, comments, replies, follows) was discoverable only by visiting each surface and noticing new state. A central inbox that aggregates "who did what" + a per-user unread count is the standard fix. Two design questions: (1) materialise notifications as rows or compute on the fly, (2) populate from server-side triggers or client-side after the action.

**Decided:** materialise as rows + populate via triggers.

- *Materialise* — the alternative ("fan out at read time by `union all`-ing run_kudos, run_comments, user_follows … filtered by recipient") is appealing because it has no schema cost, but it ties the unread badge query to the count of all engagement events on your runs forever. A `select count(*) from notifications where user_id = $1 and read_at is null` against a partial index is O(unread), which is what the bell badge actually wants. Storage cost is small (one row per kudos/comment/follow you receive), and we keep cascade-delete on the source FKs so cleanups happen automatically.
- *Triggers* — the alternative ("create a notification client-side after each kudos/comment/follow insert") splits the truth across N codepaths and gets out of sync the moment Android gives kudos via the REST API directly. SECURITY DEFINER `after insert` triggers on `run_kudos`, `run_comments`, and `user_follows` write the row in the same transaction as the source write, so a kudos either lands with its notification or both fail.

**Schema:** `notifications (id, user_id, actor_id, kind, run_id, comment_id, read_at, created_at)` with `kind ∈ {kudos, comment, comment_reply, follow}`. Two indexes: `(user_id, created_at desc)` for the list view, and a partial `(user_id, created_at desc) where read_at is null` for the badge count.

**RLS:** users SELECT / UPDATE (mark read) / DELETE their own rows. INSERT is closed off — only the trigger functions write, and they run as SECURITY DEFINER to bypass RLS for the recipient (who isn't auth.uid() at insert time).

**v1 scope:** kudos on your runs, comments on your runs, replies to your comments, new followers. Deliberately **not** included: club post replies (high noise), realtime push (poll on focus is enough). When realtime + mobile push are needed, layer on top — `notifications` is the durable record, push is a delivery mechanism.

**v1.1 scope (migration `20260903_001_notify_event_rsvp.sql`):** event RSVPs. Originally deferred over fan-out concerns; in practice the fan-out goes the *other* way (one row per RSVP into the event creator's inbox, not the reverse). Only the event `created_by` is notified — not the club admins, since the creator already is one and broadcasting to every admin on every RSVP turns into spam on bigger clubs. Only `status = 'going'` fires. The trigger is wired AFTER INSERT OR UPDATE so a Maybe→Going flip notifies; a partial unique index `(user_id, actor_id, event_id) where kind = 'event_rsvp'` + `on conflict do nothing` keeps Going→Maybe→Going churn from duplicating rows.

**UI:** sidebar bell with an unread badge and a popover showing the last 15. The full inbox is mounted as the Notifications tab on `/u/[id]` (own profile only) with all / unread sub-filters — collapsing it onto the profile page keeps the social surfaces in one place rather than scattering them across sibling top-level routes. Marking-as-read is optimistic + best-effort — the badge updates immediately and the row write is fire-and-forget.

**Trade-offs:**

1. **Storage grows with engagement.** A user with 1000 followers and a public run getting 500 kudos has 500 notification rows. Acceptable until it isn't — the cleanup hatch is a `delete notifications where created_at < now() - interval '90 days'` cron; not built yet because nobody's hit the volume.
2. **Self-engagement is silently filtered.** If user X kudoes their own run (RLS blocks this today, but the trigger guards `actor != recipient` defensively) we don't notify. Acceptable.
3. **No batch / collapse.** "Alice and 4 others gave kudos to your 5K" is a Twitter-style affordance we skip in v1 — every kudos is its own row. If the inbox gets noisy this becomes the natural improvement; the kind + run_id keys are already in place.

**Don't re-litigate unless:** notification volume becomes the user-facing complaint (then add batch-collapse), or push-on-mobile lands as a real ask (then add a separate fan-out worker that subscribes to inserts on `notifications`).

---

## 39. mobile_android and mobile_ios share a byte-for-byte Dart codebase

**Decided:** April 2026 · supersedes the "copy-then-converge per file" guidance from earlier in §24.

`apps/mobile_android/lib/` and `apps/mobile_ios/lib/` are kept identical via `diff -rq`. Same for `apps/mobile_android/test/` and `apps/mobile_ios/test/`. The pubspec deltas are limited to `name` and `description`. Platform-specific behaviour (Apple Sign-In vs Google, dotenv vs `--dart-define`, Apple Watch ingest vs Wear OS data layer, foreground-service notification on Android vs `allowsBackgroundLocationUpdates` on iOS) is dispatched at runtime via `Platform.isAndroid` / `Platform.isIOS` inside the unified files. Modules whose MethodChannel only exists on one platform (`run_notification_bridge`, `wear_auth_bridge`, `WatchIngest`) live in both apps; calls on the platform without a registered channel throw `MissingPluginException`, which the existing try/catch in each module silently swallows.

**Why:** the previous "copy-then-converge per file" rule meant the iOS twin was always weeks behind whichever Android feature shipped most recently. Drift accumulated between the twins because nobody re-ran the copy pass after every commit; by the time iOS got a Mac build, the diff was 30+ files long and the catch-up was its own session. Forcing the trees to be identical at every commit moves the cost from "audit drift later" to "include both apps in the same change now," which is much smaller per change and impossible to forget — the architecture-guard test would catch a divergent file the moment CI runs.

**How to apply it:**

1. **Editing.** Treat `apps/mobile_android/lib/` as the canonical edit surface. Apply the same diff to `apps/mobile_ios/lib/` in the same commit. Don't try to edit them in parallel — pick one, copy.
2. **Platform branches.** When behaviour genuinely differs between platforms, branch with `Platform.isAndroid` / `Platform.isIOS` inside the unified file. Don't fork the file.
3. **New deps.** Add to both pubspecs in the same commit. The architecture-guard test pins this; let it fail fast.
4. **Tests.** Same rule as `lib/`. The test suite runs against both apps; a test that only makes sense on one platform should still build cleanly on the other (skip with `Platform.isAndroid` / `isIOS` if needed).

**Trade-off:** every PR that touches either app touches both. That's worth it because the cost is now paid in linear-time editing (apply the diff to both files) instead of exponential-time drift recovery. The alternative (lift to a shared package under `packages/`) is the long-term answer, but a shared package needs an interface boundary that the per-screen deps don't naturally have yet — converging to a verbatim duplicate first lets the boundary emerge before we bake it in.

**Don't re-litigate unless:** the Mac build keeps catching iOS-specific bugs that mean iOS needs *its own* version of more than two files, at which point the verbatim-twin overhead exceeds the drift-recovery overhead and a shared-package extraction is worth doing properly. The architecture-guard test on `lib/screens/run_screen.dart` is the canary: when it starts diverging meaningfully in behaviour between platforms, that's the signal.

---

## 40. Watch ingest is asymmetric: Apple Watch goes through the phone, Wear OS uploads directly

**Decided:** April 2026 · captured during the cross-client data-consistency audit.

The two watch platforms reach Supabase by completely different routes:

- **Apple Watch.** `apps/watch_ios` records the run, writes the GPS trace to a local JSON file, and hands it off via `WCSession.transferFile(_:metadata:)`. On the phone, `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift` is a `WCSessionDelegate` that picks the file up, packs metadata + track string into a `[String: Any]`, and invokes `run_app/watch_ingest#run` on the Flutter `MethodChannel`. The Dart handler in `apps/mobile_*/lib/main.dart` (`WatchIngest._runFromArgs`) builds a `core_models.Run` and hands it to `ApiClient.saveRun` — i.e. the run goes to Supabase via the *phone's* signed-in Dart client.
- **Wear OS.** `apps/watch_wear/.../SupabaseClient.kt` talks to Supabase REST + Storage directly from the watch over Wi-Fi or watch-cellular. There is no method channel, no `WatchIngestBridge` on Android (the `run_app/watch_ingest` channel is registered by Dart but has no native counterpart — calls hit `MissingPluginException`, which is fine because no native code ever invokes it on Android).

This is intentional, not technical debt.

**Why the asymmetry:**

- *Wear OS has independent network access* on-wrist for the vast majority of users (Wi-Fi-direct + LTE on cellular models; Bluetooth proxy through the phone otherwise). Forcing every Wear OS run through the phone would mean (a) the user must have the Flutter app running in the foreground or background when the watch finishes, and (b) we'd need a Wearable Data Layer message handler on the Android phone plus idempotency on top — strictly more code, strictly less reliable. Today Wear OS users can run a 10K with the phone left at home and the run lands.
- *Apple Watch (non-cellular)* has no comparable independent path. Apple ships `WCSession.transferFile` as the "queue-on-disk-and-retry-when-phone-is-reachable" primitive, and writing a custom direct-to-Supabase upload from `watch_ios` would re-implement that queue worse. The phone bridge is the simplest reliable path *because* Apple's framework already does the queueing.

**What that means in practice:**

1. **Two ingest entrypoints on the backend, one row shape.** Both paths land rows in `runs` via Supabase RLS, so the schema is enforced server-side regardless of route. The April 2026 audit fixed the last places where the two paths drifted (laps shape, per-point `bpm`, `activity_type`, default `source` value) so that a row produced by either platform looks identical.
2. **Wear OS keeps its own generated row types.** `apps/watch_wear/.../generated/DbRows.kt` is regenerated from the same migrations as the Dart and TS row types. CI's `parity-types` check covers Dart + TS but not Kotlin yet — keep an eye on the Wear OS file when migrations land.
3. **`apps/mobile_android/lib/main.dart`'s `WatchIngest` block is dead code on Android.** `WatchIngest.attach` runs at launch but the `run_app/watch_ingest` channel never fires because nothing native posts to it. Leaving it in keeps the file byte-identical with `apps/mobile_ios/lib/main.dart` per §39.
4. **Activity type is hardcoded "run" on both watches** until either grows an activity picker. The Apple Watch hardcode is in `apps/watch_ios/WatchApp/ContentView.swift#syncRun()`; the Wear OS hardcode is in `RunViewModel.kt`. Track this together when adding the picker — they need to ship in lockstep so cross-platform parity holds.

**Trade-off:** two upload paths instead of one, two sets of HTTP/auth code (Dart `ApiClient` vs Kotlin `SupabaseClient`), and a parity audit needs to check both. The alternative (force Wear OS through the phone too) would be one path on paper but require a paired Android phone with the Flutter app live for any watch run to reach the backend — strictly worse for the user, and the "two paths in code" cost is a one-time write, not an ongoing tax.

**Don't re-litigate unless:** Apple Watch ships reliable independent networking that doesn't need WCSession (then `watch_ios` can mirror Wear OS's direct path), or Wear OS removes independent network APIs (then we'd be forced to bridge through the phone). Either is hypothetical today.

---

## 41. OAuth tokens are stored in Supabase Vault, not as plaintext columns

**Decided:** `integrations.access_token` and `integrations.refresh_token` were dropped (migration `20260603_001_integrations_vault.sql`) and replaced with `access_token_secret_id` / `refresh_token_secret_id` UUID references into `vault.secrets`. All reads/writes go through SECURITY DEFINER helpers `get_integration_tokens(user_id, provider)` and `set_integration_tokens(user_id, provider, access, refresh, expiry)`.

**Why Vault rather than `pgcrypto`:**

- The master key never leaves Supabase. Vault is libsodium with a project-managed key; the platform handles rotation. With `pgcrypto` the key would have to live in Edge Function env vars — a leaked deploy log or env-dump would give up every token at once.
- Key-handling mistakes are the most common real-world crypto bug. Vault removes that whole class — there is no key for the application to mismanage.
- Schema overhead is small: two `uuid` columns and two helper functions. The functions encapsulate the admin-only `vault.decrypted_secrets` view so EFs don't need broad grants.

**Why not Supabase Vault as the *primary* storage (i.e. naming each secret instead of referencing by id):**

- Vault is designed for app-level secrets (API keys, service tokens) — not thousands of per-user entries. Naming by `integration_access_<user>_<provider>` is workable but non-idiomatic; UUID indirection plus one helper function is clearer.
- `set_integration_tokens` updates the existing vault entry in place on rotation so the secret_id stays stable across token refreshes — anything that caches an integration row reference doesn't need to invalidate.

**Trade-off:** every read of an OAuth token is now an RPC call (`supabase.rpc('get_integration_tokens', ...)`) instead of a column projection. That's one extra round-trip per scheduled-job iteration, small in absolute terms. Service role bypasses the owner check inside the function, so the existing `refresh-tokens` Edge Function cron still works.

**Don't re-litigate unless:** Supabase removes Vault, or a regulatory requirement forces external KMS (HIPAA, FedRAMP). Both shift the calculus toward AWS KMS / GCP KMS envelope encryption.

---

## 42. Edge Function rate limits live in a Postgres counter, not Deno KV or in-memory

**Decided:** Per-user rate limiting on user-facing Edge Functions (`parkrun-import`, `strava-import`, `delete-account`, `export-data`) goes through `check_rate_limit(user, bucket, max, window)` — a SECURITY DEFINER function that does an atomic upsert-and-check on `rate_limits (user_id, bucket, window_start, count)`. Migration `20260604_001_rate_limits.sql`. Shared helper `apps/backend/supabase/functions/_shared/rate_limit.ts` turns denials into a 429 with `Retry-After`.

**Why Postgres rather than the alternatives:**

- **Deno KV** is sub-ms but per-EF-deployment. State doesn't survive cold starts or share between functions, so a "10 per hour" budget in EF instance A and another in instance B add up to 20+. For per-user durable budgets you'd end up bucketing by EF deploy, which leaks the limit.
- **In-memory leaky-bucket** is fastest but resets on every cold start and doesn't share state at all. Useful for sub-second burst-suppression, useless for "max N per hour."
- **Postgres counter** durable, shared across every EF instance, ~5 ms per check, and the SECURITY DEFINER pattern means EFs only need a function grant — no direct table access.

**Window strategy: fixed-window, not sliding.** Each call computes `floor(epoch / window) * window` and keys all hits in that wall-clock window to one row. Sliding windows would double the write rate (one row per request rather than per window) and we don't need that precision. Even denied calls increment, so a user who hits ceiling stays at ceiling+N until the window rolls — no extra punishment, but no way to reset by hammering, either.

**Trade-off:** every limited request now does an extra round-trip to Postgres. Negligible against the network calls these EFs already make (Strava, parkrun.org, etc.), and the rate-limit table grows slowly enough that an hourly `pg_cron` sweep keeps it under control.

**Tier-aware extension** (migration `20260605_001_rate_limits_tiered.sql`): a sibling function `check_rate_limit_tiered(user, bucket, free_max, pro_max, window)` resolves `user_profiles.subscription_tier` and the window check in one transaction so paywalled endpoints can pass two ceilings without a separate tier-lookup round-trip. Lifetime is treated as pro; unknown / missing tier defaults to free as the conservative fallback.

**Don't re-litigate unless:** an EF needs sub-50 ms latency and the round-trip becomes the bottleneck (move that one to Deno KV with a documented per-instance fan-out caveat), or the limit needs to vary by something other than user tier (then `check_rate_limit` taking `max` as a parameter is already the right primitive — wrap it differently).

---

## 43. Cross-route signalling on mobile uses a top-level `ValueNotifier`, not a nav stack handoff

**Decided:** When a deep screen needs to trigger an action on a different tab (e.g. `plan_detail_screen` → "Start workout" → run-tab structured runner), it sets a top-level `ValueNotifier` declared in `main.dart` and pops back to root. The destination tab listens, drains, and clears. Live example: `pendingStartWorkout` in `apps/mobile_*/lib/main.dart`.

**Why not pass the workout through nav routes:** the entry path is `Run tab → plans button → plans_screen → plan_detail → calendar → workout_detail → "Start workout"` — that's 5+ widget constructors deep, with multiple call sites for `plan_detail_screen` (run_screen, plans_screen, plan_new_screen, club_detail_screen). Threading a `PlanWorkoutRow?` as a typed `MaterialPageRoute<PlanWorkoutRow?>` would force every intermediate screen to forward the result, and the lazy `PageView` keep-alive means the `RunScreen` State may not even exist when the signal fires.

**Implementation contract:**

1. Declare the notifier at top level in `main.dart` with a clear name (`pendingStartWorkout`), nullable type, and docstring.
2. Source screen sets `notifier.value = payload`, then `Navigator.of(context).popUntil((r) => r.isFirst)`.
3. `HomeScreen` listens and switches the relevant tab.
4. The tab's `State` listens too **and drains in `addPostFrameCallback`** during `initState` so a signal that fires before the tab was lazily constructed isn't dropped on the floor.
5. Drain by reading the value, clearing it (`notifier.value = null`), and acting.
6. `removeListener` in `dispose`.

**Trade-off:** global mutable state, which we generally avoid. Justified here because the alternative is threading typed return values through routes that have multiple unrelated callers, and adding a state-management framework (Provider / Riverpod / Bloc) would be a much larger change for one cross-tab signal. Keep this pattern bounded — one notifier per genuinely cross-tab handoff, named for the action, not the data.

**Don't re-litigate unless:** the count of cross-route notifiers grows beyond ~3 (then a small message bus is justified), or we adopt a state-management framework for other reasons (then route the signals through it).

---

## 44. Watch route picker is gated by an owner-curated `is_starred` flag, not "recents" or "all routes"

**Decided:** The Wear OS app fetches routes with `?is_starred=eq.true&order=updated_at.desc&limit=30`. The owner stars / unstars routes from web (`/routes` cards + detail header) or mobile (routes list + detail). The watch is read-only — there's no "star this route" affordance on the watch.

**Why a curated flag, not "recently used" or "all owned":**
- *All owned* doesn't scale. A serious runner has 50–200 saved routes (parkrun courses, hill loops, GPX imports, holiday-week routes). A 1.4-inch round screen can't usefully list that.
- *Recents* would be opaque — the user can't pre-load the watch with "the routes I'm taking on holiday next week" without first running them on the watch, which is circular.
- *Curated star* is one tap, persists across devices, and matches existing UX patterns (Spotify Liked Songs, GitHub Stars).

**Schema:** `routes.is_starred boolean not null default false` plus a partial index `idx_routes_user_starred (user_id, updated_at desc) WHERE is_starred` so the watch fetch stays index-only as the table grows. Migration `20260606_001_routes_is_starred.sql`.

**Trade-off:** users who never star anything would otherwise see an empty watch picker. To soften the first-launch experience the watch falls back to **the 10 most-recently-updated owned routes** when the starred fetch returns nothing — capped tighter than the 30-route starred path because this is undirected and we'd rather show too few than fill the picker with stale GPX imports. Once the runner stars anything, the fallback stops engaging. We considered auto-starring top-N by `run_count` on a cron, but the false-positive blast radius (e.g. starring a route they ran once on a business trip) outweighed the convenience.

**Don't re-litigate unless:** telemetry shows the recent-routes fallback is doing all the work (then either prompt the user to curate, or revisit auto-star), or the cap of 30 starred routes is hit by power users (raise the cap and add server-side pagination — the partial index already supports it).

---

## 45. Server-side map matching uses OSRM, not Valhalla Meili or GraphHopper

**Decided:** The first real `Matcher` in `apps/job_worker/` is `OSRMMatcher` (`apps/job_worker/internal/matcher_osrm.go`), calling a self-hosted OSRM instance's `/match/v1/foot` endpoint. The worker selects it when `OSRM_URL` is set; otherwise the `PassthroughMatcher` shim stays in place so the rest of the pipeline (claim → download → match → upload → finish) is exercisable without an engine running. Local dev stack lives at `apps/job_worker/osrm/` (Geofabrik PBF + `osrm-extract` / `osrm-partition` / `osrm-customize` Makefile + `docker compose` running `osrm-routed --algorithm mld`).

**Why OSRM, not Valhalla or GraphHopper:**
- *Operational footprint.* OSRM is one Go-friendly Docker container (`osrm/osrm-backend`); the entire build is `make download && make build && docker compose up`. Valhalla bundles Meili plus a routing stack we don't use; GraphHopper is a JVM service with the heap-tuning carrying-cost that comes with that. Single-purpose binary wins.
- *API ergonomics.* OSRM's `/match` is one HTTP call: send the trace as `lng,lat;lng,lat;…`, get a snapped GeoJSON LineString back. Valhalla's Meili speaks a richer JSON schema (per-point time / accuracy / search radius) — useful eventually, overkill for v1. GraphHopper's match endpoint returns gpx-style structures we'd have to translate.
- *Profile fit.* The bundled `foot.lua` profile preserves parks, trails, and unpaved paths — exactly the network running tracks live on. `car.lua` would discard half of them. Valhalla and GraphHopper have pedestrian profiles too, but OSRM's profile config is one Lua file in the same image, no separate config tree.
- *Re-match cost.* Every matched track is keyed on `(algorithm, algorithm_version)` so swapping engines later is a re-match, not a schema change. The cost of getting the v1 pick "wrong" is bounded by re-running the queue against a different `Matcher` — cheap. So we optimised for shippability over engine purity.

**Trade-off:** OSRM's HMM is less tunable than Valhalla's Meili (no per-point GPS-noise input; no segment-confidence threshold knobs). For a 5 km urban run that's fine; for a 100 km ultra with hours of weak signal it'll occasionally produce a NoMatch where Meili would still snap. Worker handles that as `status='skipped'`, not `failed`, so the run is preserved and re-matchable when we have a better engine to point it at. Also: OSRM's URL-only `/match` GET caps coordinate count by URL length; chunking is in `OSRMMatcher.Match` (default 100 points per call, stitched back together).

**Don't re-litigate unless:** we see a sustained skip rate above ~5% on real user tracks (then re-evaluate Meili — its richer per-point metadata is what would help); we hit the chunking ceiling on multi-hour ultras (might want a single `POST /match` against a different engine instead of splitting); or we want offline / on-device matching, which is its own multi-week effort tracked under roadmap §531.

## 46. Recorder waypoint timestamps come from `pos.timestamp`, never `DateTime.now()`

`RunRecorder._onPosition` originally stamped `_currentWaypoint.timestamp = DateTime.now()`. Found during a test-coverage audit of the previously-untested `_calculatePace` helper: a synchronous inject burst (or any CPU stall that batches GPS callbacks together) collapsed every wall-clock waypoint timestamp to the same millisecond, and the function silently returned null because `endTs.difference(startTs).inMilliseconds == 0`. Same shape as the speed-clamp bug we fixed earlier — the testing.md gotcha already warned: "use GPS-reported timestamps from the `Position` rather than `DateTime.now()`."

Fix: use `pos.timestamp` for the waypoint. GPS timestamps are accurate to ~ms regardless of how the OS schedules the callback, and the Position class guarantees the field is non-null. Also makes the GPX/TCX/FIT export timestamps reflect the actual GPS time of each fix instead of the wall-clock time of the Dart-side process — a pure improvement.

**Trade-off:** if the device's GPS module ever returns a stale or wildly wrong timestamp, that error now propagates to pace and to exports. In practice all real geolocator providers (Android FusedLocation, iOS CLLocationManager) timestamp on-device from the GNSS hardware itself, so this is not a real risk.

**Don't re-litigate unless:** a real geolocator backend ever surfaces malformed `pos.timestamp` values (none do today), or we add a non-GPS fix source (pedometer-only, network-positioned) that doesn't carry an authoritative timestamp.

## 47. GPX `<time>` is parsed onto `Waypoint.timestamp` for every track-point variant

`packages/gpx_parser/RouteParser._waypointFromGpxNode` originally read only `lat`, `lon`, and `<ele>` — `<time>` was ignored. Found during the StravaImporter coverage audit: a Strava GPX import with `CSV Elapsed Time = 0` was supposed to fall back to the GPS-supplied duration (`track.last.timestamp - track.first.timestamp`) but always landed on `Duration.zero` because the parser never populated `Waypoint.timestamp`. Knock-on effect: any GPX-imported run had null per-point timestamps, which silently broke `_calculatePace`, `movingTimeOf`, `fastestWindowOf`, `hr_zones`, and the run-detail elevation/pace chart's time axis.

Fix: read the optional `<time>` child node on every `<trkpt>` / `<rtept>` / `<wpt>` and pass it through `DateTime.tryParse` onto `Waypoint.timestamp`. TCX already did this (`Trackpoint > Time`); GeoJSON has no widely-used per-point timestamp convention so it stays unset.

**Trade-off:** if a GPX file has wildly off-spec or future-dated `<time>` values, those propagate into the run record. In practice GPX exporters (Strava, Garmin Connect, Wahoo, COROS) all emit ISO 8601 UTC timestamps from the device's GNSS timestamp, so this is a safe assumption.

**Don't re-litigate unless:** we ever ingest GPX from a source that emits malformed timestamps (haven't seen one yet), or we want to derive timestamps from a GPX that explicitly lacks them (interpolate from `Activity Date` + cumulative haversine + a target pace — would need a separate code path).

## 48. Heavy import / backup parsers run in `compute()` isolates, never on the UI thread

Found during a UI-freeze audit. `StravaImporter.importFromZip` did `ZipDecoder().decodeBytes()` plus per-file GZip decompression and XML / FIT parsing all synchronously on the main isolate. A 5-year Strava export (hundreds of activities) froze the foreground for tens of seconds — the import-progress dialog stopped repainting until parsing finished. `BackupService.createBackup` and `BackupService.restore` had the same shape with `ZipEncoder().encode()` and `ZipDecoder().decodeBytes()` on multi-MB archives. The single-file route import (`routes_screen._importFile`) ran `RouteParser.fromGpx` on a potentially 5 MB XML on the UI thread.

Fix: every heavy synchronous parser body now runs inside [`compute()`](https://api.flutter.dev/flutter/foundation/compute.html). Run / Waypoint / Duration / DateTime are all sendable across isolate boundaries; `Archive` is not, so backup encode/decode serialises through `[(name, bytes)]` pairs with a thin rebuild on the main isolate. The architecture guards in `apps/mobile_android/test/architecture_guards_test.dart#heavy parsers run in compute() isolates` will fail loudly if a future refactor inlines any of these calls back onto the UI thread.

The same pass also tried swapping `_dir.listSync()` for async `_dir.list()...toList()` in `LocalRunStore` / `LocalRouteStore` cold-start, but reverted: the streaming form deadlocked the `RunsScreen` widget tests for >10 minutes — the I/O isolate's reply ports interact poorly with `flutter_test`'s fake-async zone, even when the await is sequenced before `pumpWidget`. The directory walk stays sync; the per-file decode that follows is still async + parallel via `Future.wait`, which is where the bulk of the cost actually lived. The architecture guards now *require* `listSync` so a future refactor doesn't silently re-trip the same hang.

**Trade-off:** `compute()` has fixed startup overhead (~10 ms to spawn the isolate plus serialisation cost). For a 1-row backup or a single-waypoint GPX it's a net loss vs inline. We accept that — every code path gated this way is by definition handling user-supplied data of unbounded size, and the worst-case freeze is what kills the experience.

**Don't re-litigate unless:** we add a streaming parser API that yields control on its own (e.g. a SAX-style GPX parser) — that would let us skip the isolate hop and stay on the main thread. Until then, `compute()` is the cheap, correct boundary.

## 49. Mobile list-card thumbnails mirror the web SVG track preview

`runs_screen`, `routes_screen`, `feed_screen`, `explore_routes_screen`, and the Routes tab on `club_detail_screen` previously rendered each row with a generic `CircleAvatar` icon and forced the user to tap into the detail screen to see the run / route shape. Web has shipped SVG list-card previews (`apps/web/src/lib/components/TrackPreview.svelte` + `RunTrackPreview.svelte`) on every equivalent surface for months — `parity.md` was silently `Partial` on this until now.

Two new widgets land in `apps/mobile_android/lib/widgets/`:
- `track_preview.dart` — pure `CustomPainter` that mirrors the SVG geometry one-to-one: viewBox short axis = 100 with PAD = 4; white casing stroke 4.5; coloured line stroke 2.6; up to four directional chevrons at evenly-spaced indices; green start cap + red end cap at r = 2.6. The web `isMoving` jitter guard ports as `isTrackRenderable` (5 m bounding-box diagonal threshold).
- `run_track_preview.dart` — lazy fetcher around `ApiClient.fetchTrackByPath` with a static `Map<String, List<Waypoint>?>` cache keyed on the URL; a `null` entry is the "fetch failed" sentinel so a broken Storage object doesn't get retried on every rebuild.

Routes carry `waypoints` inline so route surfaces hit `TrackPreview` directly; runs go through `RunTrackPreview` since the GPS trace lives in Storage at `track_url`.

**Why mirror the SVG geometry exactly:** the web previews are a known-good render that's been in users' hands since `apps/web` shipped. Drifting the mobile geometry — different stroke widths, different chevron count, different cap colours — would be a parity regression even though the feature itself is new on mobile. Same shape on both surfaces lets users glance at a list without re-learning what the markers mean.

**Trade-off:** `RunTrackPreview` doesn't use `IntersectionObserver`-style lazy fetching the way the web component does; it issues the fetch in `initState` and relies on `ListView.builder`'s lazy element creation to throttle off-screen requests. For a 200-run history this kicks ~10 fetches at first paint while the `Map<>` cache absorbs subsequent rebuilds. If list scrolling ever feels janky we revisit with a visibility-driven trigger (e.g. `VisibilityDetector`).

**Don't re-litigate unless:** the parallel cold-start fetches start showing up in startup latency telemetry, or the SVG geometry is intentionally redesigned on web (then port the new constants in lock-step).

## 50. Web run map mirrors the mobile NRC-style pace heatmap

Mobile (Android + iOS via the byte-identical Dart codebase) has rendered the run-detail trace as a six-bucket pace heatmap with a three-band age fade since `feat(android): draw NRC-style pace heatmap on the live + detail track` (Apr 21). Web kept a single indigo→lavender gradient on `RunMap.svelte` until now — same run, different colour story on each platform.

`apps/web/src/lib/pace_segments.ts` is a 1:1 TS port of `apps/mobile_android/lib/widgets/pace_segments.dart` — same colour ramp (`#EF4444 → #22D3EE`), same alpha bands (0.55 / 0.80 / 1.0), same activity-scaled m/s breakpoints. `RunMap.svelte` takes a new optional `activity` prop; when set AND the track carries per-point timestamps, the trace renders as a MapLibre `line` layer with data-driven `'line-color': ['get', 'color']` over the existing dark casing. Routes (which never carry timestamps) and historical imports without `ts` fall through to the legacy single-line render path so nothing regresses.

**Why mirror the buckets exactly:** the heatmap is the visual identity of the run — having the same fast-cyan mid-section on the same run on the phone and the laptop is the whole point of the alignment exercise. Drifting either side's breakpoints by even one m/s produces visibly different colour bands at the same speed, which would let the parity drift back over time.

**Trade-off:** the casing (single-colour blue halo) tints the heatmap slightly under low-saturation buckets. Acceptable — replacing the casing with a per-segment outer halo would multiply MapLibre layer count by 2× without the visual win to justify it.

**Don't re-litigate unless:** mobile changes its breakpoints / colours / alpha bands (port them over in the same PR), or we move web off MapLibre to a renderer where data-driven `line-color` isn't ergonomic.

## 51. Thumbnail projection applies a cos(midLat) longitude correction

The original `TrackPreview` projection — both the web SVG component and the Dart `CustomPainter` ported from it in §49 — scaled latitude and longitude differences by the same factor. A degree of latitude is roughly 111 km everywhere, but a degree of longitude shrinks with `cos(latitude)` (62 % of a latitude degree at 51 °N, 50 % at 60 °N). A square 100 m loop at London latitude therefore rendered as a horizontally-stretched rectangle ~60 % wider than tall. Users reported this as "the run preview doesn't follow the line I ran."

Fix: scale `(maxLng - minLng)` by `cos(midLat)` before computing the bounding box, then apply the same `lngScale` factor when projecting each point's `lng` offset. Equirectangular projection at the route's mid-latitude. The viewBox-fit logic stays unchanged so `preserveAspectRatio="xMidYMid meet"` (web) and the `Size.infinite` painter (mobile) still render at the requested aspect.

The projection lives in pure helpers — `projectTrack` in `apps/web/src/lib/track_projection.ts` and `apps/mobile_android/lib/widgets/track_preview.dart` — so the math can be unit-tested without rendering. Both suites assert that a 100 m × 100 m loop at 51 °N renders square within 2 %.

**Trade-off:** equirectangular at one latitude is still wrong for multi-degree routes where the mid-latitude isn't representative — a marathon-distance trip from London to Paris would still distort. Acceptable for thumbnail rendering: the bounding box of any single run is small enough that one `cos(midLat)` value is accurate to within sub-pixel tolerance at thumbnail scale. A proper Mercator projection would solve the multi-degree case but adds complexity we don't need until we ship a "city-to-city" feature.

**Don't re-litigate unless:** users start uploading routes that span multiple degrees of latitude (then move to Mercator), or one platform's correction drifts from the other (then re-port in lock-step).

## 52. Webhook replay protection lives in `webhook_events`, not inlined per-EF

`revenuecat-webhook` verifies HMAC-SHA256 over the raw body, which authenticates *what* was sent but does nothing against *when* — a captured POST can be replayed at any future time. Active-state replays (RENEWAL → 'pro') are idempotent today, but a stale EXPIRATION replayed *after* a re-subscription has flipped the tier back to 'pro' would silently downgrade a paying user back to 'free'. The audit/edge-functions sweep (June 2026) caught this.

The defence is two-gate, and lives in shared infrastructure rather than per-EF logic:

1. **Freshness window.** Reject events whose `event_timestamp_ms` falls outside `[now - 5min, now + 1min]`. Bounds the replay window so the dedupe table can be pruned aggressively. The +1 minute is clock-skew tolerance; a captured event older than the window forces an attacker to capture-and-replay within the freshness budget.
2. **Event-id dedupe.** `webhook_events (provider, event_id, received_at)` (migration `20260623_001_webhook_event_dedupe.sql`). Insert-first: a 23505 unique-violation maps to a 200 ok-skipped (RC retries on non-2xx). Insert before the side effect means a crash between insert and update leaves no doubled tier flip — RC's next renewal/state event corrects any missed update.

The table is provider-keyed so future webhooks (Stripe, Linear, etc.) share the dedupe store without colliding on event-id namespaces. A daily cleanup cron prunes rows older than 30 days — comfortably longer than RC's ~3-day retry horizon.

**Why insert-first rather than update-then-record:** the side effect is the irrecoverable bit. A duplicate record with no side effect is harmless; a duplicate side effect with no record is the bug. Reserving the row first means we either succeed entirely or visibly fail the reservation; we never half-process.

**Trade-off:** the freshness window means a webhook delivered through a slow proxy can be rejected as stale. RC's median delivery latency is sub-second; the 5-minute budget is comfortable. If we ever ingest a provider with a multi-minute SLA on its retry queue, raise the window for that provider only — this is why the table is provider-keyed.

**Don't re-litigate unless:** a provider's retry semantics demand a different shape (e.g. monotonically-increasing sequence numbers, in which case skip the timestamp check and use `event_id` ordering).

---

## 53. Web app + domain on AWS (S3 + CloudFront + Lambda + Route 53), not Vercel or Cloudflare Pages

The web app is deployed to AWS: static SvelteKit build on S3 (private bucket, Origin Access Control), CloudFront in front, Lambda Function URL for the single SSR route (`/api/coach`), Route 53 + ACM cert in `us-east-1` for `runonward.com` / `www.runonward.com`. Provisioned via **Terraform** (matching the workstation toolchain — see [`/home/jhoward/CLAUDE.md`](https://github.com/jaredhoward/dotfiles)), with **sops + AWS KMS** for the runtime secrets the coach Lambda reads. GitHub Actions deploys via OIDC role assumption (no long-lived AWS keys in `Settings → Secrets`).

**Why:**

- **Already in AWS.** Workstation uses AWS KMS via SSO for shared sops secrets. Adding a second cloud (Vercel, Cloudflare) introduces a separate billing/IAM/audit relationship for marginal benefit.
- **Standard, hireable, audit-friendly infra.** S3 + CloudFront + Lambda + Route 53 is bog-standard. Anyone who's done AWS knows this shape. Vercel-specific deploy semantics, CF Workers, and Pages all add platform-specific knowledge requirements.
- **Optionality for ancillary services.** When the app eventually needs SES (transactional email), KMS (per-user app-level encryption), Bedrock (alternate Claude routing), or Secrets Manager — they're already adjacent.
- **No commercial-use restriction.** Vercel Hobby is non-commercial in the ToS; a paid running app technically requires Pro at $20/mo per seat. AWS has no such gate.
- **For *this* app specifically, web-host cost is <5% of total infra spend.** The bytes that matter (run photos, GPS tracks, exports) live in Supabase Storage; LLM tokens are per-call regardless of host. So Cloudflare's bandwidth-cost advantage barely applies here, and the AWS ecosystem benefit dominates.

**Trade-off:**

- **More day-one setup** than Vercel's import-and-go. Terraform modules + per-env stacks, OIDC role, OAC, ACM cert, CloudFront response-headers policy, build-time env injection from GitHub Secrets, runtime secrets via sops/KMS, CloudWatch alarms — about a day or two of focused work. Bolting these on later is painful, so they ship together with the first deploy. See [`apps/web/deployment.md`](../apps/web/deployment.md). Operator scripts under [`bin/`](../bin/README.md) wrap the AWS / sops / terraform sequences (preflight, orchestrated apply, sops bootstrap, secret rotation, post-deploy health check, interactive DR walkthrough) so the first deploy and any rotation fit on a few commands.
- **CloudFront egress is ~$0.085/GB** (after the first 1 TB free for 12 months). Cloudflare's egress is functionally free. At the projected scale for this app the difference is single-digit dollars/month for a long time.
- **Terraform + provider lock-in.** Moving to a different cloud later means rewriting the modules. Acceptable given how rarely we'd want to. Terraform is more portable than CDK in principle, but the AWS-specific resources (`aws_cloudfront_distribution`, `aws_lambda_function_url`, etc.) don't translate.

**Architecture pinned by this decision:**

```
Route 53 (runonward.com, www.runonward.com)
   │  ALIAS / A
   ▼
CloudFront distribution (one per env: prod, preview)
   ├── default behaviour       → S3 origin (private, OAC) — SvelteKit static build
   ├── /api/coach/* behaviour  → Lambda Function URL (Node 20, streaming response)
   └── response headers policy → CSP / HSTS / X-Content-Type-Options / Referrer-Policy

ACM cert (us-east-1) — auto-renew

KMS key (per env) ──► encrypts sops files ──► Terraform decrypts ──► Lambda env vars

GitHub Actions
   │  OIDC AssumeRole (no long-lived keys)
   ▼
IAM role (s3:PutObject on artifacts bucket, cloudfront:CreateInvalidation,
          lambda:UpdateFunctionCode on the coach handler — and nothing else)
```

**Per-environment stacks**, never one bucket with prefixes — that mistake is too easy to make destructive. Two CloudFront distributions, two S3 buckets, two Lambdas. The Terraform setup uses one shared module (`infra/modules/web-stack`) consumed by per-env root modules (`infra/envs/{prod,preview}`) so the two stacks can't drift.

**SvelteKit adapter posture:** `@sveltejs/adapter-static` for the bulk. The coach handler logic lives in `apps/web/src/lib/coach/handler.ts` (transport-agnostic core) and is wrapped twice: once by `apps/web/src/routes/api/coach/+server.ts` (SvelteKit, dev-only — under `adapter-static` this route is not built) and once by `apps/web/lambda/coach/src/index.ts` (AWS Lambda Function URL with response streaming, prod). No community SvelteKit-AWS adapter — too much surface area for one route.

**Runtime secrets:** the coach Lambda reads `ANTHROPIC_API_KEY` (and optionally `SENTRY_DSN`) from environment variables that Terraform sets at deploy time. The plaintext lives in **sops-encrypted** files committed under `infra/envs/<env>/secrets.enc.yaml`, encrypted with **AWS KMS keys** managed by the same Terraform stack. Rotation is `sops <file>` → `terraform apply`. No secret values touch GitHub Secrets, no secret values touch developer laptops in plaintext.

**Don't re-litigate unless:** monthly CloudFront egress exceeds ~10 TB AND the team has bandwidth to migrate. At that scale Cloudflare's free egress could save real money, but the migration cost (rewriting IaC, redoing OIDC, cutover DNS without breaking sessions) needs justification.

---

## 54. Fix `thresholdPaceSecPerKmFromVdot` formula

The original `thresholdPaceSecPerKmFromVdot` in `apps/web/src/lib/fitness.ts` (and its Dart twin in `apps/mobile_android/lib/fitness.dart`) computed T-pace via a hand-fit cubic-quadratic-linear-constant:

```
mps = 0.0003 × VDOT³ - 0.021 × VDOT² + 0.6 × VDOT + 2.0
```

The coefficients are wrong — at VDOT 50 they yield 17 m/s (≈60 s/km), well past Eliud Kipchoge territory. Daniels' published table puts T-pace at VDOT 50 around 4:15/km (≈255 s/km). The bug silently distorted every CTL / ATL / TSB number on the dashboard's FitnessCard (TSS values came out ~1/25 of correct, so users essentially always saw "Sweet spot" recovery advice regardless of actual training load). The 90-day TrainingLoadChart was unaffected — it uses `lib/training_load.ts`, a different TSS implementation that doesn't depend on threshold pace.

**Fix:** invert Daniels' VO2 demand quadratic at the 88% rule of thumb (T-pace velocity ≈ 88% of vVO2max):

```
demand(v) = -4.6 + 0.182258 v + 0.000104 v² = 0.88 × VDOT
```

Solve for the positive root, convert m/min → s/km. Spot checks: VDOT 50 → 4:15/km, VDOT 60 → 3:40/km, VDOT 70 → 3:14/km. Matches Daniels' published tables within a couple of seconds across the meaningful range (VDOT 30-70).

**Trade-off:** existing `fitness_snapshots` rows persisted under the old formula are now stale. After deploy, the FitnessCard's `liveSnap` will jump (correctly) by ~25x; the historical chart will show a discontinuity around the deploy date. Acceptable — every snapshot from this point forward is correct, and the recovery-advice ladder finally has the dynamic range to discriminate between "loaded" / "sweet spot" / "fresh."

**Don't re-litigate unless:** Daniels publishes an updated formula or we add sex/elevation-specific calibration.

Pinned in place by `apps/mobile_android/test/fitness_test.dart#thresholdPaceSecPerKmFromVdot` (3 tests against the Daniels table) and `apps/web/src/lib/fitness.test.ts#thresholdPaceSecPerKmFromVdot`.

---

## 55. Column- and role-level `revoke` is wider than it looks: explicit grants survive

Three migrations across pass-2 and pass-3 had to be rewritten because the original `revoke` shape was too narrow:

- `20260707_001_user_profiles_column_lockdown.sql` — `revoke select (col1, col2, …) on <table> from <role>`. Silent no-op: the role still held a table-level SELECT, which Postgres applies as the broadest available grant.
- `20260723_001_events_meet_point_anon_revoke.sql` — same shape, same outcome.
- `20260711_001_definer_grant_hygiene.sql` — `revoke execute on function <fn> from public`. Silent no-op for anon / authenticated: Supabase pre-grants EXECUTE on every function in the `public` schema to those two roles as a project-wide default. Revoking from `public` (the catch-all role group meaning "all roles by default") leaves the explicit role grants intact.

Each was caught by adding a regression test that asserted the negative invariant (anon SELECT on the column raises 42501 / `has_function_privilege('anon', …)` is false), then fixed by widening the revoke / re-shaping the grant.

**The correct shape** for selectively hiding columns from a role:

```sql
revoke select on <table> from <role>;
grant select (<safe_col1>, <safe_col2>, …) on <table> to <role>;
```

That guarantees:

- The role can read only the listed columns; `select *` and any unlisted column raise `42501`.
- New columns added to the table are deny-by-default for that role — a future writer must touch this migration deliberately to expose them.
- RLS still applies on top: rows the role can't see are still hidden.

**Cost:** every caller that uses `select('*')` against the locked-down table must enumerate columns explicitly. Both the events and user_profiles cases were already enumerating safe columns at every call site (web, Dart, Edge Functions), so the fix landed without code changes elsewhere — but a future "lock down columns of table X" migration must audit `from('X').select('*')` first.

**Don't re-litigate unless:** Postgres column-privilege semantics change (they won't), or the project adopts a "read everything via SECURITY DEFINER RPC" approach that makes column grants moot for these tables specifically.

Pinned in place by `apps/backend/supabase/tests/rls_events_meet_point_test.sql` (4 tests) and `apps/backend/supabase/tests/rls_user_profiles_column_lockdown_test.sql` (5 tests).

---

## 56. Account deletion cascades through every public FK to `auth.users`

Eight tables held a `references auth.users` without `on delete cascade`: `runs.user_id`, `routes.user_id`, `integrations.user_id`, `user_profiles.id`, `route_reviews.user_id`, `clubs.owner_id`, `events.created_by`, `club_posts.author_id`. The `delete-account` Edge Function calls `auth.admin.deleteUser(user.id)` after draining Storage; Postgres raised `23503` on the first cascading FK and the EF returned `{"error":"delete failed"}`. Every authenticated user has a `user_profiles` row by virtue of `auth.svelte.ts`'s upsert-on-first-sign-in, so this 500'd for **every** user — denying the GDPR / CCPA right-to-erasure the EF exists to satisfy.

Migration `20260728_001_cascade_auth_users_fks.sql` re-creates each FK with `on delete cascade`. The semantic is **the user owns the rows; deleting their account deletes the rows.** That covers their personal data (runs, routes, integrations, profile), their authored content in shared spaces (route reviews, club posts they wrote, events they created), and clubs they own. Pre-launch this matches what saga-users.ts already had to do manually: sweep the eight tables before `auth.admin.deleteUser`. The CASCADE makes the EF correct without the workaround.

The clubs/events/club_posts cases need a one-line caveat: when a sole-admin of a club deletes their account, the club dies with them (club CASCADE → club_members + posts + events all cascade away). For an active community-owned club this is harsh — a follow-up could either (a) require ownership transfer in the UI before delete-account succeeds, or (b) flip those three FKs to `set null` plus relax the `not null` on the columns. Both are post-launch concerns; for Phase 1 the simple semantic wins.

The discovery path was the e2e `cross-user/sagas/account-deletion.spec.ts` saga: plant a saga user, plant a run with track, drive the /settings/account UI flow, capture the EF response, assert 200. The saga-users.ts fixture had been masking this for months by sweeping the eight tables itself before its own teardown — so the unit-test surface and the saga's own setup never hit the path the EF actually takes.

**Don't re-litigate unless:** product wants club-ownership-transfer semantics (then flip clubs.owner_id to `set null` + add a require-transfer step in the danger-zone UI), or any of these tables grows fields the user wouldn't want CASCADE-deleted (audit logs, etc.).

Pinned by `apps/web/tests-e2e/cross-user/sagas/account-deletion.spec.ts` — runs the full UI flow + asserts the auth row, the runs row, the user_profiles row, and the gzipped track in Storage are all gone after the click.

---

## 57. Map-matching is free; queue priority is the Pro perk

OSRM map-matching cleans the GPS-jitter output of every recorded run into a road-snapped track. We considered gating it entirely behind Pro and rejected that — Strava, Garmin Connect, Nike Run Club, Apple Fitness all show snapped tracks on their free tier; locking the feature would make the free experience feel broken on the most basic correctness dimension. The free tier needs to feel complete; Pro is for *more*, not for *less broken*.

Instead, **priority** is what's paywalled. Migration `20260730_001_tier_aware_job_scheduling.sql` introduces a single helper `job_scheduled_at_for_user(uuid)` that returns `now()` for pro / lifetime users and `now() + 30 s` for free / unknown users. Both `map_match` enqueue sites — the auto-trigger `runs_enqueue_match_job` and the manual-rematch RPC `enqueue_run_rematch` — thread that helper into the `scheduled_at` column. The worker's `claim_next_job` already filters `scheduled_at <= now()` and orders by `(scheduled_at, id)`, so a Pro job is always claimable strictly before a free job enqueued at the same wall-clock moment.

**Why `scheduled_at` offset and not a `priority` integer column:** the existing `jobs_queued` partial index on `(scheduled_at, kind)` already gives the right ordering. A new column would cost an index rebuild + a worker change for zero behavioural improvement. The existing semantic of `scheduled_at` (claimable when `≥ now()`) extends cleanly to "and Pro users get a smaller value at the same wall-clock instant".

**Why 30 seconds:** short enough that free users still see "matched track" within a minute under nominal load; long enough that Pro users measurably jump the queue under contention. One migration to tune if real-world numbers want a different number.

**Convention for future job kinds:** any new `kind` (strava_backfill, photo_transform, bulk_rematch, …) calls `job_scheduled_at_for_user(uuid)` at enqueue time. Don't inline `case ... subscription_tier ...` at enqueue sites — the helper is the single source of truth so a tier-policy change lands in one place. The TS-side EF rate-limits already follow the same shape (free / pro tiers via `checkRateLimitTiered`, e.g. `parkrun-import` 4/16 per hour, `strava-import:sync` 4/16 per hour, `export-data` 2/8 per hour); the job-queue helper completes the picture for async work.

**Don't re-litigate unless:** product wants a different model — e.g. capping free users to N map-matches per day instead of slowing them, or putting a different feature behind the paywall entirely. Each of those is a one-migration change to either the helper or the trigger.

Pinned by 3 e2e tests in `apps/web/tests-e2e/cross-cutting/job-tier-priority.spec.ts`: end-to-end via the auto-trigger (gap ≥ 25 s between free and pro), helper unit-style RPC test (pro / free / unknown-user fallback), and a manual-rematch test that pins the rematch RPC also threads the helper.

---

## 58. Job-queue priority is `scheduled_at` offset, not preemption — and every kind must be short

Companion to §57. Round-9 made `map_match` jobs Pro-prioritised by offsetting `scheduled_at`. This decision pins the rest of the contract — the run-to-completion semantic, the single-queue model, and the **<30 s job-runtime convention** that keeps the priority gain meaningful.

**Run-to-completion, never preemption.** Once `claim_next_job` flips a row to `status='running'`, the worker processes it until `finish_job` or `defer_job`. A higher-priority job arriving mid-flight waits for the in-flight job to finish — at most one job-duration of latency. We don't kill in-flight work because preemption requires state checkpointing, resumable matching, partial-result handling, and idempotency under retry — all complexity for a problem we don't have when jobs are short.

**Single queue, not two.** A `jobs_pro` / `jobs_free` split (or a `priority` column with two claim functions) only earns its complexity if (a) free jobs run long enough to starve Pro, (b) you want parallel-per-tier workers (we have one), or (c) you want preemption (see above). The single `(scheduled_at, id)` index already gives the right ordering for free; a separate column or table would cost an index rebuild + a worker rewrite for zero behavioural improvement.

**The <30 s convention.** Pro starvation only becomes a real risk when an in-flight job runs long enough that the wait dominates the priority gain. The rule:

> Every `jobs.kind` must complete in **< 30 seconds**. Anything longer is **chunked** at enqueue time into N smaller jobs that each respect the budget.

A Strava 90-day backfill is N `strava_backfill_page` jobs (50 activities each, ~5 s of work), not one job-per-90-days. A bulk re-match is N `map_match` jobs, not one bulk job. Priority is re-evaluated at each chunk boundary so a Pro user's request slots in between chunks, not after the whole thing.

**Worker enforcement: HandleTimeout.** `worker.go` wraps every `dispatch` call in `context.WithTimeout(ctx, w.Config.HandleTimeout)` (default 5 minutes — defence in depth, well above the 30 s convention). When the deadline fires, the in-flight Backend call returns `context.DeadlineExceeded`, `isTransient` classifies that as transient, and the worker calls `defer_job` rather than holding the slot. Pinned by `TestWorker_HandleTimeoutDefersStuckJob` in `apps/job_worker/internal/worker_test.go`.

**Stuck-job alerting.** The worker timeout is the in-process safety net; for jobs that survived the timeout (or were locked by a worker that crashed before reporting back), migration `20260731_001` adds two SQL functions:

- `find_stuck_jobs(p_stuck_after interval default '5 minutes')` — returns the rows still `status='running'` with `now() - locked_at > p_stuck_after`.
- `jobs_stuck_summary(p_stuck_after interval default '5 minutes')` — returns a single jsonb with `stuck_count`, `oldest_age_s`, and a 5-row sample, suitable for log scraping or a `select count(*)` alert rule.

A `pg_cron` schedule `jobs-stuck-alert` runs the summary every 10 minutes; the result lands in `cron.job_run_details` and is grep-able by an operator. **Neither function auto-fails stuck jobs** — that would race a worker about to call `finish_job` for the same row. Operator-driven remediation only.

**Don't re-litigate unless:** product wants a real-time SLA-bound job kind that can't be chunked into <30 s units (rare in this codebase — even bulk imports chunk naturally per page). At that point you'd add either (a) a second worker process dedicated to short jobs, or (b) `for update skip locked`-based per-kind worker partitioning, both of which are `main.go` changes, not architectural rewrites.

Pinned by:
- `apps/web/tests-e2e/cross-cutting/jobs-stuck-alert.spec.ts` — 4 tests: idle queue → empty sample, planted 6-min-old job → surfaces, custom threshold honours its arg, `pg_cron` schedule registered + active.
- `apps/job_worker/internal/worker_test.go::TestWorker_HandleTimeoutDefersStuckJob` — pins the per-job timeout → defer_job path with a synthetic 200 ms download against a 50 ms HandleTimeout.

---

## 59. Run-export blobs are signed-URL-only — no direct REST GET, even for the owner

The `runs` Storage bucket holds two content classes under one prefix tree: GPS tracks at `{user_id}/{run_id}.json.gz` and data-export bundles at `{user_id}/exports/<ts>.{csv,zip}`. Until `20260816_001`, the owner-folder SELECT policy (`(storage.foldername(name))[1] = auth.uid()::text`) covered both — an authenticated owner could `GET /storage/v1/object/runs/<self>/exports/<ts>.csv` directly, bypassing the signed URL the `export-data` Edge Function returns.

We narrowed the policy to exclude any path whose **second** `foldername` segment is `exports`. The intent: every export download flows through the EF (rate-limited, audit-loggable, 10-min signed URL via service role) — never through the bucket's own REST endpoint. The CSV / ZIP retention cron (`20260720_001`) keeps the blobs for 7 days; without this lockdown, a leaked or browser-history-cached path remained replayable for the full retention window even after the original signed URL expired. Tracks (`{user_id}/<run_id>.json.gz`, only one segment under the user prefix) keep working because the policy still matches single-segment paths.

Trade-offs:

- **Direct REST GET on a self-export now 404s under user JWT.** That's intentional — the EF is the only legitimate read path. If a future feature needs in-app preview of the bundle, it should call the EF, not paper around the policy.
- **Service-role writes (in the EF) and admin deletes (in `delete-account`) are unaffected.** Both already bypass RLS via `SUPABASE_SERVICE_ROLE_KEY`.
- **Owner-tracks read path is unchanged** — `RunDetail` still calls `fetchTrackByPath('{user_id}/{run_id}.json.gz')`, which the narrowed policy still allows.

Don't re-litigate unless the EF becomes a bottleneck for a use case where rate-limiting is unwanted (e.g. server-side bulk export pipelines from the user's own infra). At that point, prefer minting a longer-lived signed URL from a different EF, not widening the bucket policy.

Pinned by `apps/backend/supabase/tests/rls_storage_runs_exports_lockdown_test.sql`.

---

## 60. Functions that read column-locked tables must be SECURITY DEFINER, and they replicate RLS in the function body

`20260707_001` + `20260810_001` revoked table-level `SELECT` on `user_profiles` and re-granted only `(id, display_name, avatar_url, created_at)` to `authenticated` + `anon`. Every cross-user demographic column (currently `gender`, `date_of_birth`, plus the historical `subscription_tier`, `parkrun_number`) is deny-by-default. The self-read path is `get_my_profile()`, a `SECURITY DEFINER` RPC that returns the calling user's full row.

The audit (May 2026) turned up `segment_leaderboard_tiered` declared `SECURITY INVOKER` but reading `up.date_of_birth` + `up.gender`. Every real call from `anon` (401) and `authenticated` (403) hit `42501 permission denied for table user_profiles`; the web caller masked the error and the v2 leaderboard surface silently returned `[]`. Fixed in `20260830_001` by promoting the function to `SECURITY DEFINER`.

The corollary that bites if you forget: `SECURITY DEFINER` runs as the function owner (which has full SELECT) AND **bypasses RLS by default**. The original `SECURITY INVOKER` posture inherited RLS for free, so `segment_efforts`'s SELECT policy (`exists segment AND private.is_run_visible_to(run_id, auth.uid())`) gated rows automatically. After the promote, the function must **manually replicate the visibility filter** — route must be readable (public OR owner OR active club member) AND each effort's run must pass `private.is_run_visible_to`. Without that, a `SECURITY DEFINER` leaderboard would leak private-route efforts to any authenticated caller.

The rule, in shorthand:

> A `SECURITY DEFINER` function that reads a column-locked table must (a) check `auth.uid() is not null` and reject NULL callers with `42501`, (b) replicate the SELECT RLS of every table it joins, in its `where` clause, and (c) explicitly set `search_path` (Postgres-wide rule, already enforced elsewhere). Cross-user demographic columns in the **return type** must also be masked: `case when row.user_id = caller then col else null end`.

Don't re-litigate unless we either (a) accept widening the table-level grants (then `SECURITY INVOKER` is fine, but every cross-user read across the app inherits the wider grant), or (b) move demographics into a separate side table whose own RLS is sufficient (operationally complex for one feature). The `SECURITY DEFINER` + manual-RLS posture is the same shape `get_my_profile` and the `private.is_*_visible_to` family already use.

Pinned by `apps/backend/supabase/tests/segment_leaderboard_tiered_test.sql` (16 assertions covering anon-rejection, self-row visibility, cross-user demographic masking, private-route filtering, and the `42501`-on-null-`auth.uid()` branch).

---

## 61. Social hub IA: rename Clubs → Social, host Feed/People/Clubs as tabs under /social

The activity feed used to live under `/u/[me]?tab=feed` (a self-only tab on the user's own profile) and the top-level "Clubs" sidebar entry pointed at `/clubs`. There was no top-level surface for finding *other runners* — the only paths to a non-followed runner were drilling into `/clubs/[slug]` members, tapping the author chip on a feed/share card, or pasting a `/u/<uuid>` URL. Discovery failed when the user didn't already share a club.

The IA refactor in this commit:

- Sidebar item "Clubs" → "Social", icon `groups` → `public`, href `/clubs` → `/social`.
- `/social` hosts an ARIA tab strip with `?tab=` URL state — **Feed** (default), **People**, **Clubs**.
- **Feed** is the same activity feed (fetchFollowingFeed + 14-day window + activity-type filter chips + kudos pill + load-more cursor), extracted into `SocialFeed.svelte`.
- **People** is the new surface — name-search (debounced 300ms, ILIKE on `user_profiles.display_name`, self-excluded) plus a Suggested-for-you list (members of viewer's clubs they don't follow yet, ranked by shared-club count). Inline Follow toggle with optimistic flip + rollback.
- **Clubs** is the previous `/clubs/+page.svelte` body lifted into `SocialClubs.svelte`.

The `/clubs` and `/feed` top-level routes stay alive as thin client-side redirects (`/clubs[?tab=browse]` → `/social?tab=clubs[&clubs-sub=browse]`; `/feed` → `/social?tab=feed`; legacy `/u/[id]?tab=feed` → `/social?tab=feed`). All sub-routes (`/clubs/[slug]`, `/clubs/new`, `/clubs/[slug]/events/*`, `/clubs/join/[token]`) are unchanged so invites, bookmarks, mobile deep links, and external links keep resolving.

**Trade-off accepted:** the Feed tab no longer renders on `/u/[me]` (removed from the profile's tab list). The viewer's feed is conceptually about *who they follow*, not about the profile being viewed, so it never really fit on the profile page. The new home makes Feed visible to every signed-in user without a profile drill-in.

**Don't re-litigate** by re-introducing `/feed` or `/clubs` as top-level tabs, or by adding back a Feed tab on the profile, unless the People surface gets demoted to a sub-tab somewhere else (the gap it closes is the load-bearing part of this refactor).

Pinned by `apps/web/tests-e2e/runs/social.spec.ts` (11 tests covering tab ARIA + URL state, both legacy redirects, People search + Follow toggle + Clear, suggested empty state, feed entry render + Cycle filter empty). Sidebar nav contract is pinned by `apps/web/tests-e2e/cross-cutting/surfaces.spec.ts`.

---

## 62. `/clubs/` is anon-allowed at the layout layer; page-level guards still gate write surfaces

The layout's `isAnonAllowed()` helper now whitelists `/clubs/`. Without this, an anon visitor hitting `/clubs/sydney-run-club/events/<id>` from a shared link was bounced to `/login` even though the `events` / `clubs` RLS already allows the read (`clubs.is_public = true`).

The page-level guards on the write surfaces still hold: `/clubs/[slug]/events/new` redirects to the parent club page when `viewer_role` isn't owner/admin. The event-detail page hides the RSVP buttons, admin-actions row, and post composer when `auth.user` is null. Private clubs render the not-found card because RLS drops the row before it reaches the client.

**Don't re-litigate** by gating `/clubs/` at the layout level again — moving the guard up the stack hides the public-club share path that already worked at the RLS layer.

Pinned by `apps/web/tests-e2e/clubs/event-rsvp.spec.ts` (anon visitor test — public-club event detail renders, RSVP row absent, post composer absent).

---

## How to add an entry

1. Append below, numbered in sequence.
2. Lead with what was decided, then *why*, then the *trade-off*, then when not to re-litigate.
3. Cite the migration, commit, or PR that captures it if there is one.
4. Keep it short — one screen or less. If it's longer than that, it probably belongs in `architecture.md` or its own deep-dive doc, with a pointer from here.
