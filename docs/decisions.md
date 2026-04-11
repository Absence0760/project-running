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

## How to add an entry

1. Append below, numbered in sequence.
2. Lead with what was decided, then *why*, then the *trade-off*, then when not to re-litigate.
3. Cite the migration, commit, or PR that captures it if there is one.
4. Keep it short — one screen or less. If it's longer than that, it probably belongs in `architecture.md` or its own deep-dive doc, with a pointer from here.
