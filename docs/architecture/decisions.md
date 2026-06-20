# Architecture decisions

Short records of non-obvious choices that the code alone doesn't explain. Reach for this before proposing something that's already been considered and rejected.

This is not a strict ADR template — each entry is a few paragraphs: what we decided, why, and what we traded away. Append new entries to the bottom; don't rewrite history. Date them when you know the date.

---

## 1. Both watches are native: Apple Watch is Swift / SwiftUI, Wear OS is Kotlin / Compose-for-Wear

**Decided:** Phase 2 planning (Q1 2026 · see [roadmap.md](../product/roadmap.md)). The Wear OS half was originally Flutter; reversed in §15 below — keeping this entry to record the original framing and what changed.

Apple Watch was always going to be native Swift. Flutter's watchOS support is a non-starter for a first-class running computer — the build target isn't stable, widget-tree costs are too high under a workout, and the native health frameworks (HealthKit, CoreLocation, WKWorkoutSession) are only reachable through channels we'd have to write ourselves. SwiftUI / WatchKit is the path everyone else takes and it's the only one that lets the watch run standalone GPS sessions without the phone.

Wear OS originally shipped as Flutter on the assumption that Compose interop was good enough and that we'd reuse `core_models` + `api_client`. In practice the Flutter-on-Wear surface dragged on framework upgrades, made tile / complication work awkward, and the schema-typed Dart `RunRow` had to be re-derived in Kotlin anyway. **§15 reversed this** — Wear OS is now pure Kotlin + Compose-for-Wear, with `RunRow` regenerated from the same Supabase migrations as Dart's `db_rows.dart` via `scripts/gen_dart_models.dart`. Read §15 for the move and the trade-offs.

**Trade-off:** Two native codebases now (`apps/watch_ios/` Swift, `apps/watch_wear/` Kotlin) with their own networking, auth, and Supabase clients. Acceptable because the watch scope is intentionally small (record + navigate + sync) and the schema codegen keeps the row-shape contract enforced at compile time on both sides.

**Don't re-litigate unless:** Flutter ships a production-ready watchOS target *and* a similarly stable Wear OS target *and* the schema-codegen story works across both — at which point unifying back into Dart could be reconsidered. None of those are imminent.

---

## 2. GPS tracks live in Storage, not in `runs.track` jsonb

**Decided:** April 2026 · migration `20260410_001_runs_to_storage.sql`

A 10 km run has ~3,300 GPS points ≈ 265 KB of jsonb per row. At 10 K active users with 200 runs/year that's ~500 GB of database storage, and every dashboard query scans rows bloated with tracks that the dashboard never needs. Moving to object storage (`runs` bucket, path `{user_id}/{run_id}.json.gz`, gzipped) cut per-row size by ~99 %, eliminated jsonb column bloat on the dashboard query path, and let bulk importers (Strava, Health Connect) stay on the $25/month Supabase Pro tier instead of needing Team.

**Shape:** `runs.track_url` column points at the Storage object. Clients lazy-load the track on demand via `ApiClient.fetchTrack` (Dart) or `fetchTrack` in `apps/web/src/lib/core/data.ts` (TS). The dashboard list view never touches Storage.

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

## 6. `main` is the working branch; PRs are still the path for review-needed work

**Decided:** updated 2026-05-28 (was: `dev` is the working branch / `main` is the PR target)

All day-to-day work happens directly on `main`. PRs to `main` are still the path for anything that needs review (security work, schema migrations, recording-stack changes, ultrareview-bound batches), but most persona-hunt / unit / docs / refactor work lands as a sequence of per-piece commits on `main`. **Never push without an explicit ask** — the local commit is the deliverable, pushing is a separate ask.

**Why the change.** The earlier `dev → main` PR setup added a round-trip step that didn't earn its keep when the user is driving the work in-session. Per-piece-commits on `main` give the same bisectability + revertability with one fewer branch to keep in sync. The "never push without being asked" rule is the safety valve: nothing leaves the workstation until the user says so.

**Operating rule.** Once the user has asked for a piece of work (or a sequence), commit each piece as it lands — one piece, one commit. Tests in the same commit as the code they cover. Full enumeration of "what counts as a piece" in [`conventions.md` § Commit cadence](conventions.md#commit-cadence--one-piece-one-commit-dont-batch-a-session-into-one-lump). The older "never commit without being asked" guard still protects against proactively committing speculative work or ad-hoc workstation tweaks. Do not force-push or amend a published commit without being told.

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

**Decided:** April 2026 · `apps/web/src/lib/training/training.ts#pacesFromGoalPace`

The full Daniels training-pace model derives pace for each intensity zone from VDOT via the same implicit equation used to *compute* VDOT — there's no closed-form inverse. Real implementations use a published table of ~60 VDOT values × 5 zones. For v1 we anchor the five zones (easy / marathon / tempo / interval / repetition) on the runner's goal pace with fixed multipliers (1.22, 1.06, 0.97, 0.9, 0.85). Across the 3:00-5:00/km goal band these land within ~5 s/km of the Daniels tables, which is well inside the tolerance band a plan runner expects — most runners cannot actually hit a 1-second pace window, and the target bands we emit carry `±5-30s` tolerances anyway.

**Trade-off:** For very fast (≤3:00/km 5K) or very slow (≥7:00/km 5K) runners the multiplier model drifts further from the table — easy pace becomes too slow for elites and too fast for beginners. Neither demographic is our current target user; if we add one, swap `pacesFromGoalPace` for a table lookup without touching any caller.

**Don't re-litigate unless:** user reports show pace targets are systematically off, or we expand into the elite / total-beginner segments.

VDOT is still computed and stored (`training_plans.vdot`) for display — it's a useful fitness number for the runner even if it doesn't drive pace derivation in v1. See `docs/features/training.md § Pace derivation`.

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

A second trade-off (resolved): the refresh token originally lived in plaintext DataStore Preferences. As of remediation R2 it moved to `androidx.security.crypto` `EncryptedSharedPreferences` (Keystore-backed AES256-GCM) in `SessionStore.kt` — the access + refresh tokens are bearer credentials and a standalone watch holds a long-lived one with no phone in the loop, so it cleared the bar for app-level encryption. See [§ 127](#127-at-rest-posture-os-level-encryption-covers-device-loss-cloud-backup-extraction-is-closed-by-opting-the-apps-out-of-backup-app-level-track-encryption-stays-deferred) for the full at-rest posture (and why the bulk GPS/HR cache stays on OS-level encryption rather than app-level).

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

**Shared-device owner-tag (added 2026-05).** Originally the queue files were bare payloads keyed by uuid — `drain` unconditionally fed every file to whoever was currently signed in. On a shared device where User A's watch sent a payload during A's signed-out window then User B signed in, the next drain pushed A's run under B's account (RLS accepts the row because it embeds the caller's `user_id`, not the payload's intended owner). The fix mirrors the per-user pending-delete queue (§67): each enqueued file carries an `intended_owner_user_id` stamp set from a `last_owner.txt` sidecar that `main.dart` updates on every `signedIn` event (and at bootstrap when a cached session is restored). `drain` filters by current user — files stamped with a different user stay on disk for their rightful owner. Legacy bare-payload files (from before the envelope shipped) are detected by the absence of a `payload` key and drain unconditionally, matching the pre-stamp adoption rule. Pinned by `apps/mobile_android/test/architecture_guards_test.dart#main.dart stamps the watch-ingest queue before draining on signin` + 8 on-disk cases in `watch_ingest_queue_owner_tag_test.dart`.

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

**Update (May 2026):** The unlimited Pro coach cap was replaced with a finite **10 messages / UTC day** ceiling, and the free cap was lowered from 5/day to **2 messages / UTC day**. "Unlimited" left the worst-case Anthropic spend per stolen Pro session unbounded (the previous defence — a 60/hr `check_rate_limit` on the `coach:pro` bucket — was belt-and-braces but still allowed ~$75/day in a sustained-abuse scenario). 10/day caps that at ~$0.50/day per Pro user worst case, comfortably under the $9.99/mo price, and 10 turns is enough for two real coach sessions per day. 2/day for free is tight enough to push the conversion decision early but still lets a new user have one prompt + one clarifying follow-up before deciding. Both tiers now share the same `increment_coach_usage` + `usedToday > TIER_LIMITS[tier].dailyLimit` gate in `handler.ts`; the Pro hourly rate-limit branch is removed (the daily cap subsumes it). Existing Pro subscribers signed up under the "unlimited" copy — update marketing surfaces (`/settings/upgrade`, `features.ts`, `paywall.md`) before this lands in front of them.

---

## 24. Web is the canonical feature surface; mobile and watches are platform-additive

**Decided:** April 2026 · supersedes the informal "parity per platform" default

Every user-facing feature lives on the web app unless it is physically impossible there. Mobile (Android / iOS Flutter) and watch (watch_ios Swift / watch_wear Kotlin) clients are expected to **mirror the web's feature surface** and then **add things only a device in the pocket or on the wrist can do** (live GPS recording, sensor access, on-device crash recovery, ambient-mode rendering, haptics, OS share sheets, etc.). The web is the reference; the other clients are extensions.

**Why:** for a solo-dev, small-team product, maintaining full feature parity across five clients scales poorly. Concentrating net-new product surface on one platform — the one with the fastest iteration loop, the richest input devices, the best tooling, and the broadest discoverability — keeps the monorepo honest. Parity work becomes "mirror to mobile" rather than "pick a feature and find out which of five platforms it's missing on." The [cross-platform parity enforcement initiative](../product/roadmap.md#future--cross-platform-parity-enforcement) stops being an N-way problem and becomes a one-way flow.

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

`apps/web/src/lib/training/training.ts` is unit-tested under `tsx --test` (see [testing.md](../testing/testing.md)). The runtime is plain Node — Svelte's runes (`$state`, `$derived`, `$effect`) are compile-time syntax provided by the Vite plugin, so importing any `*.svelte.ts` module from a tested file blows up at module-load with `ReferenceError: $state is not defined`. We hit this when the unit-aware `fmtKm` / `fmtPace` formatters were first added to `training.ts` and re-imported `getUnit()` from `units.svelte.ts`.

**Decision:** unit-aware formatters live in `units.svelte.ts` (alongside the reactive `unit` signal); pure-TS modules don't import them. Svelte components that need them write a second import line. The two clusters never cross.

**Trade-off:** an extra import line in every Svelte component that wants `fmtKm` instead of one tidy "everything from `$lib/training/training`". Worth it — keeps the pure logic file testable without pulling in vitest + the Svelte plugin just to test two formatters.

**Don't re-litigate unless:** we adopt vitest with `@sveltejs/vite-plugin-svelte` (which natively transforms runes for tests), at which point the constraint disappears and a single export point is fine again.

---

## 27. Product renamed from "Better Runner" to "Threkir"; bundle IDs follow

**Decided:** April 2026 (display rebrand). **Revised:** May 2026 (bundle IDs aligned).

The user-visible product name is **Threkir** (URL: `threkir.com`). All display strings — Android `android:label`, iOS `CFBundleDisplayName` / `CFBundleName`, watchOS health-permission usage strings, web `<title>` + meta + share-card chrome, GPX `creator=` attribute — match. The Android `applicationId` + Kotlin package directory + iOS `PRODUCT_BUNDLE_IDENTIFIER` are now also `com.threkir.com`, and the WorkManager task name is `com.threkir.backgroundSync`. `BACKUP_FORMAT` stays `'run-app-backup'` since changing it would break restore of any local backup blobs already exported during the dev cycle.

**Why:** "Better Runner" was running-only branding for a multi-modal app (run + walk + hike + cycle). "Threkir" reframes the verb as forward movement rather than jogging, and `threkir.com` was the rare clean `.com` left in the running-adjacent namespace (most short slang `.com`s are squatted on Afternic).

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
- *`/live/{run_id}`* — the live-spectator surface streams `live_run_pings` over Realtime to anonymous viewers. Pings can't be clipped at render time the way the durable track is, because the table fires Realtime on `INSERT` and a client-side filter would still leak the unclipped point through the broadcast envelope. Instead, a `BEFORE INSERT` trigger on `live_run_pings` (`live_run_pings_drop_in_zone`, migration `20260618_001`) calls `privacy_in_any_zone` against the runner's zones and returns `null` for any in-zone ping — the row never lands, so Realtime never broadcasts it. The trigger is `SECURITY DEFINER` with `search_path = public, extensions` so it can read the runner's `user_settings` and reach the PostGIS `geography` type that `privacy_distance_m` uses. Trade-off: the runner watching their own `/live/{run_id}` also won't see in-zone pings, which is acceptable — the surface is for spectators and the durable track is recorded unclipped to Storage for the runner's own `/runs/[id]` view. **Belt-and-braces on the broadcaster side (added 2026-05):** `LiveBroadcaster` (mobile) also evaluates the runner's zones on every `pushPing` and drops in-zone fixes client-side. This is mandatory on the Go-hub transport (the hub bypasses Postgres entirely, so the BEFORE INSERT trigger never fires), and is a bandwidth saver on the Supabase transport (don't send a row just to have the trigger drop it). The wire goes through `RunScreen.settingsSync` → `_currentPrivacyZones()` → `LiveBroadcaster.privacyZonesProvider` so the gate is re-evaluated on every ping; mid-run zone additions in Settings take effect on the next fix, not the next run. Pinned by `architecture_guards_test.dart#LiveBroadcaster drops in-zone pings client-side`.

**Why a SECURITY DEFINER RPC, not pure-client clipping:**

The naive shape ("just fetch the owner's `privacy_zones` and clip on the client") leaks the zones — defeating the whole point. Public viewers can't be trusted with the zone polygons. So the actual implementation is a `clip_track_for_user(target_user_id, points jsonb)` SECURITY DEFINER RPC that reads zones internally and returns only the clipped output. Zones never cross the wire to a non-owner.

- *Server-side clipping at insert / update time* is destructive — the owner can't get their full track back after toggling a zone off. RPC at render time is reversible by definition.
- *Pre-storing two Storage objects per run* (full-fidelity owner-only + pre-clipped public) is the right v3 architecture, but doubles storage and forces the recorder/uploader to know about zones. Future work.
- *Modifying the `routes_set_start_point` trigger to read user_settings* is the right v2 fix for the nearby-routes leak (see below) — same `security definer` pattern, just different call site.

**The Storage download path: an Edge Function for non-owners (added retroactively).** The original ADR sketched clip_track_for_user as a single SECURITY DEFINER RPC and assumed every render site would call it on the points it received. The 2026-04 wave of clients (web `RunShareView`, mobile `public_run_screen`, the thumbnail components, the route share page) followed that pattern: fetch the gzipped blob from Storage via `fetchTrackByPath`, then pass the resulting points through `clip_track_for_user`. An `audit/storage` sweep (June 2026) found this leaked the unclipped blob: anyone reading `runs.track_url` from the public-runs SELECT policy could replicate just the Storage download (`supabase.storage.from('runs').download(path)`) and skip the RPC, getting every point inside the owner's privacy zones. Migration `20260619_001` dropped the `Anyone can read tracks of public runs` Storage policy, and a new `clip-public-track` Edge Function handles non-owner reads server-side: it downloads the blob via service-role, runs `clip_track_for_user` inside the function, and returns clipped points. Owner downloads keep the original direct path because the per-user-folder Storage policy from `20260410_001` still grants `(storage.foldername(name))[1] = auth.uid()::text`. Every client surface that previously did "fetchTrackByPath then clipTrackForUser" now does "owner: fetchTrackByPath; non-owner: fetchClippedTrackForRun" — the clip step never runs on the client side, and the unclipped bytes never cross the wire to a non-owner.

**The wire-leak follow-up: the `public_runs` view (added 2026-06).** A pre-prod public-rows audit caught a class of leaks the `is_public = true` SELECT policy on `runs` opens by default: `external_id` (which for imported runs encodes `strava:<activity_id>` / `parkrun:<event>:<date>` / `garmin:<file_id>` and links the share link to the runner's third-party account permanently), the entire `metadata` jsonb bag (which carries audit-only `imported_from` / `*_id` / `*_activity_type`, sync-state `last_modified_at`, recorder internals like `recovered_from_crash`, and — most consequentially — training-plan-linkage keys `plan_workout_id` / `workout_step_results` / `workout_adherence` that expose the runner's structured-workout paces and adherence to anyone with a share link), plus link-existence leaks via `route_id` / `event_id` (a public run linked to a private route or private-club event proves attendance/ownership even though RLS hides the joined row). Migration `20260626_001_public_runs_view.sql` adds a `public_runs` view that omits `external_id` entirely, applies a denylist over `metadata`, and nulls `route_id` / `event_id` when the joined target isn't itself public (via two SECURITY DEFINER helpers `is_public_route_by_id` / `is_public_event_by_id`). The view is granted to `anon` + `authenticated` and is the canonical client read path for public runs — every web `fetchPublic*` helper and the mobile `api_client.fetchPublicRunById` / `fetchPublicRunsByUser` / `fetchFollowingFeed` switched in the same change. Architecture-guard tests on both web and mobile assert no public-runs reader regresses to the bare table. The base-table `public runs are readable by anyone` policy was dropped in `20260701_001_drop_runs_public_select_policy.sql` once every public-runs reader was confirmed on the view: the migration adds a SECURITY DEFINER `is_run_visible_to(run_id, user_id)` helper (mirrors `is_route_visible_to`) and rewires the five dependent policies (`run_kudos` SELECT/INSERT, `run_comments` SELECT/INSERT, `run_photos` SELECT, `segment_efforts` SELECT, `live_run_pings` SELECT) to call the helper instead of the runs-EXISTS subquery, then drops the policy. Direct PostgREST `from('runs')` reads of public rows now return zero — the view is the only public path. Owner reads, owner writes, and the public_runs view continue to work unchanged.

**Routes use a parallel RPC, not the EF (added 2026-06).** Routes carry `waypoints` inline as a jsonb column on the `routes` row, unlike runs whose tracks live in Storage. So the same "render-site clip" pattern needed a different shape: a SECURITY DEFINER `clip_route_for_viewer(p_route_id)` RPC that visibility-gates internally (mirroring the routes RLS — owner / public / club member, raises 42501 otherwise) and returns either unclipped waypoints (owner) or clipped output (non-owner, delegated to `clip_track_for_user` so the zone walk has one implementation). Migration `20260625_001_clip_route_for_viewer.sql`. Pre-prod privacy-zones audit caught six leak surfaces — three on web (`/routes/[id]`, `/routes` My-routes tab, `/clubs/[slug]` Routes tab) and four on mobile (`route_detail_screen`, `routes_screen`, `club_detail_screen` Routes tab, `explore_routes_screen`); web's `RouteTrackPreview` and mobile's `route_track_preview.dart` are the new lazy-fetch wrappers (analogous to the runs `RunTrackPreview` shape with the same `raw:` vs `clip:` cache prefix). Wire-leak caveat: `select * from routes` from a non-owner perspective still returns the row with `waypoints` populated. Closing that requires either a `public_routes` view-projection or column-level grants — tracked as a follow-up alongside the public-rows audit findings; the visible-render leak the privacy-zones audit flagged is what these RPCs close. The migration also fixed a forward-compat hole on the original 20260523_001 helpers: `privacy_distance_m` and `privacy_in_any_zone` were declared `set search_path = public` only, which works in production because the calling role's default path includes `extensions` (PostGIS) but breaks under direct-SQL callers like seed.sql; the helpers are now `set search_path = public, extensions`.

There's a residual attack: a determined caller can pass a dense synthetic point grid to the RPC and recover zone geometry from the clip output. Mitigations: input length bounded to 50 000 points (caps the work for the residual probe). The RPC is granted to `anon` and `authenticated` — anonymous public-share callers are clipped via the same path. Every render site treats `viewerId == null` as non-owner so unauthenticated traffic gets the same clip pass authenticated traffic does. The earlier ADR draft contemplated keeping the RPC auth-only and shipping an anon-callable + rate-limited variant later; we collapsed that into the single grant + the `audit/rls` caller gates. For a casual-privacy threat model — which is what `privacy_zones` is for, distinct from a stalking threat model — this is acceptable.

**`routes.start_point` v2 — closed 2026-05.** The original draft of this ADR documented `routes.start_point` as a known v1 leak: the `routes_set_start_point` trigger populated the PostGIS `geography(Point)` column from `waypoints[0]` unconditionally, so a route built from home surfaced in `nearby_routes` proximity searches centred near home — the polyline was clipped by `clip_route_for_viewer`, but the *dot on the map* wasn't. Migration `20260925_001_routes_start_point_respects_privacy_zones.sql` ships the v2 fix the ADR sketched: the trigger now reads the owner's `user_settings.prefs.privacy_zones` (SECURITY DEFINER indirection so service-role writes from imports + Edge Functions also honour the gate), walks the waypoints, and snaps `start_point` to the first waypoint NOT inside any zone. If every waypoint is in a zone, `start_point` is set to NULL — `nearby_routes` already filters `start_point is not null`, so a fully-in-zone route is dropped from proximity search entirely (the route still renders on its own detail page; only the discovery surface drops it). A new trigger on `user_settings` recomputes `start_point` for every route the user owns whenever their `prefs.privacy_zones` changes, so a user who creates routes from home THEN adds a zone has their existing routes' start points migrated in the same transaction (without this, the old behaviour would stick until each route was next saved). Pinned by `apps/backend/supabase/tests/routes_start_point_privacy_test.sql` (11 pgtap cases covering INSERT / UPDATE / user_settings-trigger / fully-in-zone / no-zones / unrelated-pref-change short-circuit). The `privacy_aware_start_point` helper that backs both triggers is `revoke execute … from public, anon, authenticated` so the only caller paths are the two triggers themselves — closes the secondary "adversary calls the helper with attacker-controlled zones" surface.

**Trade-offs we're explicitly accepting:**

1. **Owner-self-share visibility.** When the run owner opens their own `/share/run/[id]` (e.g. testing a share link), they see the clipped version. Strava behaves the same way — the share page is "what your followers see," and being able to verify that is the whole point.
2. **Elevation profile retains in-zone points.** The profile is per-distance, not per-coordinate, so it leaks no location info; we keep it complete to avoid a confusing "elevation drops off cliff at end" rendering artifact.

**Don't re-litigate unless:** zones-per-user grows past ~5 in real usage (then promote to a `privacy_zones` table with its own RLS), or a third-party integration (Strava export, etc.) needs the *unclipped* track for sync purposes (then add a "Sync without privacy zones" toggle on the integration settings). The original "users report routes built from home leaking through nearby search" line was closed by migration 20260925_001 — see the "v2 — closed 2026-05" paragraph above.

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
2. **EXIF stripping (shipped, two layers).** Phones embed GPS in EXIF. The `job_worker` `photo_process` handler re-encodes uploads server-side to drop metadata; the mobile clients additionally strip the EXIF/XMP APP1 segment client-side *before* upload (`apps/mobile_android/lib/exif_strip.dart` — a lossless marker-walk that keeps the ICC profile + pixels, persona family-club #52) so a geotagged original never lands in the bucket during the async-worker window. Web currently relies on the server worker alone (its pre-upload strip would need a canvas re-encode — deferred).
3. **`owner_id` always equals `runs.user_id`** in v1. The schema separates them so a future "anyone in the club can attach a photo to a club event's race run" feature is forward-compatible without a migration.

**Don't re-litigate unless:** photo bandwidth becomes the dominant Storage cost (then add server-side thumbnail generation), users ask for video clips (different bucket, different MIME policy, probably a separate `run_videos` table), or the web client needs the same pre-upload strip the mobile clients now do (then add a canvas re-encode).

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

`apps/web/src/lib/segments/pace_segments.ts` is a 1:1 TS port of `apps/mobile_android/lib/widgets/pace_segments.dart` — same colour ramp (`#EF4444 → #22D3EE`), same alpha bands (0.55 / 0.80 / 1.0), same activity-scaled m/s breakpoints. `RunMap.svelte` takes a new optional `activity` prop; when set AND the track carries per-point timestamps, the trace renders as a MapLibre `line` layer with data-driven `'line-color': ['get', 'color']` over the existing dark casing. Routes (which never carry timestamps) and historical imports without `ts` fall through to the legacy single-line render path so nothing regresses.

**Why mirror the buckets exactly:** the heatmap is the visual identity of the run — having the same fast-cyan mid-section on the same run on the phone and the laptop is the whole point of the alignment exercise. Drifting either side's breakpoints by even one m/s produces visibly different colour bands at the same speed, which would let the parity drift back over time.

**Trade-off:** the casing (single-colour blue halo) tints the heatmap slightly under low-saturation buckets. Acceptable — replacing the casing with a per-segment outer halo would multiply MapLibre layer count by 2× without the visual win to justify it.

**Don't re-litigate unless:** mobile changes its breakpoints / colours / alpha bands (port them over in the same PR), or we move web off MapLibre to a renderer where data-driven `line-color` isn't ergonomic.

## 51. Thumbnail projection applies a cos(midLat) longitude correction

The original `TrackPreview` projection — both the web SVG component and the Dart `CustomPainter` ported from it in §49 — scaled latitude and longitude differences by the same factor. A degree of latitude is roughly 111 km everywhere, but a degree of longitude shrinks with `cos(latitude)` (62 % of a latitude degree at 51 °N, 50 % at 60 °N). A square 100 m loop at London latitude therefore rendered as a horizontally-stretched rectangle ~60 % wider than tall. Users reported this as "the run preview doesn't follow the line I ran."

Fix: scale `(maxLng - minLng)` by `cos(midLat)` before computing the bounding box, then apply the same `lngScale` factor when projecting each point's `lng` offset. Equirectangular projection at the route's mid-latitude. The viewBox-fit logic stays unchanged so `preserveAspectRatio="xMidYMid meet"` (web) and the `Size.infinite` painter (mobile) still render at the requested aspect.

The projection lives in pure helpers — `projectTrack` in `apps/web/src/lib/routes/track_projection.ts` and `apps/mobile_android/lib/widgets/track_preview.dart` — so the math can be unit-tested without rendering. Both suites assert that a 100 m × 100 m loop at 51 °N renders square within 2 %.

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

The web app is deployed to AWS: static SvelteKit build on S3 (private bucket, Origin Access Control), CloudFront in front, Lambda Function URL for the single SSR route (`/api/coach`), Route 53 + ACM cert in `us-east-1` for `threkir.com` / `www.threkir.com`. Provisioned via **Terraform** (matching the workstation toolchain — see [`/home/jhoward/CLAUDE.md`](https://github.com/jaredhoward/dotfiles)), with **sops + AWS KMS** for the runtime secrets the coach Lambda reads. GitHub Actions deploys via OIDC role assumption (no long-lived AWS keys in `Settings → Secrets`).

**Why:**

- **Already in AWS.** Workstation uses AWS KMS via SSO for shared sops secrets. Adding a second cloud (Vercel, Cloudflare) introduces a separate billing/IAM/audit relationship for marginal benefit.
- **Standard, hireable, audit-friendly infra.** S3 + CloudFront + Lambda + Route 53 is bog-standard. Anyone who's done AWS knows this shape. Vercel-specific deploy semantics, CF Workers, and Pages all add platform-specific knowledge requirements.
- **Optionality for ancillary services.** When the app eventually needs SES (transactional email), KMS (per-user app-level encryption), Bedrock (alternate Claude routing), or Secrets Manager — they're already adjacent.
- **No commercial-use restriction.** Vercel Hobby is non-commercial in the ToS; a paid running app technically requires Pro at $20/mo per seat. AWS has no such gate.
- **For *this* app specifically, web-host cost is <5% of total infra spend.** The bytes that matter (run photos, GPS tracks, exports) live in Supabase Storage; LLM tokens are per-call regardless of host. So Cloudflare's bandwidth-cost advantage barely applies here, and the AWS ecosystem benefit dominates.

**Trade-off:**

- **More day-one setup** than Vercel's import-and-go. Terraform modules + per-env stacks, OIDC role, OAC, ACM cert, CloudFront response-headers policy, build-time env injection from GitHub Secrets, runtime secrets via sops/KMS, CloudWatch alarms — about a day or two of focused work. Bolting these on later is painful, so they ship together with the first deploy. See [`apps/web/deployment.md`](../../apps/web/deployment.md). Operator scripts under [`bin/`](../../bin/README.md) wrap the AWS / sops / terraform sequences (preflight, orchestrated apply, sops bootstrap, secret rotation, post-deploy health check, interactive DR walkthrough) so the first deploy and any rotation fit on a few commands.
- **CloudFront egress is ~$0.085/GB** (after the first 1 TB free for 12 months). Cloudflare's egress is functionally free. At the projected scale for this app the difference is single-digit dollars/month for a long time.
- **Terraform + provider lock-in.** Moving to a different cloud later means rewriting the modules. Acceptable given how rarely we'd want to. Terraform is more portable than CDK in principle, but the AWS-specific resources (`aws_cloudfront_distribution`, `aws_lambda_function_url`, etc.) don't translate.

**Architecture pinned by this decision:**

```
Route 53 (threkir.com, www.threkir.com)
   │  ALIAS / A
   ▼
CloudFront distribution (one per env: prod, preview)
   ├── default behaviour       → S3 origin (private, OAC) — SvelteKit static build
   ├── /api/coach/* behaviour  → Lambda Function URL (Node 24, streaming response)
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

The original `thresholdPaceSecPerKmFromVdot` in `apps/web/src/lib/training/fitness.ts` (and its Dart twin in `apps/mobile_android/lib/fitness.dart`) computed T-pace via a hand-fit cubic-quadratic-linear-constant:

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

## 63. Single-app multi-modal expansion: run + gym + nutrition under one nav, one DB

**Decided:** May 2026

The product expands from single-modality (running) to multi-modality (running + gym + nutrition) inside **one app per platform** and **one Supabase project**, not three sibling apps that happen to share a backend.

Mobile navigation reorganises around the *action* (`Log`) rather than the *modality* (`Run`). The current `Run` bottom-nav tab disappears; a centre `Log` action button presents a sheet (Log run / Log lift / Log food — one entry per modality, one consistent verb, mirroring web; the meal slot is picked in the food-log composer, not split into meal/snack) with long-press = repeat last activity to preserve one-tap muscle memory for runners. Home becomes the cross-modality dashboard (today's run, today's lift, daily nutrition rings); History becomes a unified timeline with type filter chips. Web — less constrained by a tab ceiling — gets `Run` / `Gym` / `Nutrition` as explicit sidebar siblings.

The data model gains a shared `kind` abstraction. Existing `runs` rows acquire `kind = 'run'`; new tables for gym sessions and logged food items sit beside it. Cross-modality views (recovery score, weekly composite, AI Coach context) read from all of them through a typed adapter.

**Why one app, not three sibling apps:** the differentiator versus Strava (running silo) and MyFitnessPal (nutrition silo) is the *combination* — weekly mileage next to protein intake next to lift volume in one Home. Three separate apps make that view impossible without inventing yet another aggregator app (Apple Health, Google Fit already exist and they're not the product we want to be). Cost side: three apps means three App Store listings, three release pipelines, three permission asks, three brand investments — for a single-dev product, that's the wrong shape.

**Why one Supabase project, not three with sync:** "three apps that all sync" is the worst of both worlds — the same code-sharing complexity as one app, plus three release pipelines, plus three logins. One project means shared auth, shared social graph, and shared paywall (`subscription_tier` already exists; Pro unlocks across all modalities).

**Trade-offs accepted:**

- Tapping "Run" from anywhere is one tap today, becomes two (`Log` → Log run). Mitigated by long-press = last activity.
- Bundle size grows. Nutrition wants camera; gym is mostly silent; running wants always-on GPS. Permission asks consolidate per Apple / Google rules (we ask for what the feature needs when the user invokes it, not all of them at install).
- Home gets denser. The redesign has to be deliberate or it becomes a wall of cards. Cards self-hide when the modality has no data so a runner who doesn't log meals sees the same Home they see today.
- The web-canonical rule (§24) still holds. Each new modality builds on web first; mobile and watches mirror.

**Don't re-litigate** by:

- Splitting into `threkir - run` / `threkir - gym` / `threkir - nutrition` apps that sync — explicitly rejected.
- Adding gym / nutrition as additional bottom-nav tabs — the 5-tab ceiling is real (Routes was already folded into Social for this reason; see §61).
- Spinning the new modalities into separate Supabase projects "for isolation" — the cross-modality view is the *whole* point.

Phased delivery tracked in [roadmap.md § Phase 4](../product/roadmap.md#phase-4--multi-modal-gym--nutrition). The standalone-product-test escape hatch (ship nutrition as a genuinely independent app to validate market fit before merging) is documented there as a deliberate branch off this plan, not as a default.

**Amendment (2026-06-04) — web is ungated to match mobile; the `multi_modal_nav` flag is retired.** During rollout, web gated its three gym/nutrition surfaces behind a per-user `multi_modal_nav` flag (default off, no UI toggle), while mobile shipped them **ungated** — always-reachable surfaces with data-gated, self-hiding cards and a `keep_run_primary` toggle as the "protect the pure runner" mechanism. The net effect was an inconsistency the original §63 plan never intended: the same product was materially more discoverable on mobile than on web, and a web runner couldn't enable gym/nutrition without a direct prefs-bag DB edit. A Settings toggle was considered and rejected (mobile has no such toggle, so it wouldn't make the platforms consistent). The durable fix, now applied: the three web surfaces rely **purely on data presence**, matching mobile's self-hiding behaviour —
- the **Gym + Nutrition sidebar items** (`+layout.svelte`) are always present (the web analogue of mobile's always-present Log sheet — they are the entry point, so they can't be data-gated without a chicken-and-egg);
- the **`/dashboard`** today's-lift / recent-lifts cards + the lift→load contribution to the fitness/fatigue/form curve self-hide when the user has logged no gym sessions;
- the **`/history`** kind chips + unified timeline appear once a second modality has data.

The `multi_modal_nav` pref is **no longer read by any surface** (kept registered in `settings.md` as dormant/deprecated rather than removed, so a kill-switch could be reintroduced without a migration). The pure-runner experience is unchanged on both platforms — a runner who never logs a lift/meal sees no gym/nutrition cards or chips, only the always-present (and ignorable) sidebar items / Log sheet entry points.

**Amendment (2026-06-08, web) — `/history` becomes a pure timeline; the run-list management surface moves to a dedicated `/runs` page.** The F14/D3 rename had folded the run list into `/history` and left `/runs` as a redirect, so `/history` did double duty: the unified cross-modal timeline AND the full run-list (filters / pagination / bulk-delete / Add run / Heatmap). That made the modalities asymmetric — gym and nutrition each had a dedicated page (`/gym`, `/nutrition`) but runs did not — and made `/history`'s per-tab top section inconsistent (the Runs tab showed a heavy filter toolbar; Lifts/Meals showed a minimal chip header). The durable fix, now applied: **un-redirect `/runs` into the dedicated run-list/management page** (parallel to `/gym` + `/nutrition`, with a new `Runs` sidebar item between History and Gym), and make **`/history` a pure read-only timeline** where every tab — including Runs — renders the same timeline-row shape. Each single-modality tab carries a consistent header: a `View all` link to that modality's page + the single Log action; the All view shows a Log menu. This reverses the F14/D3 *redirect* (the route move) but keeps the rename's intent (History is the cross-modal surface). The `/runs/[id]` + `/runs/new` back-links now return to `/runs` (history.back() when arrived from `/runs` or `/history` so the list snapshot restores). **Mobile mirror (same day):** `runs_screen.dart` makes every History chip a timeline (Runs included) with a per-tab `View all` push — Runs opens `RunsScreen` *without* a `gymStore` (the offline-first run-list surface, the analogue of `/runs`), Lifts → `GymScreen`, Meals → `NutritionScreen`. Mobile uses a pushed route, not a sixth nav tab (the bottom nav is capped at five slots, per [§ 24](#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)). **Mobile's timeline is assembled from the three LOCAL stores** (`lib/local_activities.dart` over `LocalRunStore` + `LocalGymStore` + `LocalFoodStore`), NOT the server `activities` view — so it is offline-first, always reflects every modality the device holds, and updates live as the Log FAB writes a run/lift/meal. (This also retired the old server-feed loading gate + the `historyMultiModal` pref.) The inline run list now appears on the History tab only for a genuine pure runner (no lift/meal exists to populate a timeline) or a run-only mount — not as an offline fallback. **Capture parity (same change):** the Log FAB opens each modality's capture surface directly — run → recorder (the keep-alive page; a live foreground-service session can't be a sheet), lift → `showGymComposeSheet`, food → `showNutritionLogSheet` — instead of pushing the gym list / nutrition day view that forced a second tap.

**Amendment (2026-06-08, mobile) — the three Log actions land on dwell-in pages, not modals; Gym + Nutrition become keep-alive `PageView` pages like the recorder.** The "capture parity" amendment above made the three Log actions one-tap-to-capture but left them *behaviourally* inconsistent: `Log run` navigated to the keep-alive recorder **page** (you stay there for the whole run), while `Log lift` / `Log food` opened a one-shot **modal composer** (fill once, it dismisses back to where you were). A lifter logging a 45-minute session of many sets, or someone logging the day's meals across several sittings, wants the same thing a runner gets — a workspace they land on and operate in — not a modal that closes after one entry. The durable fix, now applied: **all three Log actions navigate to that modality's dwell-in page**, and Gym + Nutrition join Run as in-shell keep-alive `PageView` pages with no bottom-nav destination (`home_screen.dart` pages become `[Home, History, Run, Gym, Nutrition, Social, Settings]`; `_performLogAction` does `_goToPage(_pageGym|_pageFood|_pageRun)`). Each page surfaces its own composer one tap away (`GymScreen`/`NutritionScreen`'s `+`). Keep-alive means an in-progress recording, a half-built workout, or the day's food log survives swiping to Home and back. This is the *inverse* of "capture parity"'s direction (which made lift/food modals) — chosen because a live run is *necessarily* a page (a foreground-service GPS session can't collapse into a modal), so the cheaper way to make all three consistent is to lift Gym + Nutrition up to the page model rather than push Run down to a modal it can't be. The 5-slot nav ceiling ([§ 24](#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)) is unaffected — Run/Gym/Nutrition were never nav destinations. The Home cards + History `View all` still push their own `GymScreen`/`NutritionScreen` instances (a separate path from the Log-FAB keep-alive page).

---

## 64. Offline-pin is a separate local-only flag from star; phone pushes starred routes to Wear OS via DataLayer

**Decided:** May 2026

Two related but distinct knobs landed in the same pass:

- **Mobile** route detail gains a "Save for offline" pin — a local-only flag persisted to a sidecar file (`offline_pinned_route_ids.json`) alongside the existing `synced_route_ids.json`. Toggling it never touches Supabase: pin is a per-device cache-management decision, not a per-route property.
- **Wear OS** gains a `RoutesBridge` listener at the Wearable Data Layer path `/saved_routes`. The paired phone subscribes to its `LocalRouteStore` and pushes the user's **starred** subset on every change via a new `WearRoutesBridge` (Dart → Kotlin → DataClient.putDataItem). The watch overwrites its DataStore-backed `LocalRouteStore` and the live picker in `RunViewModel`, so a watch out of network range stays current the moment the phone has wifi or cellular.

**Why two flags:** *star* gates **what shows on the watch**; *offline-pin* gates **what stays on this phone**. A user might pin a 30-mile training route they want available without service but not want it cluttering their watch picker; conversely, a starred urban run is what they pick on the watch but doesn't need offline persistence on the phone. Collapsing them into a single "favourite" flag forced the watch picker and the phone cache to share a knob neither one fully owns.

**Why DataLayer push, not "watch fetches more aggressively":** before this change, the watch's only path to starred routes was a Supabase fetch on every pre-run screen open. A watch with no LTE and a paired phone that *did* have wifi still saw stale routes, because the fetch failed and the cache was last loaded from the previous time the watch itself had connectivity. DataLayer push routes around the watch's connectivity entirely — the phone is the source of truth, and the watch caches what the phone tells it. Supabase fetch in `refreshRoutes()` stays the canonical refresh path when the watch has its own network.

**Trade-offs accepted:**

- Pin is local-only — a phone restore from backup loses pins, since the sidecar isn't in the Supabase row. Acceptable: pins are device-scoped by intent, and "I'd like this route offline" is a one-tap re-assertion on the new device.
- The watch now has two inbound route sources (phone push + Supabase fetch); they can disagree for the few seconds between a star toggle on the phone and the next Supabase refresh on the watch. Phone push wins for the cache write, Supabase fetch wins for the next picker open — they converge within one fetch cycle.
- Apple Watch is unaffected (the SwiftUI `RouteNavigator` is still stubbed per [apps/watch_ios/CLAUDE.md](../../apps/watch_ios/CLAUDE.md)). When that lands, the same DataLayer-equivalent (`WCSession`) handoff is the obvious shape.

**Don't re-litigate** by:

- Persisting `offline_pinned` to Supabase — it's per-device on purpose.
- Pushing pinned-but-unstarred routes to the watch — the watch picker is intentionally curated by `is_starred`, and pin is a phone-cache concern, not a watch concern.
- Adding a "Pin all routes" bulk affordance — routes are small JSON files, every cached route is already on disk; the affordance the user actually asked for is a per-route opt-in indicator.

---

## 65. CSV import is a summary path, not a replacement for the Backup ZIP

**Decided:** May 2026

Mobile gained a CSV import path on the Import screen (`csv_run_importer.dart`) so users who clicked Settings → "Export runs as CSV" can re-import that file on a fresh install. Two shapes are accepted: the 5-column mobile/web Settings export (`date, distance_m, duration_s, pace_s_per_km, source`) and the 17-column backend `/export-data` GDPR export.

**Lossy by design.** CSV is a summary format — no GPS waypoints, no per-point HR, no laps. The Import screen says so plainly ("won't have a route line"). The full round-trip path is the **Backup ZIP** (`BackupService`), which surfaces alongside CSV on the Import screen and on Settings → "Restore from backup".

**Why surface Backup ZIP on the Import screen (not only in Settings):** users who hit the Import screen with "I have a file, where do I put it?" should see every accepted file type. Burying lossless restore in Settings while showing only Strava + Health on Import drives users to the lossy CSV when they had a better option in their pocket.

**Why CSV import is offline-first:** the parser is pure-Dart, writes to `LocalRunStore` directly, and `_saveImportedRuns` only attempts a Supabase batch push when `api.userId != null`. A user with no internet and no account can re-hydrate from CSV; the runs are queued for sync via the existing `SyncService` drain on next sign-in. Same is true for Backup ZIP — `BackupService.restore` already had an `_restoreOffline` branch (see ADR §44-ish era), and the Settings + Import screen wrappers now thread `routeStore` through so routes hydrate too (was previously a silent skip).

**Idempotency.** Re-importing the same CSV doesn't create duplicates: every row gets a stable `external_id` (`csv:<iso>-<distance>-<duration>` for the 5-column form, original `external_id` column when present in the 17-column form). The `runs.external_id` unique index dedupes server-side; `LocalRunStore.save` replaces by `id` locally.

**Provenance.** Imported rows stamp `metadata.imported_from = 'csv'` + `metadata.imported_at = <ISO 8601>`, joining the existing `strava` / `health_connect` / `garmin` values in the registry (`docs/backend/metadata.md`).

**Trade-offs accepted:**

- CSV-imported runs have empty tracks — the run-detail map will show "no GPS trace" copy rather than a polyline. The Import screen card explicitly warns the user before they click.
- The synthetic external_id collides if two users genuinely run the same distance in the same duration starting in the same UTC second. The collision space is small enough that the unique-index rejection at the DB is the correct failure mode (the second user gets a "row already exists" warning rather than the importer silently merging records).
- A user editing the CSV by hand before re-importing can cause arbitrary rows. That's the cost of a text-based import; the CHECK constraint on `activity_type` + the parser's tolerant-error-collection design keep the worst case bounded.

**Don't re-litigate** by:

- Adding a CSV *track* column. CSV is intentionally a summary; if you want tracks, the Backup ZIP is one tap away.
- Adding any third file format that overlaps with CSV or Backup-ZIP (e.g., an XLSX importer). The two existing summary + lossless paths together cover every legitimate user intent.
- Removing the lossy warning copy ("won't have a route line"). It's the only thing standing between "I imported and the runs have no map" surprise and the user knowing what they're getting.

---

## 66. Backup ZIP writes stream to disk and download tracks in bounded batches

**Decided:** May 2026

`BackupService.createBackup` used to buffer the entire archive in memory before encoding: `Archive` accumulated every `runs.json` + `routes.json` + per-track gzipped blob, then `_encodeArchiveInIsolate` copied entries to a worker isolate and produced one `Uint8List` of the encoded ZIP. For a power user at 5 000 runs (≈ 50 KB gzipped tracks each), peak heap brushed 300 MB+ on the worker side, OOMing mid-tier Android phones. Sequential per-track downloads pushed wall-clock past 8 minutes. Restore had the symmetric problem: `zipFile.readAsBytes()` pulled the full archive into RAM before the decoder ran.

The new shape:

- **Write side** — `writeBackupZipStreaming` opens a `ZipFileEncoder` writing incrementally to the output file. Metadata JSON entries land first. Track downloads run in bounded-concurrency batches (`_kTrackDownloadConcurrency = 6`); each batch's bytes are written to the encoder + dropped before the next batch fires. Peak heap is `O(concurrency × avg-track-size)` — roughly 5 MB regardless of total run count.
- **Read side** — `restore` opens `InputFileStream(path)` and feeds it to `ZipDecoder().decodeStream`. The decoder reads chunks on demand and lazy-loads per-file content; peak heap is the largest single track, not the whole archive.

**Server-side `format=backup` (shipped May 2026, follow-up to the original deferral):** the Go data-export service (`apps/job_worker/internal/dataexport/server.go`) gained a `format=backup` mode that emits the same `run-app-backup` v1 shape `BackupService.restore` reads. Mobile `BackupService.createBackup` tries the server first when `LIVE_HUB_URL` is configured + the user is signed in; **falls through to the local streaming writer on any failure** — non-200 response, IO error, missing access token, server cap-overflow, anything. The cap stays at `MaxRunsPerExport = 5000`. Power users beyond that automatically land on the local writer (which scales past 10 000 runs); typical users get the bandwidth + battery savings of letting the server do the fan-out track downloads. Lifting the cap further needs paginated runs select + streaming Storage upload, both bigger changes than the load-bearing local fix called for. Web has no server-side path because the web app is desktop-shaped — local browser memory handles the writer fine once it switches to per-entry streaming.

**Sanity numbers** (avg 50 KB gzipped per track, 100 ms RTT, 6× concurrent downloads):

| Runs | Wall-clock | Peak heap |
|---|---|---|
| 100 | ~2 s | ~5 MB |
| 1 000 | ~17 s | ~5 MB |
| 5 000 | ~85 s | ~5 MB |
| 10 000 | ~170 s | ~5 MB |

**Trade-offs accepted:**

- Per-file ZIP writes happen on the main isolate. Each write is < 100 ms; the network-await between batches lets the UI service paint events. No `compute()` indirection — the file-handle ownership doesn't cross isolate boundaries cleanly.
- A failed individual track download is swallowed (`debugPrint` only); the run row still ships in `runs.json` without a `tracks/{id}.json.gz` entry. Restore handles this gracefully — the run lands with an empty track. Same partial-success contract the old code had.
- ZIP encoding is not parallelisable on the device side; the bottleneck is now strictly network. Power users on slow links still wait minutes — but they don't OOM.

**Don't re-litigate** by:

- Reintroducing the in-memory `Archive` + `_encodeArchiveInIsolate` shape. The `ZipFileEncoder` + `InputFileStream` arch guard in `architecture_guards_test.dart` pins this; loosening it means OOMs on phones.
- Bumping `_kTrackDownloadConcurrency` past ~12. Storage will start to throttle, and per-phone connection-pool exhaustion shows up as flaky "track download failed" entries. Six is the empirical sweet spot.
- Making the server-side `/v1/export?format=backup` path the only one. The local writer is the safety net for power users (> 5 000 runs), for offline / no-LIVE_HUB_URL builds, and for any IO blip on the Go service.

---

## 67. Offline-saved runs carry a `created_by_user_id` owner tag — defends shared-device sign-out / sign-in

**Decided:** May 2026

The competitive line "Fully offline mode without an account — record locally, sync later if you ever sign in" works for the happy path (record offline, sign up later, runs adopt to the new user). But on a shared device, a second-order bug had been lurking: **if User A signs in, records runs, signs out, then User B signs in, the previously unsynced runs would attempt to push under User B's account.** Supabase RLS rejects every row (`auth.uid()` mismatch), the queue never drains, and User B sees a permanently-stuck "X unsynced" badge for runs that aren't theirs.

The fix is a `metadata.created_by_user_id` tag stamped at save time, plus a filter in `SyncService` that excludes foreign-owner runs from the batch push.

- **`LocalRunStore` exposes `currentUserIdProvider: String? Function()?`** — production wires `() => api?.userId` in `main.dart`. Each `save()` calls it; non-null/non-empty userIds stamp the metadata, null/empty leaves the tag absent (the signed-out case).
- **`SyncService` consults `filterRunsForCurrentUser(runs, userId)` before invoking `saveRunsBatch`.** Untagged runs (legacy, or saved while signed out) adopt to the current user. Runs tagged with the current userId push normally. Runs tagged with a different userId are silently skipped + logged — they wait in the queue for their rightful owner to sign back in.
- **`update()` does NOT re-stamp.** The owner is whoever recorded the run, not whoever's signed in when the edit happens — important on a shared device where B might edit one of A's run titles.
- **`saveFromRemote()` does NOT stamp.** Cloud-sourced rows carry their own `user_id` column; the local tag is only for run-was-created-here ownership.

**Why a metadata key, not a Run.userId field:** schema-free path. Adding `userId` to the `Run` domain model would propagate through `core_models`, `db_rows.dart` codegen, every JSON test fixture, and trigger a migration to add a `created_by_user_id` column. Using `metadata.jsonb` (already a free-form bag — see `docs/backend/metadata.md`) is one field, zero codegen, zero migration. The cloud-side `runs.user_id` column remains authoritative for server-side ownership; the metadata key is the *device-side* ownership marker.

**Why not wipe the queue on sign-out:** data loss. A user who signs out while they have unsynced runs almost always wants to sign back in and push — wiping would silently lose recorded GPS data. The owner tag is the safer path: keep the queue, just skip foreign rows during drain.

**Trade-offs accepted:**

- A user who genuinely wants to "claim" their previous account's runs (e.g. forgot which email they used) has no in-app affordance today. The runs are stuck in the queue until they sign back in with the right account. A future "adopt these runs to me" UI prompt is the natural follow-up; the wire is in place via `LocalRunStore.withCreatedByUserId`.
- The skipped-foreign-runs warning is `debugPrint` only. No UX surface yet. Listed in `roadmap.md` as a follow-up.
- A user who signs out + uninstalls + reinstalls + signs in as someone else loses the queue entirely — the unsynced runs were on the local disk and the uninstall wiped them. This is the "uninstall = lost runs" trade-off documented in `parity.md`, unchanged by this work.

**Don't re-litigate** by:

- Adding a `Run.userId` field — the metadata key is intentional; codegen churn isn't worth it for a device-side ownership marker.
- Wiping the queue on sign-out — data loss, see above.
- Stamping the tag during `saveFromRemote` — would mask cross-user contamination on the read path (a row from A's cloud account being pulled while signed in as B should be flagged, not silently re-stamped).
- Stamping during `update()` — would mean edits transfer ownership; B editing A's title would steal the run.

---

## 68. Tile rendering honours an env override so local dev can use self-hosted Protomaps without touching prod code paths

**Decided:** May 2026

The risks section of `competitors.md` flags map tile costs at scale: MapTiler has a generous free tier, but the per-request meter becomes a real cost line as DAU grows, and a demo build with a MapTiler key baked into the binary is a leak waiting to happen. The medium-term answer is self-hosted Protomaps on S3/CloudFront with PMTiles served via HTTP Range requests — a future project. The short-term answer is letting dev/demo/integration sessions point at a **local Protomaps tileserver-gl** so the production quota isn't burnt during development.

Three env vars opt into the local path. When unset, every code path falls back to MapTiler — production is unaffected.

- **Web** — `PUBLIC_TILE_STYLE_URL` (MapLibre style.json URL). Implemented in `apps/web/src/lib/routes/map-style-url.ts` (pure `buildMapStyleUrl`) + `map-style.svelte.ts` (`mapStyleUrlFromEnv` reads `import.meta.env`). Every map component imports the env-aware variant.
- **Mobile (Android + iOS twin)** — `TILE_URL_TEMPLATE` (`{z}/{x}/{y}` template). Implemented as the file-level `resolveTileUrl(env)` in `apps/mobile_android/lib/widgets/live_run_map.dart`.
- **Wear OS** — `PUBLIC_TILE_URL_TEMPLATE` BuildConfig field (BuildConfig because the value is baked at compile time, not loaded at runtime). Implemented as file-level `buildTileUrl(z, x, y, template, maptilerKey, styleSlug)` in `apps/watch_wear/.../ui/TileSource.kt`. The `TileSource.enabled` flag now lights up when EITHER the dev override OR the MapTiler key is set, so a dev session without a MapTiler key still gets tiles.

**Why three separate env vars instead of one:** each platform has its own dotenv-style convention and the wire format differs (web needs a style.json URL, mobile/Wear need a tile-URL template). A single unified name would still need per-app shape handling at the call sites — three narrow names is the cleaner shape.

**Why an env override rather than a feature flag:** flags imply runtime decisions and a UI affordance. This is a build-time configuration that one operator (the developer) flips once per machine. Env vars stay scoped to that audience without surfacing complexity to users.

**Why not migrate production at the same time:** production migration involves picking a hosting strategy (S3 + CloudFront vs Cloudflare R2 vs reusing the existing `infra/modules/web-stack` infra), tile-pipeline build cadence (daily extract from OSM? continuous?), style hosting (alongside the PMTiles or a separate static bucket?), fallback strategy (MapTiler for the long tail of un-prebuilt regions?), and a real cost projection. Each of those is a meaningful judgement call deferred to a separate ADR when the cost line crosses our pain threshold.

**Trade-offs accepted:**

- Three env-var names instead of one keeps the convention boundary clean but means three places to remember when bootstrapping a new dev machine. The bootstrap script (`bin/protomaps-dev.sh env`) prints all three.
- The Wear OS override requires a Gradle rebuild (`./gradlew installDebug -PPUBLIC_TILE_URL_TEMPLATE=…`) because BuildConfig is compile-time. Mobile + web pick up the override on next `flutter run` / `npm run dev` without recompiling.
- The dev style.json is intentionally minimal — earth + water + road lines, no labels or place names. A future fully-featured dev style is straightforward (drop a real basemap into `$PROTOMAPS_HOME/style.json`) but not necessary for the wire test.

**Don't re-litigate** by:

- Renaming the three env vars to a single one — wire formats differ, callers would still need to know which is which.
- Making the local path the default — production code paths must not depend on a Docker daemon being available on every developer machine, and demos at conferences shouldn't require a tileserver to boot before the booth opens.
- Adding a runtime UI toggle for the override — env-var-only is on purpose; users shouldn't be able to flip this.
- Wiring the production migration through this ADR — it's intentionally scoped to dev. The production decision is a separate ADR when the cost line forces it.

See [`docs/ops/protomaps_local_setup.md`](../ops/protomaps_local_setup.md) for the recipe.

---

## 69. Live spectator: dual-path (Supabase Realtime + Go live-hub) coexists; cutover is a per-deploy env flip, not a flag day

The live-spectator surface has two transports:

- **Supabase Realtime** on `live_run_pings` (original path). The recorder inserts rows; spectators subscribe via the `postgres_changes` channel. Server-side privacy-zone clipping is enforced by the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger (migration `20260618_001`).
- **Go live-hub** at `apps/job_worker/internal/livehub/` (newer path). Recorder POSTs to `/v1/live/{run_id}/push`; spectators subscribe via WebSocket. Server-side privacy-zone clipping is enforced by `Server.shouldDrop` reading `Hub.LoadZones` (fetched lazily from Supabase by the worker's service role).

**Both paths stay in the codebase until the live-hub deploy has bedded in.** The mobile recorder (`LiveBroadcaster`) gates on `dotenv.env['LIVE_HUB_URL']`: when set, it POSTs to the hub; when unset, it falls through to `ApiClient.insertLivePing`. The web spectator (`/live/[id]`) gates on `PUBLIC_LIVE_HUB_URL` the same way. Cutover is therefore a **per-deploy env flip**, not a flag day — flipping `LIVE_HUB_URL` on for a beta cohort lets the operator gauge the Go path against the Realtime baseline without orphaning anyone who still has the old build cached.

**Concretely:**

- **Recorder duplication is avoided** by the `dotenv` gate — a single ping flows down exactly one transport per app build. There is no "publish to both then dedupe on the spectator side" path; the audit looked for that race and confirmed it's not present.
- **Spectator handover during a single run** is acceptable but rare: a spectator who opens the page after the recorder flipped sees the hub path; one who opened before sees Realtime. They don't observe both. The Realtime channel survives independent of the new path so historical broadcasts replay correctly from the `live_run_pings` table.
- **Privacy-zone enforcement parity**: both transports MUST drop in-zone pings server-side. Pinned by `apps/backend/supabase/tests/rls_live_run_pings_trigger_test.sql` (Realtime) and `apps/job_worker/internal/livehub/server_test.go` `TestServer_PingInsideZoneIsDropped` + `TestServer_ZoneFetchFailureDropsFailClosed` (hub).
- **JWT auth enforcement** rolls out via the `LIVEHUB_REQUIRE_AUTH=1` sentinel on the Fly app (migration `20260930` round). Prod refuses to start without `SUPABASE_JWT_SECRET` + `LIVEHUB_ALLOWED_ORIGINS`. Mobile + web clients now Bearer the recorder JWT (mobile `live_hub_client.dart` + web `live_hub.ts` querystring `?token=…` fallback for the WS upgrade — browsers can't set Authorization on a WS handshake).

**Don't re-litigate** by:

- Merging the two transports into a single client-side adapter that publishes to both — duplicate spectator events + cache-coherence headaches in the per-room caches.
- Routing the Realtime path through the Go hub as a proxy — the whole point of Realtime is that it's already a Postgres-native fan-out path with RLS. Layering would defeat both transports.
- Removing the Realtime path before the hub deploy has 60+ days of live traffic — the trigger pgtap test is the load-bearing privacy guard if the hub's `Server.shouldDrop` ever regresses.

Audit reference: `/audit/livehub` May 2026 M5.

---

## 70. CSP `script-src 'unsafe-inline'` is an accepted risk under adapter-static; DOMPurify is the load-bearing XSS guard

The CloudFront response-headers policy sets `script-src 'self' 'unsafe-inline'`. `'unsafe-inline'` defeats the script-execution-mitigation purpose of CSP: an injected `<script>` tag (or inline event handler) would execute freely if XSS ever lands in the rendered HTML.

We ship this knowingly. Three reasons:

1. **`@sveltejs/adapter-static` bakes per-page hydration scripts directly into the emitted HTML files** without a build-time nonce. Removing `'unsafe-inline'` would break every page load (hydration fails → blank screen).
2. **Switching to a server-rendered SvelteKit adapter** (`adapter-node` behind CloudFront, or `adapter-vercel`) is the canonical fix. It's a real architecture change — server cold-start latency, container-orchestration cost, deploy-pipeline rework — and the cost is unjustified for a pre-launch product with no measured XSS surface.
3. **The actual XSS attack surface is gated at one sink**: the AI Coach's `{@html}` block in `CoachChat.svelte`, which routes through DOMPurify (`apps/web/src/lib/coach/markdown.ts`) with a narrow `ALLOWED_TAGS` / `ALLOWED_ATTR` / `ALLOWED_URI_REGEXP`. Every other user-controlled string in the app is rendered via Svelte's auto-escaping `{expr}` syntax. The OG image generators escape via `xmlEscape` before SVG embedding.

What this commits us to:

- **DOMPurify is the load-bearing XSS guard.** Removing it, widening its `ALLOWED_*` lists, or adding a second `{@html}` sink anywhere in the app requires a `/safe-edit` cycle + an updated entry here.
- **Re-validate the assumption** when a real CSP-tightening lever appears (CloudFront Functions for per-response nonce injection, an `adapter-node` migration, etc.).
- **Document in the CSP comment block** in `infra/modules/web-stack/main.tf` so a future contributor reading the policy doesn't waste a day trying to "fix" `'unsafe-inline'` without understanding the trade-off.

Audit reference: `/audit/owasp` May 2026 High #1.

**Amendment (2026-06-02) — the `script-src` gap is now mitigated with build-time hashes.** Reason #1 above was incomplete: the choice is not "nonce or nothing." For a *fully prerendered* site a nonce is impossible (a static file is byte-identical to every visitor, so a baked-in nonce is a constant), but **SHA-256 hashes** are exactly the right tool, and SvelteKit emits them natively. `svelte.config.js` now sets `kit.csp = { mode: 'hash', directives: { 'script-src': ['self'] } }`; SvelteKit hashes each page's inline hydration script at build time and ships a per-page `<meta http-equiv="content-security-policy">` whose `script-src` is `'self'` + that hash and **no `'unsafe-inline'`**. Browsers enforce the header CSP and the meta CSP as separate policies (a script must satisfy both), so the meta is the binding `script-src` layer — an injected inline script's hash is absent and it is blocked. The CloudFront header keeps `script-src 'unsafe-inline'` only as the permissive baseline that lets the legitimate inline script reach the meta-hash check; it can't carry the per-page hashes itself (one static header, many pages). `style-src` is deliberately left on `'unsafe-inline'` (Svelte `style=""` attributes can't be hash-covered and style injection isn't script execution). The one hole — a prerendered server `redirect()` page emits a stub with an un-hashed inline `location.href` script — was closed by converting `/settings` to a client-side redirect (matching `/clubs`/`/feed`/`/explore`); `tests-e2e/cross-cutting/csp-hash.spec.ts` guards both the config and the no-server-redirect-stub invariant. DOMPurify remains the first line at the `{@html}` sink; the hash CSP is now the genuine second line. (audit-xss M2.)

---

## 71. Own-hardware (an ultra-marathon watch) stays research-only; watch development is deferred indefinitely

We're considering whether to compete with Garmin Fenix / COROS Vertix in the ultra-marathon segment by building our own wrist device. **No decision has been made.** This entry records the *current default* (do not start hardware work) along with the cost ranges and triggers that would have to flip for that default to change. The research lives at [`docs/custom_watch/`](../custom_watch/README.md) — vision, competitive landscape, BOM, three-tier cost prototyping, performance path, firmware plan. The tier-1 bench-prototype firmware workspace (permitted by the 2026-05-28 amendment to this entry, below) lives at [`apps/custom_watch/`](../../apps/custom_watch/README.md).

Why the current default holds:

1. **The app is the moat, not the hardware.** Every dollar spent on hardware is a dollar not spent on the software stack that already differentiates us across web + Android + iOS + Wear OS + watchOS. The hardware path competes with our own roadmap for budget.
2. **The cost-to-first-production-intent-unit is ~$300–600k cash and 18–24 months calendar** with a small team of EE + ID + mech-E + RF consultant + firmware lead. Even tier-2 (a "wearable prototype" that isn't shippable) is $15–40k DIY or $80–250k consultant-built. Only tier 1 — a $1–2k bench prototype — is realistic for a single developer in evenings.
3. **The hardware niche is genuinely real** — Garmin / COROS / Suunto own ultra, the UIs are widely criticised, the buying demographic is technical and word-of-mouth driven. The cleanest entry vector is probably as a software partner to an ODM (the COROS-2018 playbook) or as a custom-firmware layer on an existing watch, rather than a clean-sheet PCB.
4. **Wear OS is the wrong base** for the ultra battery target (~24–40hr GPS ceiling vs the 100hr+ target the segment requires). The right base is a low-power RTOS (Zephyr or FreeRTOS) on an Ambiq Apollo4 or similar — i.e. a custom firmware project, not an app project.

What this commits us to:

- **`docs/custom_watch/` is a research baseline, not a roadmap commitment.** Nothing tracked there should appear in the roadmap's phase-tagged sections; it lives under `## Future — Hardware` as a parking-lot only.
- **Re-open the question** when one of: (a) the app has a paying user base large enough to fund a parallel hardware effort without starving the software roadmap, (b) an existing ODM approaches us about a white-label deal, or (c) a co-founder with shipped-consumer-hardware experience joins the project.
- **Don't grow `docs/custom_watch/`** with detailed schematics, EAGLE files, or PCB-CAD source until one of the above triggers. The current resolution (README + vision + competitive_landscape + bom + prototyping + performance_path + firmware + parts) is right for "research baseline"; more detail is sunk cost until the default flips. Tier-1 *firmware* code is permitted per the amendment below and lives under [`apps/custom_watch/`](../../apps/custom_watch/README.md), not here.

Don't re-litigate by:

- Treating "we have an app and a watch app, therefore we should also have a watch" as a logical next step. The economics in [`custom_watch/prototyping.md`](../custom_watch/prototyping.md) are the point of this entry.
- Spending discretionary engineering time on tier-1 bench prototypes "to keep the option warm." The option stays warm because the docs exist; building hardware on a hobby budget is how projects accidentally become consumer-electronics companies.

**Amendment (2026-05-28) — tier-1 personal investigation permitted.** Owner is starting tier-1 bench-prototype work personally as an evenings-and-weekends investigation. The [`apps/custom_watch/`](../../apps/custom_watch/README.md) directory now exists for this; treat it as research-tier scaffolding, not a product commitment or a roadmap line item. The cost discipline above still binds tier 2+ — no PCB CAD or schematic files, no case CAD, no RF consultant spend, no ODM conversations, no marketing of "we're building a watch" — until one of triggers (a/b/c) above fires. The language / RTOS choice was made the same day in [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) (Embassy on Rust on the Nordic nRF52840). If tier-1 work shows the firmware path is intractable for a single developer, the right move is to delete `apps/custom_watch/` and revert this amendment rather than escalate.

---

## 72. Bag-backed prefs are cached on disk on mobile; offline writes queue + drain on reconnect

The Settings → Preferences screen on mobile reads ~17 keys from `user_settings.prefs` + `user_device_settings.prefs` (DOB, resting/max HR, HR zones, weekly goal, week start, default activity, map style, pace format, default privacy, Strava auto-share, coach personality, auto-pause threshold, etc.). Before this change `SettingsService.load()` only succeeded with a live network round-trip — a signed-in user on an airplane saw every bag-backed tile go inert with "Sign in to edit profile-level settings", even though their account *was* signed in. Editing was also impossible: `updateUniversal` / `updateDevice` threw on the server PATCH.

**Decision:** `SettingsService` now accepts a pluggable `SettingsCache` (`packages/api_client/lib/src/settings_service.dart`). Mobile supplies a `SharedPrefsSettingsCache` (`apps/mobile_android/lib/settings_cache.dart`, mirrored to iOS). On `load()` the cache hydrates the in-memory bags *before* the network fetch, so reads light up immediately. On `updateUniversal` / `updateDevice` the change is applied to in-memory + cache first; the server PATCH is best-effort and queues a `PendingSettingsChange` on failure. On the next successful `load()` the queue drains — each pending change runs `applyPrefsChanges` against the freshly-fetched server bag so a concurrent write from another device isn't clobbered.

Trade-offs:

- **Cache scope is per-user, per-device** for the device bag, per-user for the universal bag. Sign-out drops nothing automatically; if a different user signs in on the same device they read their own cache (which starts empty until their first load). The previous user's rows stay on disk until that user signs back in — acceptable because they only contain settings, not run data, and the rows are keyed so cross-user reads are impossible.
- **Server is still authoritative.** The cache is a read-through + write-through mirror, not a source of truth. A cross-device concurrent edit during an offline window is resolved at queue-drain time by the same read-merge-write that already protects online writes (see decisions §… on the original `applyPrefsChanges` lift).
- **Web doesn't get this layer.** Web sessions are a single tab on a browser with always-on connectivity assumptions, and the existing `apps/web/src/lib/settings/settings.ts` doesn't currently need the queue. The contract on `SettingsService` is mobile-aware (the default `SettingsCache` is a no-op) so server-side tests + the web's TS port don't pay for the abstraction.
- **Cache wire format is JSON.** No migration required when a new prefs key joins the registry — `applyPrefsChanges` round-trips it.
- **`load()` never rethrows on a signed-in caller**, even when both the cache and the server are unavailable. It returns with empty bags + `isServerHydrated = false`. A signed-in user who first opens the app offline gets a usable Settings screen — writes apply to in-memory + cache and queue for the next successful drain. Pre-fix the cache-miss + server-fail path threw, forcing every bag-backed tile into the disabled "Sign in to edit profile-level settings" state even though the user *was* signed in.

Don't re-litigate by:

- Adding a "force refresh from server" button. The queue drain on next successful load is sufficient; an explicit refresh would surface a UI state that doesn't exist on web (where there's no offline mode).
- Caching values for signed-out users. Bag-backed prefs are user-scoped by definition — a user without an account has nothing to cache.
- Trying to use the cache as a primary store for non-bag data (gear, runs, devices). Each of those has its own storage characteristics (Storage objects, gpx blobs) and deserves its own per-table cache (see e.g. `LocalRunStore`).

Pinning tests: `packages/api_client/test/settings_cache_test.dart` (contract for the abstract `SettingsCache`), `apps/mobile_android/test/settings_cache_test.dart` (SharedPreferences round-trip + per-user scoping + corrupt-JSON guard).

---

## 73. Gear has a `LocalGearStore` mirroring `LocalRunStore`; client-minted UUIDs sidestep temp-id reconciliation

Settings → Gear was the last bag-backed surface on mobile that required a live network round-trip for both reads and writes. A signed-in user on an airplane saw "Failed to load gear: …" and lost every CRUD path. The fix mirrors the long-standing `LocalRunStore` pattern.

**Decision:** `LocalGearStore` (`apps/mobile_*/lib/local_gear_store.dart`) is a disk-backed `ChangeNotifier` that holds the `gear_with_distance` rows + a per-row `GearSyncState`. `GearScreen` reads + writes through the store; a best-effort `replaceFromServer` overlays the latest mileage when online; `syncWithServer(api)` drains pending rows in create → update → delete order. Offline-created rows use a client-minted v4 UUID that becomes the server id on the eventual `INSERT` — so no temp-id reconciliation pass is needed (the `gear.id` column defaults to `gen_random_uuid()` but accepts client values).

Sync-state rules:

- `pendingCreate` on a fresh local row; preserved across subsequent `updateLocal` calls so the next sync replays the full INSERT with the merged values.
- `pendingUpdate` on a synced row that's been edited locally; the next sync sends a PATCH.
- `pendingDelete` is a tombstone: synced rows stay in the in-memory map (excluded from `rows`) until the next sync issues the server DELETE, then the file is dropped. A `pendingCreate` row that's deleted locally vanishes immediately — no tombstone, since the server never saw it.

Trade-offs:

- **Mileage is stale offline.** `total_distance_m` comes from the `gear_with_distance` view, which joins on `runs`. Offline edits to a run aren't reflected in the cached gear mileage; the value refreshes on the next online `replaceFromServer`. Acceptable because mileage drift is bounded by "how recent was your last sync" and the same constraint applies on the web `/settings/gear` view (which makes no offline pretence at all).
- **Cross-device editing during an offline window has last-write-wins semantics.** If User A retires a shoe on phone, and offline-User-A-on-tablet renames the same shoe, the next sync from tablet sends a PATCH that overwrites the retire stamp with `retired_at=null`. The same pattern exists for `LocalRunStore` edits; addressing it would need per-row vector clocks. Out of scope.
- **Gear cache persists across sign-out** (no `dropUser` hook today). On a shared device, User B signing in sees an empty server fetch and `replaceFromServer` drops every `synced` row — but a `pendingCreate` row from User A would survive and try to sync under B's account. Mitigation: the same `created_by_user_id` ownership tag pattern from `LocalRunStore` (decisions §67) should be added in a follow-up; for now `LocalGearStore` is best-effort offline and assumes a single-user device.

Don't re-litigate by:

- Adding a "Sync gear now" button. The on-mount `replaceFromServer` + drain is automatic; an explicit button would surface a UI state that doesn't exist for runs.
- Reaching for a temp-id table or remapping layer. The `gen_random_uuid()` default on `gear.id` was the load-bearing choice — pinning a client-minted UUID at create time avoids the whole problem.

Pinning tests: `apps/mobile_android/test/local_gear_store_test.dart` covers create → update → retire → delete lifecycle, drain semantics, and reload-after-restart.

---

## 74. New-gear post-save flow proposes attaching past runs since `purchased_at`

A common pattern when adding gear is "I've been running in these shoes for a week — they're already at 30 km but the app shows 0." Pre-fix, the only path to attach past runs was to open each run's detail screen and pick the gear from the run-gear modal. Tedious and discoverable only if you knew the surface existed; Strava and Garmin both punt on this entirely.

**Decision:** when the user creates a new piece of gear with a past `purchased_at` and there's an online api + a `LocalRunStore` in scope, post-save we show a modal sheet listing every run since that date whose activity-type matches the gear kind (`shoe` ↔ run / walk / hike, `bike` ↔ cycle). All candidates are selected by default; the user can deselect individuals or toggle Select-all. Confirm fires a single `ApiClient.addGearToRuns(gearId, runIds)` call that upserts into `run_gear` with `ignoreDuplicates: true` so a row the user had already attached by hand is silently no-op'd.

Shape choices:

- **Trigger**: only post-CREATE (not post-edit). A user editing existing gear is already attached or has consciously chosen not to be; we don't want a surprise prompt on every save.
- **Anchor date**: `purchased_at`. If the user leaves it blank we skip the prompt — without a "use since" anchor there's no honest filter we can apply.
- **Activity filter**: by gear `kind`. Shoes match run / walk / hike (the existing trail-run alias); bikes match cycle.
- **Online-only**. Offline-created gear stays as a `pendingCreate` row in `LocalGearStore` until sync drains it; we don't queue the `run_gear` inserts alongside because that would need a parallel pending-write layer for the join table. The user can re-trigger backfill manually by editing the gear once it's synced — *deferred* until someone hits the offline-add path enough to justify the plumbing.
- **Pure helper**: `gearBackfillCandidates(gearKind, since, runs)` lives in `apps/mobile_*/lib/gear_backfill.dart` with 9 unit tests so the matching rules can evolve (new activity types, new gear kinds) without re-deriving them from the UI.
- **Duplicates are idempotent.** The upsert with `ignoreDuplicates` means a re-run of backfill (e.g. user adds a second pair of shoes whose period overlaps) doesn't error.

Trade-offs:

- **No web parity yet.** Web's `/settings/gear` form doesn't have this surface today. Flagging as a parity gap in `docs/product/parity.md` (Phase 1 row); when web ships the same we can converge on the matching rules via the shared `lib/training_load.ts` pattern (TS port of the Dart helper).
- **Mileage refresh latency.** After backfill the rolled-up `total_distance_m` on `gear_with_distance` recomputes server-side; the screen re-fetches on `_refresh()` so the new total appears within a frame. A pull-to-refresh from the user would also work.
- **No "remove backfill" path.** Once a user attaches gear to a run via the sheet, undoing means visiting that run's detail screen. We could add a "manage backfilled assignments" view; deferred until someone asks.

Don't re-litigate by:

- Auto-attaching without the confirmation sheet. The whole point of the prompt is the user might've worn different gear for some of those runs (a tempo shoe vs an easy shoe). Silent attach would land wrong data quickly.
- Reaching for a sync-state tracker on `run_gear`. The upsert is idempotent and the table is tiny per gear — no caching layer needed for now.

Pinning tests: `apps/mobile_android/test/gear_backfill_test.dart` (9 unit tests on the pure helper) + `apps/mobile_android/test/gear_backfill_sheet_test.dart` (4 widget tests on the sheet's selection + confirm + skip flows). iOS twin mirrors both.

---

## 75. Sec-GPC: 1 hard-overrides the consent cookie on the server, and `navigator.globalPrivacyControl` auto-rejects the banner on the client

Persona-hunt Round 3 finding Privacy #4. Pre-fix the cookie-consent banner ignored the Global Privacy Control signal entirely: a Firefox / Brave / DuckDuckGo / iOS Safari user with the browser-level GPC toggle on still saw the banner asking them to accept (already wrong — they opted out at the browser level), and the server-side `isConsentGiven(request)` gate read only the `cookie_consent` cookie, so Sentry + other consent-gated paths would fire for a GPC-on user until they manually clicked Reject.

Behaviour:

- **Client banner (`CookieConsentBanner.svelte`)**: on mount, if `navigator.globalPrivacyControl === true` AND the local choice is still pending, auto-call `consent.set('rejected')` and never show the banner. The "rejected" choice persists to localStorage + the cookie, so future loads see a consistent state without needing GPC to be re-read.
- **Server gate (`isConsentGiven(request)` in `apps/web/src/lib/settings/consent_cookie.ts`)**: short-circuits to `false` when `Sec-GPC: 1` is present, regardless of what the cookie says. A user who once accepted but later flipped their browser-level GPC toggle has withdrawn consent; the gate honours the new signal immediately, not on next manual visit.

Why this exact shape:

- **GPC is a binding opt-out, not a hint.** California AG + Colorado AG have ruled GPC is a binding "Do Not Sell / Share" signal under CCPA/CPRA + CPA; the EDPB treats it as an objection signal under GDPR Art 21. We can't show the banner asking again or load consent-gated SDKs on the side.
- **Header is the source of truth, not the cookie.** A user can flip the browser-level toggle without revisiting the site. The cookie reflects whatever they did at last visit; the header reflects current preference. When they disagree, the header wins.
- **`Sec-GPC: 0`** is "no opt-out" — distinct from "no signal". Some clients send it explicitly. Our `hasGpcSignalFromHeader` checks for `"1"` exactly so a `"0"` doesn't accidentally light up an else branch.

Don't re-litigate by:

- Showing the banner with a pre-checked "Reject all" when GPC is on. The whole point of GPC is the user shouldn't have to interact with another consent surface — auto-dismiss + auto-persist is the right shape.
- Reading `navigator.globalPrivacyControl` on the server. The header is what server-side code sees; the navigator property is what client-side code sees. Different surfaces, same signal.

Pinning tests:

- `apps/web/src/lib/consent_cookie.test.ts` — 13 tests across the cookie helper, the GPC helper, and the combined `isConsentGiven` gate (including the GPC-hard-overrides-accepted-cookie case).
- `apps/web/tests-e2e/cross-cutting/cookie-consent.spec.ts` — Playwright spec defines `navigator.globalPrivacyControl=true` via `addInitScript`, then asserts the banner never shows AND `cookie_consent` persists with `choice='rejected'`.

---

## 76. Training-pace derivation applies a 3% female-specific calibration to the Daniels curve

Persona-hunt Round 3 finding Woman #3. Daniels' VDOT formula (`vdotFromRace`) and the pace bands derived from goal pace (`pacesFromGoalPace`) were calibrated on a predominantly male dataset. Female runners' actual VDOT plotted on the male-default curve under-predicts their training paces by ~3-5% depending on the band — the runner is being prescribed easier-than-necessary paces across the board.

What we changed:

- `pacesFromGoalPace(goalPaceSecPerKm, gender?)` — optional second parameter. When `gender === 'female'`, the helper multiplies every band's seconds-per-km by `1.03` (3% slower). `male` / `null` / `undefined` / `nonbinary` use the original (male-derived) curve.
- `resolveTrainingPaces({...gender?})` and `GeneratePlanInput.gender` thread the option through.
- The plan wizard (web `PlanEditor.svelte`, mobile `plan_new_screen.dart`) reads `user_profiles.gender` on mount and passes it in. The runner doesn't see a new field — the gender they already set in Settings → Preferences for the segments-leaderboard demographics is reused. Null when unset → unchanged paces (back-compat).

Why uniform 3% rather than per-band:

- Sport-science literature suggests female calibration corrections in the 2-5% range depending on intensity zone. A single uniform multiplier under-prescribes at the extreme bands (especially repetition/interval) but is the right shape for the data we have — no per-band gender × VDOT calibration has been published with the rigour required to override Daniels.
- Uniform multiplier keeps the helper a pure single-line tweak that's easy to audit. When better data is published we can replace the constant with per-band weights without changing the call surface.
- The conservative direction (slower) is the right error mode — over-prescribing female athletes' paces is the harm we're correcting.

Why `nonbinary` defaults to the unmodified curve:

- No validated calibration exists for non-binary athletes. Applying a wrong adjustment is worse than no adjustment. The conservative default is documented + pinned by a test so a future contributor doesn't silently fork this branch.

Don't re-litigate by:

- Asking gender in the plan wizard. The data already lives on `user_profiles.gender` (set in Settings → Preferences under the segments-leaderboard demographics with explicit GDPR Art 9 consent). Double-asking is friction.
- Surfacing the calibration in the UI. It's an algorithmic correction, not a visible feature — runners just see paces that better match their physiology. Calling it out invites bikeshedding on the exact constant.

Pinning tests:

- `apps/web/src/lib/training.test.ts` — 3 new tests cover (a) omitting gender returns the existing (male-curve) values, (b) female calibration shifts every band 2-5% slower with the easy band ratio in `[1.02, 1.05]`, (c) nonbinary falls back to the unmodified curve.
- `apps/mobile_android/test/training_test.dart` + iOS twin — same 3 tests in lockstep.

---

## 77. Calorie estimate honours body weight + applies a 5% female-specific cross-formula calibration

Persona-hunt Round 3 finding Woman #5. Pre-fix the run-detail calorie cell used two slightly different formulas:

- Web (`/runs/[id]/+page.svelte`): `kcal = weight_kg × distance_km`. The 1 kcal/kg/km running heuristic. Ignored the activity type entirely.
- Mobile (`run_detail_screen.dart`): `kcal = weight_kg × activity_kcal_per_kg_per_km × distance_km`. Activity-aware (1.0 run, 0.5 walk, 0.7 hike, 0.4 cycle).

Neither honoured gender. The standard sport-science observation is that female runners' absolute energy expenditure at the same MET intensity is ~5% lower than male's (smaller skeletal-muscle mass per kg total body weight). Pre-fix every female runner was over-estimated by roughly that 5%.

What we changed:

- New shared pure helper `estimateRunCalories({ distanceM, weightKg?, activityKcalPerKgPerKm?, gender? })` in `apps/web/src/lib/runs/calories.ts` ↔ `apps/mobile_android/lib/calories.dart` (byte-identical iOS twin). Both surfaces now route through it so the formula is in lockstep.
- Activity coefficient defaults to the run value (1.0) — drop-in compatible with the web's previous formula. Web now also accepts an activity argument and threads `metadata.activity_type` through, so walks / hikes / cycle no longer get the run multiplier silently applied.
- Body weight falls back to `DEFAULT_BODY_WEIGHT_KG = 70` (median for an adult runner) when `user_settings.prefs.body_weight_kg` is unset. The "(est)" suffix on the label keeps the fallback honest — runners who care about precision see the cue + set their real weight in Settings → Preferences.
- Gender calibration: `female` multiplies the output by `0.95`. `male` / `null` / `nonbinary` use the unmodified curve. Same `user_profiles.gender` column the training-pace calibration (§76) and segments leaderboards already use.
- Negative `distanceM` is clamped to 0 so a buggy upstream can't surface a "burned −300 kcal" badge. Zero / negative weight or coefficient falls back to default. Defensive shape pinned by unit tests.

Why uniform 0.95 rather than per-pace adjustment:

- The literature suggests 3-8% depending on speed + slope. A uniform mid-range constant under-prescribes at extreme paces but is the right shape for the data + complexity budget.
- Conservative direction (lower) is the right error mode — the 1 kcal/kg/km heuristic already over-estimates for short slow efforts where the user typically wants a credible-ish number, not a target.

Why `nonbinary` defaults to the unmodified curve:

- Same reasoning as the training-pace calibration in ADR §76 — no validated calibration for non-binary athletes; applying a wrong adjustment is worse than no adjustment. Documented + pinned by a test so a future contributor doesn't silently fork this branch.

Don't re-litigate by:

- Adding a separate per-band coefficient for female runners. Until per-band gender × intensity calibration is published with the rigour required to override the current ladder, the uniform 0.95 stays.
- Asking gender in the run-detail UI. The data already lives on `user_profiles.gender` (set in Settings → Preferences alongside the segments-leaderboard demographics with explicit GDPR Art 9 consent). The calorie cell silently honours it; no new UI surface.

**Wear OS (persona samsung #34, 2026-05-29):** the watch's PostRun summary now shows the same estimate via a Kotlin port — `RunCalories.estimate(distanceM, weightKg?, activityType)` in `apps/watch_wear/.../recording/RunCalories.kt`, reading `body_weight_kg` from the prefs bag (added to `UniversalSettings`). One deliberate divergence: the watch reads only `user_settings.prefs`, not the `user_profiles` row, so it can't apply the gender calibration — it computes the unmodified curve. That only affects the wrist's own glanceable figure; the run-detail pages recompute with gender once the run syncs. Documented in `RunCalories.kt`. Pinned by `RunCaloriesTest.kt` (5 tests) + the `body_weight_kg` parse case in `UniversalSettingsTest.kt`.

Pinning tests:

- `apps/web/src/lib/calories.test.ts` — 11 tests across defaults + weight scaling, activity coefficient, gender calibration, and the negative-distance / zero-weight edge cases.
- `apps/mobile_android/test/calories_test.dart` + iOS twin — same 11 tests in lockstep.

Sources:

- Daniels, J. — *Daniels' Running Formula*, 3rd ed. — the male-derived VDOT + pace base.
- Ainsworth et al. — *Compendium of Physical Activities*, 2011 update — MET coefficients for running / walking / cycling.
- Ten Haaf & Weijs (2014), *PLoS ONE* — gender-specific REE + active-energy corrections; reported female calibration in the 3-8% range across endurance modalities.

---

## 78. Post-signup onboarding wizard at `/onboarding` — step-by-step, skippable per step, gated by `user_profiles.onboarded_at`

New-runner persona's #1 finding-area was "after sign-up the persona is dropped at an empty dashboard with no guidance." Existing apps (Garmin Connect, Strava, Apple Fitness) all walk new users through a 6-10 question setup before letting them reach the dashboard. We didn't, and the new-runner persona will bounce inside the first session as a result.

What we added:

- Migration `20261016_001` adds `user_profiles.onboarded_at timestamptz` (nullable) + backfills every existing row with `now()`. No retroactive re-onboarding.
- `/onboarding/+page.svelte` walks through 7 steps: display name, units, primary goal, optional demographics (gender + DOB + weight with Art 9 consent), privacy default, push notifications, done.
- Layout-level gate (`apps/web/src/routes/+layout.svelte`): a signed-in user with `onboarded_at = null` lands on `/onboarding` from any protected route. `/onboarding` is shell-less (no sidebar) so the wizard owns the whole viewport.
- Skippable per step (each step except step 1/2/5/7 has a Skip button) AND fully dismissible (the header carries a `Skip onboarding` link). Either path stamps `onboarded_at = now()` so the gate never re-fires.
- Settings layout shows a small "Finish setting up" nudge for users who left display_name, body_weight_kg, or privacy_default unset.

Why these specific choices:

- **Step-by-step, not single-page.** Lower per-step cognitive load. The new-runner persona is overwhelmed by choice; a Garmin-style "one question per screen" is the right shape for them. The trade-off is more taps for an experienced migrant, but the Skip-onboarding link + the auto-skip for existing users mean the migrant never sees the wizard anyway.
- **Per-step skip, not single big skip.** A skippable-as-block flow gets dismissed in 1 tap by users who'd actually answer 4 of the 6 questions if asked individually. The per-step pattern collects more data without forcing it.
- **Existing users auto-skip.** Backfilling `onboarded_at = now()` in the migration is the cleanest implementation. The alternative (showing every existing user the wizard on next login) would feel like re-onboarding to users who've been using the app for months.
- **`onboarded_at` on `user_profiles`, not in `user_settings.prefs`.** The auth-shell layout reads it on every login to decide the gate; `user_profiles` is already part of the post-login bootstrap (via `get_my_profile`), `user_settings` is loaded lazily. Putting the gate in the lazy bag would mean a flash-of-dashboard-then-redirect.
- **Gender persists only with Art 9 consent; DOB writes to the `user_profiles` column whenever supplied (consent gates only its health-feature *use*).** Same consent checkbox + render rule as `/settings/preferences` (it shows when gender or DOB has a value), and the consent timestamp + gender still need the tick. But the DOB column write itself is unconditional: the under-18 minor-exclusion floor in `search_user_profiles` keys off `user_profiles.date_of_birth`, so consent-gating that column left a child who declined the health checkbox with a NULL DOB and fully discoverable in people-search (persona round-5 family-club). Storing a DOB to enforce a child-safety discoverability floor is a distinct processing purpose from the Art 9(2)(a) explicit consent to *use* that DOB for HR calibration + age-banded leaderboards — so the column write happens regardless, while the prefs-bag mirror (which feeds the coach + leaderboards) stays consent-gated. `/settings/preferences` still null-writes DOB without consent — that surface is the documented carry-over below.
- **Push notifications are last.** Browser permission prompts are interrupt-the-user surfaces; landing it on the second-to-last step gives the user context for why we're asking, vs. asking on step 1 before they have any investment in the app.

Don't re-litigate by:

- Adding more required fields. The wizard's job is to lower the empty-dashboard pain, not to capture every possible profile field. Anything beyond the 7 steps belongs in Settings.
- Showing the wizard to existing users. The backfill is the explicit contract that says "they're already past it conceptually." If a future schema change adds a new required field, prompt for it in-context (banner on the surface that needs it), not by re-running onboarding.
- Forcing notification permission. The new-runner persona will deny + uninstall if pushed. Soft-ask only.

Pinning tests:

- `apps/web/src/lib/onboarding.test.ts` — 4 unit tests on the goal-key + label map + step count.
- `apps/web/tests-e2e/onboarding/wizard.spec.ts` — 4 e2e tests: existing user passes through, gate redirects null user, Skip-onboarding stamps the column, full step-by-step writes the four target fields + stamps the column.
- `apps/web/tests-e2e/auth/login.spec.ts` — updated the happy-path signup assertion to expect `/onboarding` instead of the dashboard sidebar (the new routing handoff).
- `apps/web/tests-e2e/fixtures/saga-users.ts` — updated to upsert `onboarded_at = now()` so saga users (programmatically minted, not real signups) skip the wizard and existing saga-based specs continue to land on /dashboard.

Mobile (Flutter Android + iOS twin) follows per the canonical-surface rule (decisions §24). The Dart twin will mirror the same 7-step shape + the same `onboarded_at` gate; deferred to a follow-up commit so the web shape can settle first.

## 79. Web prefs use a localStorage write-through cache + offline-drain queue, mirroring the mobile `SettingsCache` (§72)

The web `loadSettings` / `updateUniversal` / `updateDevice` API is fronted by `LocalStoragePrefsCache` (`apps/web/src/lib/settings/settings_cache.ts`). It's a direct port of the mobile `SettingsCache` abstract (`packages/api_client/lib/src/settings_service.dart`) and its `SharedPrefsSettingsCache` implementation (`apps/mobile_android/lib/settings_cache.dart`) — same key scoping, same `PendingChange` shape, same `applyPrefsChanges` merge rule.

**The pattern:**

- **Cache-first read.** `loadSettings(userId)` returns the cached universal + device bags synchronously when both are populated and fires a background refresh that drains any queued offline writes. The cold path (no cache) blocks on the server fetch as before; if the network is unreachable it degrades to empty bags rather than throwing.
- **Write-through.** `updateUniversal` / `updateDevice` apply the merge to the cache first, then push to the server. On push failure the change is queued under `settings_cache_pending_<userId>_<deviceId>` and replayed against a fresh server bag on the next successful refresh (same read-merge-write the synchronous path uses, so concurrent writes from another device aren't clobbered).
- **User-scoped keys.** `settings_cache_universal_<userId>`, `settings_cache_device_<userId>_<deviceId>`, `settings_cache_pending_<userId>_<deviceId>`. `dropUser(userId)` matches the universal key exactly and anchors device + pending on a trailing underscore so a sibling user whose id is a prefix (e.g. `a` vs `ab`) is never swept.
- **Sign-out wiring.** The auth store's `logout()` captures `priorUserId`, calls `supabase.auth.signOut`, then `dropUserCache(priorUserId)` — so a subsequent sign-in as a different user on the same browser can't read or replay against the prior account.

Why now: the dashboard's Fitness card + Intensity card both reach for the universal bag on every visit (`resting_hr_bpm`, `max_hr_bpm`, `hr_zones`); the post-signup onboarding wizard writes four target fields into that same bag. Pre-cache, every visit ate at least one round-trip before the cards could render, and a brief network blip would leave the cards empty for the entire session. Mobile shipped the offline-first version of this in §72 — the web reach-around was always going to follow once the surface area justified it (it does now).

Trade-offs:

- Stale-by-one-refresh. If user A edits HR zones on web tab A, web tab B's already-loaded dashboard keeps showing the old zones until the next mount. Same property mobile has; not a regression. The dashboard mounts on every navigation back to it, which keeps the staleness window short in practice.
- The in-memory fallback (`InMemoryPrefsCache`) is used at module init when `localStorage` is undefined (SSR). It's persistent across requests in the dev server but never holds real user data — `loadSettings` is gated on `auth.user?.id`, which is client-only via Supabase Auth.

Don't re-litigate by:

- Adding a service-worker / IndexedDB layer for the prefs bag. The bag is ~50 keys, sub-kilobyte; localStorage is the right primitive. Service-worker buys nothing here.
- Returning fresh server data from `loadSettings` on every call. That would defeat the offline-first goal. Callers that genuinely need fresh data (e.g. an admin diff against another device) should issue a Supabase query directly, not piggyback on this API.
- Promoting the cache to a Svelte 5 `$state` store. The current shape mirrors mobile's "in-memory snapshot + on-demand re-read" pattern; reactivity would require new wiring on every consumer, and we'd lose the cache-first synchronous-return property.

Pinning tests:

- `apps/web/src/lib/settings_cache.test.ts` — 40 unit tests: `applyPrefsChanges` merge contract (mobile-parity), the shared cache contract run against both `InMemoryPrefsCache` and `LocalStoragePrefsCache`, prefix-overlap regression (`a` vs `ab`), corrupt-JSON read recovery, malformed-queue-entry filtering, quota-exceeded swallowing.

---

## 80. Tier-1 firmware uses Embassy on Rust on the Nordic nRF52840 — chosen for memory safety, tooling, and async ergonomics, not for performance

[§71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) was amended on 2026-05-28 to permit owner-personal tier-1 bench-prototype firmware work, with the framework / language choice left open for a follow-up entry. This is that entry.

**Decision:** Tier-1 firmware is written in Rust using the [Embassy](https://embassy.dev/) async embedded framework, targeting the Nordic nRF52840 DK (PCA10056) as the bench-prototype board. Tooling stack is `cargo`, [`probe-rs`](https://probe.rs/), and [`defmt`](https://defmt.ferrous-systems.com/) for binary logging over RTT. UI bring-up uses [Slint](https://slint.dev/) on the Rust side; if Slint turns out to be too heavy for the Sharp MIP refresh-rate budget, fall back to a hand-rolled framebuffer driver with the existing LVGL design language as the visual target.

Why Rust + Embassy:

1. **Memory safety eliminates a whole class of firmware bugs.** Concurrent firmware that mixes interrupt handlers, threads, and shared data is where C's lifetime / aliasing footguns do the most damage. Rust's borrow checker rules these out at compile time. For a single-developer evenings-and-weekends project where debugging time is the bottleneck, this matters more than the equivalent productivity loss from writing the occasional driver from scratch.
2. **Modern tooling.** `cargo` is one command. `probe-rs` replaces the proprietary Segger toolchain with an open-source equivalent that works with any CMSIS-DAP adapter as well as J-Link. `defmt` ships structured binary logs over RTT with sub-microsecond timestamps. Combined, the developer experience is materially better than the CMake-meets-Kconfig-meets-`west` Zephyr workflow.
3. **Async-first ergonomics.** Embassy's `async fn` model expresses "wait for GPS UART, then wait for HR I²C, then sleep" as readable straight-line code. The Zephyr / FreeRTOS equivalent is either callback soup or one thread per task with the associated per-thread stack overhead.
4. **First-class nRF52840 support.** Embassy ships maintained HAL crates for the nRF52 family. `nrf-softdevice` wraps Nordic's BLE + ANT+ SoftDevice in safe Rust bindings. Production users include several shipping wearables and IoT devices.

**Why not for performance reasons.** Rust and C compile through the same LLVM backend on Cortex-M targets — `rustc` and `clang` literally share the optimisation passes. On a bare-metal MCU there's no GC, no JIT, no runtime, no interpreter overhead in either case. The two languages land within ±5% of each other on typical sensor-processing workloads, with the direction of the delta depending on the specific code. **The battery target (the metric that actually matters on this watch) is determined by hardware choices and firmware architecture, not language**, and is documented in detail in [`custom_watch/performance_path.md`](../custom_watch/performance_path.md). Anyone reading this entry hoping that "we picked Rust for the speed" is the takeaway will be disappointed; that's not the takeaway.

Trade-offs we accept:

- **Smaller driver ecosystem.** Zephyr ships in-tree drivers for the Sharp MIP display, BMP390, BMI270, and BLE host stack. Embassy doesn't — we'll write the Sharp MIP driver from scratch (~100 lines of SPI), pull a community `bmp388-rs` crate for the BMP390 (or wrap the C driver via `bindgen` if it doesn't extend cleanly), and use `nrf-softdevice` for BLE. Each of these is a couple of days of work; net loss is maybe a month of project time vs Zephyr.
- **The Maxim MAX86177 optical-HR algorithm is a proprietary C library.** Both languages have to FFI it via `bindgen`; this is a wash.
- **LVGL is C-only.** Slint is the Rust-native equivalent and is genuinely usable on MCUs as small as 320 KB flash, but it's less mature than LVGL for outdoor-watch use cases. If Slint becomes a blocker, fallback is hand-rolled SPI display routines plus a small framebuffer abstraction — we are not introducing a Zephyr port mid-project just to use LVGL.
- **Hireability narrows slightly.** Rust embedded is a minority skill in the wearable industry; if tier-1 eventually leads to ODM partnership conversations (per [`custom_watch/competitive_landscape.md`](../custom_watch/competitive_landscape.md)) the ODM almost certainly works in C/C++. The firmware-architecture rules in `performance_path.md` are language-agnostic, so a future port is real work but not a redo of design decisions.

What this commits us to:

- All tier-1 firmware code lives in [`/apps/custom_watch/`](../../apps/custom_watch/README.md), structured as a Cargo workspace.
- Drivers we write for our specific BOM (Sharp MIP, MAX86177 wrapper, u-blox NMEA parser) are published as separate crates in `apps/custom_watch/drivers/<sensor>/` so they're independently reusable and individually testable.
- `cargo test` runs on the host where it can; on-target tests use Embassy's test harness through `probe-rs`.
- CI gets a `build-firmware` job that runs `cargo build --target thumbv7em-none-eabihf` on PRs that touch `apps/custom_watch/`.

Don't re-litigate by:

- Switching to Zephyr partway through unless we hit a blocking driver issue that takes more than two weeks to resolve in Rust. The cost of a partial rewrite is higher than the cost of writing the driver.
- Adding C dependencies via `bindgen` for things that have working Rust crates. We've already accepted FFI for the Maxim HR algorithm and (if needed) the Bosch BMP390 driver; that's the budget.
- Treating the language choice as the reason for any performance characteristic. If the watch is slow, the answer is in `performance_path.md`, not in `Cargo.toml`.

If tier-1 reveals that Embassy + Rust + nRF52840 is genuinely intractable for our specific needs, the right move is to revert: switch to Zephyr + C + same MCU, port the firmware-architecture work over, and update this entry. The firmware-architecture rules are designed to be language-portable for exactly this reason.

**Amendment (2026-05-28) under [§ 92](#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints) Resolution.** § 92 codified "optimise for tier-3, period" as the new decision-making rule and flagged § 80's tier-1 nRF52840 choice as a candidate for revision (Apollo510B EVB direct would be the § 92-optimal pick at tier 1). The user's 2026-05-28 Resolution kept § 80 as-is, framing the nRF52840 choice as a deliberate first-prototype compromise to "keep costs down and get a working version first." Tier-2 migrates to Apollo510B per [§ 90](#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified); the full optimal road from tier-2 onward follows § 92's Phase 0–5 timeline. § 80's original reasoning (memory safety + tooling + async ergonomics) still holds; this amendment adds an explicit "and pragmatic first-prototype scope" frame so a future reader doesn't wonder why § 92 didn't supersede § 80.

Pinning: [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md), [`apps/custom_watch/CLAUDE.md`](../../apps/custom_watch/CLAUDE.md), [`docs/custom_watch/parts.md`](../custom_watch/parts.md), [`docs/custom_watch/performance_path.md`](../custom_watch/performance_path.md), [`docs/custom_watch/competitive_landscape.md`](../custom_watch/competitive_landscape.md).

---

## 81. Custom watch input is 5 physical buttons in the Garmin Fenix layout, no touchscreen

`vision.md` requirement #4 left the touchscreen as "optional for map panning only" and the button count as "5-button layout (Garmin pattern)" — both deliberately under-specified at scaffold time. This entry locks both in.

**Decision.** The production watch ships with exactly five physical buttons in the Garmin Fenix 7 / Enduro 3 arrangement and no touchscreen:

- Left side (3): LIGHT (top), UP (middle), DOWN (bottom)
- Right side (2): START/STOP (top), BACK/LAP (bottom)

No capacitive overlay. No touch controller IC. No haptic-replacement layer. The tier-1 nRF52840 DK keeps using its 4 onboard buttons for bring-up; a future production-PCB BSP will map LIGHT/UP/DOWN/START/BACK to the real GPIO pins.

Why exactly 5 in the Garmin pattern:

1. **Touchscreens fail in the conditions ultra runners actually experience** — sweat, rain, gloves, gel-coated fingers, river crossings. The reasoning was already in `vision.md` req #4; this entry closes the door instead of leaving it "optional."
2. **The 3+2 asymmetric split is a learned visual cue.** Experienced runners recognise "left side = workout controls, right side = navigation" without re-reading the manual. Symmetric 3+3 or novel layouts force a re-learn for the largest target demographic.
3. **5 is the well-trodden number.** Garmin Fenix 7, Polar Vantage V3, Suunto Vertical, Garmin Enduro 3 — all 5. We follow Enduro 3 specifically (5 buttons, no touchscreen) because that's the closest analogue to our target product.
4. **Dropping the touchscreen is real BOM + power + weight + sealing relief.** ~5–50 µA always-on idle draw (2–5% of total battery), ~$2–5 BOM, the cap-touch glass overlay (weight + thickness + an IPX7 seal interface), and the firmware touch driver. Death by 1000 cuts.

Trade-offs we accept:

- **Map pan/zoom is button-driven.** UP/DOWN scrolls or zooms depending on the active screen; long-press toggles modes. Slower than swipe gestures but works with gloves.
- **No quick-reply or text-entry.** The watch is a tool for the run, not a smartphone. If we ever want spectator messaging on-watch, it's preset templates selected via UP/DOWN.
- **5 buttons = 5 gasket-sealed interfaces.** Each is a fail point at the IPX7 test. Mitigation: standard piezo-style buttons with overmoulded silicone gaskets — a proven 20-year design on Garmin Fenix.

Don't re-litigate by:

- **Adding a touchscreen "just for the map" later.** The map UX has to be glove-friendly from day one; "touch for power users" splits design effort and produces a watch that's mediocre at both.
- **Switching to 3 buttons + digital crown.** COROS Vertix 2 proves the crown design works for ultra, but the UX case for 5-button discrete is the actual reason to reject crown (not the rotating-mechanism / sealing-complexity argument that's secondary at best): (a) under cognitive load at hour 26 of a 100-miler, discrete button presses are unambiguous in a way "rotate the crown N clicks, then click" isn't; (b) a button can't be accidentally actuated by a sleeve, glove edge, or arm-swing catching it, where a crown CAN rotate from contact and lose your scroll position mid-glance; (c) five independent button sensors mean one sticking doesn't lose all input — a jammed crown loses scroll AND click in one failure mode. The lack-of-rotating-seal is a side benefit of the right UX call, not the reason for it.
- **Adding a 6th button "for symmetry."** Symmetric layouts remove the asymmetric visual cue that helps gloved-hand orientation. 3+2 stays.

**Reasoning revised 2026-05-28** following the [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) audit pass. The original "Switching to 3 buttons + digital crown" bullet dismissed the crown on manufacturing complexity (rotating mechanism + sealing problem) — which is exactly the trade § 86 says to reject (tier-2 engineering convenience overriding end-state UX). Decision unchanged (still 5 buttons in the Garmin Fenix layout, still no touchscreen); the crown bullet was rewritten to lead with the UX-under-ultra-conditions case that's the actual reason. Caught by the post-planning audit because the UX argument had been there all along — just not written down explicitly.

Pinning: [`docs/custom_watch/vision.md`](../custom_watch/vision.md) requirement #4 (updated), [`docs/custom_watch/bom.md`](../custom_watch/bom.md) "Case + crystal + buttons" section (updated). The DK BSP at [`apps/custom_watch/boards/nrf52840_dk/src/lib.rs`](../../apps/custom_watch/boards/nrf52840_dk/src/lib.rs) keeps exposing the dev kit's BTN1–BTN4 as-is; the production BSP comes with the custom PCB.

---

## 82. Tier-1 firmware is "done" when one outdoor run syncs end-to-end to Supabase from the bench prototype

Until now, tier-1 in `apps/custom_watch/README.md` was a 7-step bring-up plan with no explicit completion bar. Without a Definition of Done, sunk-cost decides when tier-1 ends, and "ends" usually means "drifts indefinitely."

**Decision.** Tier-1 is complete when the bench prototype produces and syncs **one real outdoor run** — full stack from GNSS acquisition through display rendering through BLE sync to the existing Supabase `runs` Storage bucket. Specifically:

- A run recorded outdoors on a real wrist (Velcro strap is fine; the dev kit doesn't have to look like a watch).
- GPS fixes parsed from u-blox MAX-M10S via the `ublox_nmea` crate.
- HR samples from MAX86177 (raw photodiode reads + naive peak-detect is sufficient — the licensed Maxim algorithm is post-tier-1).
- Current pace + distance shown on the Sharp MIP display.
- Sync over BLE to a paired phone running the existing app, which writes to the same `{user_id}/{run_id}.json.gz` Storage path mobile + watch_wear already use.

When this happens once on a real run, tier-1 is done.

Why this bar:

- **It forces field-test instead of bench-test.** "Code compiles + runs on the DK" doesn't prove anything that matters; the DK on a Velcro strap doesn't behave like the DK on a desk. Field-test is where the bugs live.
- **It integrates the entire stack** — GNSS + HR + display + BLE + recording state machine + backend — in one shot. A passing run means every subsystem talks to its neighbours.
- **It produces a tangible artifact.** A row in your Supabase `runs` table with a real track on the map is the most credible possible demo of "this works."
- **It's concrete enough to be unambiguously passed.** No fuzziness around "credibly pitch" or "hit a power target." Either the run synced or it didn't.

What this does *not* require:

- Hitting a power-budget target. Power measurement at tier-1 is a separate open question (see [`roadmap.md` OQ3](../custom_watch/roadmap.md#power-instrumentation)); we can't measure ultra-watch battery life on a DK regardless.
- Apollo4 silicon, Sony GNSS, or any other tier-2+ migration. The nRF52840 + MAX-M10S combo on breadboard is the tier-1 target.
- A finished UI. Showing current pace + distance on the MIP display is enough; full data-screen menus + watch faces come later.
- Implementing OTA, vector maps, ANT+ pairing, sleep modes, or any other "would be nice" features. Strict tier-1 scope is GPS + HR + display + sync.
- Field validation under stress (foliage, urban canyon, multi-hour ultra). That's tier-2+ field-testing.
- Multiple runs. A second run would be "reassuring," not "decision-changing"; the bar is pinned at one to avoid the goal-post drift that traps hobby projects.

Don't re-litigate by:

- **Raising the bar to "100km ultra event tracked end-to-end."** That's tier-2+ field-testing. The point of tier-1 is to prove the stack works at all, not under maximum stress.
- **Lowering the bar to "code compiles + bench loop runs."** Code compiling proves nothing about the hardware path — see the post-scaffold audit where the original scaffold's deps were fabricated yet "the code looked fine."
- **Adding a kill-criterion clause after the fact.** Owner-personal investigations terminate when the owner stops investigating; codifying termination would treat this as a managed project, which it deliberately isn't.
- **Upgrading single-run to multi-run.** The single-run bar is intentional; multi-run discipline is a tier-2 concern when we start caring about reliability under stress.

Pinning: [`apps/custom_watch/README.md`](../../apps/custom_watch/README.md) step 7 ("Integration") is the activity that achieves this. [`docs/custom_watch/roadmap.md` "Definition of Done"](../custom_watch/roadmap.md#definition-of-done) replaces the previous TBD placeholder with a pointer to this entry.

---

## 83. Tier-1 power measurement uses Nordic Power Profiler Kit II, applied per-subsystem

Open question OQ3 from [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) resolved.

The metric that decides whether the production watch is competitive is battery life under realistic ultra-runner load. The tier-1 dev kit cannot measure that directly — the nRF52840 DK's onboard J-Link debugger + LEDs + power LDOs burn ~30 mA at idle, which dwarfs anything the firmware does and makes whole-device readings useless as a baseline. But "wait until tier 2" is the wrong answer: tier-2 silicon costs $15–40k and an architecture that misses the power budget there is a tier-2-scale mistake. Tier-1 needs an instrumentation methodology that produces forward-looking data without needing tier-2 hardware.

**Decision.** Add a Nordic Power Profiler Kit II (PPK2) to the tier-1 bench-tools kit (~$120 from Mouser / Digi-Key / Nordic direct). Use it **per-subsystem**, not whole-device:

- **Bare-MCU sleep current.** Power off everything else, measure the nRF52840 in deep sleep. Maps to tier-2 sleep power on whichever production MCU we migrate to (~3 µA target on Apollo4).
- **GPS module active vs sleep.** Power the u-blox MAX-M10S in isolation; measure acquisition + tracking + sleep separately. Matches tier-2 since the production Sony CXD5610 is the same chip class.
- **Optical-HR AFE sample current.** MAX86177 in isolation across the LED-on, LED-off, sample-readout phases. Matches tier-2 directly (same chip).
- **Display refresh energy.** Sharp MIP in isolation; per-line update vs full-frame redraw. Matches tier-2 (same display family).
- **Combined "all sensors live" rig.** Once individual subsystems are characterised, wire them together (still excluding the DK's debugger LEDs) and measure the integrated sleep-and-wake cycle.

These five datapoints map directly to the tier-2 / tier-3 power-budget table in [`performance_path.md`](../custom_watch/performance_path.md). When we later port from nRF52840 to Apollo4 + Sony CXD5610, the per-subsystem deltas predict the integrated tier-2 power; the prediction is verifiable; we discover architecture problems at tier-1 cost rather than tier-2 cost.

Why this over alternatives:

- **Whole-device measurement on the DK is misleading.** The dev board itself draws ~30 mA at idle from non-firmware sources; you'd be measuring the dev board rather than the firmware. Useless as a forward-looking baseline.
- **"Defer to tier-2"** trades $120 now against the risk of discovering an architecture problem after $15–40k of tier-2 spend. Bad odds for an investigation whose explicit deliverable (per [`competitive_landscape.md`](../custom_watch/competitive_landscape.md)) is "credible technical story for ODM conversations" — power data is the language vendors speak.
- **Bench multimeter** (already on the parts list) reads down to ~10 µA on cheap units; sub-µA sleep measurement needs the PPK2's dedicated current-source channels.

What this commits us to:

- Power measurements get captured as the per-step bring-up proceeds. Steps 3–6 each produce per-subsystem numbers; step 7 integration produces the combined number. Where they live: the `docs/custom_watch/tier1_log.md` planned in the [smaller considerations](../custom_watch/roadmap.md#smaller-considerations) section of the roadmap, created when step 3 actually starts.
- Tier-1 [Definition of Done (§ 82)](#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype) does **not** require hitting any specific power target — these measurements inform tier-2 planning, they don't gate tier-1 completion. § 82's "What this does *not* require" explicitly noted this.

Don't re-litigate by:

- **Switching to a cheaper alternative.** Cheap USB-current meters (USB Tester, MakerHawk) read down to ~1 mA — fine for charging-rate checks, useless for sleep-current. The PPK2's value is its 1 nA – 1 A dynamic range; no $20 substitute exists.
- **Deferring instrumentation until "we have time."** Power data collected during bring-up is cheap; retrofitting measurements onto already-written firmware always means restructuring code to add measurement points. Measure early.
- **Reading whole-device DK numbers as if they're meaningful.** The DK's non-firmware power draw makes whole-device readings deceptive; the convention is per-subsystem until tier-2 silicon exists.

Pinning: [`docs/custom_watch/parts.md`](../custom_watch/parts.md) "Bench tools" section adds the PPK2. [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) removes OQ3 from open questions and adds a Power instrumentation subsection under tier 1. The eventual `docs/custom_watch/tier1_log.md` (deferred until step 3 starts) captures per-subsystem readings.

---

## 84. Tier-1 firmware ships no OTA; tier-2 obligated to a production-grade dual-bank bootloader (MCUboot default)

Open question OQ4 from [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) and the related open Q#3 in [`docs/custom_watch/firmware.md`](../custom_watch/firmware.md) resolved.

`firmware.md` flagged that OTA "must be in v1.0; cannot be added later without bricking shipped units" — but tier-1 units are owner-personal dev boards that get re-flashed via USB constantly. There's no v1.0 ship happening at tier-1. The real question is when in the tier-1 → tier-2 → tier-3 progression we start designing for OTA.

**Decision.** Tier-1 firmware ships **no** OTA mechanism — no bootloader, no dual-bank slots, no image-validation infrastructure. The DK is re-flashed via USB + probe-rs for every change. Tier-2 firmware **must** ship a production-grade dual-bank bootloader before any prototype reaches a field tester; **MCUboot is the default candidate** and the specific choice gets made at tier-2 design time, but the obligation is fixed now so it's not noticed at tier-3 panic time.

When step 6 (BLE bring-up) adds `nrf-softdevice`, `memory.x` moves `FLASH ORIGIN` to `0x27000` (S140 7.x SoftDevice region) and reduces `LENGTH` from 1024K to ~860K. The comment in `memory.x` notes that tier-2 will further carve a bootloader + dual-bank slots out of this region — so a future reader sees the plan even though it's not implemented at tier 1.

Why defer to tier-2 (rather than MCUboot at tier-1):

- **Tier-1 units are throwaway.** Owner-personal, never shipped, re-flashable via USB any time. OTA at tier-1 = solving a problem we don't have.
- **MCUboot integration at tier-1 costs ~1–2 weeks** (bootloader + slot-layout + image-validation + sign-verify-boot-roll-back testing) for zero tier-1 value. Trades against [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance)'s "keep tier-1 narrow" intent.
- **Tier-2 rewrites the memory layout anyway.** New MCU candidate (Apollo4 or refreshed nRF5340), different SoftDevice version, possibly different bootloader region size. Whatever bootloader work we'd do at tier-1 gets redone — marginal carry-forward benefit.

Why MCUboot rather than rolling our own:

- **MCUboot is production-proven** across the Embassy ecosystem and the broader Cortex-M wearable industry. Known-good integrations documented, sample projects exist, security model is audited.
- **Rolling our own** is more work, more risk, no clear win unless MCUboot has a specific gap that surfaces at tier-2 design time.

What this commits us to:

- **Tier-2 firmware ships with OTA via a dual-bank bootloader before any prototype reaches a field tester.** Hard obligation, codified here.
- **MCUboot is the candidate-by-default;** if tier-2 design surfaces a reason to pick something else (e.g., MCUboot doesn't work cleanly with the Apollo4 + Ambiq SDK toolchain), the alternative must be production-grade and equivalent in capability (dual-bank, image signature verification, roll-back on boot failure).
- **`memory.x` at tier-1 step 6 leaves a comment** noting the future bootloader allocation, even though it's not carved out at tier-1.

Don't re-litigate by:

- **Adopting MCUboot at tier-1 "just to be safe."** Tier-1 firmware doesn't need OTA; adding the bootloader stack costs ~1–2 weeks of tier-1 budget for zero tier-1 benefit, and the layout gets rebuilt at tier-2 anyway.
- **Rolling our own bootloader to avoid an MCUboot integration dependency.** The integration work is well-trodden in the Embassy ecosystem; "avoid the dependency" isn't a real win unless MCUboot has a measurable gap at the tier-2 design pass.
- **Shipping a tier-2 prototype to a field tester without OTA.** The whole point of codifying the obligation here is to make this a hard "no" before it becomes a soft "we'll add it later." A tier-2 prototype reaching an external hand without the bootloader in place breaks this entry.

Pinning: [`apps/custom_watch/app/memory.x`](../../apps/custom_watch/app/memory.x) header comment updated to flag the tier-2 bootloader allocation. [`docs/custom_watch/firmware.md`](../custom_watch/firmware.md) open Q#3 (OTA) closed by this entry. [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) OQ4 removed; OTA added as a tier-2 architectural obligation.

---

## 85. Map renderer: full PMTiles vector rendering on the MCU + 16 GB external NAND flash

Open question OQ5 from [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) and the related open Q#1 in [`docs/custom_watch/firmware.md`](../custom_watch/firmware.md) resolved.

`firmware.md` flagged that vector map rendering on a Cortex-M4F is a multi-month firmware project — MapLibre Native + Mapbox GL Native assume an MMU-class CPU and tens of MB of RAM. Realistic options were: build a constrained-subset PMTiles renderer (multi-month), pre-bake into a simpler intermediate (medium effort), or punt to raster (lowest effort, worst UX). [`competitive_landscape.md`](../custom_watch/competitive_landscape.md) explicitly called out vector map quality on-watch as one of the few areas where we can credibly beat Garmin / COROS / Suunto.

**Decision.** Tier-2/3 firmware ships a constrained-subset PMTiles parser + minimal vector renderer running on the MCU. Reads PMTiles archives directly from external flash; renders lines, polygons, and label features at the active view transform. **16 GB external SPI NAND flash in the tier-2/3 BOM** (Macronix MX25R / Winbond W25Q / equivalent). Multi-month tier-2 firmware project; reference implementations to port from include MapLibre Native (too big as-is, but the algorithm shape carries) and the small-scale PMTiles readers in the Embassy / embedded-rust community.

Why PMTiles + on-MCU vector rendering (rather than the easier middle options):

- **Vector quality at every zoom level is the win.** Pre-baked intermediates trade flexibility for renderer simplicity; raster trades quality outright. Both options voluntarily concede the map-UX lever [`competitive_landscape.md`](../custom_watch/competitive_landscape.md) flagged as winnable.
- **Per [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins)**, small quality compromises compound across the dozens of decisions that make up a competitive product. The map-UX edge is exactly the kind of margin § 86 says to take.
- **Production PMTiles support is portable.** Tile generation happens server-side using existing open-source tooling (Protomaps, tippecanoe); the on-watch renderer reads a well-documented format. No proprietary pipeline to maintain.

**Power cost honesty.** Among (a)/(b)/(c), full PMTiles is the **most CPU-intensive at runtime** — every pan/zoom requires tile decode + geometry clip + rasterisation on a Cortex-M4F with no GPU. Raster (option c) just blits pixels; pre-baked intermediate (b) sits between. So this is *not* a "perf-optimal on all dimensions" pick — it's a quality-vs-power trade where visual quality wins. We accept the runtime CPU cost because:

- **Map interaction is infrequent during a run.** Users glance at the map at navigation decision points (intersections, course-deviation alerts), not continuously. Most active watch time is recording GPS + showing pace/distance, where the renderer is idle.
- **Sharp MIP refresh caps at ~10 Hz.** Even under maximum interaction the renderer can't burn CPU faster than the display can show — there's a hard upper bound on the per-second cost.
- **Estimated cost at the tier-2 power budget:** assuming ~5 minutes of active map interaction per hour during a multi-hour run, vector rendering adds an estimated **1–3% to total active-power draw** vs raster. Within the ~5% margin [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) explicitly says is worth taking for end-state quality wins.

The 1–3% estimate is **unvalidated until [§ 83](#83-tier-1-power-measurement-uses-nordic-power-profiler-kit-ii-applied-per-subsystem)'s PPK2 measurement runs at tier-1 step 4** (display bring-up). If the measured cost is >5% of total active draw, this decision gets revisited — at that point pre-baked intermediate (option b) becomes the right call. Recording this honestly per § 86's anti-rationalisation guidance: the renderer choice is a *quality-vs-power trade* where quality wins by enough margin to justify the cost, not a pick that wins on every dimension.

What this commits us to:

- **Tier-2 firmware budget includes a multi-month vector-renderer subproject.** Not on tier-1's plate (tier 1 doesn't render maps); tier-2 timeline + cost estimates have to account for it.
- **16 GB external NAND in the tier-2/3 BOM** — meaningful PCB real-estate impact (TSSOP-8 or WSON-8 package + SPI bus routing), modest BOM cost (~$3–5 at tier-3 volumes vs ~$1–2 for 4 GB).
- **Pre-bake pipeline still exists server-side** — Protomaps + tippecanoe in [`apps/job_worker/`](../../apps/job_worker) or a sibling Go service generates per-region PMTiles archives. Differs from the rejected "pre-baked intermediate" option in that the on-watch side reads standard PMTiles, not a custom format we'd own and maintain.
- **Style language:** subset of the Mapbox style spec (already what Protomaps + MapLibre standardise on). Watch ships with one bundled style; no in-watch style customisation at v1.0 (a Connect-IQ-style ecosystem question, out of scope).

What this does NOT commit us to:

- Doing the renderer work at tier 1. Tier 1 doesn't render maps; per [§ 82](#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype), the DoD is GPS + HR + display + sync.
- A specific NAND vendor — just the size class. Vendor pick at tier-2 PCB design.
- Animated map transitions or 60-fps render targets. The Sharp MIP is ~10 Hz; we render to its capability, not above.
- Raster fallback at tier 2 "to ship something." If the renderer is taking longer than expected, the right call is to scope down map coverage (one region, not global) and still ship vector at tier 3.

Don't re-litigate by:

- **Falling back to the pre-baked intermediate "to save engineering."** That's exactly the trade [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) says no to — small-margin quality wins that compound.
- **Switching to raster at tier-2 "because the renderer is taking longer than expected."** Schedule slippage isn't a quality argument; scope down coverage, don't drop the format.
- **Skipping the 16 GB flash to save $3 BOM.** Map storage is the constraint; cost-down vs the multi-year product is rounding error.

Pinning: [`docs/custom_watch/bom.md`](../custom_watch/bom.md) adds the External storage section. [`docs/custom_watch/vision.md`](../custom_watch/vision.md) requirement #5 updated. [`docs/custom_watch/firmware.md`](../custom_watch/firmware.md) open Q#1 (map renderer) closed by this entry. [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) OQ5 removed; PMTiles renderer added as a tier-2 architectural obligation.

---

## 86. Custom watch decisions optimise for end-state product performance, even at small margins

The decisions for custom_watch so far (§ 71 + amendment, § 80 – § 85) have each individually traded "tier-1 engineering cost" against "tier-2/3 product quality." The pattern across them has been to accept tier-1 deferrals when they save engineering without compromising end-state quality (e.g., [§ 84](#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) defers MCUboot to tier-2 because tier-1 doesn't need OTA at all). When the tradeoff DOES affect end-state quality, the rule is different: pick the higher-quality option even when the margin is small (~5% or less on any single metric) and the engineering cost is real.

**Decision.** For custom_watch tool / architecture / BOM picks, apply this lens explicitly:

1. **What does each option produce on the tier-3 shipped product?** Compare options on user-visible quality of the final watch — battery hours, GPS accuracy, HR accuracy, map render quality, UI responsiveness, weight, repairability, water resistance, etc. ("Performance" here is shorthand for that full quality basket, not just CPU cycles.)
2. **Pick the option with the better end-state outcome,** even when:
   - The edge is small (~5% or less on any single metric).
   - The engineering cost at the current tier is materially higher.
   - The "easier middle option" exists and would be acceptable.
3. **The exception:** when the option doesn't affect end-state quality (e.g., a tier-1-only scaffolding choice that gets rewritten at tier-2), pick the cheapest option. The rule is end-state-quality-first, not engineering-cost-blindness.

Why this rule for custom_watch specifically:

- **The watch competes in the ultra-marathon niche** against established players (Garmin Fenix / Enduro, COROS Vertix, Suunto Vertical) with multi-year head starts on hardware quality. Per [`competitive_landscape.md`](../custom_watch/competitive_landscape.md), the only credible play is being *better on the things they're weak at* — UI polish, map UX, software-update cadence, community, AI coach quality. "Better" doesn't survive accepting easier-but-worse compromises during build.
- **Small margins compound.** The watch has roughly a dozen end-state quality dimensions. A 5% concession on each compounds to a ~40–50% gap by tier-3 launch. The compounding is invisible at any single decision point — which is why this rule has to be explicit.
- **The asymmetric play depends on it.** Each "did we accept the lazy option here?" call is small in isolation but accumulates. Going easy on the small ones is how you end up with a Garmin clone that's worse than Garmin.

What this commits us to:

- **Remaining open questions in [`roadmap.md`](../custom_watch/roadmap.md)** (OQ6, OQ7, OQ8) get reasoned through with the end-state quality lens, not the tier-current-convenience lens.
- **Future decisions entries** that touch product quality cite § 86 in their reasoning when they pick the harder option.
- **When a decision picks the lazier option, the entry explicitly says why** (e.g., "no end-state quality impact" or "the harder option doesn't exist on the timeline available").

First application: [§ 85](#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) (map renderer) picks the full PMTiles + on-MCU vector renderer over the pre-baked-intermediate middle option specifically because vector quality at every zoom is the win, and the engineering cost — while real (multi-month tier-2 firmware project) — is exactly the kind of investment this rule says to make.

Don't re-litigate by:

- **Applying the rule to non-custom_watch decisions** without thinking. The main app's tradeoffs have their own rationales; § 86 is scoped to custom_watch.
- **Using "5% perf wins" as a hammer to justify scope creep.** The rule says pick the end-state-better option from the available set; it doesn't say invent new features. "Better renderer than middle option" is in scope; "let's also add nuclear-clock sync because that's 0.5% better" is not.
- **Ignoring the explicit exception** for tier-current-only choices that get rewritten anyway. Spending tier-1 engineering on infrastructure that won't survive to tier-2 is waste, not quality.

Pinning: First application in [§ 85](#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash). Future decisions in [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) OQ list will be reasoned with this lens.

---

## 87. Strategic vector 1 (Connect IQ app) runs in parallel with tier-1 firmware

Open question OQ6 from [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) resolved.

[`competitive_landscape.md`](../custom_watch/competitive_landscape.md) identified vector 1 — a Garmin Connect IQ app or data field targeting existing Garmin owners — as the cheapest possible market test of the custom_watch software-differentiation thesis. Distribution free via Garmin's marketplace, engineering cost a few weeks of Monkey C, downside risk near zero. OQ6 asked whether to start it sequentially after tier 1, in parallel with tier 1, or before tier 1.

**Decision.** Vector 1 runs **in parallel** with tier-1 firmware bring-up. Both are active simultaneously on owner-personal evenings/weekends time per the [§ 71 amendment](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely). Per-surface evening time halves; two simultaneous learning loops produce more information per calendar week than serial single-loop work.

Why parallel (per [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins)):

- **Tier-1 firmware quality improves with real market signal in hand.** Building tier 1 for 3–6 months without Garmin-owner feedback means making UX decisions in the dark. Parallel = tier 1 prioritises data-presentation patterns vector 1 validated and deprioritises the ones that flopped.
- **Vector 1 is cheap insurance against a bad investment thesis.** If a few weeks of Monkey C produces "this is the same as Garmin" feedback, that's a strong signal to reconsider tier-2/3 — better caught at ~$0 than after $15–40k of tier-2 spend.
- **§ 86 says pick the higher-quality option even when current-tier engineering cost is materially higher.** Parallel doubles the surface area being learned about per calendar week; depth-in-one-surface-first delays the cross-surface learning entirely.

(a) sequential delays critical market signal by 3–6 months for no compensating quality benefit. (c) vector-1-first conflicts with the spirit of the [§ 71 amendment](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) — pausing the thing the owner is doing-because-they-enjoy-it to do market research instead is the wrong frame.

What this commits us to:

- **A Garmin Connect IQ app or data field built using the Connect IQ SDK (Monkey C).** v1 scope intentionally minimal — one data field or one simple watch app — to test the differentiation hypothesis quickly, not to ship feature parity with Garmin's first-party offering. Specific v1 scope is a separate design question, not codified here.
- **Distribution via Garmin's Connect IQ store at free** — the install rate is the experiment, not "willingness to pay $X."
- **Tier-1 firmware per-evening time drops** to roughly 50–60% to make room. Both surfaces' first deliverable lands on a similar timeline.
- **[`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) Vector 1 status flips** from "Not started" to "Active, parallel to tier-1."

What this does NOT commit us to:

- **Feature parity with Garmin's first-party offering at vector-1 v1.** v1 is one thing materially better, not five things at par.
- **A Connect IQ business model.** Free distribution at v1; monetisation is a separate question for after the install rate validates the thesis.
- **Tier-1 deprioritisation.** Both are active; neither is paused. Tier-1's [DoD per § 82](#82-tier-1-firmware-is-done-when-one-outdoor-run-syncs-end-to-end-to-supabase-from-the-bench-prototype) stays in effect.
- **Vector 2 (Wear OS reframing) or vector 3 (ODM partnership) starting alongside.** § 86 is end-state-quality-first, not maximum-parallel-experimentation. Vector 2 overlaps too much with the existing `apps/watch_wear/` scope to be additive; vector 3 only becomes interesting after vector 1 produces signal.

Don't re-litigate by:

- **Pausing vector 1 because "tier 1 is taking longer than expected."** Schedule slippage isn't a quality argument; the surfaces are independent learning loops, sequencing them just delays learning.
- **Pausing tier 1 because "vector 1 is getting traction."** Tier 1 is owner-personal investigation, not a project that's only justified by external validation; the firmware path has its own learning goal (domain credibility for the eventual ODM conversation per [`competitive_landscape.md`](../custom_watch/competitive_landscape.md)).
- **Adding vector 2 or 3 alongside.** Per [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins), end-state-quality-first ≠ everything-in-parallel. Vector 1 produces signal first; subsequent vectors get sequenced on that signal.

Pinning: [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) "Strategic vectors" Vector 1 status flipped; OQ6 removed from open questions.

---

## 88. Vendor engagement is tiered across project maturity

Open question OQ7 from [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) resolved.

OQ7 framed it as "email all three vendors now / email Sony only / wait until tier-1 demonstrates serious intent." None of those quite captured the per-vendor reality: Sony engagement before there's a prototype likely gets filtered as tire-kicking; ADI is friendlier to small inquiries; ANT+ Alliance requires a $2–5k/year membership fee that exceeds the entire tier-1 budget AND signals commitment to ship hardware (which would breach the [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) "no commercial commitment until a trigger fires" framing).

**Decision.** Vendor engagement runs in three layers, sequenced on the project's own maturity rather than treated as one flat list.

**Layer 1 — active now (free public research, zero commercial commitment):**

- ANT+ Alliance public adopter list → confirm competitors (COROS, Polar, Suunto, Apple Watch) are granted adoption. Closes most of the "would Garmin refuse?" uncertainty without writing a check.
- Sony CXD5610 public family briefs → power consumption, mode breakdowns, package options. Enough for tier-2 BOM planning even without the NDA datasheet.
- ADI MAX86177 public datasheet (already public) → register set + power-state characteristics for the tier-1 driver work.

**Layer 2 — active when tier-1 has a working bench prototype to point at:**

- Email Sony FAE with a written project brief + a request for the CXD5610 NDA datasheet + a sampling conversation. ~4 weeks for the NDA paperwork; no commercial commitment.
- Email ADI Maxim for HR-algorithm licensing terms at the projected volume (e.g., "10k units over 24 months"). Real quote, non-binding until signed.

A working bench prototype is the credibility threshold for serious vendor engagement. Sales teams take "we have hardware running" much more seriously than "we're investigating"; doing it earlier risks burning engagement-capital for filtered-as-tire-kicker responses.

**Layer 3 — active at tier-2 greenlight (one of [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)'s triggers fires):**

- ANT+ Alliance Adopter membership application ($2–5k/year + Garmin's review). Commitment-grade — paying the fee + tipping our hand to Garmin only makes sense once we've committed to ship hardware. Per [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely), that commitment is gated; this engagement is gated with it.

Why tiered (per [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins)):

- **Layer 1 captures most of the information value for zero cost.** The ANT+ adoption question is mostly answerable from the public adopter list; Sony has public family briefs; ADI has the full datasheet. Skipping these is leaving free signal on the table.
- **Layer 2 protects engagement-capital.** Vendor sales teams have finite patience for tire-kicker inquiries; using up that patience pre-prototype means the post-prototype conversation starts on worse footing. Holding off until the prototype exists is the better-end-state-quality move per § 86.
- **Layer 3 respects [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)'s gating.** Paying ANT+ Alliance dues + revealing the project to Garmin both imply "we're committing to ship," which is exactly the commercial commitment § 71's amendment held back from authorising at tier 1.

What this commits us to:

- **Layer-1 web research happens in the same calendar window as tier-1 step 1 (parts arriving).** A handful of hours; produces a written summary that feeds tier-2 BOM planning.
- **Layer-2 emails go out** the same week tier-1 first achieves a recognisable bench prototype (somewhere between step 3 GNSS bring-up and step 7 integration — the exact moment is a judgment call).
- **Layer-3 ANT+ Alliance application waits for a [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) trigger to flip.** No exceptions; the membership fee + Garmin disclosure is too expensive to do speculatively.

What this does NOT commit us to:

- **A specific vendor at tier-2.** Sony / ADI / ANT+ Alliance are the working assumptions; if layer-1 research surfaces an alternative that's clearly better, the BOM gets revised.
- **Joining ANT+ Alliance ever.** If layer-1 research confirms competitor adoption is normal, layer 3 happens at tier-2 greenlight. If layer-1 surprises us (Garmin recently changed policy), layer 3 either gets accelerated or revisited (ship BLE-only and accept the smaller compatible-strap market).
- **A formal LLC for vendor engagement.** Layer-2 emails come from the owner-personal account with a project brief; vendors take individual inquiries with a working prototype seriously enough to start NDA conversations. Forming an LLC happens if/when a § 71 trigger flips.

Don't re-litigate by:

- **Emailing Sony / ADI before there's a bench prototype** "to save lead time." It saves nothing — the response is "contact us when you have a company" — and burns engagement capital you'd want post-prototype.
- **Joining ANT+ Alliance now** "to get the answer early." Layer-1 research gives 80% of the answer for free; the remaining 20% costs $2–5k/year + tips our hand to a competitor.
- **Skipping layer 1** "until tier 2." The free research has value at tier 1 too — feeds BOM planning, surfaces alternatives, frames vendor conversations. Free + immediate = always do layer 1.

Pinning: [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) replaces the previous flat "Long-lead-time pre-validation" list with the three-layer "Vendor engagement" structure; OQ7 removed from open questions.

---

## 89. Skip user-research interviews; vector 1 install rate is the validation channel

Open question OQ8 from [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) resolved.

OQ8 asked whether to interview 5–10 ultra runners about their Garmin / COROS pain points to validate the product vision in [`competitive_landscape.md`](../custom_watch/competitive_landscape.md), which is currently built from public forums + reviews + pattern-matching rather than first-hand conversations. The [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) lens leans toward running the interviews — ~10 hours for thesis validation is cheap on paper.

**Decision.** Skip the interview round. Validation of the differentiation thesis comes from vector 1 (the Garmin Connect IQ app per [§ 87](#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware)) install rate + organic feedback instead.

Why this beats interviews:

- **Revealed preference beats stated preference.** "Did Garmin owners install our app + leave it on their watch?" is a stronger signal than "Did Garmin owners tell us in a 30-min call that they'd want our app?" Stated-preference interviews are notoriously prone to politeness bias — people say they'd use a thing they wouldn't actually use. Vector 1's install rate cuts through that.
- **Vector 1 is already committed.** [§ 87](#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware) puts the validation pathway in flight; interviews would be redundant validation on top, not a replacement for missing validation.
- **The "cost" of interviews isn't really 10 hours.** Cold-outreaching strangers, scheduling calls, conducting them, synthesising findings — for an owner-personal investigation explicitly framed as "I'm doing this because I'm enjoying it," the social-coordination overhead is higher than the hour count suggests.

This is a defensible exception to [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins)'s "pick the higher-quality option" because:

- The interview option isn't actually higher-quality than revealed-preference vector-1 signal — interviews would supplement, not replace.
- The marginal information gain from interviews on top of vector-1 install data is small.
- [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins)'s explicit exception clause covers cases where the harder option doesn't materially improve end-state quality; this fits.

What this commits us to:

- **No formal user-research effort at tier 1.** The interview pathway stays closed unless we choose to revisit (see below).
- **Vector 1's install rate becomes the validation gate** for "is the software-differentiation thesis real?" — if vector 1 succeeds, the thesis is validated; if it flops, the thesis is weakened and tier 2 should be reconsidered.
- **No `docs/custom_watch/user_research.md`** — the doc isn't created; if interviews ever happen, it lands then.

What this does NOT commit us to:

- **Ignoring all user feedback.** Vector-1 reviews, Connect IQ store comments, organic feedback through any channel remain signal. Skipping is just skipping the structured-interview format.
- **Skipping interviews forever.** If vector 1 produces ambiguous signal (middling install rate, mixed reviews), interviews become a genuinely useful second-pass validation. The decision here is "don't do them now," not "don't do them ever."

Don't re-litigate by:

- **Adding "we should interview some runners first" when tier 1 hits a hard problem.** Hard problems get solved by debugging, not by external user research. Talking to ultra runners doesn't unblock a driver bug.
- **Citing [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) to argue interviews should happen now anyway.** This entry IS the explicit § 86 exception; the trade is recorded.

Pinning: [`docs/custom_watch/roadmap.md`](../custom_watch/roadmap.md) OQ8 removed; with OQ8 closed, all initial OQs are resolved and the "Open questions to resolve" section is restructured as a resolution-tracking table.

---

## 90. BOM refresh 2026-05-28 — Apollo510B + BMP581 swap-ins; supply alternates qualified

Audit pass on 2026-05-28 against current (May 2026) component availability flagged three categories of BOM staleness:

1. **Apollo4 Blue Plus is now last-gen.** Ambiq shipped Apollo510 (Sep 2024) and Apollo510B (Sep 2025): Cortex-M55 + Helium MVE @ 250 MHz, 4 MB MRAM, 3.75 MB SRAM, **~2× lower energy + ~10× lower latency vs Apollo4 family**, plus secureSPOT 3.0 security stack. Apollo510B specifically adds an integrated 48 MHz BLE 5.4 network processor — the like-for-like replacement for "Apollo4 Blue Plus." Lower-cost Apollo510 Lite family is sampling now with volume Q1 2026. AP510EVB is on Digi-Key.
2. **BMP390 is meaningfully outclassed.** Bosch BMP581 (capacitive vs piezoresistive) ships **~85% lower current** (1.3 µA @ 1 Hz vs ~3 µA), 80% lower noise, 33% lower temperature coefficient, 0.5 µA deep standby, ±0.1 hPa / 12-month drift. For an ultra watch where the altimeter is sampled continuously to drive elevation-gain math, this is the second-biggest perf swap available.
3. **Supply / sourcing risk shifted** since the BOM was first written: JDI's Mobara LCD fab is closing in March 2026 (Sharp Memory LCD substrate supply contracting); NOR/NAND flash 6–9 month lead times in 2025–2026.

**Decision.** Refresh the tier-2/3 BOM with:

- **MCU:** Apollo4 Blue Plus → **Ambiq Apollo510B** (production target). The tier-1 stand-in (Nordic nRF52840 DK) is unaffected — that choice is tier-1-specific per [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) and stays as the bench-prototype board.
- **Barometer:** BMP390 → **Bosch BMP581**. Drop the stale "BMP581 newer but BMP390 equally accurate" line from `bom.md`; it's now factually wrong.
- **OHR upgrade path documented:** keep MAX86177 as the PPG-only pick. **MAX86178** (PPG + ECG + BioZ + IEC 60601-2-47-compliant ECG channel) noted as the upgrade path for a future ECG-capable SKU.
- **GNSS alt clarified:** keep Sony CXD5610 as the production pick; replace the vague "u-blox dual-band wearable part" alt with the specific **Airoha AG3335M** (12 nm L1+L5; powers some Garmin/COROS-tier watches; Quectel LC29H is built on it). u-blox ZED-X20P intentionally NOT listed — that part targets industrial / UAV / robotics; power envelope is wrong for wrist.
- **Display backup:** keep Sharp LS013B7DH06 as the production pick. **Qualify LS027B7DH01 as the backup** in case the LS013 line goes NRND post-Mobara closure. Action: request a Sharp lifecycle letter before tier-2 case-CAD tooling spend (~$30–80k commitment to a specific size).
- **NAND second source:** keep 16 GB SPI NAND class (Macronix MX25R / Winbond W25Q). **Add GigaDevice GD5F as a qualified second-source** at PCB design time so a 2026 allocation event doesn't stall a tier-2 build.
- **Battery:** hold Li-Po; silicon-anode pouches (>900 Wh/L) are commercial but only at sizes too large for wrist. Tier-3+ refresh consideration only.

Why this is § 86-driven (and not over-eager updating):

- **Apollo4 → Apollo510B is well above the 5% margin** — ~2× lower energy on the same workload directly translates to materially more battery life on the MCU-active portion of the budget. For a watch whose competitive position hinges on battery, locking in a year-old part on a 3-year product is the trade [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins) says to reject.
- **BMP390 → BMP581 is ~85% lower current.** Altimeter is sampled continuously (every GPS fix + storm-detection background loop); cumulative power saving over a 100-hour battery target is real, not rounding error.
- **Supply-chain alternates** (Sharp backup, Airoha GNSS alt, GigaDevice NAND second-source) are not perf swaps — they're risk mitigation for a multi-year program where component allocation can stall a build for months. § 86 doesn't strictly require these but the marginal effort is small and the downside protection is meaningful.

What this commits us to:

- [`docs/custom_watch/bom.md`](../custom_watch/bom.md) updated: MCU + Baro swaps land in the spec; GNSS/Display/NAND/OHR alternates added; the "equally accurate" line on BMP581 fixed.
- [`docs/custom_watch/vision.md`](../custom_watch/vision.md) requirement #1 updated: "Low-power MCU (Ambiq Apollo4 / Nordic nRF5340)" → references Apollo510B for production + nRF52840 for tier-1 stand-in.
- **No change to [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) or the tier-1 scaffold** — Apollo510B is a tier-2+ production part; tier-1 stays on nRF52840 because that's where the Embassy + `nrf-softdevice` ecosystem is mature today.

Don't re-litigate by:

- **Bumping back to Apollo4 because "the Apollo510 SDK is less mature."** Apollo510B has been in volume since Q4 2025; the Ambiq SDK + HAL support is current. Locking in last-gen silicon for a tier-3 product that ships in 2027+ is exactly the asymmetric-competitiveness loss § 86 names.
- **Bumping to Apollo510 Lite to save BOM cost at launch.** The Lite series drops some peripherals; the BLE 5.4 + integrated network processor on the Apollo510B is precisely what makes it a drop-in for "Apollo4 Blue Plus." Lite as a future cost-down is fine; not as the launch SKU.
- **Skipping the Sharp lifecycle letter "because Sharp Memory LCD is the de facto standard."** Mobara closure is the warning shot; a single-source on the most-visible component of the watch with a year-and-a-half tier-2 timeline is the recipe for a build-blocking surprise.

Pinning: [`docs/custom_watch/bom.md`](../custom_watch/bom.md) MCU + GNSS + OHR + Baro + External storage + Display sections updated. [`docs/custom_watch/vision.md`](../custom_watch/vision.md) requirement #1 updated. [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) tier-1 firmware decision unchanged. [§ 85](#85-map-renderer-full-pmtiles-vector-rendering-on-the-mcu--16-gb-external-nand-flash) 16 GB external NAND class unchanged.

---

## 91. Walk-run (C25K / Galloway) is a first-class workout kind expressed by time-based intervals

New and returning runners (new + comeback personas #22) need run/walk interval sessions — run 60 s, walk 90 s, repeat — which the plan model couldn't express: `WorkoutStructure` was distance-only and `recovery_pace` was `'easy' | 'jog'`, with no "walk" notion, and there was no workout kind to flag a beginner session.

**Decision.** Add `walk_run` as a `WorkoutKind` (Postgres enum value, web `WorkoutKind` union, Dart `WorkoutKind.walkRun`, migration `20261020_001`), and extend `WorkoutStructure` so a rep/recovery can be expressed by **duration** (`duration_s` / `recovery_duration_s`) as well as distance, with `recovery_pace` widening to include `'walk'`. The live `WorkoutRunner` already supported duration-based steps, so no runner-model change was needed for expressibility — only the generator types + the kind.

**Why time-based, not distance-based.** C25K and Galloway prescribe *time* intervals ("run 1 minute, walk 90 seconds"), not distances — a beginner can't pace by distance reliably, and the whole point is a fixed effort/rest clock. Distance-based reps would be the wrong primitive for the population this serves.

**Trade-off.** `distance_m` on the structure sub-objects became optional, so display/edit consumers (`WorkoutEditor`, the workout-detail breakdown) had to handle "distance OR duration" — a `mag()`-style fallback. The advanced structure *editor* still authors distance-based intervals only; walk-run sessions are produced by the beginner plan generator (§ commit B) rather than hand-built in that editor, which is acceptable because the beginner audience uses templates, not the power-user editor.

**Don't re-litigate by** collapsing `walk_run` back into `interval` "because it's just intervals with walk recovery" — the distinct kind is what lets the dashboard, plan calendar, recorder cues ("Run"/"Walk"), and plan-compliance treat a beginner session correctly instead of scoring it like a hard interval workout. Pinning: migration `20261020_001`; `training.ts` ↔ `training.dart` parity pair (keep in lockstep); `docs/features/training.md` § walk-run.

---

## 92. Custom watch decisions optimise for tier-3 production quality, period — scope and effort are not constraints

This entry **supersedes [§ 86](#86-custom-watch-decisions-optimise-for-end-state-product-performance-even-at-small-margins)** ("even at small margins") with a stronger version: **all custom_watch decisions optimise for the tier-3 shipped product, regardless of how long the work takes or how much effort it costs.** § 86's exception clause for "tier-current-only choices that get rewritten anyway" is dropped — that loophole was being used to defer the harder, better, more-aligned option in several decisions. Validation noise at tier-1 compounds into tier-2 / tier-3 surprises; the optimal path gets validated from the start.

**Decision.** From this entry forward, the decision-making rule for custom_watch is:

1. **What's the optimal choice for the tier-3 shipped product?** That's the choice we take. End of question.
2. **Effort, time, and tier-current scope are not valid arguments for picking the lesser option.** The "this is just tier-1, we'll redo it at tier-2" framing is dropped — we don't redo at tier-2, we validate the optimal path from tier-1.
3. **The only legitimate constraint is technical feasibility.** If the optimal option literally doesn't exist yet (chip unreleased, HAL unwritten that we can't ourselves write in finite time), pick the closest available option that ports forward without surprise.

Why this supersedes § 86 (rather than sitting alongside it):

- **§ 86's exception clause was the loophole.** "Tier-current-only choice that gets rewritten anyway" is the rationale that was used to defer the harder option in [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) (nRF52840 vs Apollo510B), [§ 84](#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default) (no OTA at tier-1 vs MCUboot day one), and [§ 88](#88-vendor-engagement-is-tiered-across-project-maturity) Layer 3 (ANT+ Alliance deferred). Closing the loophole forces those decisions to be revisited.
- **Tier-1 / tier-2 / tier-3 become validation phases, not commitment gates.** Under § 92, tier-1 is "the production firmware running on production-silicon class, possibly without the final case" — not "easier prototype on different silicon."
- **The asymmetric play in [`competitive_landscape.md`](../custom_watch/competitive_landscape.md) still holds**, but it's no longer a hedge. We're not "competing on software wins because hardware competition is unwinnable" — we're "competing on EVERY dimension, with software wins on top of hardware perf parity."

**Tension with [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) — flagged for explicit resolution.** § 71's 2026-05-28 amendment scoped tier-1 as "owner-personal evenings/weekends investigation." § 92 is incompatible with that framing — the optimal-path-regardless-of-effort rule doesn't fit "investigate in spare time." Two interpretations:

- **(A, strong):** § 92 supersedes § 71 amendment. Tier-1 is no longer "owner-personal investigation" — it's "real product development on the owner's available time, with explicit understanding that the time required may be years." § 71's "tier 2+ gated" framing also drops since the phases collapse.
- **(B, weak):** § 92 binds the technical decisions only; § 71's effort cap on tier-1 still holds, which means the optimal path is acknowledged but tier-1 may take much longer than initially scoped to actually execute on it.

Interpretation must be picked explicitly before the cascading revisions land. § 92 only takes full effect under interpretation A; under B, § 92 is a wish list constrained by § 71's spare-time reality.

Existing decisions to revisit under § 92 (pending interpretation choice):

| Entry | Current decision | Under § 92 | Revisit? |
|---|---|---|---|
| § 80 | Tier-1 firmware on nRF52840 (Embassy + nrf-softdevice maturity) | **Apollo510B EVB direct**, even if it costs 6-12 months of HAL bring-up | Yes |
| § 84 | No OTA at tier-1; MCUboot at tier-2 | **MCUboot integrated from day one** — validate OTA architecture early | Yes |
| § 88 Layer 3 | ANT+ Alliance application at tier-2 greenlight | **ANT+ Alliance application now** to get Garmin's answer + start the relationship | Yes |
| § 89 | Skip user research interviews; vector-1 install rate is the validation | **Do interviews AND vector 1** — every signal is worth taking under § 92 | Yes |
| § 81 | 5 buttons (UX-honest reasoning after § 86 audit revision) | Still aligned — UX argument was the right framing | No |
| § 82 | Tier-1 DoD = one outdoor run | Still aligned — concrete completion bar; may expand "one" to "many under stress" | Maybe |
| § 83 | PPK2 per-subsystem power measurement | Still aligned — best measurement methodology already | No |
| § 85 | Full PMTiles renderer (+ honest power-cost paragraph) | Already aligned — picked the harder optimal option | No |
| § 86 | End-state quality first, even at small margins | Superseded by § 92. Don't delete; mark as "extended/superseded by § 92" | Update header |
| § 87 | Vector 1 parallel to tier-1 | Still aligned — parallel learning serves optimal-product goal | No |
| § 90 | Apollo510B + BMP581 production-target swaps | Already aligned — pure perf-driven BOM updates | No |

What § 92 commits us to (under interpretation A):

- **Tier-1 firmware target switches from nRF52840 to Apollo510B EVB.** Multi-month HAL bring-up (writing `embassy-apollo` from scratch, or wrapping Ambiq's C SDK via `bindgen`) becomes the first work item.
- **MCUboot bootloader integrated from day one.**
- **ANT+ Alliance Adopter membership application starts now** ($2-5k/year fee + Garmin review, accepting the strategic tip-of-hand).
- **User research interviews happen alongside vector 1.**
- **Tier-1 timeline expands from "3-6 months evenings/weekends" to "as long as it takes" — realistically multi-year.**
- **§ 71 amendment itself is amended** to drop "owner-personal evenings/weekends" and acknowledge this is now a serious multi-year product effort with no fixed budget cap.

Don't re-litigate by:

- **Citing § 86's exception** for any choice that affects end-state quality. § 92 dropped that exception; only "technically infeasible" counts.
- **Falling back to "easier tier-1" arguments** to skip the optimal-path investment. § 92 binds even when the optimal option is multi-month / multi-year.
- **Treating "out of scope" as a valid argument.** The user explicitly said scope is not a constraint when establishing this rule.

Pinning: pending entries (likely § 93-96) to revise § 80 / § 84 / § 88 / § 89 per the table above (after the user picks interpretation A vs B). [§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) amendment may also need an "Amendment-2" under interpretation A.

### Resolution (2026-05-28) — hybrid: § 92 long-term goal + § 80 tier-1 preserved as deliberate first-prototype compromise

User resolved the A/B interpretation question with a hybrid framing: **§ 92 + interpretation A is the long-term goal** ("create the best watch ever"; the full Phase 0–5 optimal-road timeline above stands as the north star), **but tier-1 stays on nRF52840** per [§ 80](#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) as a deliberate first-prototype compromise to "keep costs down and get a working version first." Verbatim instruction: *"so lets have a goal to create the best watch ever. but for the first prototype lets try and keep costs down and get a working version first. then we can move to better hardware. Lets keep [the optimal road] as the final goad. But for the first prototype lets go with the nRF52840 option."*

What this means for the planning sweep:

- **No cascading revisions land.** § 80, § 84, § 88 Layer 3, and § 89 all stay as originally committed. Each is now formally framed as a deliberate first-prototype compromise consistent with the resolution, not as a § 92 violation. § 80 gets an amendment noting this (below).
- **Tier-2 onward follows the optimal road.** Apollo510B production silicon per [§ 90](#90-bom-refresh-2026-05-28--apollo510b--bmp581-swap-ins-supply-alternates-qualified), MCUboot OTA per [§ 84](#84-tier-1-firmware-ships-no-ota-tier-2-obligated-to-a-production-grade-dual-bank-bootloader-mcuboot-default)'s tier-2 obligation, full ANT+ Alliance engagement per [§ 88](#88-vendor-engagement-is-tiered-across-project-maturity) Layer 3, and the rest of the Phase 0–5 timeline above.
- **[§ 71](#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) amendment stays as written for tier-1 effort framing.** "Owner-personal evenings/weekends" remains the tier-1 model. § 71's tier-2+ gating is the natural choke point where the optimal road kicks in — a § 71 trigger flipping (paying user base, ODM offer, hardware co-founder) is what enables the Phase 3+ team + capital investment the optimal road needs.

What § 92 still binds under this resolution:

- **Decisions that affect tier-2+ product quality** get reasoned through the § 92 optimal lens, not § 86's "small margins" lens. § 90's Apollo510B + BMP581 swaps are the worked example — already aligned because they're tier-2+ scope.
- **Any NEW tier-1 decision that compromises tier-3 quality requires explicit "first-prototype compromise" framing.** § 80 / § 84 / § 88 Layer 3 / § 89 are grandfathered in under this resolution; any future tier-1 decision has to either be optimal or be explicitly flagged as a Resolution-style first-prototype compromise (and recorded as such in its entry).

The full Phase 0–5 timeline in the table above remains the final-state vision. It's just not the tier-1 plan.

## 93. Training plans apply a masters (50+) recovery calibration — wider hard-day spacing + a 3-week cycle, not slower paces

Persona-hunt finding Older #30. The plan generator (`generatePlan`) scheduled the first quality session 48h after the Sunday long run (Tuesday) and stepped weekly volume back every 4th week. Both defaults are tuned for younger physiology — masters athletes recover more slowly between hard efforts, so every masters-specific plan widens hard-day spacing toward ~72h and shortens the build/recover cycle.

What we changed (mirrored across the `training.ts` ↔ `training.dart` twins):

- `GeneratePlanInput.age` — optional whole-years field. `isMastersAge(age)` is true at or above `MASTERS_AGE` (50). Null/undefined → the standard schedule (back-compat).
- When masters: the first quality day moves Tue→Wed (72h after the long run) and the second Thu→Fri (keeping ~48h between the two hard sessions); volume steps back every 3rd week instead of every 4th. `isStepBackWeek(i, masters)` centralises the cadence and always keeps week 0 at full ramp.
- The plan wizard (web `PlanEditor.svelte`, mobile `plan_new_screen.dart` via `TrainingService.fetchViewerAge`) reads `user_profiles.date_of_birth` on mount and passes the derived age. No new wizard field — the DOB the runner already set in Settings → Preferences (HR-max derivation, age-grading) is reused.

Why recovery density and not pace (unlike the § 76 female pace calibration):

- The harm being fixed is hard-day frequency, not prescribed intensity. A masters runner can still hit Daniels paces for the duration of a session; what hurts is stacking those sessions too close together.
- No age × VDOT pace table has been published with the rigour required to override Daniels. Slowing every band by an age factor would be guessing — the conservative move is to leave paces alone and fix the spacing the literature actually supports.

Don't re-litigate by:

- Asking age in the plan wizard — the DOB already lives on the profile.
- Adding a per-age sliding scale (55 vs 70). The single 50+ threshold matches how masters categories work in the sport; a finer gradient invites bikeshedding without data to back the curve.

Pinning tests: `apps/web/src/lib/training.test.ts` (5) + `apps/mobile_android/test/training_test.dart` (4) — boundary, Wed-not-Tue first quality, never-<72h invariant, 3-week step-back.

---

## 94. CTL/ATL reset after a layoff — fitness is treated as lost after 28 run-less days

**Decided (2026-05-29, persona-hunt comeback #29):** both training-load engines — `training_load.ts`/`training_load.dart` (the 90-day dashboard chart) and `fitness.ts`/`fitness.dart` (`trainingLoad` → recovery advice + `fitness_snapshots`) — now zero the CTL and ATL EWMAs after `kLayoffResetDays` (28) consecutive run-less days.

**Why:** the EWMA decays correctly during a gap, but ATL (7-day halflife) decays far faster than CTL (42-day). A few weeks into a layoff that leaves CTL elevated while ATL has cratered, so `TSB = CTL − ATL` swings strongly *positive* — the model's "well-rested, peak form, train hard / race soon" signal. For a runner coming back from injury, surgery, or illness that's both wrong and dangerous advice. After the reset, a returning runner's CTL starts from 0, so `recoveryAdvice` falls into the "fitness is still building, focus on consistency" rung instead. A new `isReturningFromLayoff(runs)` helper (recent run preceded by a ≥28-day gap) additionally swaps in explicit "welcome back, rebuild gradually" copy on the recovery card.

**Trade-off:** 28 days is a single hard threshold rather than a gradual confidence decay. It can under-credit someone who cross-trained heavily through a running gap (the model only sees runs). Chosen because the failure it prevents (telling a deconditioned returnee to go hard) is far more harmful than the failure it introduces (telling a cross-trainer to ease back in). Four weeks of zero running is well past any taper or rest week.

**Don't re-litigate unless** we add cross-training/HR-only load inputs (then the gap definition should consider those), or telemetry shows the 28-day cliff misfiring for a real cohort (then move to a graduated CTL-confidence decay). `kLayoffResetDays` is defined once in `training_load.{ts,dart}` and imported by `fitness.{ts,dart}` so all four stay in lockstep. Pinning tests: `training_load.test.ts` + `fitness.test.ts` + the Dart twins (layoff-reset series, `isReturningFromLayoff` truth table, advice override).

---

## 95. event_results is account-optional and stores non-account finisher PII for chip-timing imports

**Decided (2026-05-29, persona-hunt event-organiser #43):** `event_results` was account-only — `user_id` NOT NULL, part of the PK, self-only INSERT. A chip-timing CSV is keyed on bib + printed name + time for finishers who mostly have no account, so the table is now account-optional: surrogate `id` PK, nullable `user_id`, `bib` + `finisher_name` columns, two plain `UNIQUE` constraints `(event, instance, user_id)` and `(event, instance, bib)` (SQL NULL-distinctness keeps account and bib rows from colliding, and they double as `onConflict` arbiters), a CHECK requiring an account OR a bib+name, and an additive `event_results_insert_organiser` policy so a club's event-organiser can bulk-insert. Migration `20261028_001`.

**Why one table, not a sibling `event_external_results`:** a leaderboard is inherently a mix of account holders and bib-only finishers ranked together by time, and the existing `recompute_event_ranks` trigger already ranks every row in an `(event, instance)` group in one pass. A second table would force a cross-table UNION rank (or denormalised duplicate rank) plus a parallel copy of the redaction view and visibility policy. The self-insert invariant a separate table would "protect" isn't worth much here — the feature deliberately adds an organiser write path regardless.

**Privacy / non-account PII:** the bulk import stores **name + bib of people who are not users**. This is inherent to chip-timing import on any schema. Lawful basis: official race results are inherently public (bibs are worn visibly, finisher names are published), so `event_results_redacted` exposes `bib` + `finisher_name` un-redacted while keeping `run_id` / `age_grade_pct` / `note` owner-only. These rows are owned by the event, not a user: they are **not** touched by a user's account deletion (no `user_id`), and are cleared by the `on delete cascade` from `events` when the organiser deletes the event/instance.

**Claim flow (added 20261030_001, organiser-approve; hardened in 20261031_001):** a registered runner can claim a bib-only row; an event-organiser approves, which attaches the account (`event_results.user_id`). Approval takes a `for update` lock on the result row so two organisers approving competing claims on the same bib serialize rather than both clobbering `user_id`. Re-import needs an organiser UPDATE policy (`event_results_update_organiser_bib`, scoped to `user_id is null` bib rows) because the upsert's `ON CONFLICT DO UPDATE` evaluates the UPDATE RLS path — the original INSERT-only organiser policy let a non-owner/admin `event_organiser` do the first import but 42501'd on re-import. Organiser-approve was chosen over a claim-token or self-serve model because the approval machinery already existed (`organiser_approved` + `approve_event_result`), the organiser is the natural trust anchor (they ran the race and imported the sheet), and it needs no secret distribution. An unclaimed/unapproved row degrades gracefully to exactly the pre-claim state (on the leaderboard by printed name, unattached). A separate `event_result_claims` table (not a column) so competing claims on one bib both surface; both writes go through SECURITY DEFINER RPCs (`claim_event_result`, `decide_event_result_claim`) that re-validate against races. Deliberately **not** auto-approving on name match — names aren't proof and that reopens the impersonation hole the gate exists to close.

**Don't re-litigate unless** approval volume becomes a real complaint (then the safe refinement is auto-approving only when the claimant was a recorded RSVP'd attendee of that instance — attendance is signal, a typed name isn't), claim/approval notifications are wanted (deferred — needs a new `notifications` kind, tracked with the persona #38 fan-out work), or a retention/erasure requirement for non-account finisher PII emerges (then add an organiser-facing delete-imported-results control beyond the event cascade).

---

## 96. run_completed notifications fan out only for public runs started in the last 24 h

**Decided (2026-05-29, persona-hunt #38):** the `notifications` inbox gained two community fan-outs (migration `20261101_001`): `club_post` (a club-feed post notifies every active member) and `run_completed` (a finished run notifies the runner's followers). The `run_completed` trigger fires on `runs` INSERT and is gated on `is_public = true AND started_at > now() - interval '24 hours'`.

**Why the 24 h recency gate, not source filtering:** the obvious explosion is a bulk history import — a Strava/Garmin ZIP, a parkrun backfill, or a CSV restore can insert hundreds or thousands of public runs in one batch. Without a guard, each would fan out to every follower (a 200-follower migrator importing 2 000 runs = 400 000 inbox rows). The first instinct was to restrict to `source = 'app'`, but that excludes a legitimately fresh run that arrived via the Strava webhook an hour after finishing — exactly the kind of "X just ran" signal a follower wants. A recency window is strictly better: a fresh run from *any* source notifies; an old run from any source (the bulk-import case, or a late offline sync draining days later) does not. 24 h is wide enough to bracket an ultra-length single session and a same-day sync, narrow enough that no realistic batch import lands a meaningful number of rows.

**Trade-off:** a run saved private and later flipped public never notifies (the trigger is INSERT-only; there's no UPDATE path), and a genuinely fresh run synced more than a day late is silently dropped. Both are acceptable v1 gaps — most app-recorded runs save public-from-start (honouring `privacy_default`) and sync promptly. There is also no per-kind mute yet: a follower of a prolific runner gets one inbox row per public run. The dismiss + mark-all-read affordances cover the noise for now; a notification-preferences surface is deferred until it's actually asked for. Device push (FCM/APNs) for both new kinds stays deferred per roadmap Phase 4b — the row is the delivery surface and the in-app inbox renders it.

**Don't re-litigate unless** the no-UPDATE-path gap draws complaints (then add an `is_public` false→true UPDATE branch with an `OLD.is_public` guard to avoid double-fire), or per-kind notification muting is requested (then a `notification_prefs` bag keyed by kind, checked in each trigger or at read time).

---

## 97. Coach-athlete roster is a web-first invite/accept link model (persona-hunt coach #46)

**Decided (2026-05-29, persona-hunt #46):** a human coach connects to an athlete through a shareable invite token, not a follow or a club. Migration `20261102_001` adds `coach_athletes` — one row per link: `coach_id`, nullable `athlete_id`, `status` (`pending` | `active` | `ended`), `invite_token`, plus `note` / `accepted_at` / `ended_at`. The coach mints a `pending` row (athlete_id null) on `/coaching` and shares `/coaching/accept/<token>`; the athlete redeems via the `redeem_coach_invite` SECURITY DEFINER RPC, which sets `athlete_id = auth.uid()` and flips the row to `active`. RLS scopes every read/write to the two parties; either may end a link (`status='ended'`), and a coach may delete an unredeemed invite.

**Why a token, not a directed follow or a request/approve queue:** a coach often onboards athletes who aren't on the app yet, so the link has to survive "share a URL, they sign up, then accept" — a follow presumes both accounts already exist and a request queue adds an approval round-trip the invite URL already encodes. The token also makes the consent explicit and revocable from both ends, which is the property the run-visibility tier (§ 98) leans on. `athlete_id` is nullable precisely so one coach can hold many open invites at once; a partial unique index keeps at most one live (`pending`/`active`) link per `(coach, athlete)` pair while letting unredeemed invites (null athlete) coexist.

**Why web-first / MVP scope:** per § 24 the web app is the canonical surface, and the coaching roster is pure CRUD over a link table — no device capability is involved — so it ships web-only first with no mobile/watch mirror yet. v1 is invite / accept / roster-list / end-link only. **Deliberately deferred:** coach-owned training plans and plan assignment, plan-edit notifications to the athlete (persona #48), notifications on accept, and any mobile/watch surface. Consent-gated coach run visibility (#47) builds directly on the `active` link — see § 98.

**Don't re-litigate unless** coaches need to invite a specific known user without copy-pasting a URL (then add a directed-invite-by-handle path alongside the token), or an org/club wants to manage a shared roster of coaches (then the link grows a `club_id` scope and the roster surface moves under the club).

---

## 98. An active coach reads an athlete's runs (private + public); the raw GPS track stays owner-only

**Decided (2026-05-29, persona-hunt #47):** the coach-athlete link (`coach_athletes`, migration `20261102_001`, persona #46, decisions § 97) is the consent spine for run visibility. Migration `20261103_001` adds a `private.is_active_coach_of(coach, athlete)` SECURITY DEFINER helper, a `runs` SELECT policy (`active coach reads athlete runs`), and a coach branch inside `private.is_run_visible_to`. Net effect: a coach with a `status = 'active'` link can read all of their athlete's run rows — **public and private** — and the social rows hanging off them (run_kudos / run_comments / run_photos / segment_efforts / live_run_pings, all gated on `is_run_visible_to`).

**Why redemption is the consent:** the athlete forms the link by redeeming the coach's invite token (`redeem_coach_invite`); that deliberate act *is* the consent to share training. No separate per-athlete share toggle in v1 — the link's existence carries it. Ending the link (status → `ended`, either party) revokes everything immediately because the helper only matches `'active'`. The policy is SELECT-only; a coach never gains a write path into an athlete's runs (the owner-only `users own their runs` FOR ALL policy is the sole UPDATE/DELETE path).

**Trade-off — the raw GPS track stays owner-only.** The `runs` Storage bucket SELECT policy (`20260410_001`, first-path-segment = `auth.uid()`) is intentionally left untouched, so a coach reads the run row + stats but not the track bytes. Non-owner track access already routes through `clip_track_for_user` (privacy zones, §33) via the `clip-public-track` Edge Function, which serves public runs only. Granting a coach raw track storage would silently bypass the privacy-zone clip — a real privacy decision (does the athlete want their home location visible to the coach?) plus an Edge Function change. That tier is deferred rather than smuggled into an RLS migration. A second consequence falls out of gating the social-table INSERT policies on the same helper: a coach can now kudos/comment on the athlete's private runs. That is intended — coach feedback on a run is the point.

**Don't re-litigate unless** coaches need the track to render a map in the roster run-review UI (then add a coach branch to `clip-public-track` or a sibling EF that clips against the athlete's zones — keep it routed through `clip_track_for_user`, never a raw Storage grant), or athletes ask to share only a subset of runs with a coach (then a per-run or per-link visibility flag checked in the helper).

**Amendment (2026-06-02) — run PHOTOS are also carved out of the coach tier (audit-storage).** The original net-effect above listed `run_photos` among the social rows a coach inherits via `is_run_visible_to`. On reflection that was inconsistent with the very same "raw track stays owner-only" trade-off in this entry: photos (faces, home interiors, kids, recognisable locations) are at least as sensitive as the track. Migration `20261125_001` adds `private.is_run_photo_visible_to(run_id, user_id)` (owner-or-public, **no** coach branch) and swaps it into both the `run_photos` table SELECT policy and the `run-photos` Storage SELECT policy. So a coach now reads the run row + stats + comments + kudos + segment efforts + live pings, but **not** the athlete's uploaded photos (private-run photos; public-run photos remain visible to everyone, and the event-gallery path is unchanged). Like the track, coach photo access — if ever wanted — should be an explicit `photo_sharing_consent` opt-in, not a side effect of the link. Pinned by `coach_photo_consent_test.sql`.

---

## 99. The community heatmap is a route browser, not just a density blob (web)

**Decided (2026-05-31):** the public `/routes/heatmap` surface kept reading as one undifferentiated red blob — good for "where do people run" ambience, useless for "find me a route I can run." Rather than make the heat layer itself filterable (it can't be — heat *is* density), we split the concern: the heat layer becomes a **dimmable background** (its opacity interpolates 0.85 → 0.25 across zoom 11 → 16) and the discrete, actionable route layer gets the controls. That layer carries (a) filter chips, (b) MapLibre-native clustering so a dense area is one count bubble instead of an unclickable pile, and (c) a viewport-synced collapsible list panel that mirrors the same `routePins` the map shows (hover a row → the map's name tooltip; click → route detail). All three read off one fetch — `discoverable_routes_in_bbox` gained a `p_filter` arg (migration `20261113_001`).

**The four lenses:** `popular` (default — featured OR `run_count > 0`, identical to the prior hard-coded blend so old callers are unchanged), `featured`, `friends`, and `hidden_gems`.

**Why `friends` = "created by people you follow", not "run by them":** the intuitive ask was "routes my friends have actually run." The schema can't back it cheaply — there is no retained run↔route association. `runs.route_id` is nullable and set only when a runner explicitly picks a saved route before recording, so the vast majority of runs carry NULL; `routes.run_count` is a fire-and-forget trigger counter, not a per-run linkage. "Run by friends" would resolve to a near-empty set. So `friends` is `routes.user_id IN (your followees) AND is_public` over the existing `user_follows` graph — populated, indexable, and what "my friends' routes" means on a discovery map anyway. `auth.uid()` is read inside the SECURITY DEFINER body; an anon caller gets an empty followee set (fail-closed). Revisit if/when a durable run↔route match table lands (the map-match pipeline could persist one).

**Why `hidden_gems` has a sanity floor:** the real pollution risk on this surface was never public *runs* (the heatmap is route-geometry only) — it's junk public *routes* (test scribbles, 50 m fragments). There is no quality column, so the lens floors on `distance_m >= 1000` and `run_count = 0 AND NOT featured`. Grow the floor (waypoint count, self-intersection) if junk still leaks.

**Mobile is deliberately behind.** The discovery browser is web-only; mobile `/routes/heatmap` still fetches only the raw heat + nearby polylines (no discoverable-pins layer at all). That's the web-canonical / mobile-additive policy (§ 24), not an oversight — bringing mobile to parity also means a clustering dependency on the byte-identical Flutter twin, tracked as a follow-up in `roadmap.md` § 4 and `parity.md` § Discovery.

---

## 100. Discovery is a results-sidebar layout with race-distance band filters (web)

**Decided (2026-05-31):** the first cut of the discovery browser (§ 99) hung the controls — search, lens chips, legend, list panel — as separate floating cards over the map, which overlapped each other and the canvas, and offered no distance filtering. Two changes:

**Layout: results sidebar beside the map, not floating over it.** The component is now a flex row — a fixed-width sidebar (search + a **Filters** popover + the scrollable results list) next to a `flex: 1` map. Side-by-side is the runner-app-standard discovery layout (AllTrails / Komoot / Strava) and structurally eliminates overlap: the only thing floating on the map is its own MapLibre nav controls + a sidebar-collapse handle. Collapsing the sidebar fires an explicit `map.resize()` because the canvas width changes. The lens chips, the distance bands, and the heat/clubs layer toggles all live inside the Filters popover (opened from a button next to the search) with an active-filter count badge + Reset, so the default view is just search + list + map.

**Race-distance bands.** Runners search by race distance, so the discovery filter is 5K / 10K / Half / Marathon / Ultra, multi-select, combinable with the lens. Rather than encode band keys in SQL, the client owns the windows (`apps/web/src/lib/routes/distance_bands.ts`, the single source of truth) and passes them to `discoverable_routes_in_bbox` as two **parallel bound arrays** `p_dist_min[]` / `p_dist_max[]` (migration `20261114_001`); a route matches if it falls in ANY band (`unnest(min, max)` + `EXISTS`), so any permutation works, and a NULL upper bound is open-ended (ultra). Filtering is server-side so the per-viewport 100-route cap applies *after* the distance filter — a client-side filter would hide marathons that exist beyond the first 100 popular routes. Windows are tolerant (a "5K" is rarely exactly 5.00 km) with gaps between bands (a 15 km route is no race distance and matches nothing); `bandForDistance` badges each list row. The bands are web-only logic — no Dart twin — so they are not a TS↔Dart parity pair.

---

## 101. Discovery routes are drawn on hover, not all at once (web)

**Decided (2026-05-31):** the discovery map used to draw the full polyline of *every* nearby public route at zoom ≥ 12 (the `nearbyPublicRoutes` overlay) — a wall of overlapping lines. That overlay is removed. Routes are now represented by their dot + list row, and **only the route you're hovering draws its line** (Strava/Komoot-style preview). Hovering a dot *or* its list row reveals that one route's line + a cyan halo on its start dot and tints the matching list row — a **synchronized hover** across both surfaces.

**Informed by UX research** on map list/marker interactions, which split cleanly into things users like and things they hate:
- *Like:* synchronized hover (highlighting the row **and** its marker together — Baymard found 76% of sites get this wrong); hover as a preview of what a click gives; markers that stay clickable (AllTrails' most-cited complaint is "the map isn't clickable").
- *Hate:* **flicker** — the single most common map-interaction complaint across every library (info windows flickering on mouseover, markers redrawing/jumping); accidental triggers; the map lurching.

So the implementation is built explicitly against flicker: route geometry comes from the already-privacy-clipped `fetchRouteById` and is **cached per id** (a second hover never refetches), the draw is **async-guarded** (a slow fetch can't paint after the cursor moved on), re-hovering the same id is a **no-op**, clearing is **debounced (90 ms)** so crossing from a dot onto its line — or between adjacent rows — doesn't flash, and there is **no pan/fit on hover** (the map never lurches). Click paths are untouched (dot → popup, row → route, the previewed line itself → route), so **touch devices, which never fire hover, lose nothing** — they get the tap popup + the row link. Geometry is fetched per-route on demand rather than bulk-loaded, so the hover preview adds no per-viewport payload.

---

## 102. Mobile route-discovery is the web browser adapted for touch, not a literal port

**Decided (2026-05-31):** the web discovery browser (§§ 99–101) shipped on mobile (`apps/mobile_android/lib/screens/routes_heatmap_screen.dart` + its iOS twin), but the touch + small-screen constraints force three deliberate adaptations rather than a 1:1 copy:

1. **Layout: bottom sheets, not a sidebar.** A phone can't show a persistent results sidebar beside the map, so the results list lives in a `DraggableScrollableSheet` and the filters live in a `showModalBottomSheet` opened from an AppBar Filters button (with an active-count badge). The lens + race-distance band chips are the same set as web.

2. **Interaction: tap-to-preview, not hover.** Touch has no hover, so the web hover-preview becomes a tap: tapping a route's pin *or* its list row selects it — drawing that one route's line + a halo on its start dot and switching the sheet to a route card with a "View route" action. A second tap (the card's action) navigates. This mirrors web's pin-popup flow and keeps the "lines hidden until you ask for one" decluttering (§ 101). Selecting from the list pans the map to the route; selecting a pin doesn't (it's already on screen).

3. **Clustering: pure Dart, no new dependency.** flutter_map has no native marker clustering (web gets it free from MapLibre). Rather than add a clustering package to the byte-identical twin, `lib/heatmap_clustering.dart` does a greedy pixel-proximity merge at the current zoom via an injected projector — clusters break apart as you zoom in, same behaviour, zero new deps, unit-testable. `lib/distance_bands.dart` is the Dart twin of `distance_bands.ts` (a new TS↔Dart parity pair). The two `discoverable_routes_in_bbox` / `clubs_in_bbox` Dart fetchers route through `api_client` like every other Supabase call.

Route geometry for the preview comes from the existing `fetchRouteById` (already privacy-clipped). This is the web-canonical → mobile-additive flow of § 24 working as intended: build on web, then mirror with platform-appropriate UX.

---

## 103. The density heat layer is off by default, and only fetched when on

**Decided (2026-05-31):** the heat layer (§ 99 made it a dimmable background) is now **off by default** on both web and mobile. At any zoom where you can read individual routes, the heat traces each route's densified path and reads as "the route is already shown" — which fights the hidden-until-hover/tap model (§ 101/§ 102) and was the top user complaint ("I still see the route without hovering"). It's now opt-in via Filters → Heat; the default discovery view is basemap + clustered dots + reveal-on-interaction.

**And it's not fetched until enabled.** `heatmap_points_in_bbox` densifies up to 200 routes into ~5k points server-side per call; doing that on every pan only to hide the result is pure waste. The web `refresh()` and the mobile `_refresh()` skip the heat fetch entirely while the layer is off, and fetch on demand when it's turned on (and on pan only while on). So the default view costs zero heat compute / bandwidth no matter how dense the seed data gets — which, with the discovery RPCs all being bbox-windowed + capped (100 pins / 200 densified routes per call), keeps the heatmap fast as more public routes land in a city.

Fixing this surfaced a latent bug: the web layer-visibility `$effect`s early-returned on `!mapLoaded` *before* reading their toggle `$state`, so Svelte never tracked it and the effect never re-ran when the toggle flipped (the layer never actually showed/hid; the toggle-tests missed it because they only checked the checkbox state). The fix is to read the reactive value before the readiness guard.

---

## 104. The per-run og:image PNG renders at request time in the share-run Lambda, not at build time (persona round-5 very-social)

**Decided (2026-05-31, persona-hunt round-5 very-social):** `/og/run/<id>.png` moved from an adapter-static build-time prerender (with a 50k-run cap) to request-time rendering. The share-run Lambda (persona Casual #4) already owned `/share/run/<id>` HTML at request time; it now also matches `/og/run/<id>.png` and renders the card via a shared `renderRunOgPng` helper (`apps/web/src/lib/share/og_run_png.ts`) that both the Lambda and the SvelteKit dev endpoint call. A new CloudFront `/og/run/*` behaviour routes the path to the Lambda; the SvelteKit endpoint is `prerender = false`.

**Why:** under adapter-static, a prerendered image only exists for run ids known at the last build. A run created after that build — or beyond the 50k cap — had no PNG, so social unfurls of a fresh share showed a broken/missing image even though the HTML head (Lambda-rendered) was correct. Generating on demand makes the image exist for any id, regardless of build cadence — closing the same gap for the PNG that Casual #4 closed for the HTML.

**Trade-off — packaging the native rasteriser.** `@resvg/resvg-js` is a native `.node` addon; esbuild can't inline it. The original authors deferred the PNG-in-Lambda work for exactly this reason. The fix keeps the loader + the `@resvg/resvg-js-linux-arm64-gnu` package external in `build.mjs` and copies both into the zip's `node_modules` (the Lambda is arm64). The build fails fast with the explicit `npm install --cpu=arm64 --os=linux` command if the arm64 package isn't resolvable on the build host. A missing/private/deleted run renders a generic branded card at **HTTP 200**, never a 404 — a broken unfurl image is the bug being fixed. The operator verification step is logged in `docs/product/followups.md`.

**Don't re-litigate unless** the Lambda cold-start cost of loading @resvg becomes a problem (then split the PNG into its own function, or pre-warm), or the card needs the run polyline (then route through `clip_track_for_user` like the route og:image, never a raw Storage read — same privacy posture as § 33).

**Amendment (2026-06-04) — the same treatment shipped for routes.** `/share/route/<id>` (HTML + JSON-LD) and `/og/route/<id>.png` had the identical build-time-prerender gap (a 5k `entries()` cap; a route made public after a build served the SPA-shell head + a 404 image, and a public→private flip stayed on S3 until overwritten). Both now render at request time in a dedicated **`share-route` Lambda** (`apps/web/lambda/share-route/`), a symmetric mirror of share-run: the page `+page.ts` + og `+server.ts` are `prerender = false`, CloudFront has `/share/route/*` + `/og/route/*` behaviours, and the og:image track is privacy-clipped via `clip_track_for_user` (so a home/work coordinate never reaches the unfurl — § 33). The route HTML head reuses `buildRouteShareCanonical` / `buildRouteJsonLd` / `buildRouteOgSvg`. Same generic-card-at-200 contract for private/deleted ids. Kept as its own Lambda (not folded into share-run) so deploy / rollback / concurrency on one share surface can't affect the other.

---

## 104. Overlapping start pins list their routes; routes can be pinned to keep them visible

**Decided (2026-05-31):** two follow-ons to the hover-preview model (§ 101 / § 102), both on web + the mobile twin.

**Overlapping pins → a list, not an arbitrary pick.** Routes that share (or nearly share) a start collapse into a cluster, and pins at an *identical* coordinate can never be zoomed apart. The old behaviours were dead ends: clicking such a cluster zoomed uselessly, and past the cluster zoom the hover handler previewed `e.features[0]` — whichever pin rendered on top, arbitrarily. Now hovering a cluster (web) or an overlapping leaf stack opens a **list popup** of its routes (`getClusterLeaves` for clusters; `queryRenderedFeatures` at the cursor for un-clustered overlaps, de-duped by id), each row previews its line on hover and opens on click. On mobile (where pixel-proximity clustering means same-start pins are *always* clustered) tapping a cluster opens the equivalent bottom **sheet** — the pure-Dart clusterer already hands the screen `cluster.items`.

**Keep-on-map (pin).** A pin affordance (row button + a "Keep on map" button in the route popup + a "Clear N kept" header control) keeps a route's line drawn — in **violet**, on its own layer below the cyan hover preview, persisting across pan + filter changes — so several routes can be compared at once. It is deliberately cheap: only pinned routes are fetched, reusing the hover `geomCache`, so a route is fetched at most once and the default view costs nothing. Chosen over a "show all route lines" toggle precisely because that would reintroduce the bulk-geometry fetch + clutter the hidden-until-asked model removed (the compute the owner repeatedly flagged).

---

## 105. On the discovery map a click keeps a route; navigation is an explicit "View route" link (web)

**Decided (2026-05-31):** clicking *any* route surface on `/routes/heatmap` — a list row, a map dot, a previewed line, or an overlap-popup row — used to navigate to `/routes/[id]`. A single mis-click yanked the user off the discovery map, discarding their filters, pan, and kept routes; the dot was the worst offender (it opened a popup whose primary action was the same navigation). The owner flagged this as bad UX.

**A click now *inspects*, never *leaves*.** Clicking a route toggles "keep on map" (draws / removes its violet line) everywhere. Navigation moved behind an explicit, labelled **"View route →"** link — one per sidebar row, one per overlap-popup row. The route dot no longer opens a navigable popup at all; it just keeps / un-keeps. This collapses the older two-control model (§ 104: a separate keep button + a click-to-navigate row) into one: the row body *is* the keep target, and the old pin button is replaced by the View link. Power users keep a fast path — the View link is a real `<a href>`, so ctrl/cmd-click and right-click still open the detail page directly. Club pins are unchanged (their popup is informational, its only action a "View club" link).

This is **web-only for now**: the mobile twin already avoids the mis-click trap (a tap selects → shows a route card → the card's button navigates), so it has no equivalent bug to fix. Whether mobile should adopt the same click-keeps model (rather than its select-card) is an open product question, not a parity regression.

---

## 106. Membership/role oracles moved to `private` via `ALTER FUNCTION SET SCHEMA`, not by re-emitting every policy

**Decided (2026-06-01):** the four club/event membership oracles — `is_club_member`, `is_club_admin`, `is_event_organiser`, `is_race_director` — were SECURITY DEFINER functions in the `public` schema, so PostgREST exposed each as an anon-callable RPC (`POST /rest/v1/rpc/is_club_member` returns `true`/`false` for any (caller, club) pair — a membership/role oracle, even on private clubs). Audit-findings 2026-05-30 Medium. Same class as `is_run_visible_to` (§ corollary above / migration `20260812_001`), and the same fix: move them into the `private` schema, which PostgREST does not expose.

**How matters.** The `is_run_visible_to` migration re-created the function in `private` and re-emitted each of its ~6 dependent policies with the `private.`-qualified name, leaning on the final `drop function` failing loudly to prove completeness. These four oracles are referenced by ~30 policies across ~33 migration files — re-emitting each one's *latest* body verbatim is a large transcription-error surface (a survey agent already missed several call sites). Instead, migration `20261120_001` uses **`ALTER FUNCTION public.is_club_member(uuid) SET SCHEMA private`**: this preserves the function's OID, and Postgres records RLS policy → function dependencies by OID, so every dependent policy's stored expression is rewritten to `private.is_club_member(...)` automatically and atomically — zero policies touched, zero transcription risk (verified empirically: a policy reading `is_club_member(club_id)` reads `private.is_club_member(club_id)` immediately after the move).

**The trade-off / gotcha.** `SET SCHEMA` does *not* fix SECURITY DEFINER **callers** of the oracles — plpgsql/sql function bodies re-parse unqualified names at execution time using their own `search_path`, not by OID. Eight such callers exist (`approve_event_result`, `decide_event_result_claim`, `clone_plan_template`, `claim_event_result`, `clip_route_for_viewer`, `get_club_invite_token`, `get_event_meet_point`, `segment_leaderboard_tiered`); each gets `private` appended to its `search_path` so the unqualified call resolves to the moved function without re-emitting its (often long) body. The **full pgtap RLS suite is the completeness net** here, not a `drop function` — the first reset surfaced the callers `SET SCHEMA` alone left broken (`function is_club_member(uuid) does not exist`). Pinned by `membership_oracles_private_schema_test.sql`. The functions also dropped from `database.types.ts` (they were public RPCs); regenerated in the same change. **Don't** re-add one of these helpers to `public`, and **don't** add a new SECURITY DEFINER caller with `search_path = public` that calls them — it'll fail at runtime until `private` is on its search_path.

---

## 107. Vector 1 starts as a Connect IQ data field (grade-adjusted pace), not a full watch app

**Decided (2026-06-01):** the strategic-Vector-1 probe ([§ 87](#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware)) is scaffolded at `apps/watch_garmin/` as a Connect IQ **data field** in Monkey C — one metric (grade-adjusted pace, Minetti 2002 model) injected into Garmin's native run screen — **not** a full Connect IQ watch app.

**Why a data field.** It's the cheapest of the four Connect IQ app types: Garmin keeps owning the recording, GPS, FIT file, and sync, so there's no sandbox fight over mid-activity networking, no OAuth-on-watch, and no Garmin business approval — it ships through the Connect IQ Store at near-zero risk. The full watch-app shape (our own recording UI + direct Supabase POST via `Communications.makeWebRequest` on a phone tether) is the real "is our UX better than Garmin's" test but is months of work; we gate starting it on the data field proving install demand, which is the validation channel [§ 89](#89-skip-user-research-interviews-vector-1-install-rate-is-the-validation-channel) already named.

**The trade-off / exemption.** `watch_garmin` is **research-tier and exempt from the web-first rule** ([§ 24](#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)) the same narrow way `apps/custom_watch/` is — it's a platform probe, so it's absent from `parity.md`. The exemption covers *proving the toolchain*, not pioneering product features: grade-adjusted pace is **not a web feature yet**, so on this surface it's a demo, and shipping it to users is gated on it landing on web first (tracked in `followups.md`). Monkey C can't import the Dart/TS parity helpers, so the GAP model is a **third** hand-maintained copy — kept tiny and source-commented. **Don't** treat `watch_garmin` as a parity client, and **don't** ship a metric here that doesn't exist on web.

---

## 108. Web i18n is detected client-side, with a lazy-loaded message catalogue — not an Accept-Language SSR framework

**Decided (2026-06-01):** the web i18n runtime (`apps/web/src/lib/i18n/`) negotiates the active locale **on the client**, on first mount, from a stored preference → `navigator.languages` → English, and applies it to `<html lang/dir>` plus a reactive message signal. There is **no `Accept-Language` parse in `hooks.server.ts`**, contrary to the original audit framing (i18n-readiness W-2/W-3).

**Why client-side.** The web app ships via `@sveltejs/adapter-static` with `prerender` + an `index.html` SPA fallback — **there is no per-request SSR server in production** (only the coach Lambda runs server-side). The HTML is baked at build time, so a server-side `Accept-Language` header has nowhere to run. Client detection mirrors the established pattern for the `preferred_unit`, `week_start_day`, theme, and `formatPrice` signals, all of which already key off `navigator.language` after hydration. The first-paint English flash is the same window the theme toggle already tolerates.

**The shape.** A hand-rolled runtime, not inlang/Paraglide/sveltekit-i18n. English is statically bundled (the fallback dict + prerender default); every other locale is a **dynamic `import()`** chunk, so a single-locale visitor downloads only their own strings and the i18n layer adds ~nothing to the initial payload — this is the explicit responsiveness choice (a runtime that eagerly bundles all locales would bloat the JS). `m(key, params)` reads the reactive `dict` so call sites re-render on locale change; missing keys fall back to English then the raw key. `Messages = typeof en` + `satisfies Messages` on each locale makes a missing/extra key a compile error; `messages_parity.test.ts` guards it (and `{placeholder}` integrity) at runtime.

**The trade-off.** Extraction is incremental — strings move into the catalogue surface-by-surface (shell first), and an un-extracted literal simply stays English until its turn. A bare `<html lang="en">` in `app.html` is correct as the *prerender default* only; never read it as the live locale. RTL has a switch-point (`dirForLocale`) but no RTL locale ships yet; the CSS is already logical-property-clean (rtl_css_guards). **Don't** add an `Accept-Language` server hook for the static site, and **don't** statically import the non-English catalogues.

**Amendment (2026-06-10) — plurals are encoded inline in the message value, ICU-style, not as `*One`/`*Other` key pairs.** `interpolate()` now resolves `{var, plural, one {…} other {…}}` blocks by selecting the CLDR category via `Intl.PluralRules` for the active locale (`#` → the count, `=N` exact matches win, named placeholders still substitute). This matches mobile's ARB `{n, plural, …}` shape, so a count string can't render "1 sets" on web while mobile says "1 set". The convention for any new countable-noun string: write one ICU value with `one`/`other` branches (add other CLDR categories only for locales that need them; `ja` collapses to a lone `other`) — **do not** add sibling `fooOne`/`fooOther` keys. The pre-existing hand-rolled `*One`/`*Other` pairs predate this and migrate to the ICU runtime incrementally. Invariant counts (parentheticals, units, ordinals) stay plain — there's no noun to inflect.

---

## 109. The dashboard's CTL/ATL/TSB numbers, recovery advice, and readiness ring read the same training-load series as the chart

**Decided (2026-06-01):** on the dashboard, the displayed Fitness/Fatigue/Form numbers, the recovery-advice line, and the readiness ring all derive from the **final point of `computeTrainingLoadSeries`** (`training_load.ts` / `.dart`) — the same series the training-load chart plots. `computeSnapshot` (`fitness.ts` / `.dart`) stays the source for VO₂max / VDOT / qualifying-run-count only.

**Why.** The two modules compute training load differently: `fitness.ts` uses a threshold-pace TSS with EWMA `prev + (sample−prev)/tau`, while `training_load.ts` uses TRIMP-when-HR / distance-fallback stress with EWMA `alpha = 1 − exp(−1/halflife)`. Driving the *number + advice* off one module and the *chart* off the other let them straddle the TSB advice threshold — the card could read "+30, fresh, go race" directly above a chart whose curve said otherwise (persona round-5 pro). One series, one truth.

**The trade-off.** The displayed CTL/ATL/TSB now match the chart's model (TRIMP/distance) rather than `fitness.ts`'s TSS model, so the numbers shifted slightly for existing users — an acceptable one-time change in exchange for internal consistency. The two stress models were deliberately **not** merged (that's a larger behavioural change); they coexist, and the dashboard simply commits to the chart's as canonical for the load trio. Source-level guards pin the single-source wiring on both web (`dashboard_fitness_source_guard.test.ts`) and mobile (`fitness_card_test.dart`). **Don't** re-point the card or readiness ring back at `computeSnapshot` for the load numbers.

---

## 110. Coach assistant messages are written by a service-role client; clients may only insert their own `role='user'` turns

**Decided (2026-06-01, XSS audit H1):** the `coach_messages` INSERT policy is `with check (auth.uid() = user_id and role = 'user')` (migration `20261122_001`), and the coach handler persists the assistant turn through a **service-role** Supabase client that bypasses RLS — not the user-JWT client it uses for everything else. Content is capped at 64 KiB by a DB CHECK (`NOT VALID`) matching `MAX_COACH_ASSISTANT_CONTENT_BYTES`, and the handler truncates to the same bound before insert.

**Why.** The handler runs *as the authenticated user* (anon key + the caller's JWT — `handler.ts`), so the old owner-only INSERT policy let any caller (or a hand-rolled REST request) write a `role='assistant'` row whose `content` is rendered via `{@html renderMarkdown(...)}` in `CoachChat.svelte`. DOMPurify sanitises it and `coach_messages` SELECT is owner-only, so the live blast radius is self-XSS — but it is a least-privilege violation and would become cross-user stored XSS the moment a coach-athlete shared-thread read path exists (the §97/§98 coach run-read path deliberately does **not** cover `coach_messages`). Because the handler and a malicious client are the *same* role, the only way to give the handler a write the client lacks is to write under service-role.

**The trade-off.** This introduces `SUPABASE_SERVICE_ROLE_KEY` into the coach Lambda env (provisioned via the env's sops secrets file; the share-run Lambda has a separate env and never sees it) — a high-privilege secret scoped to one function. When the key is absent the coach still streams; only assistant-message persistence is skipped (logged). The one-time localStorage→DB migration now imports only the user's own turns. pgtap pins the contract (`coach_messages_role_lockdown_test.sql`). **Don't** route assistant writes back through the user-JWT client, and **don't** widen the INSERT policy to accept `role='assistant'`.

---

## 111. Settings → Preferences auto-saves; only the Art 9 demographics keep an explicit, consent-gated Save

**Decided (2026-06-01):** the preferences page no longer has a global "Save Preferences" button. Every cross-device pref persists the moment it changes — selects/toggles on `change`, number inputs (mileage goal, voice interval, resting/max HR, HR zones) on `blur` — with a subtle inline "Saving…/Saved" cue. The **demographics** (gender + DOB) are the sole exception: they keep a dedicated **"Save demographics"** button gated on the GDPR Art 9 consent checkbox.

**Why.** The page was a confusing mix — theme, language, and privacy zones applied instantly while everything else waited for a Save button, so a user who'd just seen Language change live would change "Week starts on", navigate away, and silently lose it. Auto-save makes the whole page behave the way the instant controls already did. Demographics stay explicit because they're special-category data: persisting them must be a deliberate, consent-confirmed action, and auto-saving them would entangle the write with the still-open consent-flow-consistency follow-up. Auto-save is safe here because `updateUniversal` is already offline-first (write-through cache + pending queue, [§79]).

**The trade-off.** Per-field writes are **debounce-coalesced** (~350 ms) into a single batched `updateUniversal` so two fields blurred back-to-back can't clobber each other on a stale bag snapshot (the bug the HR clear-path test caught); `beforeNavigate` flushes anything still pending so a change-then-leave never drops. The unit toggle additionally **awaits** its `user_profiles.preferred_unit` dual-write before the "Saved" cue, since the auth store reads that column on the next load. **Don't** reintroduce a global Save button, and **don't** fold gender/DOB into the auto-save path until the consent-flow item is resolved with counsel.

---

## 112. The mobile route-heatmap keeps the map full-bleed: a results pill + modal list + selection card, not an always-present draggable sheet

**Decided (2026-06-01):** on `routes_heatmap_screen.dart` (Android + iOS twin) the discovery results no longer live in a permanently-mounted `DraggableScrollableSheet`. The map is full-bleed; a floating "N routes" pill opens the list as a **dismissible modal** sheet, and selecting a pin/row shows a **compact dismissible card** at the bottom. The Locate FAB floats just above whichever is showing. Web keeps its desktop **sidebar** unchanged — this is a deliberate mobile-only layout divergence, allowed under [§24](#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive) (same feature, platform-native presentation).

**Why.** The old sheet had `minChildSize: 0.12`, so even collapsed it permanently ate the bottom of the map and obscured pins exactly where routes near the user cluster; the drag-to-resize was the part the owner disliked. A modal that opens on demand and swipes away matches what map apps (Google Maps, Komoot) converge on and keeps the map the hero on a small screen.

**The trade-off.** The list is a snapshot taken when the pill opens (the modal scrim blocks panning anyway — close, pan, reopen); pin-toggles inside the modal refresh it via a `StatefulBuilder` `setSheet`, the same pattern the Filters sheet already uses. **Don't** port this to web — its sidebar is correct on desktop, and the owner likes it.

---

## 113. Mobile i18n uses Flutter gen-l10n + ARB, with committed (non-synthetic) output and a per-device locale

**Decided (2026-06-01):** the Flutter apps localize via the **standard** stack — `flutter_localizations` + `intl` + `.arb` catalogues + gen-l10n — rather than a hand-rolled runtime like web's ([§108](#108-web-i18n-is-detected-client-side-with-a-lazy-loaded-message-catalogue--not-an-accept-language-ssr-framework)). The six locales match web (`en/de/fr/es/ja/pt-BR`, plus the base `pt` fallback gen-l10n requires for `pt_BR`). Two non-obvious choices:

- **Generated output is committed under `lib/l10n/gen/`, not synthetic.** `l10n.yaml` sets `output-dir: lib/l10n/gen` (synthetic-package mode is removed in current Flutter). gen-l10n output is **package-name independent**, so the generated Dart is byte-identical between the `mobile_android` / `mobile_ios` twins and rides the existing `lib/` mirror with zero special-casing — `diff -rq` stays clean and the only pubspec delta remains `name` + `description`. Committing (vs per-machine regen) removes any risk of a Flutter-patch-version difference emitting divergent output on one twin.
- **Locale is a per-device setting, never DB-synced.** Mirrors web's localStorage-only model: stored in `Preferences` (`_kLocale`, a canonical tag; absent = follow device), driven reactively through a global `localeNotifier` into `MaterialApp.locale`, **not** routed through `SettingsSyncService.updateUniversal`. `locale_support.dart` is the pure Dart twin of web's `locale.ts` (`negotiateLocale` etc.), unit-tested alongside an ARB key-parity test that mirrors web's `messages_parity.test.ts`.

**Why.** gen-l10n is the idiomatic Flutter path (plural/placeholder/ICU support, tooling, `Localizations.localeOf` integration) and avoids reinventing web's runtime in Dart. Per-device locale matches the existing theme/unit prefs and web's behaviour — language is a device choice, not a roaming account preference.

**The trade-off.** ARB keys can't contain dots, so web's dotted keys map to camelCase (`nav.dashboard` → `navDashboard`) — a mechanical transform that keeps web↔mobile coverage cross-checkable. The catalogues are **separate** from web's `.ts` (no shared source of truth); the parity tests on each side are what keep them honest. RTL (`EdgeInsetsDirectional` sweep) is deferred until an RTL catalogue is added — same call web made.

## 114. Grade-adjusted pace lands on web/mobile first as a shared Minetti parity helper, computed over ≥5 m segments and shown only when it diverges from raw pace

**Decided (2026-06-02):** grade-adjusted pace (GAP) — the effort-equivalent flat pace over hilly terrain — ships as a pure TS↔Dart parity pair (`apps/web/src/lib/runs/grade_adjusted_pace.ts` ↔ `apps/mobile_android/lib/grade_adjusted_pace.dart`) surfaced on run detail, ported from the on-watch Connect IQ field (`apps/watch_garmin/source/GradeAdjustedPaceView.mc`). This satisfies the web-first prerequisite [§107](#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app) put on shipping that field to real users. Non-obvious choices:

- **Energy model is Minetti et al. 2002** (the same 5th-order polynomial the watch field already uses): GAP factor = `C(grade)/C(0)`, equivalent-flat distance for a segment = horizontal distance × factor, and overall GAP = total time / total equivalent-flat distance. Grade is clamped to ±45% (Minetti's fitted range) so a GPS-altitude spike can't manufacture an absurd factor.
- **Grade is measured over ≥5 m segments, not point-to-point.** GPS altitude is jittery between consecutive ~1 s fixes; accumulating horizontal distance to a 5 m floor before taking a grade sample (mirroring the watch field's `MIN_SEGMENT_M`) is what keeps the aggregate honest. Segments missing elevation fall back to factor 1 rather than dropping out.
- **The cell is hidden unless GAP differs from raw average pace by ≥2 s/km**, and the helper returns null without elevation or timestamps. A flat run's GAP *is* its raw pace, so an always-on cell would be noise on the most common run; GAP earns its place only when terrain actually moved the number.

**Why a shared helper, not a watch-only number.** GAP is a product metric, not a watch gimmick — keeping the algorithm identical across web, both mobile twins, and the Connect IQ field means the figure a runner sees on the wrist matches the one on run detail. The parity pair + mirror test suites (10 tests each side) are what hold that line.

## 115. A run's public gear chip reads through a SECURITY DEFINER projection RPC, not a relaxed `gear` RLS policy

**Decided (2026-06-02):** the gear chip on the public run-share page reads via `public_run_gear(p_run_id)` (migration `20261126_001`) — a `SECURITY DEFINER` function that checks `private.is_run_visible_to` and returns only the public columns (`id, kind, name, brand, model`) of gear linked to that run.

**Why not just relax the `gear` SELECT policy?** The obvious "let non-owners read gear on a public run" RLS policy can't work: Postgres RLS is **row-level, not column-level**. Any policy that makes the gear *row* visible exposes every column on it — including the owner-private inventory metadata (`notes`, `purchased_at`, `target_distance_m`, `retired_at`). A definer function that hand-projects the safe columns is the only way to publish the shoe/bike model on a public run without leaking the rest of the owner's gear locker. (`fetchRunGear` had a defence-in-depth comment pinning a public-column list on the old table join *precisely* anticipating this; the RPC makes the projection structural instead of advisory.)

**Secondary fix bundled in the same migration:** the original `run_gear` SELECT policy (`20260827_001`) wrapped `is_run_visible_to` in an `exists (select 1 from runs r …)` whose inner read was itself gated by the caller's base-`runs` RLS — which `20260701_001` had stripped of public-run exposure. So the policy silently returned nothing for the exact public-share audience it was written for, and the chip rendered for the owner only. The fix calls `is_run_visible_to` directly, matching the sibling social-table policies (kudos / comments / photos). General lesson: **a visibility helper that's already `SECURITY DEFINER` must be called directly in a policy — wrapping it in a subquery over an RLS-gated base table re-subjects it to the caller's RLS and defeats the point.**

## 116. Indoor/trackless HR series live in a sidecar Storage object, not synthetic TrackPoints or a metadata blob

**Decided (2026-06-02):** per-point heart rate for an indoor / treadmill run (HR but no GPS fix) is stored as its own gzipped Storage object `{user_id}/{run_id}.hr.json.gz` in the existing `runs` bucket, pointed to by a new `runs.hr_series_url` column (migration `20261127_001`). The HR-zone breakdown reads it when the run's `track` carries no `bpm` samples.

**Why a sidecar, not the two obvious alternatives:**

- **Not HR-only `TrackPoint`s** (emit a waypoint with `bpm` and no lat/lng). The zone consumers (web `bpmTimedSamples`, Dart `hrZoneBreakdown`) read only `bpm`/`ts` and would be happy — but every *coordinate* consumer would break: Go `BuildGpx` emits `lat="0" lon="0"` for zero-value floats, the EF `buildGpx` emits `lat="undefined"`, and `Waypoint.fromJson` throws on a null/absent `lat`. A wide blast radius for zero benefit to the chart.
- **Not `metadata.hr_series`.** The `metadata` jsonb bag is pulled by `SELECT *` on every list/dashboard query; a few thousand HR samples per run would bloat the hot path that never needs them.
- **A sidecar** keeps the samples out of the row and off the coordinate pipeline entirely. It reuses the `runs`-bucket RLS (`{user_id}/...` keyed on `auth.uid()`), so no new bucket or policy — only a path-shape CHECK mirroring `track_url`'s.

**The privacy line that falls out of it:** the HR sidecar carries **no location**, so unlike the track it is plain owner-only audit data — it is deliberately never routed through `public_runs` or `clip_track_for_user`. Exposing your average HR is a different (and not-yet-made) product decision from exposing where you ran.

---

## 117. Notification delivery ships email first, on the Go worker, because email needs no third-party push credential

**Decided (2026-06-03):** the first off-app notification-delivery channel (roadmap Phase 4b) is **email**, implemented as a `notification_email` job kind on the Go worker (migration `20261130_001`). An AFTER-INSERT trigger on `notifications` enqueues one job per row; `handler_notification_email.go` resolves the recipient's preference + address and sends over SMTP. Event-day reminders are a sibling piece: `enqueue_event_reminders()` (hourly pg_cron) inserts an `event_reminder` notification for every `going` RSVP whose occurrence is inside the next 24 h, which then rides the same email path.

**Why email, why now.** Phase 4b was framed as "push (FCM/APNs) — blocked on user-supplied Firebase/APNs credentials." That's true for the *native* leg only. Email needs no push credential — it sends over SMTP to the local Mailpit catcher (`:54325`) in dev and a provider (Resend/SES SMTP) in prod, so the entire fan-out → preference → render → deliver path is buildable and **end-to-end testable on the local Docker stack today**. It unblocks the user-visible Phase 4b outcome (you get told about your events) without waiting on an operator to stand up Firebase. The `notifications` row stays the single source of truth (`§ 38`); the email handler is one consumer of it, and a future FCM/APNs sender is a second consumer of the same rows — no schema change when it lands.

**Why the Go worker, not an Edge Function.** This matches the established "port a scheduled/triggered job onto the queue" pattern (`token_refresh`, `photo_process`) — the worker already owns `jobs`-queue draining, service-role reads, and the <30 s-per-job budget that one-email-per-recipient satisfies. An EF would have re-implemented the queue semantics the worker already has.

**The shape that falls out.**
- **Preference:** a universal `user_settings.prefs.email_notifications` key (`all | important | off`, default `important`) — a jsonb-bag key, no migration (`docs/backend/settings.md`). Default `important` emails reminders/cancellations/coach-plan-updates/DMs and **not** the social loop (kudos/comments/follows/club-posts/run-completed), so a fresh user isn't spammed; `all` opts into everything; `off` is a full kill-switch. Unknown values fail toward `important`.
- **Reminder identity:** RSVPs already pin the concrete occurrence in `event_attendees.instance_start`, so the scheduler needs **no recurrence expansion** — the set of occurrences anyone cares about is the set of distinct `instance_start` values people RSVP'd to. A new nullable `notifications.event_instance_start` is the third leg of the reminder's `(user, event, occurrence)` identity; a partial unique index dedupes the hourly re-runs.
- **Address source:** email lives only in `auth.users`, unreachable via PostgREST; the worker reads it through the **GoTrue admin API** with its service-role key (no public mirror added).
- **Delivery semantics:** at-least-once. `notifications.email_sent_at` is the terminal-state stamp (sent OR deliberately skipped); the only duplicate window is send-ok/mark-failed, the standard email trade-off. When `SMTP_HOST` is unset the handler finishes the job done but **leaves the row unstamped**, so a later email-enabled deploy still sends it.

**The trade-off / when not to re-litigate.** Email isn't push — no lock-screen banner, deliverability depends on the provider, and there's no in-app token. That's accepted: it's the credential-free 80% while native push waits on Firebase/APNs. Web push is a separate not-blocked slice (VAPID is self-generated; the client subscribe path already ships — `parity.md`) and is the natural next consumer. **Don't** re-route notification delivery through an Edge Function, **don't** add a per-kind reminder that bypasses the `email_notifications` preference, and **don't** treat the "blocked on Firebase/APNs" note as covering email or web push — it covers the native leg only.

---

## 118. Async-job failures are made observable two ways — exhausted retries terminate in `failed`, and a pg_cron alert watches the `failed` surface

**Decided (2026-06-03):** with the Strava webhook moved off the synchronous `strava-webhook` Edge Function onto the Go worker's async `kind='strava_event'` pipeline, ingest failures no longer surface as a non-200 that makes Strava retry — the worker acks 200, enqueues, and drains later. To keep failures from going silent, migration `20261201_001_jobs_failed_alert.sql` closes two gaps: (1) `defer_job` now lands an exhausted-retry job (`attempts >= max_attempts`) in `status='failed'` instead of re-queuing it, and (2) a `jobs-failed-alert` pg_cron entry runs `jobs_failed_summary()` every 10 min, emitting `{failed_count, by_kind, sample}` into `cron.job_run_details` for a future Sentry/Slack scraper to route on `failed_count > 0`.

**Why both.** There were two distinct silent-failure classes. Permanent failures (`finish_job(failed)`) already landed in `status='failed'` but nothing watched the table — the alert fixes that. Exhausted transients were worse: `defer_job` re-queued them, but `claim_next_job` only claims `attempts < max_attempts`, so once the budget was spent the row sat in `queued` **forever**, un-claimable, never reaching `failed`, invisible to both `find_stuck_jobs` (running-only) and any queue-lag count (can't tell an exhausted job from a fresh one). Flipping exhausted retries to `failed` routes them into the same surface the alert watches.

**Why fail inside `defer_job` and not via a reaper.** Unlike `find_stuck_jobs` (§ the 20260731 stuck-alert), which deliberately does *not* auto-fail rows because an external observer could race a worker about to call `finish_job` on the same row, flipping to `failed` inside `defer_job` is race-free: it's the worker that holds the job (claimed `for update skip locked`, `locked_by` = itself) choosing a terminal state for the attempt it just ran, on the exact code path that would otherwise re-queue. No second actor, no race.

**Trade-off / when not to re-litigate.** `find_failed_jobs` is windowed (default 15 min) because `failed` rows are never purged — an unbounded query would alert forever on old failures; the window is the "what failed since I last looked" lens, sized to overlap the 10-min cron cadence. The cron only *records* the count in `cron.job_run_details`; wiring an actual pager (Sentry/Slack) is still operator work, same as the queue-lag alert. **Don't** retire the synchronous `strava-webhook` Edge Function rollback path until that scraper is live, **don't** add a reaper that auto-fails `running` rows (that's the race `find_stuck_jobs` avoids), and **don't** widen the failure window without remembering it counts un-purged history.

---

## 119. Lifecycle email (welcome, later digest) is a separate `lifecycle_email` job kind keyed by a template name, not the notification channel

**Decided (2026-06-03):** transactional/relationship mail that has no `notifications` row — starting with a "thanks for signing up" welcome — rides a new `lifecycle_email` job kind (migration `20261202_001`) carrying `{user_id, template}`. The Go worker's `handler_lifecycle_email.go` renders the named template (`renderLifecycleEmail` in `mailer.go`) and sends through the same SMTP path as `notification_email`. The welcome is enqueued by an AFTER-INSERT trigger on `user_profiles`, which is created exactly once per user by `confirm_age_and_terms()` (`20260929_001`) — the INSERT branch fires on real signup; the returning-user `on conflict do update` branch doesn't fire an INSERT trigger.

**Why a separate kind, not `notification_email`.** The notification channel is coupled to a `notifications` row (it renders from one, stamps `email_sent_at` on it, and gates on the `email_notifications` preference). A welcome has none of that: no inbox row, and it must send regardless of preference (you can't opt out of the email confirming you signed up). Forcing it through the notification path would have meant a fake notification row + a preference exemption — more contortion than a sibling kind. The template-name payload also generalises: the weekly digest and re-engagement mail will be the same kind with their own templates (and, unlike welcome, their own opt-in preferences + one-click unsubscribe, since those are bulk/engagement, not transactional).

**Send-once.** `lifecycle_email_log (user_id, template)` is checked before send and written after, so a job retry — or a crash between send and `finish_job` — can't re-send. Delivery is at-least-once (a duplicate only escapes the narrow send-ok/record-fail window), matching the `notification_email` `email_sent_at` discipline. The log is RLS deny-all (service-role/worker only). When no SMTP sender is configured the handler finishes the job done without recording, so a later email-enabled deploy still sends; an unknown template is a permanent skip, not a retry loop.

**Trade-off / when not to re-litigate.** Welcome carries no `List-Unsubscribe` header — it's a one-off relationship message, not a subscription; the footer still links to `/settings/preferences`. The trigger fires on the `user_profiles` insert (signup), not on `auth.users`, deliberately keeping triggers out of the auth schema. **Don't** route welcome/digest through `notification_email`, **don't** gate the transactional welcome on `email_notifications`, and **don't** ship the weekly digest on this kind without first adding its opt-in preference + RFC 8058 one-click unsubscribe + bounce suppression (the bulk-sender requirements that a one-off welcome doesn't trip).

---

## 120. Emails are localized server-side from a DB-synced `locale` pref + a worker-side catalogue — the one place locale leaves the device

**Decided (2026-06-03):** the worker renders emails in the recipient's language. Because emails are sent server-side, the worker needs the user's locale — but neither client exposes it server-side: web detects locale client-side (§108) and mobile keeps `Preferences.locale` per-device and explicitly **not** DB-synced (§113). So the clients now also write the active UI locale tag into `user_settings.prefs.locale` (a universal, DB-synced bag key — `docs/backend/settings.md`), and the worker reads it (`localeFromPrefs`) and renders from a per-locale catalogue (`apps/job_worker/internal/email_i18n.go`) covering the same six locales as the app (en/de/fr/es/ja/pt-BR), with English fallback per key.

**Why this doesn't violate §113.** §113's rule is that the *device UI locale* is per-device and not synced — so signing into the app on a friend's phone doesn't flip their app language. That still holds: `prefs.locale` is a **separate** value used only for server-sent comms, written as a side effect of the language picker, never read back to drive the app's UI. The device picker stays the source of truth for what each device displays; `prefs.locale` is "what language to email this person in," which is genuinely account-level, not device-level. Two distinct concerns that happened to look like one.

**The shape.** Email copy moved out of Go string literals into `emailCatalogue[locale][key]` (key = notification kind / `welcome` / `default`) + `emailSharedByLocale` (footer + manage-preferences strings). `normalizeEmailLocale` collapses region tags (`de-DE`→`de`, `pt`/`pt-PT`→`pt-BR`) and unknown locales to English. The HTML carries `<html lang>`. `email_i18n_test.go` pins catalogue parity (every locale has every key, no empty strings) — the worker's mirror of the web `messages_parity` + mobile `l10n_parity` tests. The deep links + brand chrome are locale-independent; only copy changes.

**Trade-off / when not to re-litigate.** The email catalogue is a **third** translation surface (after web i18n and the mobile ARBs) that must be kept in lockstep by hand — there's no shared source because the three runtimes (TS, Dart, Go) can't import one. That's accepted: emails are few and short, and the parity test catches a *missing* key (not a *stale* translation). A user who never picks a language and whose client hasn't written `prefs.locale` gets English — acceptable default. **Don't** read `prefs.locale` to drive in-app UI (that's §113's per-device locale), **don't** add an email locale without adding it to all six catalogue entries (parity test fails closed), and **don't** try to unify the three translation catalogues — the runtime boundary makes it not worth it.

---

## 121. Transactional subscription emails (Pro receipt, payment-failed dunning) fire from a user_profiles AFTER-UPDATE trigger; recurring ones skip the send-once log

**Decided (2026-06-03):** the Pro-purchase receipt (`pro_welcome`) and the payment-failed dunning (`payment_failed`) reuse the `lifecycle_email` job kind (§119), enqueued by an AFTER-UPDATE trigger on `user_profiles` (migration `20261203_001`) keyed off the columns the RevenueCat webhook writes: `subscription_tier` entering a paid tier (free → pro/lifetime) → `pro_welcome`; `billing_issue_at` going null → non-null → `payment_failed`. The trigger has a `WHEN` guard so ordinary profile edits don't run the body, and is a distinct AFTER trigger from the BEFORE `lock_subscription_columns` guard (§ the 20260624 lock) — different phase, no conflict. Since service-role (the webhook) is the only caller that can change those columns, it fires exactly on real billing transitions.

**Why a trigger, not the webhook enqueuing directly.** The `revenuecat-webhook` Edge Function already does one thing — map events to column writes. Hanging email-enqueue off the *column transition* (rather than the event) means any future writer of `subscription_tier`/`billing_issue_at` (a manual grant, an admin tool, a different IAP provider) gets the right email for free, and the email logic lives next to the welcome trigger it mirrors rather than smeared into the webhook.

**The once-vs-recurring split.** `welcome` is once-per-account, so the handler dedups it via `lifecycle_email_log`. `pro_welcome`/`payment_failed` are **recurring** — a churn-and-re-subscribe is a legitimate second receipt; a second billing failure after the first cleared is a legitimate second dunning. Routing them through the permanent (user, template) log would wrongly suppress the second send. So `oncePerUserTemplates` gates the log to `welcome` only; recurring templates rely on the trigger's transition guard (`OLD` vs `NEW` distinct) as the dedupe, and the handler neither checks nor writes the log for them. Their copy uses a generic `footerTransactional` ("service message about your account") rather than the welcome footer, and the dunning CTA targets `/settings/upgrade`.

**Trade-off / scope.** Renewal *success* receipts are deliberately not sent (RENEWAL keeps `subscription_tier=pro`, so there's no transition — only the first purchase emails). Three sibling transactional emails were considered and **not** built, for concrete reasons: **data-export-ready** adds no value (the export endpoint is synchronous and returns a 10-minute signed URL inline — an async email would arrive stale); **password-changed / new-device** need infrastructure that doesn't exist (no GoTrue auth hooks configured, no sign-in/device tracking); **account-deletion receipt** can't use this mechanism (the worker can't look up the email post-deletion, `delete-account` drains the user's pending jobs, and the send-once log cascades away with the user) — it needs the email passed inline at deletion time and a non-cascading record, tracked in `followups.md`. **Don't** add the once-per-user log to a recurring transactional template, and **don't** move the enqueue into the webhook.

**Amendment (2026-06-20) — account-deletion receipt shipped (migration `20270217_001`, `account_deleted` template).** Of the two shapes the original entry floated — inline-send from the EF vs enqueue-with-carried-address + non-cascading record — we built the **enqueue** shape. Inline-send would have meant a *second* email transport (an SMTP client in Deno) plus a duplicate of the six-locale i18n catalogue inside the EF; the whole email layer is deliberately one transport in the Go worker (`mailer.go` + `email_i18n.go`), so the enqueue shape keeps that single source of truth. The mechanics: (1) the `delete-account` EF captures `user.email` + the `user_settings.prefs.locale` BEFORE the cascade and, AFTER `admin.deleteUser` succeeds, inserts a `lifecycle_email` job carrying `{template:'account_deleted', email, locale}` with **no `user_id`**; (2) because the EF's mandatory job-drain filters on `payload->>user_id`, a payload without that key is *naturally* exempt — no drain special-casing, and it's enqueued after the drain anyway; (3) the worker's `handleLifecycleEmail` routes inline-address templates to `handleAccountDeletionReceipt`, which dedups on a SHA-256 hash of the address via the non-cascading `account_deletion_receipts` table (no FK, 30-day cron retention) since `lifecycle_email_log` would cascade away with the user; (4) the receipt copy carries no `/settings/preferences` link (the account is gone). The accepted residue is exactly the one the original entry named: the deleted address lingers in `jobs.payload` until the job drains (minutes), then only as a hash in `account_deletion_receipts`. `account_deleted` rides the existing `lifecycle_email` kind, so no `jobs.kind` CHECK change. GDPR Art 17 confirmation mail — no per-feature compliance gate; goes live with the shared `SMTP_HOST` worker gate.

---

## 122. Gym + food get `LocalGymStore` / `LocalFoodStore` mirroring `LocalGearStore`; gym stores its sets inline, one file per workout

**Decided (2026-06-03):** the Phase 4 multi-modal modalities (gym, nutrition) land their offline-first caches the same way gear did (§73). `LocalGymStore` (`apps/mobile_*/lib/local_gym_store.dart`) and `LocalFoodStore` (`apps/mobile_*/lib/local_food_store.dart`) are disk-backed `ChangeNotifier`s — one JSON file per row under `<appDocs>/gym/` and `<appDocs>/food/`, a per-row `{Gym,Food}SyncState` (`synced` / `pendingCreate` / `pendingUpdate` / `pendingDelete`), client-minted v4 UUIDs that become the server id on the eventual INSERT (`gym_workouts.id` / `food_log.id` default to `gen_random_uuid()` but accept a client value), and a `syncWithServer(api)` that drains create → update → delete with per-row failure isolation. `replaceFromServer` preserves pending rows and overwrites only `synced` ones, exactly as gear does.

**Typed domain views (2026-06-04).** `GymWorkout` (+ `GymSet`) and `FoodEntry` live in `core_models` (`src/gym.dart`, `src/food.dart`) with `.fromRow(...)` factories keyed on the generated `GymWorkoutRow`/`GymSetRow`/`FoodLogRow` column constants. `StoredGymWorkout.workout` and `StoredFood.entry` expose them so screens read typed fields (`w.workout.title`) instead of reaching into the raw `row` map by string key — the gym screens are migrated; the nutrition screen consumes `FoodEntry` when it lands. The store still holds the row map internally (it's what drains to the api), and the inline-set rendering helpers keep iterating the raw set maps — the DTOs are the read-facing view, not a rewrite of the persistence shape.

**Gym stores its sets inline.** A `gym_workouts` row owns N `gym_sets`; the composer always edits the whole set list, so `StoredGymWorkout` carries `sets` inline in the same file rather than a separate `gym_sets/` store. The drain maps the inline sets back to `GymSetInput` and `createGymWorkout`/`updateGymWorkout` replace the set list wholesale server-side (the api already does delete-then-reinsert). `set_index` is positional (the list index) — never persisted as a field — so a reorder is just a list reorder. This avoids a parent/child two-store reconciliation entirely.

**Shipped ahead of the screens.** Like the api_client gym/food methods (commit `9d8f6b58`), the stores ship before the gym/nutrition UI and are therefore not yet wired into `main.dart` or `sync_service` — there's no consumer to drain them and wiring an unused store would be speculative. The wiring lands with the screens (the multi_modal.md file plan's Gym/Nutrition rows). Pinning tests: `apps/mobile_android/test/local_{gym,food}_store_test.dart` (22 + 21 tests) cover lifecycle, drain order, reload-after-restart, gym's inline-sets round-trip, newer-wins, and the `_v` schema stamp.

**Same trade-offs as §73 carry over:** last-write-wins on a cross-device offline window, no `dropUser` hook (best-effort single-user device until the `created_by_user_id` ownership tag from §67 is added). Don't re-litigate by adding a "sync now" button or a temp-id remap layer — the client-minted UUID is the load-bearing choice.

**Conflict-resolution alignment (2026-06-04).** The three per-row stores were brought into lockstep on the modification clock: gym/food's `replaceFromServer` now applies **newer-wins** for `synced` rows (a server fetch that's *older* than the local copy — read-replica lag — no longer clobbers it; the local synced row's clock is built from the server's `last_modified_at` so successive refreshes compare like-for-like), mirroring `LocalRunStore.saveFromRemote`. Gear has no `last_modified_at` column so it keeps the server-overwrites-synced behaviour, but two clock bugs were fixed: `createLocal` now stamps `lastModifiedAt` from the same `now` as `created_at`, and `_markSynced` preserves the existing clock instead of bumping it to "now" (a bumped clock would make a freshly-drained row beat the very server copy it was pushed from). These are the L-FILE H4 / M2 / L3 findings from the data-architecture audit.

**Routes (M3).** `LocalRouteStore` has no per-row modification clock (the `Route` DTO carries no `last_modified_at`), so its conflict signal is the `_syncedIds` sidecar instead. `saveBatch(..., markSynced: true)` — the server-ingest path — now skips any route that is present locally **and** unsynced, so a server pull can't clobber a pending local edit and silently drop its push (the route-store form of newer-wins). A clean route (synced, or not present locally) still takes the server copy. The local-save path (`markSynced: false`) is unaffected.

**Deferred (tracked).** The three per-row stores (gear/gym/food) still each carry their own copy of the sync-state machine; extracting a generic `OfflineSyncStore<S,R>` base over them is a pure no-behaviour-change de-duplication left as a focused follow-up — **all the divergence findings it would close are already fixed above**. Run/route stay out of that base by design (sidecar model, not a per-row clock). Tracked in [`docs/product/followups.md` § Mobile](../product/followups.md).

---

## 123. Mobile local stores persist through a crash-atomic write helper (`writeJsonAtomic`); `_rewriteAll` writes before it prunes

**Decided (2026-06-03):** every record and sidecar write in the five mobile file stores (`local_run_store`, `local_route_store`, `local_gear_store`, `local_gym_store`, `local_food_store`) goes through `writeStringAtomic` / `writeJsonAtomic` in `packages/core_models/lib/src/atomic_io.dart` — a `.tmp` sibling write + `flush` + atomic POSIX `rename`. A bare `File.writeAsString` truncates the destination to zero bytes before streaming the new content, so a process death mid-write (OOM-kill, power loss, force-quit) left a zero-byte or partial file that `jsonDecode` rejected on the next cold-start — the record silently vanished. `rename` is atomic on Android ext4/f2fs and iOS APFS: a reader sees either the old file or the fully written new one. The helper uses a per-write unique temp suffix so two concurrent writes to one target don't race on the rename (last rename wins, matching the prior last-write-wins semantics).

**`_rewriteAll` (gym/food/gear) writes new files before deleting orphans.** The old `replaceFromServer` path deleted every `.json` in the directory *then* rewrote — a crash in the gap emptied the store and lost any unsynced `pendingCreate` rows. It now writes every live row first (each atomic) and only then prunes ids that no longer exist, with a per-file try/catch on the prune. No empty-directory window.

**Enforced, not just documented.** `architecture_guards_test.dart` fails CI on any bare `writeAsString` in the five stores and on a `_rewriteAll` that deletes before it writes.

**Scope / not in scope.** The in-progress recording file (`in_progress.json`) is *not* covered here — it uses its own crash-safe append-only NDJSON path (`_appendInProgressLine`, see [run_recording.md](../features/run_recording.md)). At-rest encryption of the plaintext GPS/HR JSON is a separate open item (audit L-FILE H3, Phase 3c). The synced-ids sidecar's unbounded growth (audit L-FILE H5 pruning half) is also still open (Phase 3b); only its atomicity is closed here. This entry closes the data-loss-grade Criticals L-FILE C1/C2 from the data-architecture audit (Phase 0a/0b).

---

## 124. Dart reads/writes of `runs.metadata` keys + Storage bucket names route through `MetadataKeys` / `StorageBuckets` constants in `core_models`

**Decided (2026-06-03):** the canonical key names for the `runs.metadata` jsonb bag and the Supabase Storage bucket names live as `static const` strings in `packages/core_models/lib/src/metadata_keys.dart` (`MetadataKeys.activityType == 'activity_type'`, `StorageBuckets.runs == 'runs'`, …). Dart writers/readers reference the constant instead of a bare string literal, so a typo or a casing drift (`activity_type` vs `activityType`) is a compile error rather than a silently-missing field at runtime. The same applies to the two Storage buckets the typed client touches (`runs`, `run-photos`) — previously raw `storage.from('runs')` literals scattered across `api_client.dart`. Postgres *table* names already flow through the generated `RunRow.table` etc., so those weren't in scope.

**The registry guard resolves the constants.** `metadata_registry_test.dart` historically scanned for `metadata['literal']` patterns; centralising behind `MetadataKeys.*` would have blinded it. The scanner now parses `metadata_keys.dart` into an `identifier → wire value` map and resolves every `MetadataKeys.<ident>` reference back to the wire key, so the "every key referenced in Dart is registered in `metadata.md`" guarantee survives the migration. Both literal and constant forms are detected, so a mixed codebase (the conversion is incremental — only the high-traffic writer files were re-pointed first) stays covered.

**Scope.** This is a Dart-side ergonomic + drift-defence layer; it does not change the wire format or the registry's role as the cross-platform (web / watch_wear / watch_ios / Edge Function) coordination point. The registry in [metadata.md](../backend/metadata.md) is still the source of truth; `MetadataKeys` is the Dart mirror of it.

---

## 125. Mobile file-store records carry an on-disk schema version (`_v`) with a read-side forward-migration hook

**Decided (2026-06-04):** every record (and sidecar) the five mobile file stores persist is stamped with `_v = kLocalStoreSchemaVersion` (currently 1), defined in `packages/core_models/lib/src/local_store_schema.dart`. On read, each store resolves the version via `localStoreRecordVersion(json)` and routes through a per-store forward-migration branch before parsing.

**Why.** Before this, a record's JSON shape was implicit. When a shape changed (e.g. the gym lap-shape migration, or the pending-deletes `{ids}`→`{deletes}` change) the only defence was ad-hoc "try the new shape, fall back to the old" branches, and a stricter future parser could silently drop an unrecognised legacy file — data loss. An explicit version turns "what shape is this file" into a single read and gives every future incompatible change a documented home (bump the constant, add a branch keyed on the version read back).

**Today the migration is a pass-through.** v1 is forward-compatible with the legacy unstamped shape (v0 = no `_v`): per-row stores gained only the extra `_v` key; the run envelope (`{run, synced}`) and the route file (a flat `Route.toJson()` — `_v` is a flat key that `Route.fromJson` ignores) are unchanged otherwise. So a v0 file still loads. The read hook also logs (doesn't fail) when it sees a `_v` *newer* than it understands — a cross-version device where the other phone runs a newer build — and reads the known fields. The in-progress NDJSON recording file is out of scope (it has its own crash-safe append format, §123).

**Trade-off.** A few extra bytes per record and a stamp on every write. Cheap insurance against the silent-drop failure mode. Don't strip `_v` to "clean up" a record — the absence of a stamp is itself meaningful (legacy).

## 126. Activity-model canonicalization: drop vestigial `runs.kind`, promote `activity_type` + `is_dnf` to columns, keep telemetry in jsonb; new narrow unions use text+CHECK

**Decided (2026-06-04, remediation Rounds 3–4):** migrations `20261206_001`–`20261208_001` (schema + server) and `20261210_001`–`20261215_001` (constraints/retention), with the web + mobile client read/write sites switched in Round 4.

- **Dropped `runs.kind`** (F1/D1). It only ever held `'run'`; the `activities` view injects the `'run'`/`'lift'`/`'meal'` literal per UNION branch, so the discriminator column was dead weight.
- **Promoted exactly two `runs.metadata` keys to real columns** (F3/D4): `activity_type text not null default 'run'` (+ CHECK) and `is_dnf boolean not null default false`. The telemetry trio (`avg_bpm` / `steps` / `elevation_m`) stays in the jsonb bag. The bar for promotion is "present on most rows AND filtered/aggregated/constrained in SQL" — `activity_type` (CHECK + `activities`/`public_runs` views + gear auto-tag + VDOT) and `is_dnf` (the PR-exclusion filter) clear it; the telemetry trio is displayed but never filtered, so promoting it would widen every row for no query benefit.
- **Renamed `food_log.logged_at` → `started_at`** (F8) so all three modality tables share the timestamp name the `activities` view depends on — no per-table synonym.
- **New narrow unions get `text` + a `CHECK (… in (…))`, not a Postgres enum** (F16/D2). `ActivityType` joins `RunSource` / `RouteSurface` / … as a TS-union ↔ CHECK pair guarded by `check_constraint_unions.mjs`. The three legacy real enums (`workout_kind`, `plan_phase`, `goal_event`) stay as-is. text+CHECK keeps "add a value" a one-line CHECK re-state (an enum needs `alter type`) and keeps the value list in lockstep across TS / Dart / SQL through one guard.

**Trade-off.** A phased Tier-2 rollout: the promoted columns carry defaults, so an un-migrated client that still writes only the jsonb key inserts cleanly (lands as the default) until its sites switch. Web + mobile (byte-identical twin) switched in Round 4; the watch→phone WCSession bridge still ships `activity_type` in its payload, so a non-run *watch* activity currently lands as `'run'` on the column with the real value in the bag until the bridge is switched — the documented interim state, harmless pre-prod. See the column-vs-jsonb checklist in [`conventions.md`](conventions.md) before pushing any new "attribute pretending to be metadata" into the bag.

**Don't re-litigate unless** a telemetry key starts being filtered/aggregated in SQL (then promote it the same way), or a fourth modality needs a real discriminator back (then it's a new purpose-built column, not the resurrected `kind`).

---

## 127. At-rest posture: OS-level encryption covers device loss; cloud-backup extraction is closed by opting the apps out of backup; app-level track encryption stays deferred

**Decided (2026-06-04, remediation Phase 3c-b/c):** the three tiers of the resolved at-rest decision (master plan 3c) are now landed except the deliberately-deferred fourth:

- **(a) Wear refresh token → `EncryptedSharedPreferences`** — done earlier (R2). The watch's bearer tokens are the one local secret worth app-level encryption because a standalone watch holds a long-lived refresh token with no phone in the loop. `SessionStore.kt` uses a Keystore-backed `MasterKey` (AES256-GCM).
- **(b) Exclude the GPS/HR cache from cloud backup, mobile + watch** — this round. **Android (mobile + Wear): `android:allowBackup="false"`** on both `<application>` tags. It's a blanket opt-out rather than a surgical `dataExtractionRules` exclusion *on purpose*: on Flutter the Supabase session (access + refresh JWT) persists in `SharedPreferences` (default `supabase_flutter` storage), and the GPS/HR run cache persists under `app_flutter` — so the two backup domains that hold anything are both sensitive, and everything in them is server-re-derivable. There is nothing left that benefits from backup, so excluding the whole app is simpler and strictly safer than excluding one subtree and leaving tokens in `sharedpref`. (A restored `EncryptedSharedPreferences` blob is also undecryptable on a new device — its Keystore master key never leaves the original device — so backing the Wear token up would be useless anyway.) **iOS: `isExcludedFromBackup` on the Documents directory** (`AppDelegate.swift`, best-effort at every launch). path_provider's `getApplicationDocumentsDirectory()` → `NSDocumentDirectory`, where every local run/route/gym/food JSON file lives; excluding the directory node excludes its whole subtree from iCloud / iTunes backups. **watchOS** writes its crash checkpoint + track NDJSON under `Caches` (`CheckpointStore.swift`), which iOS already excludes from backup by definition — no code needed.
- **(c) Document that OS-level FDE covers device-at-rest** — this entry. On Android, **file-based encryption (FBE)** is mandatory on devices shipping with Android 10+ and ties `/data/data/<pkg>` decryption to the user credential; on iOS/watchOS, **Data Protection** encrypts app files at rest (default class `NSFileProtectionCompleteUntilFirstUserAuthentication`) once the device has a passcode. The lost/stolen-device threat is therefore handled by the platform; we add nothing for it. The remaining exposure was cloud-backup extraction, which (b) closes.
- **(d) Full app-level encryption of the track files stays deferred** — the GPS/HR JSON caches are large and re-derivable, and the real threats (device loss, cloud-backup) are covered by (a)–(c). App-level encryption only buys protection under a narrower model (active MDM adversary, shared/jailbroken device) at the cost of encrypting every multi-MB track on every read/write. Revisit only if such a threat model becomes real.

**Guards.** `architecture_guards_test.dart` pins `allowBackup="false"` in the phone manifest and `isExcludedFromBackup` in `AppDelegate.swift` (the iOS check auto-skips on the Android twin, same idiom as the Info.plist guards). Wear's `BackupExclusionManifestTest.kt` pins the watch manifest flag (runs in CI via `testDebugUnitTest`).

**Trade-off.** `allowBackup="false"` also means per-device-only local state (a paired BLE strap id, device-scoped prefs) does **not** restore across a phone migration. Acceptable: settings re-sync from `user_settings` on next sign-in, runs re-sync from the server, and re-pairing a strap is one tap — none of it is worth the privacy cost of shipping GPS traces and bearer tokens into a cloud backup.

**Don't re-litigate unless** the threat model gains an MDM / shared-device adversary (then (d) — app-level track encryption — comes back on the table), or local storage starts holding something genuinely non-re-derivable that a user would expect to survive a device swap (then revisit the blanket opt-out in favour of a surgical `dataExtractionRules` / per-file backup include).

---

## 128. `race_pings` and `live_run_pings` stay two tables — column overlap is not table identity (F5 closed: won't-consolidate)

**Decided (2026-06-04, remediation F5):** the two live-position-stream tables are **kept separate**. R4 closed the retention-parity gap (migration `20261213_001` gave `race_pings` the cleanup cron `live_run_pings` had since `20260509_001`); the remaining "they look near-identical, consolidate them" item is resolved as **won't-consolidate**, documented here rather than migrated.

**Why not consolidate.** The two tables share ~6 column *definitions* (`lat`/`lng`/`elapsed_s`/`distance_m`/`bpm`/`user_id`/`at`/`id`), but a table's identity is its **key + constraints + access rules**, and on every one of those they diverge:

- **Key.** `live_run_pings` is keyed by `run_id` (single FK → `runs`); `race_pings` by `(event_id, instance_start)` (composite FK → `race_sessions`). A merged table needs both key sets nullable plus a `CHECK` that exactly one is populated — the polymorphic-association shape, which throws away the DB-enforced guarantee that a `run_id` can't appear in an event-keyed row. (Contrast F15/§126's `notifications.(activity_kind, activity_id)`: that polymorphism is correct because notifications genuinely *reference many* heterogeneous activities — these pings are not one stream referencing many things, they're two streams with different owners.)
- **RLS.** `live_run_pings` visibility flows through `is_run_visible_to(run_id)` (public-or-owner); `race_pings` through the `race_sessions → events → clubs` chain (club membership / public-club). Consolidating replaces two narrow policies with **one policy that branches on a discriminator** — strictly harder to audit, and the exact surface where `20260715_001` already had to plug a leak (unauthenticated `instance_start` guessing exposing private-club race coordinates). With the project's RLS-correctness investment (audits + pgtap), two separate policies are the safer asset.
- **Retention, insert, indexes.** 4h vs 48h TTL (a solo live-share is ephemeral; a scheduled race replay isn't); owner-only insert vs own-ping-while-race-is-running; `(run_id, at asc)` for chronological playback vs `(event_id, instance_start, at desc)` + a per-user index for the leaderboard. A merged table either branches all of these on `kind` or compromises each.
- `live_run_pings` carries `ele`; `race_pings` doesn't. Minor, but it's one more "nullable for half the rows" column a merge would add.

**Trade-off.** We keep two near-identical `CREATE TABLE`s, two `_drop_in_zone` BEFORE-INSERT triggers, and two retention functions. The duplication is shallow: both triggers already delegate to the shared `privacy_in_any_zone(...)` helper, so only the ~10-line trigger wrapper and the column list repeat — not the load-bearing logic. That shallow repetition is a cheaper price than a polymorphic table with branching RLS. The realtime publication lists both tables; clients subscribe by table, not by a `kind` filter, which keeps each subscription's payload narrow.

**On "consolidate for the long term".** Evaluated purely as a design question (ignoring migration cost): a single physical `pings` table is *not* the better long-term form, because it would **de-normalize**. The two streams have structurally different keys — scalar `run_id` vs composite `(event_id, instance_start)` — which can't be one clean FK; a merged table needs three nullable columns + a `CHECK`-exactly-one, i.e. it *replaces two NOT-NULL FK constraints with nullable columns and a CHECK* (weaker integrity), and centralizes two declarative RLS policies into one branching one (harder to audit). The actual normalized long-term form, *if* this ever grew to 3+ live-stream types (group runs, virtual races, …), is **class-table inheritance** — a shared `live_pings` base holding the common telemetry (`lat`/`lng`/`ele`/`elapsed_s`/`distance_m`/`bpm`/`at`/`user_id`) plus thin per-context stream tables owning the divergent FK + RLS. That *adds* tables, and only pays off at N≥3. At today's N=2 it's over-engineering, and a nullable-FK polymorphic single table is never the right shape (it's exactly what CTI exists to avoid). So: stay at two now.

**Don't re-litigate unless** a third live-position-stream type appears (then introduce the shared `live_pings` base + thin per-context stream tables — class-table inheritance — *not* a nullable-FK union of the two existing tables), or the privacy-zone trigger logic starts to drift between the two copies (then extract the wrapper into one shared trigger function both tables attach — still two tables, one trigger body).

---

## 129. Mobile create/edit-entity forms all present as a full-screen dialog via one shared `showFullScreenForm` wrapper

**Decided (2026-06-04):** every "add / edit X" surface on the Flutter clients presents identically — a `MaterialPageRoute(fullscreenDialog: true)` hosting the form in a `Scaffold` + `AppBar(title)` + `SafeArea` — built through the single helper `widgets/full_screen_form.dart` (`showFullScreenForm<T>` + `FullScreenFormBody` + `FormSectionLabel`). Migrated: gear, club, event, goal, gym, and planned-workout edit; the manual-run screen (`AddRunScreen`) is pushed with `fullscreenDialog: true` for the same presentation but keeps its own `Scaffold` (it has a `Form` + validation + a nested route picker that don't fit the simple body chrome).

**Why.** The forms had drifted into three different presentations — `showModalBottomSheet` (gear / event / workout-edit), a bare back-arrow `MaterialPageRoute` page (club), and a `fullscreenDialog` (goal / gym) — so the same conceptual action looked and dismissed differently depending on where you opened it. The bottom-sheet variant was also the buggiest: it fought the soft keyboard (`viewInsets` + `FractionallySizedBox` both reflow on open — the "slow and glitchy" feel) and repeatedly put the Cancel/Save buttons under the Samsung gesture bar (it only padded for `viewInsets`, not `viewPadding`). The full-screen dialog is what Material recommends for multi-field forms with text + pickers, the `Scaffold` handles the keyboard via `resizeToAvoidBottomInset`, and `FullScreenFormBody` encodes the keyboard-else-nav-bar inset once instead of each form re-deriving (and mis-deriving) it.

**Trade-off / contract.** New mobile create/edit forms must route through `showFullScreenForm` rather than hand-rolling a sheet/page; the heading goes in the AppBar (don't duplicate it inline in the body), and the body is `FullScreenFormBody(children: [...])`. The helper lives under `lib/widgets/` (twin-mirrored), not `ui_kit`, to sit beside the forms that use it. Don't force a genuinely complex screen (its own `Scaffold`, multi-step nav) through `FullScreenFormBody` — push it with `fullscreenDialog: true` and keep its `Scaffold`, as `AddRunScreen` does.

---

## 130. F17 column-naming uniformity: `created_by` → `author_id`, the three non-`is_` booleans → `is_*`, output columns included

**Decided (2026-06-04, remediation plan 2d / F17):** migration `20261217_001` renamed the five owner-column / boolean-flag outliers onto the house convention now written in [`conventions.md` § SQL](conventions.md):

- `events.created_by` and `segments.created_by` → `author_id` (the authored-content/user-object tables — `club_posts`, `run_comments`, `reports`, `segments`, `events` — now all use `author_id`; `created_by` is retired).
- `device_tokens.notifications_enabled` → `is_notifications_enabled`, `routes.featured` → `is_featured`, `race_sessions.auto_approve` → `is_auto_approve` (booleans read as `is_<predicate>`).

**Why the full version, not "document the rule" or a half-rename.** The original F17 finding mis-stated the problem as "one lone outlier each"; in fact `created_by` was on **two** tables and **three** booleans skipped `is_`, so a single-column rename would have made consistency *worse* (`events.author_id` vs `segments.created_by`). The choice was a documented contextual rule vs. a real uniformity migration; the latter was taken so the schema is genuinely uniform rather than carrying a written exception.

**Why output columns were renamed too (the load-bearing call).** `routes.featured` and `race_sessions.auto_approve` surface through views / RPCs (`public_routes`, `discoverable_routes_in_bbox`, `race_sessions_redacted`). Renaming only the base column would relocate the drift to the column-vs-output boundary (`routes.is_featured` but `public_routes.featured`) — the same inconsistency F17 set out to remove. So the outputs were renamed to match. The mechanism matters: **`ALTER VIEW … RENAME COLUMN`** renames a view's output label *in place*, preserving every grant and the in-body redaction logic (no DROP-cascade, no grant reconstruction — which on the security-redaction views would have been the risky part). Only `discoverable_routes_in_bbox`, whose flag is a `RETURNS TABLE` output column, needed drop + recreate + re-grant. RLS policies, CHECK constraints, column GRANTs and indexes follow a column rename by attnum automatically; function *bodies* (text) were recreated where they named the old columns. The whole `race_sessions` redaction + `public_routes` lockdown posture is pinned by the existing pgtap suite (859 tests green post-rename).

**Trade-off.** A one-time wide sweep — base columns, two view outputs, one RPC return type, regenerated TS + Dart/Kotlin row types, ~13 web + a handful of Dart/api_client + Go-export + Edge-Function + ~30 pgtap + seed sites. Client-side **domain** field names (`Route.featured` in Dart, the GeoJSON `featured` property in `RouteHeatmap`) were intentionally **left** — F17 is about database columns, and renaming a domain field would churn the local-store JSON format for no schema benefit. The DB-facing reads that feed them were renamed; the local names stay.

**Don't re-litigate unless** a future column genuinely can't take an `is_`/`author_id` form (then document the exception here rather than forcing it), or a view output column needs renaming where `ALTER VIEW RENAME COLUMN` can't reach it — then the DROP-cascade + grant-reconstruction cost is real and worth weighing against leaving the output name alone.

---

## 131. Safety-contact finish alerts are a separate opt-in feature on a `safety_email` job kind — not a relaxation of the `run_completed` is_public gate

**Decided (2026-06-04):** the family-club persona wanted a partner to be told a runner finished *even on a private run* (a safety use case). The existing `run_completed` notification (`20261101_001`) only fans **public** runs out to **followers**; removing its `is_public` gate would broadcast every private run to all followers — a privacy regression. So this is a distinct feature: a `safety_contacts` table (migration `20261218_001`) + a `safety_email` worker job kind that alerts ONE designated, double-opt-in contact on every finish regardless of `is_public`.

**The shape.**
- **Email-identified, account-linked on confirm.** A contact is always identified by `contact_email`; `contact_user_id` is filled only when an app-user contact confirms in-app. Storing only the email at add time is deliberate — it avoids an **account-enumeration** leak (an owner can't probe whether an arbitrary address belongs to a registered user). The contact-side cascade-delete still works because `contact_user_id` (when set) FK-cascades from `auth.users`; the owner side cascades on `owner_id`.
- **Both-sides opt-in.** The owner's opt-in is implicit in creating the row; the contact's is `confirmed_at`. A row that exists AND is confirmed === both agreed. Two confirm paths: in-app (`my_pending_safety_requests()` matches the caller's account email via a definer read, `confirm_safety_contact()` links + confirms) and an unauthenticated email-link `confirm_safety_contact_by_token()` for external (non-app-user) contacts.
- **Owner can't self-confirm.** There is no owner UPDATE policy and a BEFORE INSERT trigger forces `confirmed_at`/`contact_user_id` null, so an owner can never preset the opt-in and start emailing an address that never agreed.
- **Finish trigger.** A `runs` AFTER INSERT enqueues a `safety_email` `finish` job per confirmed contact, **no `is_public` gate**, but with the same **24h recency guard** `run_completed` uses so a bulk history import can't blast a contact with years of old finishes.

**Why a third email kind, neither `notification_email` nor `lifecycle_email`.** It can't be `notification_email`: there's no `notifications` inbox row, and — critically — it must NOT be gated on the *runner's* `email_notifications` preference (a safety contact opted in explicitly and must not be silenced by the runner's social-email setting). It can't be `lifecycle_email` either: the recipient may be a non-user identified only by an email, and the copy carries per-finish context (distance, time). So `safety_email` is its own kind with two templates (`finish`, `confirm`); no send-once log (a finish is a fresh event each run, and a rare duplicate beats a missed safety alert). Reuses the same SMTP transport + locale catalogue as the other two. `contact_user_id`, when present, only localizes the mail.

**Trade-off / scope.** Mobile UI (a Settings safety surface) is deferred to a later session (R2-B); web Settings + the email-link confirm page ship now. Native push to a locked phone still waits on the FCM/APNs leg (`§ 117`) — email is the credible-now channel, matching the persona's "a watching partner already sees the finish" framing. Account *deletion* (Art 17) is covered by the FK cascades; the Art 20 *export* of `safety_contacts` is a documented follow-up (the export-guard keys on a literal `user_id` column, which this table doesn't have, so it isn't auto-flagged). **Don't** relax the `run_completed` is_public gate to cover this, **don't** route safety mail through `notification_email` (it would inherit the preference gate), and **don't** resolve email→user at add time (the enumeration leak).

---

## 132. Age grade for non-parkrun races uses the embedded USATF-MLDR 2025 factor tables — never a from-memory approximation

**Decided (2026-06-04):** the age-grade % on run-detail was only ever shown for parkrun imports (the scraped `metadata.age_grade` string). A manual / Strava / FIT race with a known distance, duration and the runner's DOB got nothing — a gap precisely for the masters audience that values age grading most. We now compute it client-side for any standard-distance race when that scraped key is absent.

**Why a real dataset, not a formula.** Age grading is a table lookup (an open-class world-standard time per distance/sex × a single-year age factor), not a closed-form curve, and a *wrong* age grade is worse than none — it misleads the exact runners who care. So the factors are taken **verbatim** from the authoritative published tables, not reconstructed from memory. Source: the **USATF Masters Long Distance Running (MLDR) 2025** road tables (Alan Jones + Tom Bernhard, approved 2025-01-10) — the current road-running age-grade standard, distributed **CC0 1.0** at `github.com/AlanLyttonJones/Age-Grade-Tables`. The 2025 edition's open standards match current world records (marathon M 2:00:35 / F 2:09:56), which is the cross-check that they're the real numbers.

**The shape.**
- The raw RunScore source files + a generator live under `scripts/age_grade/`; the generator emits two committed data modules (`age_grade_tables.ts` / `age_grade_tables.dart`) with **identical numbers by construction**, so there's no hand-transcription and a future WMA edition is a drop-in-and-regenerate. 22 standard distances (1 mile…200 km, **including ultras** — a differentiator vs Strava), single-year factors ages 5–99, M/F.
- The logic is a TS↔Dart parity pair `age_grade.ts` ↔ `age_grade.dart` (12 mirrored tests each): `agePct = openStandard / (durationSec × ageFactor) × 100`, with **nearest-standard distance match within ±2 %** (absorbs ~1 % GPS over-read on a certified course without grading a 5.4 km jog as a 5 km; the standard distances never collide at that tolerance), **age on race day** (not today), and a **binary-sex gate** — unset / non-binary returns null (the tables have no standard without a male/female reference) rather than guessing.
- The parkrun scraped value still wins when present; the computed value only fills the absence.

**Trade-off.** We embed ~4k factors on each client (~50 KB) rather than adding a backend RPC — keeping the calc offline + instant on run-detail and avoiding a round-trip, at a small bundle cost. Non-binary runners get no age grade by design (no standard exists); if World Athletics ever publishes one, it's a table swap. Watches stay recording-only (the analysis surface lives on web/mobile). **Don't** approximate the factors, **don't** age-grade a non-standard distance, and **don't** hand-edit the generated `*_tables` modules — re-run the generator.

---

## 133. Web push is a second consumer of the notifications rows, sent by the Go worker on a `web_push` job — stdlib crypto, a separate preference + send-state, and a subscription-gated enqueue

**Decided (2026-06-04):** `§ 117` always framed native FCM/APNs as "another consumer of the same notifications rows." Web push is the credible-now slice of that promise — the browser subscribe path (`apps/web/src/lib/util/push.ts` + `/sw.js`) already shipped and the VAPID key is operator-self-generated (no Firebase/APNs account needed). So we built the server leg: a `web_push` job kind (migration `20261219_001`) that the Go worker drains alongside `notification_email`.

**The shape, and why it deliberately diverges from the email channel.**
- **Same rows, separate everything else.** The web-push handler reads the SAME `notifications` row the bell + email read, but with its own `web_push_sent_at` send-state column (independent of `email_sent_at`: a notification can be emailed but not pushed), its own `push_notifications` preference (independent of `email_notifications` — muting email must not mute push, and vice-versa; same `all|important|off` shape + `important` default + shared `importantKinds` classification), and its own enqueue trigger.
- **Subscription-gated enqueue.** Unlike the email enqueue (fires for every row, lets the worker resolve the address), the `web_push` enqueue trigger fires ONLY when the recipient has a `push_subscription` on some device. Web-push adoption is a minority of users, so enqueuing a per-notification job for everyone who can't receive it is wasteful at scale; gating in the trigger keeps the queue lean. A user who subscribes *after* a notification was created doesn't retro-receive it — the same (correct) property the email channel has.
- **Per-device fan-out + prune.** A user can have several browser subscriptions (one per device) on `user_device_settings.prefs.push_subscription`; the handler sends to each. A push service reporting the endpoint dead (404/410) triggers a prune via the `clear_push_subscription` SECURITY DEFINER RPC (PostgREST can't express a jsonb key-delete in a PATCH); a 429/5xx defers the whole job (Tag = `notif-<id>` coalesces the re-send client-side).

**Why a stdlib sender, not a web-push library.** RFC 8291 (aes128gcm message encryption) + RFC 8292 (VAPID JWT) is ~150 lines on Go's `crypto/ecdh` + `crypto/hkdf` + `crypto/aes` plus the worker's existing `golang-jwt`. Vendoring a third-party web-push library for a small, stable spec would add supply-chain surface for no real saving; `internal/webpush/` is round-trip-tested (encrypt → decrypt with the UA private key → assert plaintext) so correctness is pinned without a network.

**Trade-off / scope.** Gated on `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY`/`VAPID_SUBJECT` on the worker; unset → jobs finish done while leaving rows pending (same posture as the email nil-sender). A `push_notifications` category UI toggle (web + mobile, mirroring the email one) is the remaining follow-up — gating works on the `important` default without it. **Don't** fold push gating into `email_notifications`, **don't** reuse `email_sent_at` for the push channel, and **don't** drop the subscription gate in the enqueue trigger (it's what keeps the queue from a job-per-notification-per-user). Native FCM/APNs is the next sibling — copy this shape (its own enqueue gate + `*_sent_at` column + handler).

## 134. Cross-modality is two-directional but asymmetric: gym → run readiness is deterministic, nutrition → run guidance is not — and the nutrition goal goes dynamic (base + exercise)

**Decided (2026-06-08):** with gym + nutrition shipped beside running, the question was how far to wire the three together. The answer is "interconnect, but keep the deterministic readiness math run-recoverable."

- **Gym → run readiness (deterministic, already true; now visible + opt-out).** Lifts feed the same CTL/ATL/TSB curve as runs (`§ 63` lift→load), so a heavy session raises fatigue and lowers form. That was silent; the dashboard Fitness card now shows a transparent note when recent lifts are factored in, and a `exclude_gym_from_readiness` universal pref drops lifts from the readiness/recovery curve for runners who want a pure run signal. The run-only curve is recoverable by construction (`training_load.ts` separable provenance), so the toggle is display-side, not a data change.
- **Nutrition goal goes dynamic — "base + exercise."** `computeNutritionTargets` previously read a single activity-multiplier TDEE that ignored what you actually did today. It now treats the activity-level pref as a **non-exercise baseline** and adds **measured workout calories** (`exercise_calories.ts`/`.dart` — a new parity pair: ~1.036 kcal/kg/km for runs, a 5.0-MET model for gym) on top. `/nutrition` shows the `base + exercise` breakdown on workout days. This avoids the double-count the old multiplier would create once real workouts are added, and matches how MyFitnessPal/Garmin behave.
- **Nutrition → run readiness stays OUT of the deterministic curve — on purpose.** Under-eating's effect on readiness is real but hard to model reliably, and `training_load.ts` deliberately keeps run readiness from being corrupted by auxiliary inputs ("well-rested, train hard" on bad data is dangerous advice). So fuelling adequacy stays the **AI Coach's** soft-reasoning job (the coach context already carries a 7-day nutrition rollup, `§ coach context`), not a number that moves the readiness ring.

**Scope / follow-up.** Both surfaces are web-first (canonical, `§ 24`); the `exercise_calories` math has a Dart twin but the mobile *surfaces* (dynamic-TDEE on `nutrition_screen`, the readiness note + exclude toggle on the mobile dashboard) are a tracked mobile-mirror follow-up. Calorie burn is gross (not net of resting metabolism) — a conservative simplification documented in `exercise_calories.ts`.

---

## 135. Durable per-store summary index + windowed hydration for the offline-first local stores

**Decided (2026-06-08):** the offline-first mobile stores (`LocalRunStore`, plus gym/food via `OfflineSyncStore`) loaded **every** row into memory on init — fine at a few thousand rows, a real memory footprint + slow cold-load at the tens-of-thousands a multi-year multi-modal user accumulates (roadmap "Windowed / paged local stores"). The durable fix is a per-store **summary index** + **windowed hydration**, not a naive "recent-N-in-memory" store (which an adversarial design pass showed silently breaks every all-history consumer).

- **Summary index (the cold-load win).** Each store keeps one on-disk `index.json` holding a compact `RunSummary` (or `OfflineSyncStore.summaryOf`) per row — scalars only, never the GPS track or bulky metadata (`laps`, `workout_step_results`). Cold-load reads that ONE file into the full in-memory index instead of decoding N per-row files. The index is a **batched, atomic, crash-safe sidecar** (`writeJsonAtomic`, flushed once per mutation — never per-row) and is **a cache, never the source of truth**: a missing / corrupt / drifted index (id-set mismatch vs the on-disk run files) self-heals via a full parallel walk + rebuild — the post-crash recovery + first-launch migration.
- **Windowed hydration (the memory win).** Only a **resident window** of full `Run` objects stays in memory: the newest `kResidentWindow` (200) by date **∪ all unsynced runs**. The residency-of-all-unsynced invariant is load-bearing — `unsyncedRuns` (and therefore the sync drain) reads the track-bearing resident `_runs`, never the track-less summaries, so a track-less summary can never be uploaded with an empty track. `runById` hydrates an out-of-window run from disk on demand; `recentWindow` / `hydrateOlder` / `iterateAllRuns` round out the API.
- **All-history consumers read the index, not the window.** Fitness, mileage, goals, recap, gear backfill, period summary, import dedup, and run-detail route-comparison read `summaryRuns` (track-less full-history `Run`s) so they stay correct under windowing without holding every full run resident; the TS↔Dart parity helpers keep their `List<Run>` signatures unchanged because `RunSummary.toRun()` rebuilds a track-less run. `runs_screen` filters/sorts/summarises over the index and resolves only the visible page to resident full runs (thumbnails + detail-nav hydrate via `runById`). **Dashboard PBs moved to the authoritative server `personal_records` cache** (with an offline resident-window track-scan fallback) — the old in-memory track scan couldn't see windowed-out or cloud-synced runs anyway.

**Why not naive recent-window-in-memory.** ~8 consumers need the *whole* history (all-time PBs, yearly mileage, route PB across years, import dedup against old `external_id`s). A store that only kept recent rows would silently corrupt all of them. The summary index keeps the whole history cheaply (scalars) while only the *full objects* are windowed — correctness + the memory/cold-load win together.

**Trade-off / scope.** `summaryRuns` allocates transient track-less `Run`s per call (a GC spike on a filter change, not retained) — accepted over churning the parity-helper signatures; can be optimised to read summaries directly later. The slow-path rebuild holds the full set for that one session (the read is already paid); the next launch windows it. Gym/food keep hydrating all rows on load (their consumers read full rows directly) — the index there is the cold-load fast path + `loadInWindow` for the nutrition single-day view to adopt later; gear writes no index (no windowed surface). Pinned by the `_loadAll` index-first guard + the crash-atomic write guards in `architecture_guards_test.dart`, and the windowed cold-load suite in `local_run_store_test.dart`.

---

## 136. Route builder auto-routes on every waypoint, backed by a per-segment cache

**Decided (2026-06-09):** the route builder snaps to roads **automatically as each waypoint is placed** (added, dragged, inserted, removed, undone, out-and-back'd) rather than behind an explicit "Calculate Route" button. Mobile already worked this way; web had drifted to a batch model where you placed every pin and then waited on one all-segments-at-once OSRM pass — the "place 100 points, wait minutes" complaint. The web Calculate / Recalculate / undo-recalculate buttons (and their i18n keys + the `calculateRoute` / `undoCalculate` exports) are gone; `features.md`'s spec already described per-click auto-draw, so this brings the implementation back to the spec.

- **Per-segment cache (`SegmentCache` web / `RouteSegmentCache` mobile).** Re-routing the whole waypoint list on every placement would be O(n) OSRM calls per pin — fine for a 5-point route, minutes of waiting at 100. The cache is keyed by **endpoint coords + profile** (order-sensitive — A→B ≠ B→A on one-way streets; exact-coord match so a dragged pin's two adjacent segments miss and re-fetch while the rest stay hits). A re-route after one new pin fetches exactly the **one new segment**; the prior N−1 are cache hits. The route builder owns one instance for the editing session and clears it on Clear. Recency-bounded (2000 entries) as a memory backstop.
- **Cache successes only.** A straight-line fallback from a transient OSRM hiccup is **never** cached — it must re-try on the next pass, or a momentary outage would freeze a wrong line in place after the service recovered.
- **Incremental routing must not raise the busy flag (the load-bearing subtlety).** Web's map-click / marker / drag handlers all early-return while `isRouting` is true (that guard protects the multi-second `generateLoop`). If per-pin routing flipped `isRouting`, the next click during the ~1 s snap would be **swallowed** and placement would feel sticky. So incremental auto-routing runs with `skipBusyToggle: true` — it never raises `isRouting`; the existing `routeVersion` cancellation makes a newer placement supersede an in-flight one (latest pin wins). Mobile already relied on its generation counter for the same reason and deliberately doesn't gate taps on the routing flag.

**Trade-off.** Adding a pin to an already-snapped route briefly reverts to the straight-line preview while the one new segment fetches (the existing invalidate-then-redraw path) — a sub-second flicker, the same visual the old drag path already produced, now auto-resolved instead of waiting on a button. The cache holds OSRM geometry for the session only (not persisted). `routing.ts`'s `segment_cache.ts` and `routing.dart`'s `RouteSegmentCache` mirror each other by design (same key shape, ok-only, recency cap); they aren't a formally-listed twin pair (neither is the rest of `routing.*`), so keep them in lockstep by hand.

---

## 137. Generate-a-route-by-distance moves server-side to a dedicated Lambda + self-hosted GraphHopper round_trip

**Decided (2026-06-09):** the "generate a loop of N km from here" feature moves off the in-browser heuristic and onto a server-side call to a self-hosted **GraphHopper** `round_trip` engine, fronted by its own AWS Lambda Function URL (mirroring the coach + share Lambdas). The old client path scaffolded a radial polygon at a guessed radius, snapped it to roads via OSRM, and **bisected** the radius across ~4 latency-bound iterations to home in on the target distance. The single-radius knob is a poor lever on lopsided road networks — when the reachable streets are dense on one side and sparse on the other, scaling one radius can't hit the target without overshooting badly (a 5 km target produced an 8.22 km lasso), and each correction costs a full round-trip so the loop runs out of iterations before it converges. GraphHopper's `round_trip` algorithm targets the requested distance *inside* the engine per call, so a single request lands close; we race a few seeds (`heading`/seed variations) server-side and pick the best-shaped loop by **enclosed-area efficiency** (`apps/web/src/lib/routes/generate/select.ts`) so the result is a real loop, not a there-and-back spur.

- **GraphHopper is loop-generation only; OSRM is retained.** OSRM still owns server-side **map-matching** (`apps/job_worker/`) and manual-waypoint **snapping** (`routing.ts` / `routing.dart`). GraphHopper is added *alongside* it for the one thing OSRM's `route` API can't do well — distance-targeted loop synthesis — not as a replacement. Two engines, two jobs.
- **`GRAPHHOPPER_URL` is server-only (never `PUBLIC_`).** The browser never calls GraphHopper directly; it calls our `/api/routes/generate` endpoint, which calls the engine. The user's start coordinates therefore never reach a third party — privacy parity with the self-hosted OSRM posture (both engines run in our own infra; coordinates don't leave it). The Lambda returns `{coordinates, distanceM}`; it answers `501` when the engine URL is unconfigured, `502` when the engine is unreachable, `503` on an unhandled error.
- **Graceful client fallback.** When the endpoint is unconfigured or down, the client falls back to the prior in-browser OSRM radial heuristic, surfacing the existing `routeBuilder.generatedDistanceLonger/Shorter/couldntGenerateLoop` copy — the server path is a quality upgrade, not a hard dependency, so a dev machine with no GraphHopper still generates loops.

**Trade-off.** Adds a second routing engine to self-host (one more Fly app + Lambda + CloudFront behaviour + WAF rule + alarms to operate) for a single feature. Justified because the in-browser bisect couldn't be made to converge reliably on real networks without more latency-bound iterations than a responsive UI tolerates — the overshoot was a correctness problem, not a tuning one. The OSRM fallback means the new infra is never load-bearing for basic functionality.

**Amendment (2026-06-10): a sampled via-point polygon generator runs *ahead* of round_trip.** round_trip is still a radial heuristic — per seed it drops one turnaround point and routes out-and-back-ish, so it can't compose a tidy loop from a dense nearby grid. The v2 generator (`apps/web/src/lib/routes/generate/loop_polygon.ts` + `loop_select.ts` + `loop_generate.ts`, design in `docs/features/route_loop_generation.md`) places K via-points on a sampled ring around the start and drives OSRM's multi-waypoint `/route/v1/foot` to *force* a compact loop, then scores candidates by the same `areaEfficiency` metric `select.ts` uses. `handleGenerate` tries this polygon path FIRST whenever `OSRM_URL`/`PUBLIC_OSRM_URL` is set, and only falls through to round_trip when the polygon generator returns `null` — a loop-poor location where every candidate is a zero-area spur (validated dense ~5.4 km / medium ~5.5 km within band; the reported sparse start returns `null` → round_trip, exactly as the PoC predicted). The OSRM start coordinate is forwarded server-side, so even a `PUBLIC_OSRM_URL` value never leaks user coordinates. **Deferred:** the doc's first-class "loop-poor" UX (a largest-achievable-loop probe + a 3-way generate-shorter / accept-out-and-back / try-a-different-start choice) is *not* built — loop-poor starts still fall through to round_trip and reuse the existing "shorter than X, use Y instead" shortfall banner. Tracked as a follow-up.

**Amendment (2026-06-10): the v3 graph-cycle generator is BUILT; the v2 polygon generator is retired.** Both geometric generators reason about shape, not the street graph, so neither traces the neighbourhood loop a human would pick on an irregular grid (a 432-sample polygon sweep found *zero* in-band loops at the report start where a loop demonstrably exists). v3 (`docs/features/graph_cycle_loop_generation.md`) operates on the **real foot graph**: a new standalone Go sidecar (`apps/graph_cycle`) parses the same regional OSM PBF the OSRM/GraphHopper stack uses into an in-memory foot graph and searches it for **disjoint-path cycles** — direction-sampled far-points around `D/2`, penalised (×8) edge reuse on the return leg (strict removal disconnects bottlenecked sparse networks), scored by the same `areaEfficiency`. `handleGenerate` now tries **graph-cycle FIRST** (when `GRAPH_CYCLE_URL` is set) → `round_trip` (+ multi-distance) fallback → existing shortfall UX; the polygon path (`loop_polygon`/`loop_select`/`loop_generate`) is deleted and `osrmUrl` dropped from `GenerateConfig`. Deployed like GraphHopper (own Fly app, public https, `X-Engine-Key` guard — but in-process, not Caddy, since we own the Go server). **Live-validated** on a 405 MB Virginia extract (14.2 M nodes, 28 s build): dense Richmond starts trace clean loops (areaEff **0.50–0.57**, 5 km ±11 %, 82–537 ms/request); the report start `37.6518,-77.3614` is confirmed loop-poor (best 5 km loop areaEff 0.145, its only genuinely round loop at ~12.8 km), and the search surfaces that *largest clean loop* for free — subsuming the deferred loop-poor probe (the 3-way UX itself stays deferred). The sidecar is our own Fly infra, not a new third party (sub-processor changelog updated). Prod deploy is operator-gated (Fly app create + volume + PBF seed + secret); everything up to it is shipped.

---

## 137. One env-file convention across every app: `.env.example` · `.env.development` · `.env.local`

**Decided (2026-06-09):** every app that needs env for local development uses the same three-file scheme, so a fresh clone runs without a copy step and there's one mental model:

- **`.env.example`** — committed placeholder template. Documents every variable; real values blank.
- **`.env.development`** — committed, **non-secret** ready-to-run local defaults (loopback URLs + the *public* Supabase local-demo keys, which are identical on every machine). This is the file each toolchain actually loads.
- **`.env.local`** — gitignored per-machine override for your real keys. **Precedence is toolchain-specific** (see mechanics below): `.env.local` wins for Gradle and Go, but **not for Vite/web**, where a mode file (`.env.development`) outranks it — so on web a key left *present-but-empty* in `.env.development` overrides (nullifies) the same key in `.env.local`, and any secret meant to come from `.env.local` must be **absent** (not blank) from `.env.development`. The shell / deploy env wins everywhere.

Before this, the three were inconsistent: web committed `.env.development` (Vite auto-loads it in dev), mobile + Wear committed `.env.local` (the opposite of the Vite idiom), and backend committed only `.env.example`. The trigger was a committed web `.env.development` shipping a localhost tileserver URL — Vite loads that file in CI too, which hid the map style switcher and reded the e2e suite (see the tile-override fix). Standardizing removed the "which file does this app use?" tax.

**Per-toolchain mechanics differ because only Vite has a "mode":**
- **Vite (web)** auto-loads `.env.development` for `vite dev`. Priority, highest first (verified empirically on Vite 8): **shell env > `.env.development.local` > `.env.development` > `.env.local` > `.env`**. The mode file outranking `.env.local` is the opposite of the common assumption — a per-machine web override therefore goes in your shell or the gitignored `.env.development.local`, **not** `.env.local`.
- **Supabase functions (backend)** load no file automatically; you pass `--env-file .env.development` (or `.env.local`).
- **flutter_dotenv (mobile)** loads a *named* asset from the bundle. It loads `.env.development`; the per-machine override is **`--dart-define`** (merged on top, winning), **not** a `.env.local` file — a gitignored file can't be a guaranteed-present build asset. Release builds read neither (the `kDebugMode` gate), so no local value ships in an APK.
- **Gradle (Wear)** reads `.env.development` then overlays `.env.local` at configure time; the release build type reads neither.
- **Go (job_worker)** has no `.env` convention at all, so a ~20-line stdlib `loadEnvFiles(".env.local", ".env.development")` runs at startup (existing env wins, earlier file wins). Chose stdlib over godotenv: the module pins a Go toolchain some build hosts can't satisfy with `GOTOOLCHAIN=local`, so adding a dependency + `go.sum` entry for 20 lines wasn't worth it. A `.dockerignore` keeps `.env*` out of the build context, and the multi-stage image ships only the binary, so prod sees neither file — Fly secrets are the sole source.

**Safety:** the committed `.env.development` files carry only the public Supabase demo JWTs; both the `gitleaks` allowlist and the `env-isolation` workflow scan them (by path) to fail the build if a *real* key ever slips in.

**Trade-off.** `.env.development` and `.env.example` are near-duplicates for an app whose only local values are blanks (backend) — accepted for uniformity. Mobile's override being `--dart-define` rather than `.env.local` is a documented exception forced by the asset-bundle loader, not a drift.

**Amendment (2026-06-09).** The web Protomaps tile override moved from `.env.local` *into* the committed `apps/web/.env.development` (`PUBLIC_TILE_STYLE_URL=http://localhost:8080/styles/basic/style.json`), and `apps/web/.env.local` was deleted. Reason: per the Vite precedence above, `.env.development` outranks `.env.local`, so the old `.env.local` placement never took effect — the committed *present-but-empty* `PUBLIC_TILE_STYLE_URL=` silently won, leaving the route builder's map blank (it lacks the OSM fallback that `RunMap` falls back to, so only `/routes/new` looked broken). This reverses the original trigger above, so CI is kept green a different way: e2e forces the var back to empty via the Playwright `webServer.env` in `tests-e2e/playwright.config.ts` + `playwright.livehub.config.ts` (process.env outranks every `.env` file), so the suite still falls through to MapTiler / the OSM raster instead of chasing a tileserver the runner doesn't boot. The gitignore still covers `.env.*`, so a future `apps/web/.env.local` holding real secrets can't be committed — but note those secret keys must be **absent** from `.env.development`, not blank, or the blank wins.

---

## 138. Web gym reads that need all-time or distinct-only data moved server-side; per-surface RPCs replace whole-history client reads

**Decided (2026-06-10, perf-hunt follow-up):** the web gym surfaces stopped pulling the user's entire `gym_sets` history (`fetchGymSetHistory()` — unbounded, a 3-year lifter ≈ 15k rows shipped to the browser on every load) and now each reads only what it renders, via four owner-scoped SECURITY-INVOKER RPCs: `gym_exercise_records()` (per-exercise all-time bests → `/gym/records`), `gym_exercise_set_history(p_name)` (one exercise's sets, normalised-name matched → `/gym/exercise` + `/gym/[id]`), `gym_exercise_names()` (distinct names → History autocomplete), plus a `sinceDays` window on `fetchGymSetHistory` for the dashboard's recent-only needs. Migrations `20261224`–`20261226`; each pinned by pgtap.

**Why server-side.** All-time records are *maxima* — a windowed client read can't produce them, and the only alternatives were "keep shipping everything" or "aggregate on the server." This mirrors the run-PR precedent (PR aggregation already lives only in SQL, `refresh_personal_records_for_user`), so the web client-side `exercise_records.ts` roll-up was retired and its math moved into the RPC, with pgtap pinning it to the same `gym_prs.ts` fixture the badge engine uses. The single-exercise + names reads went to RPCs (not client filters) because the match must be on the *normalised* exercise name, which PostgREST can't express as a filter.

**Trade-off — a parity pair was intentionally broken.** `exercise_records.ts` was a documented byte-identical TS↔Dart pair; the web side is now the RPC while mobile keeps its client-side `exercise_records.dart` + `gym_records_screen.dart`. The two compute the same bests via different paths, each pinned by its own tests, and are no longer kept byte-identical (removed from the parity-pairs list). The `gym_prs.ts`↔`.dart` PR-engine pair and `exercise_history`↔`.dart` stay byte-identical. Mobile still reads its full set history client-side — the same perf issue exists there and is a separate, Dart-side follow-up.

**Residual.** The `/gym` list's temporal per-workout PR badges (`prWorkoutIds`) still read the full history: deciding "did each displayed workout set an all-time PR up to that point" inherently needs every prior set across all exercises, so it can't be windowed or served by a bests RPC. Fully eliminating it needs a write-time `gym_workouts.pr_kinds` flag with a cascading recompute (changing a record-holder flips later workouts' badges) — a multi-day feature tracked in `followups.md`.

---

## 139. Routes is a run-modality surface; mobile nav is a Fitness hub

**Decided (2026-06-11, shipped):** as the app went multi-modal, each modality's planning assets settled inside its own surface — gym owns routines, nutrition owns targets — except Routes, which had shipped as a top-level web sidebar peer of Gym/Nutrition *and* (on mobile) under Social. Both mis-frame a run-planning tool. Routes now co-locates under the run surface on both platforms: web drops the standalone `/routes` sidebar item and nests Routes under `/runs` via a shared `RunSurfaceTabs` strip (the `/routes` URL is preserved so bookmarks / club deep links / shares don't break); mobile moves Routes out of Social into Fitness→Runs. Mobile additionally adopts a `Home · Fitness · [+]Log · Social · You` bottom nav: **Fitness** is a modality hub (`fitness_hub_screen.dart`, sub-tabs All/Runs/Gym/Nutrition) that absorbs the former standalone History tab as its All timeline and gives each modality a persistent review/plan front-door; Settings folds into a `You` tab; Coach keeps no nav slot and is pinned on Home; the `[+]Log` keep-alive capture pages + foreground-service recording are unchanged.

**Why "Fitness", not "Train".** The working title in `multi_modal.md` was "Train", but the hub holds nutrition too, which you don't "train" — "Fitness" is the only label that honestly covers run + gym + nutrition.

**Trade-off.** This re-churns mobile nav that had just shipped (G5) — accepted because leaving Routes mis-placed + the modalities without a front-door was the larger cost, and batching the routes relocation with the nav rewrite meant `home_screen.dart` was reshaped once. Supersedes the routes-half of [§ 61](#61-social-hub-ia-rename-clubs--social-host-feedpeopleclubs-as-tabs-under-social) and corrects [§ 63](#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)'s "Routes was folded into Social" note (that was mobile-only; web had it as a top-level item).

**Amendment (2026-06-11): Training Plans nested too.** Plans-nesting was initially deferred (the web strip first shipped as `Runs · Routes` only). It is now closed on both platforms, exactly mirroring the Routes relocation: web widens `RunSurfaceTabs` to `Runs · Routes · Plans` and `/plans` mounts the strip in place of its old standalone `/dashboard` back-link (the `/plans` URL is preserved); mobile's `FitnessHubScreen` threads the existing `TrainingService` from `home_screen` and surfaces a Plans entry alongside Routes in the Fitness→Runs sub-tab (`RunsScreen.onOpenPlans` → `PlansScreen`). Like `/routes`, `/plans` keeps no top-level nav item — it is reached from the run surface plus its deep links (dashboard CTA, coach plan switcher, notifications, club templates).

**Don't re-litigate** by re-adding a top-level Routes sidebar item, a standalone mobile History destination, or a Settings nav slot — Routes lives under the run surface, History is Fitness→All, Settings is in You. Full design + rollout in [multi_modal.md § redesign](../features/multi_modal.md#proposed-redesign-pending-sign-off--the-train-hub--routes-relocation).

---

## 140. Yoga/pilates session content uses a dedicated `session_plans` engine (mirroring gym routines), not the gym-routine schema

**Decided (2026-06-11, P1 shipped):** the yoga/pilates domain is time-or-reps × per-side × sequence-critical × breath-cue — not sets × reps × load — so it gets a sibling relational family (`session_plans` / `session_plan_blocks` / `session_plan_items`, migration `20270103_001`) that mirrors the gym-routine engine's *shape* (plan→blocks→items, an expand-once parity-paired pure helper, self-hiding) while diverging on the axes. The `kind` column is a narrow union + CHECK (`SessionItemKind = hold|reps|flow`) registered in `check_constraint_unions.mjs`. A `class` event optionally attaches a `session_plan_id` (the rich successor to the lightweight `events.gym_template` jsonb seam, which stays as the zero-effort path); only an event organiser may set it (a BEFORE trigger backs the events UPDATE RLS), and the column carries an explicit SELECT grant because `events` is under a column-level lockdown (20260818_001). RLS mirrors club-owned routes: author owns, `is_public` is world-readable, club-owned plans are member-read / admin-write.

**Why a new engine, not gym routines.** Reusing gym routines would force load/RPE semantics onto poses and lose hold-time + per-side + flow ordering. The expand helper (`expandSessionSteps`, web `social/session_steps.ts` ↔ mobile `session_steps.dart`) flattens blocks→items in position order and splits a per-side item into consecutive Left/Right steps, carrying cumulative time (a reps step with no duration contributes 0).

**Trade-off.** P1 builds the session schema before execution proves out — accepted because it is additive, web-first, independently useful (build + read a sequence even with no runner), and gate-free on the legal axis (no payments, no sub-processor). P1 is the validation probe; P2–P4 (follow-along runner, TTS, `workoutDraftFromSession` logging a `gym_workout`, `LocalSessionStore`) are gated behind it and remain deferred.

**Don't re-litigate** by re-modelling session content onto `gym_workouts` rows or building the runner/logging before P1 shows instructors/self-practitioners actually author sessions. Full design in [session_planner.md](../features/session_planner.md).

**Amendment (2026-06-12) — P2 shipped; "remain deferred" above is now stale for the follow-along + log layer.** The P2 follow-along runner + logging landed web-first and on the mobile twin: web `SessionRunner.svelte` + `SessionExecutionBand.svelte` (the `/sessions/[id]` Start overlay), the mobile follow-along runner on `session_detail_screen.dart` backed by `LocalSessionStore` (byte-identical iOS twin), `workoutDraftFromSession`, the `gym_workouts.metadata` session trio (`session_plan_id` / `session_step_results` / `session_adherence`), and the `computeSessionAdherence` parity pair. TTS cueing on web and P3–P4 (catalog/sharing, deeper progression) remain deferred — only the P2 follow-along + log clause of the trade-off above is superseded.

---

## 141. The gym programming engine ships as a four-slice, web-first depth tier that relocates the engagement gate into P1

**Decided (2026-06-11, P1 shipped — migration `20270101_001`).** (Originally drafted in `gym_programming.md` as §140; §140 went to the session-plans ADR, which landed first — this is the same decision, renumbered to §141.) The engine sequences so **P1 (reusable routines + "repeat last") *is* the validation gate**, not a separate measurement phase: `gym_routines` → `gym_routine_exercises` → `gym_routine_sets` + a `gym_workouts.metadata` jsonb bag, prefill-only. If repeat-rate clears an owner-set threshold (~20% of gym sessions over 4–6 weeks) we proceed to P2 (supersets / set-types / rest / time-distance + `expandRoutineSteps`), P3 (a `GymWorkoutRunner` mirroring `WorkoutRunner` — prescribed-vs-actual `gym_step_results` + `gym_adherence` in `gym_workouts.metadata`, adherence on reps/load at the 80%-of-target cutoff applied **per axis**, not pace), and P4 (linear / double-progression / 5×5 / %-e1RM / RPE-autoreg; Coach-authored progression clamped by the same pure prescriber).

**Why relational, not jsonb.** The plan is relational — the deliberate divergence from `plan_workouts.structure jsonb`, justified by per-exercise querying + row-by-row progression — with one jsonb escape hatch (`progression_params`). The plan→session link lives in `gym_workouts.metadata.routine_id` (a string, **not** an FK), so deleting a routine leaves prior sessions intact (immutable history). P1 shipped web (`/gym/routines` library + builder + detail) **and** the mobile twin (`LocalRoutineStore` + screens, byte-identical iOS); the `gym_routine` parity pair (`routineFromWorkout` + `prefillFromRoutine`) reuses `gym_prs.normaliseExerciseName`. The manual engine is fully free; only Coach-*authored* progression (P4) is metered via the existing per-tier coach cap.

**Trade-off.** P1 builds the routine schema before the gate formally clears — accepted because P1 is itself the cheapest probe and a durable standalone win ("repeat last" + ending the flat-`set_index` reconstruction heuristic via explicit `position` + `exercise_key`). If repeat-rate is weak, freeze at P1 and leave P2–P4 specced-but-unbuilt.

**Don't re-litigate** by modelling routines on `plan_workouts` jsonb or building the runner/progression before the P1 signal lands. If Coach-authored progression (P4) ever reads logged sets, loop in the CISO/Security Analyst before that path ships. Full design in [gym_programming.md](../features/gym_programming.md).

**Amendment (2026-06-12) — P2/P3 execution shipped; "freeze at P1, leave P2–P4 specced-but-unbuilt" above no longer describes P2/P3.** The execution layer landed across platforms: web `GymSessionRunner` (`/gym/session/[routineId]`) with `GymExecutionBand.svelte` + `RestTimer.svelte`, the shared `GymWorkoutRunner` in `packages/run_recorder/`, the mobile `gym_session_screen.dart` + `gym_execution_band.dart` twin backed by `LocalGymStore` (byte-identical iOS), `expandRoutineSteps`, and the `gym_adherence` (`computeRoutineAdherence`) + `gym_progression` (`nextPrescription`) parity pairs writing the `gym_workouts.metadata` execution trio (`routine_id` / `gym_step_results` / `gym_adherence`). P4 (deeper progression-engine wiring) remains specced and still gated on the P1 repeat-rate signal — only the P2/P3 portion of the trade-off above is superseded.

---

## 142. Admin authorization is DB-enforced via `app_admins` + a `private.is_admin` oracle, never client-side route gating

**Decided (2026-06-12, migration `20270104_001`).** The report-moderation back-office (`/admin/reports`) is the first admin-only surface. Because the web app is a **statically-prerendered SPA** served from S3/CloudFront, any client-side route guard is shipped to the browser and is therefore not a security boundary — a non-admin can read the bundle and call the API directly. So authorization lives entirely at the database: an `app_admins (user_id, …)` allow-list table (RLS-enabled, no user-JWT read policy → default-deny; grant/revoke via service_role), a `private.is_admin(uid)` SECURITY DEFINER oracle in the `private` schema (so PostgREST never exposes it as an anon RPC oracle, mirroring the membership oracles of §… `20261120_001`), and **every moderation RPC hard-denies a non-admin with `42501` before touching report data**. The client calls a cheap `am_i_admin()` RPC *only* to choose chrome (queue vs not-authorized state); it changes nothing about who can actually read or write.

**Why a table, not a `user_profiles.is_admin` column.** A dedicated table keeps the grant cleanly auditable (`granted_at`/`granted_by`), revocable with one DELETE, and outside the column-grant lockdown surface that `user_profiles` already carries. It also means no client ever reads an admin flag off its own profile row.

**Trade-off.** Triage-only in v1: an admin marks a target's pending reports reviewed/dismissed with a note — there is deliberately no content takedown / visibility flip (suppression stays a separate, considered action; auto-hide was already out-of-scope per the report MVP). Admin tooling is **web-only** (no mobile/watch twin) per §24 — back-office surfaces don't need a device mirror.

**Don't re-litigate** by adding a client-side `requireAdmin` guard *as the* boundary, by moving `is_admin` into `public`, or by relaxing any RPC's `42501` gate. If a takedown action is added later, it must be its own admin-gated RPC with its own audit trail. Pinned by `admin_moderation_test.sql` (admin-allowed vs non-admin/anon-DENIED on every RPC).

---

## 143. A coach assigns a training plan by deep-cloning one of their own into an athlete-owned plan; clone-not-subscribe, gated on the active link

**Decided (2026-06-12, migration `20270106_001`).** The coach-athlete link (§97) + consent-gated read (§98) let a coach *review* an athlete but not *give* them a plan. `assign_plan_to_athlete(source_plan, athlete, start_date)` closes that: a SECURITY DEFINER RPC that deep-clones one of the coach's own plans (or a club template they can read) into a new `training_plans` row **owned by the athlete** (`user_id = athlete_id`), date-shifted from `start_date`, mirroring the `clone_plan_template` precedent. A nullable `training_plans.assigned_by_coach_id` records provenance. Surfaced on `/coaching/athletes/[id]` when the athlete has no active plan.

**Why athlete-owned, clone-not-subscribe.** The assigned plan flows through the unchanged "users own their plans" RLS, the client-side auto-match, and every plan surface exactly like a self-created plan — the athlete can edit, complete, or abandon it, and later edits to the coach's source do **not** propagate (same call as §35 templates). The coach keeps the read + `plan_workouts`-edit access from `20261116_001` to keep tuning it. Consent is the `status='active'` link (the athlete redeemed the invite); ending the link blocks future assignments but leaves already-assigned plans with the athlete (it is their data).

**Trade-off.** The RPC **raises if the athlete already has an active plan** rather than silently abandoning the athlete's own plan — the coach coordinates with them first (the UI shows an explanatory note instead of the form). Web-only this slice (the whole `/coaching` roster is web-only per §24); the assigned plan reaches the athlete through the mobile plan surfaces that already exist, so no twin work. The athlete is notified on assign — a `plan_assigned` notification raised by a trigger on the assigned-plan insert (migration `20270107_001`, in-app/bell only). Coach-authored-directly-in-athlete-account (vs. clone-from-own) is deferred.

**Don't re-litigate** by adding an FK from `gym_workouts`/`runs` to the source plan (the link is provenance only), by letting the coach's source-plan edits propagate to assigned instances, or by auto-superseding the athlete's existing active plan. Pinned by `assign_plan_to_athlete_test.sql` (consent gate, ownership, deep-clone, self-assign, unreadable-source, active-plan conflict, ended-link revocation) + `tests-e2e/coaching/assign-plan.spec.ts`.

---

## 144. Plan generator v2 (adaptive rescheduling) ships as a trend-gated, suggestion-only layer over the shipped re-plan engine; the fitness-signal phase is CISO-gated

**Decided (2026-06-12, P1 shipped).** "Adaptive weekly rescheduling driven by adherence" (the last deferred training-engine item) ships as a thin pure layer, **not** a new engine. P1's `adaptiveReplanRemaining` (TS↔Dart parity pair `plan_adaptive_replan`) classifies the trailing 3 *completed* weeks' drift via the existing `weeklyDrift`, and only when a **sustained trend** (≥2 of 3 weeks flagged the same direction) is found does it delegate the actual future-only deltas to the shipped `replanRemaining`. So the new layer decides **whether + why**; the existing engine decides **what**. It reuses the existing preview-and-apply surface (web `/plans/[id]` + mobile `plan_detail_screen`) with a reason + confidence badge. No schema, no RPC, no fitness signal in P1.

**Why trend-gated over the existing manual re-plan.** The shipped "Re-plan remaining" acts on a single signal (a missed long run, last week over). The adaptive layer's whole value is **suppressing single-week noise** — it requires a 2-of-3 trend before nagging, so a one-off bad week doesn't trigger a plan rewrite. Same conservative discipline (past + taper frozen, never auto-mutates, only suggests) inherited from `replanRemaining`.

**The CISO gate.** P2 introduces fitness-gated direction (TSB/ATL/CTL from `training_load.ts`) — the first time health-derived load (HR/TRIMP) feeds a *training prescription*. Per the SOC 2 posture, **P2 must not reach prod users without CISO / Security-Analyst sign-off.** As of 2026-06-12 the P2 math is merged + wired on web (`/plans/[id]`), but the fitness input is passed **only behind `PUBLIC_ADAPTIVE_FITNESS_GATE` (off by default)** — so it is inert in prod (mirrors the paid-events "built but credential-gated before prod" pattern, §139). **Flipping that flag on for a prod build is the sign-off-gated action.** P3 (atomic multi-week reschedule RPC, needed only once a change re-indexes `plan_weeks` — i.e. P4 territory; premature before then, §"no preemptive abstractions") and P4 (date-shifts + deload insertion) are deferred. The mobile UI wiring of the fitness input follows web per §24.

**Don't re-litigate** by lowering the 2-of-3 trend bar (it's the noise filter), by letting the adaptive layer mutate past/taper weeks, by adding a fitness signal to P1's module, or by shipping P2 without the sign-off. The full phased design is in `reviews/plan-generator-v2.md`. Pinned by `plan_adaptive_replan.test.ts` ↔ `plan_adaptive_replan_test.dart` (7 each) + `tests-e2e/plans/adaptive-replan.spec.ts`.

---

## 145. Gym routines become shareable as club-scoped templates (membership-gated), NOT via a global `is_public` flag

**Decided (2026-06-12, migration `20270109_001`).** `gym_programming.md` deferred "public-routine sharing" because shipping a global `is_public` public-read branch *before* a browse UI exists lets any authenticated user enumerate every public routine's `notes` + planned sets through the REST API (a `public-rows` leak). The leak-safe subset ships now: a `gym_routines.club_id` makes a routine **club-owned**, readable only by club members via `private.is_club_member` (mirrors club-owned routes + session plans, §"clone_session_template"). Two SECURITY DEFINER RPCs do the work — `publish_gym_routine_as_template(routine, club)` (author + `private.is_club_admin` gated) deep-copies a personal routine into a new club-owned one; `clone_gym_routine_template(template)` (author-or-member gated) adopts it back into a personal copy. The global `is_public` + browse UI stays deferred.

**Why tighter than the session-planner publish.** `publishSessionAsTemplate` is a *client-side* insert whose RLS with-check only validates `author_id` — so a non-member author can set an arbitrary `club_id` and inject a template into a club they don't belong to (accepted there as a mild spam vector). The gym publish is a **server-side RPC that also requires `is_club_admin` of the target club**, closing that hole. Adopt mirrors `clone_session_template` exactly (rate-limited, deep-copy, nothing stripped — the published target loads ARE the template).

**Don't re-litigate** by adding a global `is_public` read branch to `gym_routines` without shipping the browse UI in the same migration (the original leak concern), or by relaxing the publish admin-gate back to the session-planner author-only shape. Pinned by `gym_routine_club_templates_test.sql` (13 tests) + `tests-e2e/gym/club-routine-template.spec.ts`.

---

## 146. The three reusable-plan engines share one create front door (`/plans/new` hub), but NOT one form or one club-create path

**Decided (2026-06-12, commit `2b45a10f`).** The product grew three independent "reusable plan" engines — training plans (`/plans/new`, weeks × runs × paces), session plans (yoga/pilates, `session_plans`, timed pose sequences), and gym routines (`gym_routines`, sets × reps × load) — each with its own create surface. Session-plan create was the worst: it lived only on `/sessions`, which had **no nav entry point at all** (URL-only). We consolidate the **entry point**, not the data model: `/plans/new` becomes a hub with a Training / Session / Gym-routine chooser that swaps in the matching editor (`PlanEditor` / `SessionPlanEditor` / `RoutineEditor`). The chooser shows on the bare entry; an explicit `?type=` skips it (so a contextual deep link doesn't ask the kind twice). `?club=<id>` targets a club. The club Templates tab exposes this as a single "Add template" button (`/plans/new?club=<id>`) — the user picks the kind in the hub — rather than three per-section buttons that would duplicate the hub's own 3-way choice.

**Why a chooser, not a merged form.** The three forms share almost no fields (a multi-week pace schedule vs. a single timed pose sequence vs. a sets×reps×load routine), so a single unified form would be worse, not better. The chooser gives one discoverable front door while keeping three correct editors underneath.

**The club-create asymmetry is deliberate.** Only the **session** branch creates a club-owned artifact in one step (`createSessionPlan(club_id)` — the client insert whose RLS with-check validates only `author_id`, the accepted mild-spam vector noted in §145). Training and gym club templates stay **build-then-publish** (`setPlanIsTemplate` / the admin-gated `publish_gym_routine_as_template` RPC) — `createTrainingPlan`/`createGymRoutine` have no one-step club create, and the generators are heavier. So `?club=` is honoured one-step for session, informational for the other two.

**Don't re-litigate** by trying to merge the three editors into one form, or by adding a one-step `club_id` create to training/gym without an admin-gated server path (would widen the §145 spam vector to two more engines). The standalone `/sessions` modal + `/gym/routines/new` routes stay as deep-link entry points. Pinned by `tests-e2e/plans/create-hub.spec.ts` + `tests-e2e/sessions/club-template-create.spec.ts`.

**Amendment (2026-06-14): the gym branch is now one-step too — via the admin-gated RPC, not a direct insert.** Picking "Gym routine" from a club's Templates tab previously created a *personal* routine and dropped the admin on `/gym/routines/<id>` with no club template produced — `?club=` was silently informational, so "add a gym template to my club" appeared not to work. `onGymCreated` now, when `clubId` is present, publishes the freshly-built routine to the club through the existing `publish_gym_routine_as_template` RPC (the same admin-checked, `SECURITY DEFINER` path the routine-detail "publish" button uses) and returns to the Templates tab — matching the session branch's one-step UX. This does **not** widen the §145 spam vector: the RPC verifies `is_club_admin`, unlike the session branch's direct client insert. The cost is a leftover personal source routine on the author's `/gym/routines` list (identical to how publishing a training plan leaves its source) — gym still has no club-admin INSERT policy, so a single-row club-owned create would need a new `create_club_gym_routine` RPC (deferred; the leftover-source cost is acceptable and consistent with training). Training stays build-then-publish (heavier generator, separate publish flow). Pinned by `tests-e2e/gym/club-routine-template-create.spec.ts`.

---

## 147. Cross-club activity discovery is one `security invoker` RPC scoped to public clubs, surfaced as a `/social` Discover tab

**Decided (2026-06-12, migration `20270110_001`).** Until now events were reachable only inside a club you already knew or belonged to (`fetchUpcomingEvents` is club-scoped) — there was no way to find "a paid pilates class on Sundays" or "a weekly group run" across clubs. Rather than a class-only search, discovery is **unified over the typed-events model**: one `search_public_events(query, category, cadence, byday, paid, limit)` RPC filters every `category` (run/cycle/class/social) by discipline (pg_trgm index on `events.discipline`), recurrence cadence, weekday (`recurrence_byday @> array[?]` for recurring, `starts_at` weekday for one-offs), and free/paid (presence of an `event_pricing` row). It surfaces as a 4th tab on `/social` (Feed · People · Clubs · **Discover**), mirroring where clubs + people discovery already live (anti-clutter: no new global nav item).

**Why `security invoker`, not `SECURITY DEFINER`.** Mirrors `search_clubs`: the RPC filters `clubs.is_public = true`, and the events RLS (`20260416_001`) already lets anyone read a public club's events, so the function can only ever return rows the caller could already see — no privileged path, works logged-out. A private club's events are structurally undiscoverable.

**Scope / deferred.** Ships category + discipline + cadence + weekday + free/paid + **time-of-day** (morning/afternoon/evening). The time-of-day filter required anchoring events to a timezone first: migration `20270111_001` adds `events.timezone` (IANA, captured from the organiser's browser at create time via `Intl.DateTimeFormat().resolvedOptions().timeZone`), and the RPC resolves the local hour via `starts_at AT TIME ZONE coalesce(events.timezone, 'UTC')` so "7pm" means the event's local 19:00, not the UTC instant — for a recurring series the anchor's local hour is the fixed weekly time (DST shifts the UTC instant, not the 19:00 intent). Legacy rows (null timezone) fall back to UTC. `events` is column-SELECT-locked, so the new column needed an explicit `grant select (timezone)` for the security-invoker RPC to read it as anon. **Geo/location filtering has now shipped (see amendment below).** Web-only; a mobile discovery surface is deferred. Pinned by `search_public_events_test.sql` (pgtap, 13 assertions: public-vs-private + each filter + local-hour vs UTC-hour + near/far proximity) + `tests-e2e/social/discover.spec.ts`.

**Amendment (2026-06-12, migration `20270112_001`): geo proximity shipped, filtered by the CLUB's location.** The deferred "near me / near a place" slice now ships: `search_public_events` takes `p_center_lng/p_center_lat/p_radius_m` (default 50km) and, when a center is supplied, gates on `ST_DWithin(clubs.location_point, center, radius)` and orders nearest-first, returning a `distance_m` for an "X away" label. The key privacy decision: it filters by the **club's** geocoded `clubs.location_point` (public, already geocoded by ClubEditor, GiST-indexed), **never** the event's `meet_lat/meet_lng` — those are deliberately revoked to members-only via `get_event_meet_point` (`20261027_001`) precisely so discovery can't scrape a class's exact studio/home address. A studio's classes are at the studio, so the club point is the right granularity anyway. Clubs with a null `location_point` are correctly excluded under an active "near me" (we can't place them) but still surface on every other filter. Reuses the `search_clubs` geocode → `ST_DWithin` pattern exactly; the web UI resolves a center via `geocodePlace` (typed place) or `navigator.geolocation` ("Use my location"). Location stays off `gym_workouts`/`session_plans` (a logged workout/template can happen anywhere).

**Don't re-litigate** by switching the RPC to `SECURITY DEFINER` (it would have to re-implement the public-club gate the RLS already enforces, for no gain), by filtering time-of-day in the *viewer's* timezone (a 19:00-New-York class must read as evening regardless of who's searching — the anchor is the event's local zone, not the searcher's), or by filtering proximity on the event's precise meet point (revoked by design for privacy — discovery is club-granularity).

---

## 148. Event-level visibility — a public club can mark an individual event members-only

**Decided (2026-06-12, migration `20270113_001`).** Event visibility used to be inherited entirely from the parent club (`20260416_001`): an event was readable iff its club was (`is_public OR owner OR member`). A **private** club's events were therefore already members-only — but a **public** club had no way to hide an individual event (a committee meeting, a members-only social, a draft) from the world, and since cross-club discovery shipped (§147) every public-club event was globally discoverable. Added `events.is_public` (boolean, default `true` → preserves prior behaviour) and an event-level gate.

**One source of truth, inheritance for the rest.** The tightening lives in the single `events` SELECT policy: `<club gate> AND (events.is_public OR is_club_member(club_id))`. `is_club_member` covers owner + admins + members (the owner is enrolled as an `owner` `club_members` row by `enroll_club_owner`). Every other event-delegating surface — `event_attendees` (read + self-RSVP insert), `event_results`, `race_pings`, `run_photos` (table + storage bytes), the event photo gallery — already gates via an `exists (… from events …)` subquery, so the caller's RLS on `events` is applied inside that subquery and they **inherit** the change automatically. Two surfaces needed explicit fixes because they bypass that inheritance: event-tied `club_posts` (its SELECT checks the club only — re-gated so an event-tied post inherits event visibility) and `is_event_visible` (the `SECURITY DEFINER` helper backing the `event_pricing` SELECT policy — `SECURITY DEFINER` strips the caller's RLS, so it was leaking a members-only event's pricing to non-members; recreated to mirror the event-level gate). `search_public_events` adds an explicit `is_public = true` filter (defence-in-depth + it keeps a *member's* own private events out of global discovery, which is the right discovery semantic). `get_event_meet_point` was already gated on `is_club_member`, which is correct for a private event unchanged.

**Why a boolean, not inheritance-only or a visibility enum.** Mirrors `clubs.is_public` exactly (least surprise); the private-club case is already handled by the club gate, so the flag only changes the public-club case. A three-state enum (public / members / draft) was considered and rejected as premature — `is_public=false` already expresses "members-only", and a draft state has no requester. Default `true` means every existing row and every client that doesn't set it stays public.

**Trade-off / surface.** The change touches the security-critical RLS layer, so it's pinned by `rls_events_test.sql` (23 pgtap assertions: non-member/anon hidden, member/owner visible, attendees + event-tied posts + pricing all hidden from non-members, discovery exclusion) + the web e2e (`event-visibility.spec.ts`). Web exposes a "Members only" toggle in `EventEditor` (shown only for a public club) + a badge on the detail page; mobile mirrors both — the `event_form_sheet` create toggle (gated on the club being public, via `buildCreateEventBody`'s `is_public`) and the detail-page badge. **Per SOC 2 / GovRAMP this RLS change wants CISO sign-off before a production deploy.**

**Don't re-litigate** by moving the gate out of the single `events` SELECT policy into each delegating surface (the `exists(… from events …)` inheritance is the whole point — duplicating the predicate is how they'd drift), or by assuming a new event-delegating surface inherits for free if it's `SECURITY DEFINER` (it won't — `is_event_visible` is the cautionary tale; a definer helper must re-implement the event-level gate explicitly).

---

## 149. The mobile dashboard computes ONE training-load series and feeds it to every consumer

**Decided (2026-06-13, perf-hunt).** `dashboard_screen.dart` rendered three surfaces off training load — `FitnessCard` (CTL/ATL/TSB + recovery advice), `ReadinessCard` (TSB), and `TrainingLoadChart` (the plotted curve) — and each independently called `computeTrainingLoadSeries(...)` in its own `build()`. Two problems: (1) **perf** — the O(runs) aggregation (two full passes + a 216-iteration EWMA walk) ran 3–4× per dashboard build, on the full track-less `summaryRuns`, re-run on every unrelated store/preference rebuild; (2) **correctness** — the chart passed `lifts: _readinessLifts()` while the two cards passed **no lifts**, so for any gym user (opt-out off) the headline fitness/fatigue/form number and the recovery advice silently disagreed with the curve right beside them, violating the cards' own "can't disagree with the displayed form" contract.

**Fix.** The dashboard `State` exposes `_trainingLoadSeries(runs, now)` — the single series, computed with `_readinessLifts()` (which already honours the `exclude_gym_from_readiness` opt-out, §134). `build()` computes it once and threads the instance into `FitnessCard`, `ReadinessCard`, and the chart via an optional `loadSeries` param; the cards read `loadSeries.last` instead of recomputing. The param is optional so standalone callers (widget tests) still self-compute a run-only series.

**Trade-off / behaviour change.** This is the deliberate part: a gym user with the opt-out OFF now sees lift load reflected in the Fitness + Readiness cards (previously run-only there, lift-inclusive only on the chart). That's the documented intent — the cards are *supposed* to match the chart — so it's a bug fix, not a new feature, but it does move the displayed CTL/ATL/TSB for those users. Pure run-only readiness is still one toggle away (`exclude_gym_from_readiness`). Pinned by `fitness_card_test.dart` (the card honours an injected `loadSeries` over a self-recompute). Cross-build memoisation (skipping the recompute when nothing changed) was left out — `now` changes every build and `summaryRuns` has no stable identity, so it'd need a run-store revision counter; the per-build single-compute already removes the dominant 3–4× waste.

**Don't re-litigate** by reintroducing a per-card `computeTrainingLoadSeries` call — the whole point is one series, one lift decision, one source of truth shared by the number, the advice, and the curve.

---

## 150. A legal / CISO / counsel sign-off is a pre-prod deploy gate, not a reason to leave code unwritten

**Decided (2026-06-13, owner directive).** Several features in the docs were parked as "blocked on owner+CISO+counsel sign-off" (Stripe Connect payouts, Art 9 health-data consent flows, privacy-boundary changes, GDPR retention). That gating was being read as "don't write the code yet," which left half-built or stubbed surfaces and a growing followups backlog of *code* that was actually only waiting on a *review*. The owner clarified the intended model: **write all the code; the sign-off gates the production deploy, not the keyboard.**

**Policy.** Build the complete code path — privacy/consent/payout logic, tests, docs — and land it on `main` behind a **fail-closed** gate (a default-off feature flag, an unset live secret/key, a dev-only bypass). Counsel/CISO then review *shipped code*, which is more reviewable than a description of intent, and the sign-off becomes a line on the pre-deploy checklist (flip the flag / set the live key), not a `- [ ]` "blocked on legal" follow-up. The gate must live in **config**, never in missing code, and must keep the feature unreachable by real users until the sign-off lands.

**Trade-off.** Code for not-yet-approved features sits on `main` ahead of its legal clearance. That's acceptable *because* the fail-closed gate makes it inert in prod, and it's strictly better than the alternative (un-reviewable intent + drifting stubs). It does mean reviewers must trust the gate — so the gate's default-off/unset state is itself something tests pin (e.g. paywall + Stripe-key + flag guards).

**Boundary.** This does **not** dissolve genuine external blockers: a missing third-party credential/account (Garmin OAuth approval, a Firebase project, a RunSignUp key) or on-device/hardware/real-fixture validation still gates *going live*. The rule there is the same in spirit — write every line that doesn't require the secret, behind the same fail-closed gate, so only the credential/validation remains.

**Don't re-litigate** by re-parking codeable work as "blocked on legal" in followups. If a session finds a compliance-gated feature unbuilt, the default is to build it behind the gate, not to defer it. Recorded in `CLAUDE.md § Compliance sign-offs gate prod, not code`.

---

## 151. AI route descriptions are an L4 enhancement over a templated baseline, never a standalone LLM feature

**Decided (2026-06-14, commits on `feat/ai-route-description`).** A route's detail page can describe the route in prose. The obvious build is "call an LLM with the route's stats." Instead the feature is two layers: a pure templated describer (`route_description.ts` / `.dart` twin — `describeRoute` buckets distance band, surface, m/km elevation character, and loop-vs-point-to-point shape into structured parts; `localisedTemplate` renders them in the viewer's locale + units) is the **always-works L1 baseline**, and the LLM call (`/api/coach/route-describe` → `claude-opus-4-8`, adaptive thinking) is a **strictly-additive L4 enhancement** that only ever *replaces* the baseline text on success.

**Why.** Three reasons. (1) *Layered resilience* — the run-recording contract that a higher-layer failure can't break a lower one applies here too: a free user, an unset `ANTHROPIC_API_KEY`, a model error, a `stop_reason:'refusal'`, an empty completion, or a timeout all degrade to the templated text, so the affordance never shows a blank box or a hard error. (2) *Cost + paywall* — the LLM path is a Pro perk gated server-side on `is_pro()` (fail-closed), so free users still get a useful description with zero model spend, and the gate can't be bypassed from devtools. (3) *Grounding* — the model is handed the verified templated facts and told to stay strictly within them, so it embellishes phrasing without inventing landmarks or scenery the app doesn't know about.

**Trade-off.** The templated sentence is plain (a structured i18n template, not natural per-locale grammar), and the AI text isn't persisted (it's regenerated per view, not saved to `routes.description`). Both are acceptable: the baseline reads fine, and not persisting keeps the write path and a not-yet-built owner "save this" affordance out of scope. The endpoint reuses the coach Lambda's transport + the dev `+server.ts` bypass gates rather than standing up a new function.

**Boundary / not-yet-done.** The mobile route-detail *UI* doesn't wire the affordance yet — only the `route_description` Dart twin exists (for parity + a future mobile surface). Persisting an owner-chosen description and an "out-and-back" shape distinct from "loop" (the stored waypoints can't tell them apart) are deferred.

**Don't re-litigate** by adding a raw "just call the LLM" describe path with no templated fallback, or by moving the paywall gate client-side. The gate is server-side and the fallback is the floor.

---

## 152. Route course markers are their own table with server-derived position and a redacting viewer RPC

**Decided (2026-06-14, migration `20270129_001_route_markers.sql`).** A route can be annotated with course markers (aid stations, cut-offs, crew access, hazards, notes, climbs). Two shape choices: (1) markers live in their own `route_markers` table rather than as a field on `routes.waypoints`; (2) a marker's `position_m` (distance along the route) is **derived server-side** from the existing `routes.geom` LineString via a trigger (`ST_LineLocatePoint × ST_Length`), not computed client-side; (3) the canonical display read is a SECURITY DEFINER RPC `route_markers_for_viewer` that redacts in-privacy-zone markers for non-owners.

**Why.** (1) A separate table gives each marker its own RLS, index, and a future per-marker photo without bloating the bulk `waypoints` UPDATE — and mirrors the `route_photos` precedent. (2) Server-deriving position means the client can't drift from the geometry and a stale client can't write a wrong distance; the trigger reuses the same `geom` column the spatial queries already maintain. (3) Markers follow route visibility, but a public course must not leak a pin dropped at the owner's home — so the read path mirrors `clip_route_for_viewer` (decisions §33): the RPC loads the owner's privacy zones and drops any marker inside one for a non-owner, fail-closed. Base-table RLS (`private.is_route_visible_to`) stays as defence in depth.

**Trade-off.** Two reads on the detail page (route + markers RPC) instead of one inlined column. Acceptable — the markers list is a distinct surface and the RPC keeps the redaction server-side where the zones live.

**Boundary / not-yet-done.** Club-defined custom marker kinds (a `club_marker_kinds` catalogue + `route_markers.club_marker_kind_id`) are specced but not built; markers can only be placed on the detail page (not the `/routes/new` builder) since they attach to a saved line. See [route_markers.md](../features/route_markers.md).

---

## 153. The race roadbook allocates goal time by grade-adjusted effort and shares via URL params, not a schema

**Decided (2026-06-14, `roadbook.ts`/`.dart` + `/routes/[id]/roadbook`).** The roadbook turns a route's markers + a goal finish time into a per-checkpoint crew sheet (projected arrival, cutoff margin). Two choices: (1) goal time is allocated across legs by **grade-adjusted effort** (`gradeFactor`, Minetti) by default — climbs get proportionally more time — not by even pace; (2) the runner's goal/start/pacing-model live in the **page's URL query params**, with **no persistence layer** (no `race_plans` table) in v1.

**Why.** (1) Even splits are wrong on vert-heavy ultra courses — the differentiator over Strava/Garmin is an effort-honest schedule, and the app already had the Minetti model (decisions §107) sitting unused for this. It degrades cleanly to even pace when a route has no elevation (and the UI backfills vert from Open-Meteo on demand). (2) The headline use case is "send crew a link and they see the same sheet" — URL params deliver that with zero schema, RLS, or a management UI, and the page is print-friendly + copy-as-text for a crew chat. Saving named plans is a clean follow-up once the engine + UI are proven.

**Trade-off.** A roadbook isn't saved — reopening needs the link (or re-entering the goal). Acceptable for v1; the `race_plans` table is the deferred next phase. Effort allocation assumes the runner *targets* even effort, which most pacing strategies approximate; a fade/positive-split model is a later refinement.

**Boundary / not-yet-done.** Saved named race plans, a fueling column (carbs/hr synced to aid stations via the nutrition engine), a Riegel-seeded default goal + confidence badge, and GPX/FIT waypoint export to the watch are all deferred. See [race_roadbook.md](../features/race_roadbook.md).

---

## 154. Offline checkpoint check-in is account-optional with merge-in/out conflict resolution in one SECURITY DEFINER RPC; Art 9 weigh-in built fail-closed

**Decided (2026-06-14, migration `20270201_001`).** Race-director operations (aid-station volunteers stamping each runner in/out → live results + cutoff board) is built on two tables — `event_checkpoints` + `checkpoint_crossings` — with three load-bearing choices. (1) A crossing's identity is **account-optional**, mirroring `event_results`: `user_id` OR `bib` + `runner_name`, never fully anonymous (CHECK + two NULLs-distinct UNIQUE keys). (2) Offline conflict resolution is **merge in/out**, not last-write-wins, performed inside a single `upsert_checkpoint_crossing` SECURITY DEFINER RPC that is the SOLE writer (no direct-write RLS policy): a second call for the same `(checkpoint, instance, identity)` reconciles to ONE row with `in_time = least(existing, new)`, `out_time = greatest(existing, new)`. (3) The P3 weigh-in / medical fields are Art 9 health data **built now but fail-closed** per §150 — they persist only when the checkpoint's `requires_weigh_in` is true AND the caller passes `p_health_consent`, the columns are SELECT-locked from anon/authenticated, and organisers read them only through `fetch_checkpoint_crossings_for_organiser`.

**Why.** (1) Most ultra fields are bib-on-paper, not app accounts — requiring an account would make the volunteer surface useless; `event_results` already proved the account-optional shape. (2) Two volunteers on two phones with no signal each mint a UUID for the same runner; last-write-wins would lose an in_time or an out_time, while `least`/`greatest` (which ignore NULLs) give earliest-in / latest-out / fill-the-gap for free, and putting it in one SECURITY DEFINER writer means the merge can never be bypassed by a raw table write. (3) §150 says build the code behind a fail-closed gate rather than stub it — so the weigh-in path is complete and tested, and only the prod flip waits on owner + CISO + counsel. Cutoff projection reuses the one `checkpoint_projection` helper shared with the roadbook (§153) and the predictive tracker, grading on `roadbook.ts`'s scale so "tight" means the same thing everywhere.

**Trade-off.** Merge-in/out can't represent a genuine double-pass (a runner who legitimately re-enters a checkpoint) — out-and-back loops needing that would need a per-pass key; not a P1 concern. The single-writer RPC means no bulk `COPY` import path for crossings yet. Health data behind a deploy-time sign-off means the weigh-in UI ships dark until counsel clears it.

**Boundary / not-yet-done.** The P2 organiser live board, P4 public results page, the offline `local_crossings_store` drain, and grade-adjusting the projected remaining legs are tracked in [race_director_ops.md](../features/race_director_ops.md).

---

## 155. The race fueling plan extends the roadbook engine with flat per-hour rate prefs, not weight-derived sweat estimates

**Decided (2026-06-14, `fuel_plan.ts`/`.dart` + the Fueling toggle on `/routes/[id]/roadbook`).** The fueling layer is the deferred half of the roadbook (§153). Four choices. (1) It **reuses the roadbook engine** rather than forking one: `buildFuelPlan` consumes the roadbook's already-allocated per-leg durations and scales carbs + fluid onto each leg from a per-hour rate, so fuelling inherits the grade-adjusted-effort allocation (a long climb leg gets proportionally more carbs/fluid) for free, plus a `carryToNextAid` roll-up per refill checkpoint. (2) Rates are **flat per-hour prefs** — `carbs_per_hour` (60 g/hr) + `fluid_per_hour` (500 ml/hr) in the universal settings bag — **not** weight-derived sweat-rate / ml-per-kg estimates, deliberately keeping the feature out of the Art 9 health-special-category consent gate (a per-hour strategy number is an effort label, not a body measurement, like `nutrition_activity_level`). (3) **Heat is a non-persisted multiplier** (`HEAT_FLUID_FACTOR` = 1.5, fluid only) — a screen/URL toggle, not a stored pref, so the saved baseline stays moderate-conditions. (4) kcal per leg is **computed but not shown** (via `runCalories` only when a bodyweight is present) — kept in the model for a later surface but omitted from the UI to avoid clutter.

**Why.** Forking a second pacing model would have duplicated the effort-allocation logic and let the two drift; scaling onto the roadbook's existing leg durations is the single-source-of-truth path. The flat-rate choice is the §150 fail-closed instinct applied to scope: a weight-based sweat model is a genuinely better number but drags in consent plumbing for a v1 that crews can use today, so the durable-but-gated weight model is the deferred upgrade, not a blocker. Heat-as-toggle matches how a runner actually reasons ("it's hot today, carry more") without polluting the persisted plan.

**Trade-off.** Flat per-hour rates ignore body mass and individual sweat rate, so the fluid figure is a planning baseline, not a physiological prescription. No in-run execution: the plan is read off the roadbook, not pushed to the recorder.

**Boundary / not-yet-done.** In-run fueling reminders are a deferred separate phase — they need the run recorder + the live workout band (`workout_execution_band.dart`) and so ship later; weight-derived fluid (behind the Art 9 gate) and surfacing the computed kcal are the other follow-ups. See [race_fueling_plan.md](../features/race_fueling_plan.md).

---

## 156. Predictive live tracking reuses the roadbook cut-off legs and fails to `unknown` when the fix is stale

**Decided (2026-06-14, `live_cutoff_eta.ts`/`.dart` + the next-cut-off card on `/live/[id]` + `live_spectator_screen.dart`).** The spectator personas (Moab 240 / UTMB / WS100 families following from home) don't want a dot — they want *"is my person going to make the next cut-off?"*. The card fuses three already-shipped pieces rather than adding a model or schema: (1) it projects the live runner onto the planned line with `distanceAlongRoute` (the nearest-point inverse added to the `route_geometry` pair), (2) it reads the cut-off **limits** straight off the roadbook legs (`buildRoadbook` — the limit is independent of the goal time used to build them, so any nominal goal works), and (3) `nextCutoffEta` grades the projected arrival (current elapsed + remaining distance ÷ recent pace) against that limit on the same `safe/tight/miss`→`on/tight/behind` scale as `checkpoint_projection`. Pace is **recent flat pace** (last ~5 pings); grade-adjusting the remaining legs is deferred exactly as it is on `checkpoint_projection`. No schema — all reads, works logged-out.

**Why.** The honest-staleness rule is the load-bearing decision. The live feed already had to learn that a lost-signal runner must read *stale*, not a fresh green dot (§the `live_freshness` pair). A predictive ETA amplifies that risk: projecting an arrival off an 18 h-old fix would manufacture confidence exactly where the spectator is most anxious. So `nextCutoffEta` returns `status: 'unknown'` whenever the fix is stale **or** pace is unknown — the card still names the checkpoint + distance but suppresses the verdict and shows "waiting for a fresh signal". Reusing the roadbook legs (not a parallel cut-off model) keeps one source of truth for "what counts as a cut-off / tight", the same instinct as `checkpoint_projection` re-importing `CUTOFF_TIGHT_S` from `roadbook`.

**Trade-off.** Flat recent pace over-/under-shoots on a big climb or descent ahead (grade-adjusted remaining would be better — deferred). The card only appears when the run is linked to a **public** route that carries cut-off markers, so a private route or a markerless route shows nothing; that is the correct fail-closed default (no route context → no claim) but means the feature lights up only for organised races with a marked course.

**Boundary / not-yet-done.** Grade-adjusted remaining pace, an EWMA pace window, and surfacing the projection on the organiser board (it already shares `checkpoint_projection`) are the follow-ups. See [predictive_live_tracking.md](../features/predictive_live_tracking.md) + the spectator flow in [flows.md](../features/flows.md#predictive-next-cut-off-will-they-make-it).

---

## 157. Avatar upload uses the public `avatars` bucket with owner-scoped writes + an owner SELECT policy; remove-then-insert, not upsert

**Decided (2026-06-16, `data.ts uploadAvatar`/`removeAvatar` + `/settings/account` avatar control + migration `20270203_001`).** The `avatars` Storage bucket had existed since `20260927_001` (public, 2 MB, image-MIME-only, owner INSERT/UPDATE/DELETE) — created so `delete-account` had something to sweep — but nothing ever *wrote* to it: `user_profiles.avatar_url` was populated only from OAuth `identity_data` at sign-up, and `/settings/account` had no avatar control. This adds the missing in-app path. The bucket stays **public** (not signed-URL like run/route photos) because an avatar is public profile data: it renders on the logged-out `/u/[id]` profile, on share pages, and on the spectator live view as a bare `<img src={avatar_url}>`, and a public object URL is the only value that satisfies the existing `avatar_url ~* '^https?://'` CHECK (`20260808_001`) for owner **and** anonymous viewers without per-view signing.

**Why remove-then-insert, not upsert.** A profile picture wants a stable path so the URL is predictable. The obvious `upload(..., { upsert: true })` is rejected by the bucket's RLS — Supabase's upsert path also requires the UPDATE policy's WITH-CHECK, which this bucket grants differently; a plain INSERT onto a freshly-cleared path is the write that passes. So `uploadAvatar` removes every `{uid}/avatar.{ext}` first, then does a clean INSERT, and a `?v=<ts>` cache-bust on the (stable) URL keeps an `<img>` off the previous picture. EXIF/GPS is stripped client-side via the existing `stripExifFromFile` before the upload — the bucket has no server-side strip worker, so on a public bucket the client strip is the only thing standing between a geotagged selfie and a world-readable GPS leak (same rationale as the run-photos pre-upload strip).

**The non-obvious gap this surfaced.** The bucket shipped with no SELECT policy — the original reasoning (in `storage_bucket_privacy_test.sql`) was that a public bucket serves downloads via the CDN bypass, so a SELECT policy would be "dead code." That's true for the `/object/public/...` *download* path, but the authenticated Storage `.list()` and `.remove()` operations query `storage.objects` under RLS — so without a SELECT policy an owner can neither enumerate nor delete their own avatar: `.remove()` silently no-ops and a re-upload then collides with the stale object. Migration `20270203_001` adds an **owner-scoped** SELECT policy (`auth.uid() = foldername[1]`, not a bare `bucket_id` check that would leak every user's avatar rows), and the pgtap pin was inverted from "MUST have NO SELECT policy" to "MUST have exactly one owner-scoped SELECT policy."

**Boundary / not-yet-done.** Shipped web + mobile (Android/iOS byte-identical twin): web's `/settings/account` avatar control and the mobile Profile-photo tile both go through the same data-layer shape (`data.ts uploadAvatar`/`removeAvatar` ↔ `ApiClient.uploadAvatar`/`removeAvatar`), stripping EXIF client-side and remove-then-inserting. EXIF strip covers JPEG (the format that carries camera GPS); PNG/WebP pass through. No image resizing/cropping — the 2 MB cap + native `<img>` / `Image` scaling stand in. Pinned by `tests-e2e/settings/avatar-upload.spec.ts` (web: upload → owner + cross-user render → EXIF-stripped JPEG → remove) + `test/settings_account_avatar_test.dart` (mobile widget).

---

## 158. The block gate on kudos / comment INSERT resolves the run owner in a SECURITY DEFINER predicate, not an RLS-visible subquery

**Decided (2026-06-16, migration `20270204_001` + `block_kudos_comment_gate_test.sql`).** The `run_kudos` / `run_comments` INSERT policies added in `20261012_001` (the user-blocks self-defence primitive — persona-hunt Round 3 finding Woman #1) gated the write with `not is_blocked_either_way(auth.uid(), (select r.user_id from runs r where r.id = run_id))`. That owner subquery runs under the INSERTing user's RLS on `runs`, and since `20260701_001` dropped the public-runs SELECT policy on the base table (public reads go through the `public_runs` view), a kudoser/commenter can only see their **own** runs — so for anyone else's run (the only run you ever kudos or comment on) the subquery returns `NULL`, `not is_blocked_either_way(actor, NULL)` is always `true`, and the block predicate was satisfied for every cross-user write. The block silently failed to stop the exact harassment vector — kudos/comment notifications — it was built to stop, in both directions.

**Why this fix.** It mirrors how `20260812_001` already solved "the actor can't see the run row under RLS" for the visibility check: resolve the owner inside a SECURITY DEFINER predicate (`private.is_blocked_for_run(actor, run_id)`) that joins `runs`→`user_blocks` in definer context, so the block check sees the real owner regardless of the caller's RLS-restricted view of `runs`. The other `is_blocked_either_way` call sites were already correct — `user_follows` / `direct_messages` evaluate it against columns on the inserted row, and `search_segment_leaderboard` / `public_profile_by_id` run in definer context — so only the two engagement-write policies needed the change.

**Trade-off / boundary.** Found by an e2e journey (`tests-e2e/social/follow-engage-block-journey.spec.ts`) that drove a post-block kudos write through a real user JWT and expected the RLS denial. The bug shipped because `20261012_001`'s own pgtap (`user_blocks_test.sql`) pinned the follow-INSERT block path but never the kudos/comment one — the lesson restated in the backend `CLAUDE.md` "drop policy" gotchas: pin the *write* you're gating, against a real JWT, not just the helper. The read side is unchanged (a block is still a write/profile-unfurl gate, not a content-hide, as `20261012_001`'s comment notes); this fix only restores the write denial.

---

## 159. Derived-count trigger functions must be SECURITY DEFINER or a club owner can't delete their account (Art-17 erasure)

**Decided (2026-06-16, migration `20270205_001` + `club_owner_account_deletion_test.sql`).** `clubs_member_count_trigger()` — the AFTER INSERT/UPDATE/DELETE trigger on `club_members` that maintains `clubs.member_count` — was the lone derived-count trigger written `SECURITY INVOKER`; its siblings (`routes_run_count_trigger`, `refresh_personal_records_for_user`) are `SECURITY DEFINER`. That asymmetry made **any club owner undeletable**: GoTrue's `admin.deleteUser` (what the `delete-account` Edge Function calls) runs the `auth.users` delete as the `supabase_auth_admin` role, the `ON DELETE CASCADE` strips the owner's `club_members` row, and the trigger's `update clubs set member_count = …` then runs as `supabase_auth_admin` — which has no UPDATE privilege on `public.clubs`. The UPDATE raises permission-denied, GoTrue returns the generic "Database error deleting user", and the EF 500s. A GDPR Art-17 erasure failure for a whole class of users.

**Why it stayed hidden.** A superuser delete — `supabase db reset`, raw `psql DELETE FROM auth.users` — cascades fine, because the privilege gap only bites under the `supabase_auth_admin` role GoTrue actually uses. So schema-drift checks, local resets, and even the e2e saga fixture (`saga-users.ts` pre-deletes owned clubs in `OWNER_TABLES` before the auth delete) all sailed past it. It surfaced only when an e2e journey (`tests-e2e/cross-cutting/account-data-rights-journey.spec.ts`) drove the real delete-account EF for a club-owning user and got a 500.

**The rule.** Any trigger that writes a table during a cascade reachable from `auth.users` deletion must be `SECURITY DEFINER` (with a pinned `search_path`), so the cascade write runs as the function owner regardless of which role drives the delete — never `SECURITY INVOKER`. When adding a derived-state/count trigger, match the existing DEFINER siblings. pgtap can't assume the `supabase_auth_admin` role, so the regression is pinned at two layers: the `prosecdef = true` attribute (cheap, catches a revert) plus the full delete-account path in the web e2e journey.

---

## 160. Saved routes are read by id from the `public_routes` view, not embedded off `saved_routes`, so a bookmarked public route actually shows in My routes

**Decided (2026-06-16, `fetchRoutesWithError` in `core/data.ts`).** My routes (`/routes` "My routes" tab) is the union of the caller's owned routes and their bookmarked (`saved_routes`) routes. It used a PostgREST embed — `saved_routes.select('saved_at, route:routes(*)')` — which resolves the route body through the **base `routes` table** under the caller's RLS. But the base `routes` SELECT policy only exposes the caller's **own + club** routes (public routes are read through the `public_routes` view + `clip_route_for_viewer`, mirroring the runs pattern from `20260701_001`). So a route the user bookmarked from **Explore** — i.e. another user's *public* route, which is the entire point of bookmarking — embedded to `null` and silently vanished from My routes. The bookmark feature was effectively dead for its primary use case; only a self-bookmark or a club route ever rendered.

**Why this fix, not a base-table policy.** Adding a "public routes are selectable" policy to the base `routes` table would make the saved embed work, but it would also expose `routes.waypoints` (the full geometry) to every viewer, bypassing the `clip_route_for_viewer` privacy-clipping the view/RPC split exists to enforce. So the fix stays client-side: fetch the saved `route_id`s, then read their bodies **by id from the `public_routes` view** (public-route metadata — enough to render a My-routes card; waypoints stay behind the clip path) **unioned with the base table** (for own / club-visible saved routes), preferring the fuller base-table row. Found + pinned by `tests-e2e/routes/route-discover-save-review-journey.spec.ts` (a cross-user discover → save → review journey). Web-only — mobile has no `saved_routes` read path.

## 169. Turn-by-turn voice cues use a self-contained geometric generator over the route polyline, not an external routing engine

**Decided (2026-06-19, trail navigation slice — `turn_cues.ts` ↔ `turn_cues.dart`, `trail_navigation.md` open question #1).** Spoken "in 200 m, turn left" cues are derived **purely from the saved route's polyline geometry** — the bearing change at each interior vertex, thresholded to suppress GPS/drawing noise, near-coincident vertices merged — by the `turn_cues` parity helper (`generateTurnCues`), consumed mobile-side by the pure `TurnCueAnnouncer` decision core and spoken through the existing best-effort `audio_cues` TTS path.

**Why the geometric generator, not OSRM or a nav SDK.** Three options were on the table: (a) the pure geometric generator; (b) reuse the OSRM client already in the route builder (`routing.dart`/`routing.ts`) to get named-road `steps`; (c) a dedicated nav SDK (Mapbox Nav / Valhalla / GraphHopper). We chose **(a)** as the shipping baseline because it is the only one that satisfies the L1 "basics always work" contract for the headline use case — a runner following a saved line on trail **with no signal**: zero dependency, zero network at cue time, no API key, works on any route. The cost is that it announces *geometric* bends ("turn left"), not road/trail-name-aware instructions ("turn onto Oak St"). **(b)** was rejected as the baseline because it needs connectivity at cue-generation time (it could be a later additive enhancement that pre-computes named-road cues at pin time and caches them on disk, falling back to (a) offline — the helper is structured so it can later *consume* an engine's step list while the generator stays the offline fallback). **(c)** was rejected for the dependency + key + cost it adds for marginal benefit on a follow-a-known-line feature. **Layered resilience:** the cue is an L4 auxiliary effect — wrapped in the same `_ttsCue` try/catch as split/off-route cues, gated on a `Preferences.turnByTurnCues` device toggle (default on with audio cues), and never able to disturb the recording / L0 clock / L1 distance.

## 170. Offline tile packs are a sibling on-disk cache (eviction-resistant), not LRU-evicted and not in Supabase

**Decided (2026-06-19, trail navigation slice — `offline_tile_pack.dart` + `tile_pack` parity helper).** "Save for offline" on a route now downloads the map tiles covering the route's bounding box (slippy-map `{z}/{x}/{y}` across the live map's zoom band) to `${cacheRoot}/offline_packs/<routeId>/` — a **sibling** directory of the general LRU tile cache (`map_tiles`), so a pinned pack is **never LRU-evicted** out from under a runner heading offline. Removing the offline pin deletes the pack dir. The live map reads through the pack first for a followed route (`OfflinePackTileProvider`), then falls through to the network/LRU path.

**Why a sibling on-disk cache, not the LRU cache or Supabase.** The whole point of an offline pin is durability — the existing `map_tiles` LRU cache (`tile_cache.dart`, 500 MB budget, oldest-mtime eviction) can drop a pinned route's tiles the next time the user explores elsewhere, which is exactly the failure the feature exists to prevent. So packs live outside the LRU budget, deleted only on un-pin. Tiles are **not** stored in Supabase — they're third-party raster tiles, an on-disk cache concern (extending the §64 offline-pin reasoning), not user data. **Caps, fail-closed:** the pure `tilesForBbox` enforces a per-pack tile ceiling (`kMaxTilesPerPack` = 5000, z12–z16) so a pathological bbox can't silently download gigabytes (status `tooLarge`, no download); each tile fetch is its own try/catch (L4) so a failed tile is skipped and the pack completes **partially** ("N of M cached, retry") rather than aborting — a partial/failed pack never breaks the online map. **Tile-licensing gate:** bulk-persisting prod MapTiler tiles for offline use must be confirmed against MapTiler's ToS before this ships to prod with the prod tile source; if disallowed, the offline pack uses the self-hosted Protomaps/PMTiles path (`protomaps_local_setup.md`). The code is source-agnostic (it caches whatever `currentTileUrl()` resolves), so this is a deploy-time config gate, not a code change.

## 171. `route_conditions` is a `route_reviews`-shaped own table with a privacy-zone-redacting `_for_viewer` RPC

**Decided (2026-06-19, migration `20270215_001_route_conditions.sql`).** Community condition reports ("creek crossing flooded", "trail closed", "ice on the north face") are an **own table** mirroring `route_reviews` (not a `routes.*` jsonb field, not the owner-only `route_markers` shape): each report gets its own RLS, a `(route_id, created_at desc)` freshness index, a narrow `condition` + `severity` union (CHECK + TS unions `RouteConditionKind`/`RouteConditionSeverity` + the `check_constraint_unions.mjs` PAIRS guard), and an **optional** anchor (`lat`/`lng`) whose `position_m` (distance along the route) is derived server-side by trigger.

**Why this shape + the redacting RPC.** Reports follow the route's visibility: the **visibility-gated INSERT** (`auth.uid() = user_id and exists (select 1 from routes where routes.id = route_conditions.route_id)`, picking up `routes` RLS) lets **any signed-in viewer** of a route file a report — not just the owner, which is the entire point of a community condition layer. DELETE is the author **or** the route owner (spam cleanup on one's own route). The canonical read goes through `route_conditions_for_viewer(p_route_id)` (SECURITY DEFINER), which gates visibility and **nulls the lat/lng/position_m of any anchored report inside one of the route owner's privacy zones for a non-owner viewer** — the condition analogue of `route_markers_for_viewer` / `clip_track_for_user` (§33), so a public course can't leak a pin dropped at the owner's home. The client read (`fetchRouteConditions` web + `ApiClient.fetchRouteConditions` mobile) **fails closed to `[]`** on RPC error so a redaction failure never leaks. This is a privacy-boundary surface — flag it for the privacy reviewer at PR time (`/audit/privacy-zones`); the review is a pre-deploy gate, not a reason to stub. **Freshness policy:** reports are never auto-expired; the UI fades a report older than 30 days and the reporter/owner can delete.

---

## 161. Learn guides are repo-committed markdown/MDsvex prerendered to static HTML, not a DB-backed CMS

**Decided (2026-06-19, `apps/web/src/lib/learn/`, `learn_pages.md`).** The public Learn surface (`/learn` hub + `/learn/<slug>` articles + `/learn/category/<id>`) authors each guide as a `.md` file with YAML frontmatter under `src/lib/learn/guides/`, indexed at build time by `import.meta.glob` and compiled by the already-wired mdsvex preprocessor. Every Learn route sets `prerender = true` (+ `entries()` over the guide slugs / categories), so the whole surface bakes to static HTML in `build/learn/` and rides the S3 + CloudFront path (§53) with **zero runtime cost and no Lambda** — unlike `/share/*`, whose per-id, mutable content needs the share Lambda. Guides are version-controlled, reviewed in PRs, and diffable: a solo dev's "CMS" is the repo.

**Why not a DB-backed CMS.** A `guides` table would add RLS policies, an editor UI, and a runtime read path on a page that is meant to be public, cacheable, and crawlable without JS — all avoided. The trade-off is honest: adding or editing a guide is a code change + deploy, not a web form. For evergreen, low-churn marketing content that is a feature (review gate, no drift), not a cost. If non-engineer live authoring is ever needed, revisit with a headless CMS feeding the *same* prerender step — do not build that speculatively.

**Web-only, no twin.** Like the landing page, `/privacy`, `/compare`, this is acquisition/SEO content, which is a web property (§24) — there is no App Store SEO benefit to native guide screens and a Flutter twin would only create three-surface content drift. SEO mirrors `/share/route` exactly (title / canonical / Open Graph `og:type=article` / Twitter card / escaped `Article` + `BreadcrumbList` JSON-LD via `learn_meta.ts`); the sitemap gets hub/category/guide entries from the build-time index, so they ship even when the Supabase routes/runs fetch fails. Localization: chrome strings ship in all six locales now; guide *prose* is English-only with a `<slug>.<locale>.md` fallback resolver wired in `guides.ts` for later translation (scope still owed — see `learn_pages.md § i18n`). The "your first race" guide's CTA points at `/social?tab=clubs` pending a public race-calendar feature.
## 162. The coach roster is a read-only SECURITY DEFINER aggregation re-checking consent per athlete; the ACWR injury-risk policy lives in the shared helper, not the SQL

**Decided (2026-06-19, migration `20270206_001_coach_roster_summary.sql`, coach_roster.md).** The multi-athlete coach roster dashboard is a single SECURITY DEFINER RPC `coach_roster_summary()` that aggregates per-athlete triage signals (7-day load, plan %, ACWR injury-risk, last-run recency) in one round-trip. Three load-bearing choices: (1) the RPC re-checks the **active `coach_athletes` link per athlete inside the definer body** (a `mine` CTE on `coach_id = auth.uid() and status='active'`), never leaning on the caller's RLS — SECURITY DEFINER bypasses it, so the CTE is the only consent gate; a non-coach gets zero rows and an unauthenticated caller raises, fail-closed. (2) The RPC returns **raw** acute (7d) + chronic (28d-avg) distance-proxy load sums; the **ACWR ratio + injury-risk band thresholds live in the shared `coach_load` parity helper** (web `training/coach_load.ts` ↔ mobile `coach_load.dart`), not the SQL, so web / mobile / the RPC display agree on one testable risk policy. (3) The roster surfaces **no track bytes** — run row stats only, so it opens **no new privacy boundary**: every value is already coach-readable under the shipped run-visibility (§98) + plan-read policies; this only aggregates it.

**Why.** A client fan-out (one runs query + one plan query per athlete) is correct at small roster sizes but is N+1 and re-implements the consent recheck N times. One definer RPC is the durable shape: server-side aggregation, one consent recheck, one place the math lives. Keeping the ACWR thresholds out of the SQL is the same instinct as every other narrow-policy-in-one-place rule — a band edge that drifted between the SQL and the client would mislabel an athlete's injury risk on one surface. A new athlete with <28 days of history reads as `insufficient` (not a false green "low"), so the chip never tells a coach it's safe to push someone the model can't actually assess.

**Trade-off.** The distance-proxy load is coarser than the calibrated TRIMP curve on the athlete's own dashboard — but the roster column is a triage signal ("ramping vs tapering / who's overcooked"), which the acute:chronic ratio gives from the proxy alone; the per-athlete review surface still has the full curve.

**Boundary / not-yet-done.** No paywall gate in v1 (coaching isn't paywalled); if multi-athlete coaching is later paywalled, gate the section behind `ProGate` with a default-off flag. Saved roster sort, a per-athlete sparkline, and configurable load windows are deferred. No CISO/counsel sign-off gate — no new personal-data exposure beyond the shipped consent grant; this ADR is the artifact a reviewer evaluates if they consider the aggregation itself a new surface.
## 163. A public recap is an opt-in FROZEN `public_recaps` snapshot, not a live recompute

**Decided (2026-06-19, migration `20270207_001`, `docs/features/recap.md`).** The Year-in-Running / "Wrapped" recap is personal data; an annual recap browser-side card existed but had no shareable URL, so a posted recap link couldn't unfurl. The fix is a per-user, tokenised `public_recaps` table: the owner explicitly **publishes**, which freezes the recap's aggregate numbers into a `snapshot jsonb`. The share page (`/recap/share/[id]`) + og:image (`/og/recap/[id].png`) render from that frozen snapshot, and the uuid id is the capability token (RLS: owner full CRUD, anyone may SELECT by id).

**Why a snapshot, not recompute-on-read.** An unauthenticated unfurl bot can't recompute a recap from the owner's `runs` (RLS hides them), and a recap shouldn't change under a reader after it was posted. Snapshotting solves both: the reader sees a stable card, and no private-run access is needed. **Why a table, not URL-encoded numbers** (the rejected cheap path): URL-encoding the whole recap is fragile, has no revoke, and still can't carry the owner's display name for the card. The table gives an explicit publish + a revoke (delete the row → the link 404s / falls back).

**Privacy / fail-closed.** Private by default — nothing exists until the explicit publish action. Only **aggregate, non-track** numbers go in `snapshot` (totals / badges / monthly strip) — no GPS, no per-run rows, mirroring `og_run_image.ts`'s no-polyline discipline. No CISO/counsel gate is required for pure aggregates, but the publish action carries a clear "this makes a public link" disclosure (`recap.makePublicExplain`). The og endpoint always 200s with a branded fallback so an unfurl never breaks. Mobile reuses the same table via `ApiClient.publishRecap` + `recapSnapshotJson` (frozen shape identical to the web `YearInRunningRecap`), sharing the web `/recap/share/[id]` URL through the OS share sheet — the device share sheet is the additive part, the page is web-canonical. Deploy-time follow-up: the `share-recap` prod Lambda's CloudFront/OIDC/release wiring in `infra/` (mirrors `share-run`).
## 164. The badge catalogue is code; awards are a persisted `achievements` table derived by a `personal_records`-style full-rebuild trigger, with thresholds duplicated into SQL and pinned

**Decided (2026-06-19, migration `20270208_001`, `apps/web/src/lib/social/badges.ts`).** Achievements ship as two halves. (1) The **catalogue** — which badges exist, their tiers, and their numeric thresholds — lives in a pure code module (`badges.ts` ↔ a future `badges.dart`), the guided-runs "library as code" pattern. It is versionable, unit-testable, and re-renders on locale switch because entries carry i18n keys, not strings. (2) **Awards** — which user earned which badge/tier, when, off which numeric — are persisted rows in an `achievements` table, because an award is a durable event (unlike the recap's recomputed-per-view trophies). Derivation is a SECURITY DEFINER `award_achievements_for_user(p_user)` that **fully re-derives** the user's earned set from `personal_records` + `runs` aggregates + completed plans and `insert ... on conflict do nothing`s the new ones — mirroring `personal_records`' "a full rebuild is simpler to reason about and flat-cost at per-user scale" choice. The function returns only the newly-inserted rows so an AFTER-INSERT trigger writes the `'achievement'` notification exactly once per new badge, never on a re-derive.

**The threshold duplication is deliberate.** The numeric thresholds live in BOTH the `badges.ts` catalogue AND the SQL award function (rather than reading the JS catalogue from SQL, which would lose the testable pure helper). The contract is held by tests on both sides — `badges.test.ts` pins the helper, `achievements_test.sql` pins the SQL — so a drift in either fails CI. **Trade-off:** a threshold change is a two-file edit; the alternative (single SQL definition) trades that for an untestable, locale-coupled catalogue. **Privacy:** badges default `is_public = true` (they're meant to be shared) with an owner-only per-badge visibility flip; non-owner reads are RLS-gated to `is_public = true` (fail-closed — no public policy means no leak), and the share page / OG card embed only a milestone + a date, never track/location data, so no CISO gate is required. **Segment badges deferred** (leaderboard rank is too volatile for a durable award); the `segment` `source_kind` is reserved. Web shipped; mobile twin deferred. See [features/achievements.md](../features/achievements.md).
## 165. Challenge progress is computed at read time via a single GROUP-BY RPC (no per-participant fetch, no denormalised counter), and the leaderboard RPC is SECURITY DEFINER because the public-runs SELECT policy was retired

**Decided (2026-06-19, migrations `20270209_001` + `20270210_001`, [challenges.md](../features/challenges.md)).** A challenge's value for each participant is computed at read time by `challenge_leaderboard(p_challenge_id, p_by_team)` — ONE query joining `challenge_participants` to a per-user (or per-team) aggregate over that runner's `runs` within `[starts_at, ends_at)`. N participants → 1 round trip, 0 client-side per-user fetches, no denormalised progress column to drift. Ranking is `rank() over (order by value desc)`; the `challenge_progress` TS↔Dart pair carries the identical `metricFromActivity` extraction so an offline-optimistic client estimate can't diverge from the board.

**Why DEFINER, not invoker (a spec delta).** The spec called for SECURITY INVOKER (RLS on `activities` governs). But the "public runs readable by anyone" SELECT policy on `runs` was retired earlier — public-run access now flows through the `public_runs` view + `clip-public-track`, and the base-table policy only exposes the caller's own + coach-linked runs. A SECURITY INVOKER aggregate would therefore see only the **caller's** runs and zero every competitor's total. So `challenge_leaderboard` (and `recompute_challenge_completion` + `sweep_challenge_completions`) are **SECURITY DEFINER, gated on `is_challenge_visible(p_challenge_id)`**: participants opted in by joining, so the board may sum a participant's private runs too — but it returns only the per-user/per-team SUM, never the run rows, exactly like `event_results`. A private/club board still can't be read by a non-member (the visibility gate fails closed).

**Why completion is an explicit RPC + cron, not a per-run trigger.** `recompute_challenge_completion` awards the durable `challenge_badges` row + stamps `completed_at` + fires a `challenge_complete` notification when the goal is met (idempotent via the unique badge row). It's called opportunistically client-side after a run saves (best-effort, swallow-to-debug) and by a daily `sweep-challenge-completions` pg_cron job. A per-run trigger that fanned out across every challenge the runner is in would be unbounded write amplification; the RPC + sweep bounds it. **`vert` was dropped from the metric set** at landing — there is no first-class per-run elevation column (`runs.metadata.elevation_m` is import-only + frequently absent), so a vert board would silently undercount; ships in a later slice once elevation is first-classed.
## 166. Native push (FCM / APNs) is a third consumer of the notifications rows, fail-closed on operator credentials, with a per-device enabled-flag fan-out

**Decided (2026-06-19, migration `20270212_001_native_push_channel.sql` + `apps/job_worker/internal/nativepush/` + `apps/mobile_*/lib/push_messaging_bridge.dart`).** The locked-phone delivery leg copies the `web_push` sibling-consumer pattern (§133) exactly, swapping the transport. The same `notifications` row is read by the in-app bell, the `notification_email` channel, the `web_push` channel, and now `native_push`; each carries its own `*_sent_at` idempotency guard (`native_push_sent_at`) and gates on the **same** `push_notifications` preference (one "push" channel covers browser + native — no separate pref). An AFTER-INSERT trigger enqueues one `native_push` job per recipient, gated on the recipient having at least one `device_tokens` row with `is_notifications_enabled = true` (avoids a no-op job for the push-less majority — the same coarse gate `web_push` puts on subscription presence). The worker's `nativepush.Sender` routes on `device_tokens.platform`: `android` → FCM HTTP v1 (OAuth2 service-account bearer), `ios` → APNs HTTP/2 (`.p8` ES256 JWT), with iOS falling back to FCM when only FCM is configured. Both transports are stdlib + the existing `golang-jwt` — no Firebase Admin SDK, same dependency-light call `webpush/` made.

**Fail-closed on operator credentials (§150), not a paywall or a CISO gate.** Pushing an already-consented notification is not new privacy-sensitive processing — the `push_notifications` pref + the per-device `is_notifications_enabled` flag are the user controls. So all credential-independent code ships now: `nativepush.NewSender` returns `(nil, nil)` when neither FCM nor APNs is configured, the handler drains `native_push` jobs to done **without** stamping `native_push_sent_at` (rows stay pending for a later credentialed deploy), and a per-platform unconfigured transport (`ErrPlatformNotConfigured`) likewise leaves the row pending rather than failing. The mobile bridge no-ops when Firebase isn't initialisable (no `google-services.json` / `GoogleService-Info.plist`), so dev builds compile + run without the operator artifacts. Going live is a deploy-time checklist item (provision Firebase + APNs key, set `FCM_SERVICE_ACCOUNT_JSON`/`FCM_PROJECT_ID` and/or `APNS_KEY_P8`/`APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_TOPIC` on the worker, drop the config files into `android/`+`ios/`), recorded in `email.md`'s Production ops — not a `- [ ]` "blocked on legal" follow-up.

**Two-axis user control.** The universal `push_notifications` pref is the worker-side category gate (`all|important|off`, default `important`); `device_tokens.is_notifications_enabled` is the per-device fan-out filter the enqueue trigger + `FetchDeviceTokens` honour. The mobile settings toggle mirrors the pref choice down to the current device's flag (`setDeviceNotificationsEnabled`) so muting push on one phone doesn't strand a token row that another device shares. A dead token (FCM `UNREGISTERED` 404 / APNs 410) is pruned via the `clear_device_token` service-role RPC; a 429/5xx defers the whole job. The device-token write path (register on sign-in, re-register on `onTokenRefresh`, remove on sign-out) is the first writer of `device_tokens`, which shipped its table + owner-scoped RLS back in `20260506_001` but never had a client.
## 167. Charity fundraising pages reuse the paid-events Stripe Connect rail; a fundraiser is polymorphic over (run | event); donation status is service-role-only; live charges stay prod-gated

**Decided (2026-06-19, migration `20270213_001_fundraisers.sql`, `donations-checkout` EF + the donation branch in `stripe-events-webhook`).** A runner or club organiser attaches a public charity fundraiser to a run **or** a club event — a goal thermometer + a public donation feed + a share URL — and anyone (incl. a logged-out stranger) can donate via Stripe-hosted Checkout. Rather than a parallel payment stack, fundraising **reuses the paid-events destination-charge marketplace wholesale** (decisions §139): the same `instructor_payout_accounts` + `host_can_take_payment()` payout account (the fundraiser owner's), the same `events-connect-onboard` onboarding, the same `events-checkout/lib.ts` session/fee/idempotency helpers, and the **same single `stripe-events-webhook` endpoint + secret** — extended with one `metadata.kind==='donation'` branch (`isDonationSession`), not a second webhook. The donation checkout is a thinner variant of the event one (no capacity, no sales window, donor may be anonymous — a donation has no seat).

**Design choices.** A `fundraisers` row is polymorphic over `(run_id | event_id)` via a nullable-FK pair + a `(run_id is not null) <> (event_id is not null)` CHECK and a partial unique index per anchor — mirroring how `event_results.run_id` / `event_orders.event_id` coexist. The `donations` ledger copies the `event_orders` discipline verbatim: **status is service-role-only** (the `lock_donation_status` trigger + no client INSERT/UPDATE policy → the webhook is the sole, idempotent CAS writer; a replayed `checkout.session.completed` finds the donation already `paid` and no-ops, so it can't double-count), donor identity / Stripe ids / `owner_user_id` / `platform_fee_cents` are **revoked from client roles**, and the public feed + thermometer are served by the visibility-gated `fundraiser_feed` / `fundraiser_totals` SECURITY DEFINER RPCs (public-safe columns only; totals are a `sum`, never per-row). A fundraiser on a publicly-visible anchor is anon-readable (it's a share target); one on a private run is owner-only (fail-closed, `fundraiser_anchor_visible`).

**Trade-offs / gating.** Funds settle to the **fundraiser owner's** Connect account, not the charity's directly (the runner collects and is trusted to forward) — the honest direct-to-charity alternative is a larger build and an owner decision (fundraising.md open question 3). Mobile is **read + web-handoff only** (donate routes to the web `/fundraisers/[id]` page, mirroring paid-events P3) to contain IAP blast radius. The whole live-charge path is **prod-gated, fail-closed, identical posture to paid events**: `donations-checkout` returns `503 stripe_not_configured` when `STRIPE_SECRET_KEY` / `STRIPE_EVENTS_ALLOWED_REDIRECTS` are unset, the webhook `503`s without `STRIPE_EVENTS_WEBHOOK_SECRET`, and TEST MODE is enforced in P1 (`sk_test_` only). **Pre-deploy checklist before live charges:** (1) owner + CISO + counsel sign-off — counsel must confirm whether platform-facilitated charitable solicitation triggers US state charitable-registration / disclosure rules; (2) operator sets live `sk_live_` / `whsec_` keys (default unset); (3) confirm the funds-flow trust model (owner-collects vs direct-to-charity) is the intended one. This is a deploy gate, **not** a reason to leave code unwritten — the full path is built + test-mode-verified.
## 168. Race results live on the `runs` row (`source='race'`), a public `race_listings` calendar is its own table, and auto-match-on-record is an inform-tier, layered-resilience-wrapped post-save check

**Decided (2026-06-20, migration `20270214_001`, race_calendar.md).** The race calendar + results-import feature (parity backlog #10) makes four shape decisions worth pinning:

1. **No parallel results table.** An imported / auto-matched race result is written **onto the runner's existing `runs` row** — `source='race'` (already in the `runs.source` CHECK since `20260505_001`) plus the owner-only race metadata keys (`race_name`/`bib`/`chip_time`/`gun_time`/`overall_place`/`age_group_place`/`age_group`). This reuses the per-user `external_id` dedup index (`external_id = race:{name}:{date}:{bib}`) and the existing `public_runs` owner-only strip rather than standing up a second results entity. A nullable `runs.race_listing_id` FK links a matched run back to its calendar entry, mirroring `runs.event_id`.

2. **The calendar (`race_listings`) is its own table and publicly discoverable.** A race calendar is public discovery data, so the table has a `for select using (true)` policy (anon included) and one `security invoker` proximity RPC (`search_race_listings`) cloned from the `search_public_events` precedent. Authenticated users may submit a `manual` listing; a `before insert or update` trigger (`force_unverified_listing`) forces `is_verified=false` on any non-service-role write so a submitter can't masquerade a crowd listing as provider-verified, and the UPDATE policy locks a listing once verified.

3. **Auto-match-on-record is inform-tier and layered-resilience-wrapped.** After a run is saved, a best-effort check offers — but never silently writes — an official result when a same-day listing matches by distance band (+ proximity when a start point is known). The scoring is the pure `race_match` TS↔Dart parity pair (`raceMatchScore`, same-day required, signals normalised over what's available, threshold 0.5). The match enriches the **existing** in-app run row (no duplicate `race:` run) and the importer's `onConflict` insert path is only for results with no recorded counterpart. The candidate fetch is swallowed (an L4 auxiliary effect) so a race lookup can never break run detail.

4. **RunSignUp is built fail-closed behind a missing API key; parkrun stays the shipped scraper; per-site scrapers are deferred.** The `race-results-import` + `race-listings-sync` Edge Functions return `503 provider_not_configured` when `RUNSIGNUP_API_KEY`/`_SECRET` are unset (the dev/CI default), and the UI shows an unavailable explainer — the whole RunSignUp leg is inert until the credential is provisioned (a genuine external blocker, per the compliance-sign-offs-gate-prod house rule: write the full path now, gate it fail-closed). parkrun's existing scraper pattern (auth-before-parse, tiered rate limit, body caps, fail-loud upstream, `privacy_default` honouring) is mirrored exactly. Per-site scrapers (ChronoTrack / UltraSignup / RaceResult) stay scoped follow-ups to avoid brittle/abusive crawling; the durable non-API path is structured manual paste.

**Trade-off.** Storing results on `runs` means the race result is only as durable as the run row and can't exist without one for a recorded-then-matched run; the importer's separate-insert path covers the no-recording case. Re-evaluate the parallel-table question only if a result needs fields that don't fit the metadata bag or needs to exist wholly independent of a run.

---

## How to add an entry

1. Append below, numbered in sequence.
2. Lead with what was decided, then *why*, then the *trade-off*, then when not to re-litigate.
3. Cite the migration, commit, or PR that captures it if there is one.
4. Keep it short — one screen or less. If it's longer than that, it probably belongs in `architecture.md` or its own deep-dive doc, with a pointer from here.

## 172. Auto-hide on reports is a SECURITY DEFINER count of *vetted* reporters (≥ 5 public runs) tripping at 3, flipping a soft `shadow_hidden` excluded from public surfaces — owner notified, admin-revertible, shipped without CISO review by owner's call

**Decided (2026-06-20, migration `20270218_001`, backlog E1+E3).** A target (`user` / `club` / `route`) auto-hides when **3 distinct reporters with ≥ 5 public runs each** hold a pending report on it. The counting + flip live in `auto_hide_target(kind, id)`, a SECURITY DEFINER function invoked by an AFTER INSERT trigger on `reports`. SECURITY DEFINER is required twice over: the reputation gate reads *other* reporters' public-run counts (base-table RLS blocks that for a normal caller, same reason `public_run_counts` is DEFINER), and the flip writes a target the reporter doesn't own. The reputation weighting (E3) is the same `is_public`-run gate the People search uses, so a puppet-account swarm with no run history can't trip the hide.

**Why a soft `shadow_hidden` boolean, not a delete or a status enum.** Auto-hide is a *pending-review* state, not a verdict — the content still exists, the owner + admins still see their own row through the untouched owner-RLS / admin paths, and it's one-flag reversible. Every public/search/discovery surface gains `and not shadow_hidden`: the `public_routes` view (cascades to `search_public_routes` / `nearby_routes` / `routes_within_box`), `discoverable_routes_in_bbox`, `search_clubs` + `clubs_in_bbox`, `public_profile_by_id` + `search_user_profiles`. The owner is notified exactly once on the false→true transition via a new `content_hidden` notification kind. Admins revert with the admin-gated `admin_unhide_target` RPC, surfaced as a Hidden badge + Unhide button on `/admin/reports` (the queue RPC `fetch_pending_reports` grew a `shadow_hidden` column). Comment / club_post / run reports never auto-hide — they have no `shadow_hidden` column and v1 takedown stays a manual admin step; the function early-returns for those kinds.

**The trade-off + the compliance call.** Three reputable reporters is a low bar — a coordinated brigade of 3 real accounts could hide a legitimate target until an admin reverts it. That's deliberate: the hide is reversible + the owner is told immediately, so the cost of a false positive is a notification + an admin click, while the cost of a false negative (abusive content staying public) is higher. **A CISO review was recommended for this moderation surface and the owner chose to proceed without it** — recorded here per the "compliance sign-offs gate prod, not code" rule; the code shipped behind the normal admin gate, the sign-off (if later required) is a deploy-time item, not unwritten code. Don't re-litigate N/M without an abuse-data signal; if brigading becomes real, raise M or add a per-reporter cooldown rather than lowering the soft-hide reversibility.

## 173. Meal templates are a relational `meal_templates` + `meal_template_items` pair that instantiates into `food_log` by copy, never by FK — the nutrition twin of gym routines

**Decided (2026-06-20, migration `20270219_001`, [multi_modal.md § Nutrition](../features/multi_modal.md)).** "Saved meals logged with one tap" (roadmap Nutrition mid tier) is modelled exactly like the gym `gym_routines` save-as-routine pattern, one tier simpler: a `meal_templates` parent (owner-scoped `user_id`, a name, a default `meal_slot`, a client-stamped non-authoritative `item_count`) + a `meal_template_items` child whose columns **mirror the `food_log` row shape** (`item_name` / `meal_slot` / `calories` / `protein_g` / `carbs_g` / `fat_g` / `external_id`). Logging a template **copies** its items into fresh `food_log` rows at "now" — there is **no FK** between a template and the entries it spawned, so deleting a template leaves prior logged meals intact (immutable diary), exactly like a deleted `gym_routines` row leaves logged `gym_workouts` untouched. A template is a reusable plan, not a dated activity, so it never feeds the `activities` view.

- **Pure plan↔log shaping is the `meal_template` TS↔Dart parity pair** (`templateFromEntries` + `entriesFromTemplate`), the nutrition analogue of `gym_routine`'s `routineFromWorkout` / `prefillFromRoutine`. The slot resolution (item slot → template default → log-time override) lives there once so web (`logMealTemplate` in `core/data.ts`) and mobile can't drift. The default slot is derived from the source entries only when they agree (a mixed-slot day → null).
- **Offline-first on mobile** via `LocalMealTemplateStore` (items inline, client-minted UUID = server id, drains create → delete), sibling of `LocalRoutineStore`. No edit path in v1 (build / save / delete only), mirroring gym P1.
- **DSAR**: owner-scoped personal data, wired into both export paths with the items nested (PostgREST embed), and erased by the `auth.users` FK cascade on account deletion. No compliance gate — it's ordinary food-log-shaped data the subject already provides.
- **Not built**: recipe builder (N ingredients scaled → one logged item — the next roadmap bullet), public/shared meal templates, and an edit path. Deferred, not designed against.

## 174. The weekly-digest send is a fail-closed pg_cron enqueue, not an unscheduled builder — the prod gate is the unset SMTP credential, and the digest is the one category that emits RFC 8058 one-click unsubscribe

**Decided (2026-06-20, migration `20270220_001`).** The weekly-digest worker backend (handler, builder, suppression rail, stateless-HMAC unsubscribe token, the `weekly_digest` jobs.kind) all landed earlier behind the gate (`20270108_001`), but the builder `EnqueueAllWeeklyDigests` was left deliberately UNSCHEDULED. This migration ships the missing scheduler as a `pg_cron`-driven SQL function `enqueue_weekly_digests()` (Monday 08:00 UTC) that selects opted-in recipients (`user_settings.prefs.email_weekly_digest = 'on'`, mirroring the Go builder's `FetchDigestCandidates`) and enqueues one `weekly_digest` job each, dedupe-safe per recipient (`NOT EXISTS` over live `queued|running` rows — the `event_reminder`/`token_refresh` cron pattern).

**Why scheduling it now is correct, not a compliance bypass.** Per the "compliance sign-offs gate prod, not code" rule, the gate lives in fail-closed *config*, not missing code. `handleWeeklyDigest` returns early when `w.Email == nil` (SMTP unset), so without `SMTP_HOST`+`APP_BASE_URL` (including prod until an operator provisions them) the cron's jobs drain to `done` WITHOUT sending. Even with SMTP live, every recipient is hard-gated on the opt-IN pref (default off) AND the `email_suppressions` block list. Enabling a real send is three operator steps — provision SMTP + `WEEKLY_DIGEST_UNSUB_SECRET`, land SPF/DKIM/DMARC, obtain CISO + counsel sign-off (bulk mail under CAN-SPAM + GDPR/ePrivacy) — a pre-deploy checklist, not unwritten code.

**Why the digest emits `List-Unsubscribe-Post`, and nothing else does.** RFC 8058 one-click requires `List-Unsubscribe-Post: List-Unsubscribe=One-Click` alongside a POST-able `List-Unsubscribe` URL. The mailer carries an `Email.ListUnsubscribePost` flag set true ONLY by `renderWeeklyDigest` (its `List-Unsubscribe` URL is the unauthenticated POST endpoint `/unsubscribe/weekly-digest`). Transactional mail whose `List-Unsubscribe` deep-links to the GET-only preferences page leaves it false. `composeEmail` guards `&& listUnsub != ""` so the header can never appear without a URL.

## 175. Recipes are the sum-into-one-entry sibling of meal templates — same relational shape, but logging produces a SINGLE `food_log` row of the combined per-serving macros

**Decided (2026-06-20, migration `20270221_001`, [multi_modal.md § Nutrition](../features/multi_modal.md)).** "N ingredients → one logged meal" reuses the §173 meal-template shape — a `recipes` parent (owner-scoped `user_id`, name, default `meal_slot`, client-stamped `ingredient_count`) + a `recipe_ingredients` child mirroring the `food_log` macro columns — with two deliberate differences:
- **A recipe sums; a template enumerates.** Logging a meal template copies one `food_log` row per item; logging a recipe writes **a single `food_log` row** carrying each ingredient's macros × its `quantity`, summed, then divided by a `servings` count (`servings >= 1` CHECK). One serving yields the per-serving macros under the recipe's *name*. The summed entry carries no `external_id` — it's a composite.
- **The sum is the `recipe` TS↔Dart parity pair** (`recipeFromEntries` + `sumRecipe` + `logInputFromRecipe`). `sumRecipe`'s rule: a macro stays null only when *no* ingredient carried it; a missing macro on one ingredient contributes 0. Per-serving totals round to 0.1 to match the `numeric(_,1)` columns.
- **Same instantiate-by-copy contract as §173**: no FK from `food_log` to `recipes`; a recipe never feeds the `activities` view. Offline-first via `LocalRecipeStore`. No edit path in v1.
- **DSAR**: owner-scoped, both export paths, ingredients nested, FK-cascade erasure. No compliance gate.
- **Not built**: per-ingredient quantity editing in the UI, shared/public recipes, an edit path. Deferred.

## 176. The exercise catalogue is an additive nullable FK (`gym_sets.exercise_id` alongside free-text `exercise_name`), never a required binding — seeded globals are shared read-only reference data, owner customs are personal data

**Decided (2026-06-20, migration `20270222_001`).** The gym-mid "exercise database (FK from `gym_sets.exercise_id` instead of free text)" bullet is built **additively, never destructively**. The wording "instead of" is the trap; replacing free text would orphan every existing logged set and break the offline-first `LocalGymStore` path. Instead:
- A new `exercises` catalogue table holds structured entries. `author_id NULL` = a **seeded global** (read-only for every authenticated user, ~43 common compounds + isolations + cardio); non-null `author_id` = an **owner custom** (read/write by that owner only). RLS: read = `author_id is null or author_id = auth.uid()`, write = `author_id = auth.uid()`. `name_key` is `normaliseExerciseName(name)`, the identity `gym_prs` / `gym_routine_exercises` bind by.
- `gym_sets.exercise_id` is a **nullable** FK with `on delete set null`. A set may reference a catalogue entry OR stay free-text; `exercise_name` is **always** populated, and PR computation stays keyed on the normalised name, so the link is provenance, not the grouping key.
- **Why nullable + alongside, not required + replace** (the tradeoff): a required `exercise_id` + backfill is brittle (unmatched names have nowhere to go), breaks the offline path, and forces every `GymSetInput` construction + test fixture to supply a value (the round-1 build-break trap). Nullable-alongside preserves all data, keeps the offline path writing free-text, and makes the catalogue a self-degrading UX enhancement.
- The composer (web `GymEditor.svelte` + mobile `gym_compose_sheet.dart`) merges catalogue names into history autocomplete and binds `exercise_id` only on a normalised-key match; anything else logs free-text with `exercise_id` null.
- **DSAR**: only owner customs (`author_id = uid`) are exported; seeded globals are shared reference data. Wired into both export paths.
- **Not built**: a catalogue browse/picker UI, muscle-group analytics off `category`, public/shared customs, binding `exercise_id` from a routine step. Deferred.

## 177. The lifecycle drip selects its cohorts in SQL and rides the digest's rails as a new `lifecycle_drip` kind — one mechanism, three templates, its own opt-in, a stream-scoped unsubscribe

**Decided (2026-06-20, migration `20270223_001`).** The "lifecycle drip (re-engagement / onboarding / streak nudges)" engagement item is built as the third engagement stream on the EXACT rails the weekly digest established (`§ 174`), not a bespoke path:
- **A new `lifecycle_drip` jobs.kind carrying `{user_id, template}`**, three templates under one mechanism (`drip_onboarding`, `drip_reengagement`, `drip_streak`) — mirroring how `lifecycle_email` carries welcome / pro_welcome / payment_failed. The worker handler (`handler_lifecycle_drip.go`) is the digest handler's sibling: nil-sender skip, opt-in gate, suppression hard-block, render, send.
- **Cohort selection lives in the `enqueue_lifecycle_drip()` SECURITY DEFINER SQL function**, not the Go handler — the durable split. Set-based windowed queries (onboarding = opted-in account 2–6 days old with no run; re-engagement = a run >30 d ago but no row in the cross-modal `activities` view in 30 d; streak = ran the last two calendar days but not yet today) decide who gets which template and write it into the payload; the handler just honours the gate and sends the named template. A daily 09:00-UTC pg_cron fires it, dedupe-safe per `(user_id, template)`.
- **A SEPARATE opt-IN pref `email_lifecycle_drip`** (default off), never folded into `email_notifications` (transactional) NOR `email_weekly_digest` (the other engagement stream) — opting into one engagement stream is not consent to another (CAN-SPAM + GDPR/ePrivacy). Gated in BOTH the enqueue SQL and the handler (defence in depth).
- **The unsubscribe token + endpoint are generalised to be stream-aware**, rather than copied: `digesttoken.Mint/Verify` take a `stream` arg (the scope namespaces the MAC so one stream's link can't unsubscribe another), and `internal/unsubscribe` mounts `/unsubscribe/weekly-digest` AND `/unsubscribe/lifecycle-drip` off the ONE shared `WEEKLY_DIGEST_UNSUB_SECRET`. The per-stream pref flip is independent, but the `email_suppressions` row a suppression inserts blocks EVERY stream to that address (the safe default — one "stop emailing me" stops all marketing).
- **Why SQL-side cohort selection + fail-closed gate** (the tradeoff): the alternative — a Go builder that fetches candidates and computes cohorts in-process — duplicates the windowing the DB does natively, fans out N reads per candidate, and drifts from the data. Pushing selection into one `enqueue_*()` function (the precedent every other cron uses) keeps it one set-based pass and makes the cron the operator-flippable surface. Per `CLAUDE.md` "compliance gates prod, not code": the whole path ships, fail-closed on the unset SMTP credential (jobs drain to `done` without `SMTP_HOST`), with CISO/counsel sign-off recorded as a pre-deploy checklist item — the cron is harmless no-op churn until SMTP is provisioned.
- **Not built**: the opt-in toggle UI (web Settings checkbox + mobile switch) for the engagement streams — the pref is read server-side today; a per-recipient send cap / frequency cap across the two streams; analytics on drip open/convert. Deferred.

## 178. Route-photo server-side thumbnails + EXIF strip reuse the run-photo worker shape — a `route_photo_process` kind with bucket-aware backend methods, not a copied handler

**Decided (2026-06-20, migration `20270224_001`).** The deferred half of roadmap row 8 (server-side thumbnails + an EXIF worker for route photos) ships as the exact sibling of the run-photo `photo_process` path, not a parallel implementation:

- **A new `route_photo_process` jobs.kind** carrying the identical `{photo_id, storage_path, owner_id}` payload as `photo_process` (the `PhotoProcessPayload` struct is shared — same shape, same meaning). The worker's `handleRoutePhotoProcess` is the run handler's twin: download → strip JPEG APP1/COM → 512w thumbnail → PATCH `route_photos.thumb_512_path`. Non-JPEG is a no-op; bad payload / empty path are permanent; storage 5xx is transient.
- **Storage access is refactored to bucket-aware private helpers** (`downloadFromBucket` / `uploadToBucket` / `updateThumb512Path` on `SupabaseClient`), and BOTH the run-photo and the new route-photo public methods delegate to them. The run methods hardcoded the `run-photos` bucket; rather than copy three methods with a different bucket literal, the literal becomes a parameter so there is one transport path. The `Backend` interface gains `DownloadRoutePhoto` / `UploadRoutePhoto` / `UpdateRoutePhotoThumb512Path`.
- **Two enqueue triggers** cover the two upload shapes the clients already use: an AFTER INSERT (web uploads the object first, then inserts the row with the final `storage_path`) and an AFTER UPDATE OF `storage_path` (mobile inserts a placeholder empty-path row, uploads, then PATCHes the real path). The placeholder insert is skipped; the service-role thumb PATCH never re-enqueues (it doesn't change `storage_path`).
- **Defence in depth, not a behaviour change for clients.** The web + mobile route-photo galleries were already built forward-compatible — they select `thumb_512_path`, sign it, and prefer it (`p.thumbUrl ?? p.url` / `_galleryUrl`) — and the clients already strip EXIF client-side before upload. This change populates the column the clients were waiting on and adds the server-side re-strip so a route's photos don't depend solely on a well-behaved client. No client code changed.
- **Why mirror the run path rather than generalise into one handler taking a bucket+table arg** (the tradeoff): the two handlers are ~30 lines of straight-line glue and the per-kind dispatch + the per-kind enqueue trigger already make them distinct units; collapsing them into one parameterised handler would couple two job kinds' error semantics and obscure the dispatch. The DRY win that matters — the HTTP transport — lives in the shared `SupabaseClient` helpers, not the handler. Pinned by 8 Go handler tests + the pgtap `route_photos_enqueue_process_test.sql` (6 assertions) + the allowlist test.
## 179. Learn-guide prose localizes via a `<slug>.<locale>.md` lookup with field-by-field English fallback — applied uniformly to body, H1, and listing cards; the English copy stays the prerendered canonical

**Decided (2026-06-20).** The `/learn` surface shipped (`§ 161`) with six-locale chrome but English-only prose and a half-wired resolver. The prose-localization mechanism is now complete on the existing repo-committed-MDsvex foundation, not on a DB-backed translation store: a guide's translation is just another committed file, `apps/web/src/lib/learn/guides/<slug>.<locale>.md`, indexed by the same `import.meta.glob` as the English source. Three pure resolvers in `guides.ts` close it: `getGuide(slug, locale)` (localized body, else English), `localizedGuideMeta(slug, locale)` (localized title/description **falling back field-by-field** to the English frontmatter), and `isEnglishFallback(slug, locale)` (drives the "this guide is in English" notice). The non-obvious calls:
- **Localize the LISTING, not just the article.** The hub + category cards build off the English index (one card per slug), so localizing only the article body would show a non-English visitor an English card title above a localized body a click away. `GuideCard` + the article H1 both re-resolve through `localizedGuideMeta`, so the listing → body reads consistently in the active locale and degrades to English as one unit.
- **The English body stays the prerendered, canonical copy.** The site is `adapter-static`; `entries()` bakes the English guide into `build/learn/<slug>.html` with English `<head>` meta (canonical URL, OG, `Article` JSON-LD). The localized body + title are lazy-resolved **client-side** after `initLocale` swaps the active locale — there is one indexed URL per guide (no `/de/learn/...` variants, no `hreflang` fan-out), which is the right SEO posture for an acquisition surface whose canonical language is English.
- **Localized frontmatter must agree with its English sibling on the structural fields.** `slug`/`category`/`order`/`cta.feature` are identical to the source (only `title`/`description` translate); `guides.test.ts` fails the build on drift, because the card's route + section come off the English index and a mis-filed localized file would link a card under the wrong category. The resolver keys off the filename suffix, which must be a supported non-default locale with an English source to fall back to — also guarded.
- **Why repo-committed files over a translation CMS / message-catalogue keys** (the tradeoff): guide prose is long-form evergreen Markdown, not UI strings — putting it in the `m()` catalogue would bloat every locale chunk and lose the MDsvex authoring/review-in-PR ergonomics that `§ 161` chose deliberately; a CMS reintroduces the runtime + attack surface `§ 161` rejected. A per-locale sibling file keeps translations version-controlled, prerender-compatible, and addable without touching code. The cost is that a new translation is a code change + deploy, accepted as consistent with `§ 161`.
- **Shipped state:** `road-running-101` is fully translated into all six locales as the proof + template; the other seven guides stay English and the resolver falls back. Authoring the remaining translations is content work with no further mechanism change.
