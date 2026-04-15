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

**Trade-off:** The phone-side receiver is blocked on `mobile_ios` gaining real Supabase auth (currently a scaffold). Until then the watch can't sync anything on device. For watch-sim-alone dev we keep `SupabaseService.swift` alive under `#if DEBUG` and surface a "DEBUG: Sync Direct" button that signs in with seed creds — Release never compiles that file. The acknowledgment semantics are weaker than the old path: `session(_:didFinish:)` only confirms the phone received the file, not that Supabase accepted the write. Good enough to start; a future roundtrip ack can tighten it.

We rejected "any device via CoreBluetooth peripheral mode": watchOS restricts background advertising and there's no receiver on the other end of that pipe that isn't the phone anyway. WCSession covers every real pairing.

**Don't re-litigate unless:** the phone app moves off Flutter in a way that makes `WCSessionDelegate` hard to implement, or we find `WCSession.transferFile` is unreliable in practice for large runs (50KB JSON is trivial today).

---

## How to add an entry

1. Append below, numbered in sequence.
2. Lead with what was decided, then *why*, then the *trade-off*, then when not to re-litigate.
3. Cite the migration, commit, or PR that captures it if there is one.
4. Keep it short — one screen or less. If it's longer than that, it probably belongs in `architecture.md` or its own deep-dive doc, with a pointer from here.
