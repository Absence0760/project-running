# Turn-by-turn offline trail navigation + condition reports — implementation plan

> **Status:** Planned — specced 2026-06-15, not yet built. This is an implementation handoff plan, not a description of shipped behaviour. Tracked in [roadmap.md § Planned features](../product/roadmap.md#planned-features--specced-2026-06-15).

## Goal & user value
Three deferred pieces of parity backlog #5 ("Trail / offline navigation"). For a
runner heading out on a saved route, especially on trail with no signal:
1. **Route condition reports** — community-sourced notes ("creek crossing flooded",
   "trail closed for logging", "ice on the north face") attached to a route, with a
   freshness/severity signal, so a runner knows what they'll hit before they go.
2. **Offline tile packs** — download the map tiles covering a route's bounding box
   to disk so the live map renders with zero connectivity (today only the route JSON
   is pinned via "Save for offline", decisions §64 — the map itself goes blank offline).
3. **Turn-by-turn voice cues** — spoken "in 200 m, turn left" cues generated from the
   route polyline, layered onto the existing TTS audio-cue stack while following a route.

"Save for offline" (per-route pin) + the phone→Wear OS DataLayer push of starred
routes already ship (decisions §64). This plan adds the three remaining capabilities.

## What already exists to build on (verified)
- **Route-attached table + RLS pattern to copy:** `route_reviews` —
  `apps/backend/supabase/migrations/20260414_001_route_reviews.sql` +
  `20260627_001_route_reviews_insert_gate.sql` (the visibility-gated INSERT: `auth.uid() = user_id and exists (select 1 from routes where routes.id = <table>.route_id)`; owner-self read; owner-only update/delete). The newest route-attached table is
  `route_markers` (`20270129_001_route_markers.sql`) — copy its shape for: own table (not a `routes.*` jsonb field), `route_id`/`user_id` FKs with `on delete cascade`, a `kind` narrow union via CHECK + TS union + `check_constraint_unions.mjs` PAIRS entry, a `meta jsonb`, visibility via `private.is_route_visible_to`, and a `*_for_viewer()` SECURITY DEFINER read RPC that redacts in-privacy-zone points (decisions §33).
- **Web data helpers to mirror:** `apps/web/src/lib/core/data.ts` — `fetchRouteMarkers` (line ~5212, calls `route_markers_for_viewer` RPC, fails closed to `[]` on error), `addRouteMarker` (~5223), `asRouteMarker` (~5200). `route_reviews` has the analogous review CRUD in the same file.
- **types.ts overlay pattern:** `apps/web/src/lib/types.ts` — `RouteMarkerKind` union (line 84), `RouteMarker = Omit<RouteMarkerRow, 'kind' | 'meta'> & { kind; meta }` (line 93). Copy for `RouteConditionRow` → `RouteCondition`.
- **Web route-detail surface:** `apps/web/src/routes/routes/[id]/+page.svelte` (+ `+page.ts`, + a `roadbook/` child) — where a conditions panel mounts on web.
- **Mobile route-detail surface:** `apps/mobile_android/lib/screens/route_detail_screen.dart` + `public_route_screen.dart` (read-only mirror). Reviews/segments/photos panels already mount here (`widgets/segments_panel.dart`, `widgets/route_photos.dart`) — a `widgets/route_conditions.dart` follows the same shape.
- **Offline pin store (decisions §64):** `apps/mobile_android/lib/local_route_store.dart` — `pinOffline` / `unpinOffline` / `isOfflinePinned`, sidecar `offline_pinned_route_ids.json`, `offlinePinnedRoutes` getter (lines 27–61). The tile-pack download hooks onto the existing pin toggle.
- **Tile cache (disk):** `apps/mobile_android/lib/tile_cache.dart` — `FileCacheStore` over `${cacheRoot}/map_tiles` (lines 47–51), shared by every `flutter_map` via `flutter_map_cache` + `dio_cache_interceptor`. The offline pack writes into a *sibling* directory so it isn't LRU-evicted with the general cache.
- **Tile format:** PMTiles via tileserver-gl (`docs/ops/protomaps_local_setup.md`); prod tiles are MapTiler raster. A tile pack is a set of `{z}/{x}/{y}` raster tiles for the route bbox at the zoom range the live map uses.
- **Turn-cue geometry foundation (parity pair already exists):** `apps/web/src/lib/routes/route_geometry.ts` ↔ `apps/mobile_android/lib/route_geometry.dart` — `interpolateAlongRoute` (line 28), `distanceAlongRoute` (line 72, projects a live GPS fix onto the polyline → cumulative distance), `polylineLengthMetres` (line 117). The turn-cue generator consumes these; the live "distance to next turn" reuses `distanceAlongRoute` (already fed by the recorder's off-route detection).
- **TTS stack to layer onto:** `apps/mobile_android/lib/audio_cues.dart` — locale-aware (`tts*` ARB keys, `setLanguage(ttsLanguageTag(...))`), already wired into `run_screen.dart` for split/pace/off-route cues with `_ttsCue('name', () => ...)` best-effort wrappers. Off-route detection already runs in `packages/run_recorder` while following a route.
- **Course-marker pin vocabulary to reuse on the conditions UI:** `apps/web/src/lib/routes/route_markers.ts` ↔ `apps/mobile_android/lib/route_markers.dart` (`ROUTE_MARKER_KINDS`, pin colour + i18n label key per kind). The conditions feature gets its own narrow-union kind set in the same style.

## Data model / migrations
One migration: `route_conditions`. Walk to a fresh date (CLI parses version as
`YYYYMMDD`; same-day collides) — use the next free date after the latest
(`20270202_001_search_clubs_club_links.sql`), e.g. `20270203_001_route_conditions.sql`.

```sql
create table route_conditions (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes(id) on delete cascade not null,
  user_id     uuid references auth.users(id) on delete cascade not null,
  condition   text not null
              check (condition in ('clear','muddy','flooded','snow_ice',
                                   'overgrown','closed','hazard','other')),
  severity    text not null default 'info'
              check (severity in ('info','caution','impassable')),
  note        text check (note is null or length(note) between 1 and 500),
  -- optional anchor point along the route (e.g. "creek crossing at 4.2 km").
  lat         double precision check (lat is null or lat between -90 and 90),
  lng         double precision check (lng is null or lng between -180 and 180),
  position_m  numeric(10,2),                 -- derived from route geom by trigger
  created_at  timestamptz not null default now()
);
create index route_conditions_route_recent on route_conditions (route_id, created_at desc);
```
- **`position_m` trigger:** copy `route_markers_set_position()` from `20270129_001` verbatim (ST_LineLocatePoint × geography length), guarded for null lat/lng (a condition without an anchor leaves `position_m` null).
- **RLS (copy `route_reviews` insert-gate exactly):**
  - SELECT: public via `private.is_route_visible_to(route_id, auth.uid())` (owner/public/club) + owner-self read of own conditions.
  - INSERT: `to authenticated with check (auth.uid() = user_id and exists (select 1 from routes where routes.id = route_conditions.route_id))` — gates on route visibility, blocks planting rows on enumerated private route ids.
  - UPDATE/DELETE: owner only (`auth.uid() = user_id`). Add a route-owner DELETE so an owner can clean up spam on their own route (mirror the rationale in `20260627_001`'s header).
- **`*_for_viewer()` read RPC:** `route_conditions_for_viewer(p_route_id uuid)` SECURITY DEFINER — returns visible conditions and **redacts the lat/lng of any condition anchored inside one of the route owner's privacy zones for non-owner viewers** (decisions §33; mirror `route_markers_for_viewer`). The web/mobile read goes through this RPC, not a raw select.
- **Narrow unions in lockstep:** add `condition` + `severity` to `apps/web/src/lib/types.ts` as TS unions (`RouteConditionKind`, `RouteConditionSeverity`) overlaid via `Omit & {...}`, and append both `(route_conditions, condition)` and `(route_conditions, severity)` to the `PAIRS` array in `apps/web/scripts/check_constraint_unions.mjs` so `parity-types` guards drift. Dart treats both as raw `String`.
- **Two codegen passes (mandatory, both committed in the migration commit):**
  - `cd apps/backend && npm run gen:types` → `apps/web/src/lib/database.types.ts`
  - `cd ../.. && dart run scripts/gen_dart_models.dart` → `packages/core_models/lib/src/generated/db_rows.dart`
  - Verify locally with `cd apps/backend && supabase db reset` first (CI's `parity-types` + `schema-codegen-drift` gate it).
- **Offline tile packs + turn cues need NO schema** — tile packs are an on-disk cache (a sibling-file concern like the offline pin, decisions §64); turn cues are derived pure logic.

## Web implementation (canonical)
Web is canonical for **condition reports** (a feature surface — build here first,
mirror to mobile). Offline tile packs + turn-by-turn voice are device-led
(physical-exception list, §24) and are **mobile-only** — web gets neither.
- `apps/web/src/lib/core/data.ts`: `fetchRouteConditions(routeId)` (calls `route_conditions_for_viewer`, fails closed to `[]`), `addRouteCondition(input)`, `deleteRouteCondition(id)`, `asRouteCondition(row)` — copy the `route_markers` helpers (lines 5200–5260).
- `apps/web/src/lib/types.ts`: `RouteConditionKind`, `RouteConditionSeverity`, `RouteCondition` overlay (copy the `RouteMarker` block at lines 83–95).
- `apps/web/src/lib/components/RouteConditions.svelte`: a panel listing conditions newest-first (condition chip + severity colour + relative age + note + optional "at X km"), with a "Report condition" composer (kind dropdown + severity + note + optional drop-a-point-on-the-map anchor) for signed-in users who can see the route. Mirror `RouteReviews`/`SegmentsPanel.svelte`. Severity colour + age decay (a 30-day-old "muddy" report is faded vs a 1-day-old one) computed by the parity helper below.
- Mount `RouteConditions.svelte` in `apps/web/src/routes/routes/[id]/+page.svelte` (and the shared/public route view) below the existing reviews/segments panels.

## Mobile implementation (Android + iOS twin)
All `lib/`+`test/` edits mirrored byte-identical to `apps/mobile_ios/` per commit
(decisions §39). No new nav destination (6-tab ceiling untouched — everything
hangs off route-detail and the run screen).

### A. Condition reports (mirror web)
- `apps/api_client` (`packages/api_client`): typed `fetchRouteConditions` / `addRouteCondition` / `deleteRouteCondition` (route through `ApiClient`, not raw Supabase — mobile rule).
- `packages/core_models`: `RouteCondition` domain model if the row shape isn't 1:1 (it is close — likely just the generated row + the two raw-string union fields).
- `apps/mobile_android/lib/widgets/route_conditions.dart`: panel + report composer, sibling of `widgets/route_photos.dart` / `widgets/segments_panel.dart`. Owner + route-visibility gate the report affordance; report sheet uses `showFullScreenForm` / the modal idiom. Self-fetches on mount; failures fall back to an empty state (L4). Mounted on `route_detail_screen.dart` (full controls) + `public_route_screen.dart` (read-only).

### B. Offline tile packs
- `apps/mobile_android/lib/offline_tile_pack.dart`: a `ChangeNotifier`-style store + downloader. On "Save for offline" (the existing `LocalRouteStore.pinOffline` toggle on `route_detail_screen`), enumerate the `{z}/{x}/{y}` tiles covering the route's bbox across the live map's zoom range (cap zoom span + a per-pack tile-count ceiling — guard against a huge route × deep zoom blowing up disk), fetch each tile via the existing tile HTTP path, and write to `${cacheRoot}/offline_packs/<routeId>/{z}/{x}/{y}.png` (a **sibling** of `map_tiles` so the general LRU cache can't evict a pinned pack). Removing the pin deletes the pack dir. Expose progress (`downloaded/total`) for a progress indicator, and a per-pack byte size.
  - **Layered resilience:** the pack downloader is an L4 auxiliary effect — wrap each tile fetch in its own try/catch, never let a failed tile abort the whole pack or the pin toggle; surface "N of M tiles cached, retry" rather than a hard failure. A failed/partial pack must never break the online map path.
- Wire the live map (`widgets/live_run_map.dart` / `tile_cache.dart`) to **check the offline pack dir first** for a route being followed, then fall through to the network/LRU cache. The pack is read-through: present → serve from disk; absent → normal path. This is the only `tile_cache.dart` change.
- Pure helper for tile enumeration goes in the parity pair below (testable without I/O).

### C. Turn-by-turn voice cues
- Generate cues from the polyline via the new parity helper (below), at run start when following a route.
- In `run_screen.dart`, while following a route, on each snapshot compute distance-to-next-turn via the existing `distanceAlongRoute` (route_geometry) and fire a best-effort TTS cue through the existing `_ttsCue(...)` wrapper + `audio_cues.dart` (e.g. announce at ~300 m, ~100 m, and at the turn). Reuse the off-route detection already running in `packages/run_recorder`. **L4:** wrap in `_ttsCue` exactly like the existing split/off-route cues — a TTS failure never disturbs the recording. Gate on a new `Preferences.turnByTurnCues` toggle (Settings → Preferences, default on when audio cues are on) so a road runner can silence it.

## TS↔Dart parity helpers
Two new pure pairs (kept in lockstep, matching test counts; the
`shared-library-syncer` agent flags divergence):
1. **`turn_cues`** — `apps/web/src/lib/routes/turn_cues.ts` ↔ `apps/mobile_android/lib/turn_cues.dart`.
   `generateTurnCues(waypoints, {minTurnAngleDeg, mergeWithinM})` → ordered
   `TurnCue { positionM, bearingInDeg, bearingOutDeg, direction: 'left'|'right'|'slight_left'|'slight_right'|'straight'|'uturn', distanceFromStartM }`.
   Pure geometry over the polyline (bearing deltas at each vertex, threshold to
   suppress noise, merge near-coincident vertices). Builds on `route_geometry`'s
   bearing/length primitives. Even though it's consumed mobile-only today, keeping
   it a parity pair lets web later surface a printable cue sheet and keeps the math
   reviewable on web. (If the user picks an external routing engine — see Open
   questions — this helper instead *consumes* the engine's returned turn list; the
   geometric generator stays as the offline fallback.)
2. **`tile_pack`** — `apps/web/src/lib/routes/tile_pack.ts` ↔ `apps/mobile_android/lib/tile_pack.dart`.
   `tilesForBbox(bbox, minZoom, maxZoom)` → list of `{z,x,y}` (slippy-map math) +
   `estimateTileCount` / a cap guard. Pure — the actual fetch/write stays in
   `offline_tile_pack.dart`. Web side exists for testability + a future
   "download size" preview if web ever offers pack management.

## Tests (same commit as the piece)
- **Backend (pgtap):** `apps/backend/supabase/tests/route_conditions_test.sql` — RLS: owner reads own on a private route, non-owner can't INSERT on an enumerated private route id (the insert-gate), public route is reportable by any signed-in user, owner can delete a foreign condition on their route, `position_m` derived, `route_conditions_for_viewer` redacts an anchor inside an owner privacy zone for a non-owner. (Remember: `runs` fixtures need `metadata.activity_type`; `"request.jwt.claims"` double-quoted; valid hex UUIDs.)
- **Web (Playwright):** `apps/web/tests-e2e/routes/route-conditions.spec.ts` (matching the existing `tests-e2e/clubs|social|messages` layout) — report a condition, see it in the panel, delete own; severity/age rendering; private-route negative (no report affordance when not visible).
- **Parity unit tests (matching counts both sides):**
  - `apps/web/src/lib/routes/turn_cues.test.ts` ↔ `apps/mobile_android/test/turn_cues_test.dart` (+ iOS twin): straight line → no cues, a 90° left → one `left` cue at the vertex, sub-threshold wiggle suppressed, U-turn detected, coincident-vertex merge, empty/1-point input. Aim ~10 each, identical cases.
  - `apps/web/src/lib/routes/tile_pack.test.ts` ↔ `apps/mobile_android/test/tile_pack_test.dart` (+ twin): bbox → correct tile set at one zoom, multi-zoom union, count cap triggers, antimeridian/degenerate bbox. ~8 each.
- **Mobile widget tests:**
  - `apps/mobile_android/test/route_conditions_test.dart` (+ twin): empty state, a seeded condition renders chip + age + note, report composer writes via the api stub, read-only on `public_route_screen`. Bake in the mobile-test gotchas (store I/O `tester.runAsync`, no `pumpAndSettle` on map animations, `showTopBanner` timer).
  - `apps/mobile_android/test/offline_tile_pack_test.dart` (+ twin): downloader with an injected fetcher (mirror `routing.dart`'s `OsrmFetcher` seam) — happy path writes N files, a failing tile is isolated (pack still partially completes), pin-removal deletes the dir, the count cap is enforced.

## i18n keys to add
**All six web locales** (`apps/web/src/lib/i18n/` — the dotted-key catalogues) AND
**all mobile ARBs** (`app_{en,de,fr,es,ja,pt_BR}.arb` + `pt` base, both twins),
real translations, then `flutter gen-l10n` + mirror `lib/l10n/gen/`. Representative:
- `routeConditions.title` / `routeConditionsTitle` → "Conditions"
- `routeConditions.report` / `routeConditionsReport` → "Report condition"
- condition labels: `routeConditionMuddy`, `routeConditionFlooded`, `routeConditionSnowIce`, `routeConditionOvergrown`, `routeConditionClosed`, `routeConditionHazard`, `routeConditionClear`, `routeConditionOther`
- severity labels: `routeConditionSeverityInfo` / `Caution` / `Impassable`
- `routeConditionsAtKm` (placeholder `{distance}`) → "at {distance}"
- `routeOfflinePackDownloading` (`{done}`/`{total}`), `routeOfflinePackReady`, `routeOfflinePackPartial`, `routeOfflinePackSize` (`{size}`)
- turn cues (TTS, mobile-only `tts*`): `ttsTurnLeftIn` / `ttsTurnRightIn` (`{distance}`), `ttsTurnLeftNow` / `ttsTurnRightNow`, `ttsSlightLeft` / `ttsSlightRight`, `ttsUturn`; settings toggle `prefTurnByTurnCues` → "Turn-by-turn voice cues"

## Docs to update
- `docs/product/roadmap.md` item 5: tick the now-shipped sub-features (conditions, offline tile packs, turn cues); update the "still deferred" clause. Record the routing-engine decision once made.
- `docs/product/parity.md`: add/flip a Trail-navigation row's Web (conditions ✓) and Android/iOS (✓) cells; note web is N/A for tile packs + voice.
- `docs/features/integrations.md` or a feature doc: the offline tile-pack design (sibling cache dir, read-through, zoom/count caps) belongs alongside the map-cache notes; the conditions table belongs in `docs/backend/api_database.md` (new table + RLS + the `_for_viewer` RPC).
- `docs/backend/metadata.md`: no change (no `runs.metadata` key added).
- `docs/architecture/decisions.md`: **append three short ADR entries** — (1) the routing-engine choice for turn cues (the open question, once answered); (2) offline tile packs are a sibling on-disk cache (not LRU-evicted, not in Supabase), extending the §64 offline-pin reasoning; (3) `route_conditions` is a `route_reviews`-shaped own table with a privacy-zone-redacting `_for_viewer` RPC.
- `apps/mobile_android/CLAUDE.md` + `apps/mobile_ios/CLAUDE.md`: add the new files (`widgets/route_conditions.dart`, `offline_tile_pack.dart`, `turn_cues.dart`, `tile_pack.dart`) + the new parity pairs to the lockstep list in the root `CLAUDE.md`.
- `apps/web/CLAUDE.md`: note `RouteConditions.svelte` + the new data.ts helpers + the two parity pairs.

## Gating / compliance
- **No paywall.** All three are free capabilities.
- **Privacy (must be fail-closed):** condition anchors can leak location, so the
  read path MUST go through `route_conditions_for_viewer` (SECURITY DEFINER,
  privacy-zone-redacting for non-owners) — the same §33 contract as
  `route_markers_for_viewer` / `clip_track_for_user`. `fetchRouteConditions`
  fails closed to `[]` on RPC error. This is a privacy-boundary surface; flag it
  for the privacy reviewer at PR time (a `/audit/privacy-zones` run) — but write
  the whole code path now behind the fail-closed RPC; the review is a pre-deploy
  gate, not a reason to stub (CLAUDE.md "Compliance sign-offs gate prod, not code").
- **No third-party credential gate** unless an external routing engine is chosen
  for turn cues (see Open questions) — the offline geometric generator needs no
  key, so the feature ships fully without one; an external engine would be an
  additive enhancement behind its own key.

## Commit plan (ordered, path-scoped)
1. **Migration + codegen + pgtap** — `apps/backend/supabase/migrations/20270203_001_route_conditions.sql`, `apps/web/src/lib/database.types.ts`, `packages/core_models/lib/src/generated/db_rows.dart`, `apps/web/scripts/check_constraint_unions.mjs`, `apps/backend/supabase/tests/route_conditions_test.sql`. (Run `supabase db reset` + both generators first.)
2. **Web conditions** — `apps/web/src/lib/types.ts`, `apps/web/src/lib/core/data.ts`, `apps/web/src/lib/components/RouteConditions.svelte`, `apps/web/src/routes/routes/[id]/+page.svelte`, web i18n catalogues, `apps/web/tests-e2e/routes/route-conditions.spec.ts`.
3. **`turn_cues` parity pair + tests** — `apps/web/src/lib/routes/turn_cues.ts` + `.test.ts`, `apps/mobile_android/lib/turn_cues.dart` + `apps/mobile_android/test/turn_cues_test.dart`, iOS twins.
4. **`tile_pack` parity pair + tests** — `apps/web/src/lib/routes/tile_pack.ts` + `.test.ts`, `apps/mobile_android/lib/tile_pack.dart` + test, iOS twins.
5. **Mobile conditions** — `packages/api_client`, `packages/core_models` (if a model is needed), `apps/mobile_android/lib/widgets/route_conditions.dart`, mounts in `route_detail_screen.dart` + `public_route_screen.dart`, mobile ARBs (both twins) + gen-l10n output, `apps/mobile_android/test/route_conditions_test.dart`, iOS twins.
6. **Offline tile packs** — `apps/mobile_android/lib/offline_tile_pack.dart`, the `tile_cache.dart` / `live_run_map.dart` read-through change, pin-toggle wiring in `route_detail_screen.dart`, ARBs, `apps/mobile_android/test/offline_tile_pack_test.dart`, iOS twins.
7. **Turn-by-turn voice** — `run_screen.dart` cue firing, `audio_cues.dart` phrases, `Preferences.turnByTurnCues` + Settings toggle, ARBs, tests, iOS twins.
8. **Docs sweep** — roadmap, parity, api_database, decisions (×3), the CLAUDE.md files.

Path-scope every commit (shared tree). Run the relevant test suite + `dart analyze` / web lint per commit.

## Open questions / decisions owed by the user
1. **Routing engine for turn cues (the flagged decision).** Three options:
   - **(a) Pure geometric generator (recommended default).** Derive turns from the
     saved polyline (the `turn_cues` parity helper). Zero dependency, fully offline,
     works on any route. Limitation: it announces *geometric* bends, not
     road/trail-name-aware instructions ("turn onto Oak St") — fine for following a
     known line, weaker than a true nav engine.
   - **(b) OSRM (already in the stack).** `apps/mobile_android/lib/routing.dart` +
     `apps/web/.../routing.ts` already speak to OSRM for the route builder; OSRM's
     route response includes turn-by-turn `steps`. Reuse it to get named-road cues
     — but it needs connectivity at *cue-generation* time (do it at route-save /
     pin time, cache the cue list on disk for offline playback). The public demo
     server has quota limits (already noted in `routing.dart`).
   - **(c) A dedicated nav SDK (Mapbox Nav / Valhalla / GraphHopper).** Richest, but
     a new dependency + likely a key + cost.
   **Recommendation:** ship (a) as the always-works offline baseline now (it
   unblocks the feature with no external dependency, matching the L1 "basics always
   work" contract), and layer (b) as an opt-in enhancement that pre-computes
   named-road cues at pin time and caches them — falling back to (a) offline. Confirm
   this before building, since it shapes whether `turn_cues` *generates* or *parses*.
2. **Offline tile-pack zoom range + size cap.** What max zoom + per-pack tile
   ceiling (disk budget)? Proposal: z10–z16 for the route bbox, hard cap ~5,000
   tiles/pack with a warning, packs counted against a global offline budget shown in
   Settings. Needs a number.
3. **Tile licensing for offline storage.** Confirm the MapTiler (prod) ToS permits
   bulk-downloading + persisting tiles for offline use; if not, the offline pack
   must use the self-hosted Protomaps/PMTiles path (`docs/ops/protomaps_local_setup.md`)
   for prod. This is a hard external gate on shipping tile packs — flag to the user.
4. **Condition freshness/expiry.** Should stale conditions auto-expire (e.g. a
   "flooded" report older than 30 days stops showing) or just fade? Proposal: never
   delete; the parity helper fades by age and the UI lets the reporter/owner delete.
   Confirm the decay policy.

## Sequencing for the implementer
1. Read `route_reviews` (`20260414_001` + the `20260627_001` insert-gate) and `route_markers` (`20270129_001`, incl. `route_markers_for_viewer` + the `position_m` trigger) — these are the templates for the table, RLS, and the privacy-redacting read RPC.
2. Resolve **Open question #1** (routing engine) and **#3** (tile licensing) with the user — both change what gets built. #2 + #4 can default per the proposals.
3. Write the `route_conditions` migration (copy the trigger + RLS + `_for_viewer` RPC), `supabase db reset`, run both codegen passes, add the `check_constraint_unions.mjs` pairs, write the pgtap. Commit (piece 1).
4. Build web conditions end-to-end (types → data.ts → `RouteConditions.svelte` → mount → i18n → Playwright). Commit (piece 2).
5. Build the `turn_cues` then `tile_pack` parity pairs with matching tests both sides + iOS twins. Commits (pieces 3, 4).
6. Mirror conditions to mobile (api_client → widget → mounts → ARBs → tests → twin). Commit (piece 5).
7. Build offline tile packs (downloader + read-through + pin wiring + tests + twin). Commit (piece 6).
8. Build turn-by-turn voice (cue firing + phrases + Settings toggle + tests + twin). Commit (piece 7).
9. `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` (and `test/`) empty after each mobile commit. Run the privacy-zones audit on the conditions surface.
10. Docs sweep (piece 8): roadmap, parity, api_database, three decisions entries, the CLAUDE.md files.
