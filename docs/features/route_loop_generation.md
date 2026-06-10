# Route loop generation v2 — design proposal

**Status: PROPOSAL — not built.** Would augment the GraphHopper `round_trip`
generator ([decisions §137](../architecture/decisions.md)) for the "Generate a
route by distance" feature. Written 2026-06-09 after a user reported generated
loops radiating out on a long road instead of using the dense street grid near
the start. **Refined after a multi-start, multi-distance proof-of-concept — read
"What the PoC found" before committing to a build.**

## Problem

`round_trip` is a **radial heuristic**: per seed it picks one heading, drops a
turnaround point on a circle in that direction, and routes out-and-back-ish. It
never searches the local street graph for a compact cycle, so it can't compose a
tidy loop from the nearby grid.

## What the PoC found (read this first)

Tested **polygon-of-via-points** loops — place K via-points on a ring around the
start, route `start → v1 → … → vK → start` via the live `foot` engine — scored
with the **`areaEfficiency`** metric already in `select.ts` (enclosed area vs a
circle of equal perimeter: 0 for an out-and-back, →1 for a round loop):

| Start | best on-target loop | areaEfficiency | verdict |
|---|---|---|---|
| Dense (Arlington) | 4926 m (−1%) | 0.22 | real compact loop ✓ |
| Medium (Reston) | 4950 m (−1%) | 0.29 | real compact loop ✓ |
| Sparse (the report, `37.6520,-77.3611`) | best 4551 m | **0.00** | out-and-back, not a loop ✗ |

Two conclusions, both load-bearing:

1. **Where loops exist, this is a clear win.** Dense + medium both yield real
   ~5 km loops within −1% of target, vs `round_trip`'s radial out-and-backs. The
   best rotation **varies per start** (dense + medium peaked at 270°, sparse at
   0°), confirming we must *sample* rotations, not fix one.
2. **It does NOT fix the reported sparse start — and nothing can.** Every
   candidate there is a zero-area out-and-back, and probing targets from 1.5 km
   to 5 km found *no* compact loop at any distance. The nearby grid is too small;
   reaching those distances requires leaving it. `round_trip`'s out-and-back
   there is the network's limit, not a bug. No generator can conjure a loop the
   streets don't contain.

**Metric correction (a real bug in the first sketch).** I originally scored
"compactness" as `maxDistFromStart / perimeter`. That is wrong twice over: a
tight out-and-back *cluster* has low max-distance but **zero enclosed area**
(it was being mislabelled "compact"), and a big far-away circle has a low ratio
too. The correct shape metric is the existing **`areaEfficiency`** — distance
handles magnitude, `areaEfficiency` handles loop-vs-spur. Reuse it; do not invent
a max-distance metric.

## Goal / success criteria

- Distance within ~±10% of target **where a loop exists**.
- Real loop shape: `areaEfficiency` above a spur floor (~0.12–0.15).
- Latency: a few seconds (user-initiated "Generate").
- **Honest, helpful behaviour where no loop exists** (see the fallback below) —
  not today's generic "13% short, try a different start."

## Approach: sampled via-point polygons + areaEfficiency selection

Use the routing engine (OSRM — already the manual builder's snapping engine) as
a **routing primitive**; our logic places via-points to force a compact loop.
K = 3 (triangle) is the primary shape — K = 4 blew up far more often in the PoC.

### Search (two-stage, efficient)
1. **Coarse parallel sample**: ~8 rotations × ~4 radii = ~32 independent route
   calls (parallel). Don't fix a rotation — the good one is location-specific.
2. Keep candidates within ±15% of target **and** `areaEfficiency` > floor.
3. **Refine** the radius at the best 1–2 rotations with a few more radii.
   Radius→distance is *mostly* monotonic at a good rotation but snapping breaks
   it, so **sample-and-pick-closest, not strict bisection**.
4. **Reject bad snaps for free**: OSRM `/route` returns `waypoints[].distance`
   (snap distance) — drop a candidate whose via-point snapped too far. No extra
   `/nearest` calls.

Total ≈ 35–45 engine calls per generate; OSRM route calls are ~10–50 ms and
parallelizable → ~0.5–1 s wall-clock.

### Loop-poor fallback (first-class, not an afterthought)
When no candidate clears the distance + shape bar (the reported case):
- Probe + report the **largest real compact loop achievable** nearby (e.g.
  "best loop near you is ~2 km").
- Offer three honest choices: (a) generate that shorter real loop, (b) accept an
  out-and-back to the requested distance (today's `round_trip`), (c) try a
  different start. Strictly better than the current generic warning.

## Architecture

- Server-side in `apps/web/src/lib/routes/generate/`, transport-agnostic so the
  SvelteKit route and the production Lambda both reuse it (decisions §53), same
  shape as today's handler.
- A new placement/score module calls OSRM's multi-waypoint `/route`; extend
  `select.ts` (reuse `areaEfficiency`, add the spur floor + loop-poor detection).
- **Keep `round_trip` as the fallback** for the out-and-back option and as a
  safety net — no regression for areas it already handled.

## Determinism + variety

Deterministic by default (no RNG → reproducible + cacheable). A `variation` index
re-rolls among the top-N scored candidates so "Generate again" yields a different
good loop, replacing `round_trip`'s seed re-roll.

## Phases + effort

- **P1 — core**: via-point placement + (θ,r) sampling + `areaEfficiency` scoring
  + snap-distance rejection; validate dense/medium/sparse. ~1 day. *(PoC already
  retired the core research risk.)*
- **P2 — refinement**: radius sample-refine, variety re-roll, selection polish.
  ~0.5–1 day.
- **P3 — loop-poor UX + integration**: largest-achievable-loop probe + the 3-way
  choice; wire into `/api/routes/generate` (polygon-first, `round_trip`
  fallback). ~1 day.
- **P4 — tests + ship**: unit tests (pure placement/scoring, mocked engine) +
  e2e happy path + measure across density tiers + docs/§137 + Lambda parity +
  tuning. ~1 day.

**Total ≈ 3.5–4 days.**

## Risks + mitigations

- **Some areas have no loop at the target (the reported case).** Detect (nothing
  clears the bar) → loop-poor UX. *Cannot be fixed algorithmically* — set
  expectations.
- Via-point snaps to a bad road → blow-up. Reject via the route's snap distance +
  the distance/`areaEfficiency` bar.
- Engine-call volume > `round_trip`. Coarse parallel + refine only winners; cap
  ~45.
- Self-overlap / figure-8 placements. `areaEfficiency` already penalises
  low-area shapes.

## Recommendation

**Build it — with eyes open.** Validated as a clear win in dense + medium areas
(where most users start: real ~5 km loops at −1% vs radial out-and-backs), and it
forces a genuinely better loop-poor fallback UX. **It will not fix the specific
start in the report** — that location cannot form a compact loop at any distance,
and no generator can change that. So:
- If the goal is "fix that screenshot," this is *not* it — that's a
  network-limited location; the honest fallback UX is the only improvement
  available there.
- If the goal is "much better loops for normal locations + honest, helpful
  behaviour where loops don't exist," it is — recommend P1 first to confirm
  robustness across diverse starts before committing to P2–P4.
