# Predictive live tracking — "will they make the next cutoff?"

> **STATUS: handoff spec, not built.** Self-contained brief for an implementing
> session. Read [CLAUDE.md](../../CLAUDE.md) first for the web-first / twin /
> i18n / commit-cadence conventions. Web is canonical; mobile mirrors; iOS twin
> byte-identical.

## Context / why

The live spectator page (`/live/[id]`, mobile `live_spectator_screen.dart`)
shows a runner's position + an honest staleness badge. The Moab 240 / UTMB /
WS100 **spectator** personas don't actually want a dot — they want the answer
to *"is my person going to make the next cutoff?"*. We now have route course
markers with cutoffs ([route_markers.md](route_markers.md)) and the roadbook
cutoff math ([race_roadbook.md](race_roadbook.md)). Fuse them with the live
feed: project the runner's arrival at the next aid/cutoff from recent pace +
remaining distance, and show an on-pace / tight / behind indicator — **without
over-claiming when the position is stale** (the personas' core complaint).

## Reuse (don't re-implement)

- **Live feed + staleness:** `/live/[id]/+page.svelte`, `lib/runs/live_hub.ts`,
  the `live_freshness.ts ↔ live_freshness.dart` parity pair (`freshnessFor` —
  age clamp + stale flag), `live_run_pings` / `race_sessions`. A live run links
  to its route via `runs.route_id`.
- **Route + cutoffs:** `fetchRouteMarkers` (RPC `route_markers_for_viewer`,
  already anon-readable on public routes) + `roadbook.ts` cutoff parsing
  (`parseCutoff`, the `cutoff` leg shape).
- **Distance-along-route:** `route_geometry.ts` (`interpolateAlongRoute`,
  `polylineLengthMetres`) — you need the *inverse* (nearest point on the
  polyline → distance-along-route). `RunMap.svelte` has `nearestTrackIdx`;
  factor a `distanceAlongRoute(point, waypoints)` helper.

## Design

1. **New parity helper** `live_cutoff_eta.ts ↔ .dart`:
   `nextCutoffEta({ distAlongRouteM, recentPaceSecPerKm, roadbookLegs, freshness })`
   → `{ checkpoint, distanceToM, projectedArrivalElapsedS, marginS,
   status: 'on'|'tight'|'behind'|'unknown' }`. Returns `unknown` when the
   position is **stale** (don't fabricate confidence off an 18 h-old fix — this
   is the whole point). Reuse the roadbook cutoff legs for the limits.
2. **Spectator card** on `/live/[id]` + `live_spectator_screen.dart`: "Next
   cut-off" — name, distance to go, projected arrival, a green/amber/red margin
   chip. Gated on: the live run is linked to a route that has cutoff markers.
   Honour staleness (show "last known" + suppress the verdict when stale).
3. **Pace source:** recent average over the last N pings (decide N), or
   effort-adjusted (GAP) remaining distance for a better hill estimate.

No new schema (all reads). Works logged-out (anon spectator).

## Commit cadence

1. `distanceAlongRoute` helper (extend `route_geometry`) + tests.
2. `live_cutoff_eta.ts/.dart` parity helper + unit/mirror tests.
3. Web spectator card + i18n + Playwright (seeded live run + route + cutoff).
4. Mobile mirror (+ iOS twin) + Flutter test.
5. Docs.

## Tests

- Unit: on-pace / tight / behind; **stale → `unknown`** (no false ETA); runner
  past the last cutoff → none.
- Playwright on `/live/[id]` with a seeded finished/live run linked to a route
  with a cutoff; assert the margin chip + that a stale fixture suppresses it.
- Flutter widget test for the card.

## Open decisions for the implementer (ask the user if unsure)

- Pace window (last 3 pings vs whole-run average vs EWMA).
- Effort-adjusted remaining (GAP) vs flat pace for the projection.
- Exactly when to flip to `unknown` (reuse `live_freshness`'s stale bucket).

## Docs

Extend the live-tracking section of [flows.md](flows.md), add a parity row in
[parity.md](../product/parity.md), and a decisions ADR if the staleness/ETA
contract is non-obvious.
