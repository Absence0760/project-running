# Predictive live tracking — "will they make the next cutoff?"

> **STATUS: shipped web + mobile (2026-06-14).** `/live/[id]` next-cut-off card +
> `live_spectator_screen.dart`, backed by the `route_geometry` (`distanceAlongRoute`)
> and `live_cutoff_eta` parity pairs. See [decisions.md § 156](../architecture/decisions.md#156-predictive-live-tracking-reuses-the-roadbook-cutoff-legs-and-fails-to-unknown-when-the-fix-is-stale)
> for the staleness/ETA contract and the [flows.md spectator section](flows.md#predictive-next-cut-off-will-they-make-it).
> The brief below is preserved as the design record.
>
> **Decisions taken vs the open questions below:** pace window = recent flat pace
> over the last ~5 pings; **flat** pace (grade-adjusted remaining deferred, as on
> `checkpoint_projection`); flip to `unknown` reuses `live_freshness`'s `stale`
> bucket (and also when pace is unknown). Follow-ups: grade-adjusted remaining,
> an EWMA pace window.

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
  to its route via `runs.route_id`. When the latest `live_run_pings` row carries
  `coarse=true` (the privacy-zone last-seen carve-out, migration
  `20270121_001`), the dot renders as an approximate hollow amber ring + an
  "Approximate / last seen near here" badge on both clients so a SAR watcher
  reads it as a ~1 km cell, not a precise fix — distinct from, and orthogonal
  to, the staleness badge. The multi-runner event leaderboard
  (`/live/event/[id]/[instance]/+page.svelte`) consumes the same `freshnessFor`
  per row: each on-course runner shows an "Updated N ago" readout and flips to a
  DELAYED badge + stale row once past the window, so a lost-signal runner is
  never shown as fresh-current on the board either. The same `coarse=true`
  last-seen carve-out was extended to `race_pings` (migration `20270309_001`):
  an in-zone race ping is retained coarsened + flagged rather than dropped, and
  the event leaderboard renders the coarse row with the same amber
  "Approximate / last seen near here" chip + a hollow amber map marker (the
  MapLibre circle layers switch to a wider warning halo + a transparent-fill
  amber ring via a data-driven `['case', ['get', 'coarse'], …]`). Web-only —
  there is no mobile event-live spectator surface reading `race_pings`
  (`race_controller.dart` only broadcasts), so the mobile coarse rendering
  stays scoped to the solo `/live/[id]` twin.
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
   Honour staleness (show "last known" + suppress the verdict when stale). The
   suppressed (`unknown`) state distinguishes its two causes on both platforms:
   a **stale** fix reads the amber-delayed `live.cutoffSignalLost` copy
   ("Signal lost — can't project arrival") — web adds the DELAYED-amber card
   border, mobile renders the line amber w700 matching its Delayed freshness
   treatment — while a merely still-connecting fix (a fresh single ping, no
   pace yet) keeps the neutral `live.cutoffWaitingSignal` /
   `liveCutoffWaitingSignal` line, so a runner who went dark mid-race is never
   mislabelled as still starting up. (Mobile mirror shipped 2026-07-11 —
   `_CutoffCard.stale` on `live_spectator_screen.dart` + the
   `liveCutoffSignalLost` ARB key in all seven catalogues.)
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
