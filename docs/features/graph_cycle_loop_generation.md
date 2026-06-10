# Graph-cycle loop generation (v3) — design proposal

**Status: PROPOSAL — not built.** The durable fix for "Generate a route by
distance" producing *clean neighbourhood loops* everywhere, not just where the
street grid happens to be roughly circular. Successor to the polygon generator
([route_loop_generation.md](route_loop_generation.md), v2) and the GraphHopper
`round_trip` fallback ([decisions §137](../architecture/decisions.md)). Written
2026-06-10 after a user observed that even with good distance accuracy, the
generated route "still didn't use the loop in the neighbourhood."

## Problem — why v2 (polygon) and round_trip both fall short

Both current generators reason about **geometry**, not the **graph**:

- **`round_trip`** picks headings and lets the engine build a round trip. It
  meanders and leaves out-and-back tails — it doesn't trace the cleanest circuit.
- **The v2 polygon generator** places via-points on a *ring* and routes between
  them. It only works where the local loop is roughly circular (dense, regular
  grids). On an irregular neighbourhood grid it finds nothing.

**Evidence (live OSRM, start `37.6518,-77.3614`, 5 km target):** a wide-open
polygon sweep — **K = 3/4/5 × 18 rotations × 8 radius fractions = 432 placements**
— found **zero** in-band loops (`areaEfficiency > 0.12`). Yet `round_trip` *did*
return a real 5.24 km loop there. So **a loop exists in the graph** that no
geometric placement can find — because the loop follows an irregular path through
the grid that evenly-spaced points on a circle can never trace. Geometry guesses;
it doesn't *search the streets*.

The only thing that reliably traces the circuit a human would pick is to operate
on the **actual local street graph** and search it for cycles.

## Goal / success criteria

- Trace a **real loop on the local street network** of length ≈ ±10% of target,
  with low self-overlap and no gratuitous out-and-back tails (high enclosed-area
  efficiency), **including on irregular grids** where v2 returns nothing.
- Adapt per-location (the loop's shape is whatever the streets allow).
- Latency: a few seconds (user-initiated). Falls back gracefully where no cycle
  near target exists (genuinely loop-poor → existing shortfall UX).
- Server-side + transport-agnostic (decisions §53), same as the existing handler.

## Approach: direction-sampled disjoint-path cycles on a local foot graph

Operate on a **pre-extracted routable foot graph** (nodes = intersections, edges
= road segments with length + foot-permission). For a start `S` and target `D`:

1. **Sample candidate far-points** `F` across many bearings AND a *spread* of
   network shortest-path distances around `D/2` from `S`. The final loop length is
   **not precisely controllable** — the disjoint return path can detour well past
   `D/2` — so, exactly as in the `round_trip` multi-distance race, we sample widely
   and keep whichever *actual* loop lands closest to target rather than trusting a
   single divisor.
2. For each `F`, find **two near-disjoint shortest paths** `S→F` and `F→S` and
   concatenate them into a **cycle**. Suurballe's algorithm gives the optimal
   edge-disjoint pair; the cheap heuristic (route `S→F`, remove *both directions*
   of its edges, route `F→S`) is fine for the spike. Disjointness is what kills the
   out-and-back tail `round_trip` leaves. Edge-disjoint still permits **node
   reuse** (a figure-8 touching one intersection twice) — the shape score below
   penalises that; node-disjoint is cleaner but fails far more often in sparse
   graphs, so prefer edge-disjoint + scoring.
3. **Score** each cycle: distance error `|len − D|` (primary), the existing
   `areaEfficiency` shape metric (enclosed area vs equal-perimeter circle), and a
   self-overlap penalty. Reject near-degenerate results.
4. **Pick** the best by the v2 selection contract: in-band → roundest, else
   closest-to-target. Return `null` when no cycle clears the bar (loop-poor →
   existing shortfall UX). Generation is deterministic; "Generate again" re-rolls
   the far-point direction among the top-scored candidates for variety (as v2).

This is the classic "round trip via two disjoint paths," done on a real graph we
control rather than guessed geometrically. It is far more tractable than full
cycle enumeration (a handful of shortest-path computations per candidate `F`) and,
crucially, it **searches the streets**, so it finds the loop the 432-sample
geometric sweep could not.

### Alternatives considered
- **Budgeted DFS / branch-and-bound cycle search** — exact but exponential; needs
  aggressive distance-to-`S` pruning + visit penalties. Higher quality ceiling,
  far higher complexity. Keep as a future upgrade if disjoint-paths underperforms.
- **Biased random walks that close near `S`** — simple, generates variety, but
  noisy shape and weak distance control. Possible variety source, not the core.
- **Isochrone boundary + connect** — essentially what `round_trip` approximates;
  no better than v2 on irregular grids.

## Data source — the crux decision

The cycle search needs a **local routable graph**. Options:

| Source | Pro | Con |
|---|---|---|
| **Pre-extracted foot graph sidecar from our PBF** (recommended) | Fast, offline, consistent with OSRM/GraphHopper (same OSM extract), no external rate limits | New sidecar to build + deploy + keep PBF-in-sync |
| Overpass API (live OSM) | No graph to maintain | External dependency, rate-limited, slow/fragile per-request, server egress of coordinates |
| Export OSRM/GraphHopper's internal graph | Reuses a running engine | Neither exposes its graph as a usable API; brittle |

**Recommended for prod:** a **Go sidecar** (matches `apps/job_worker/`) that parses
the same regional `.osm.pbf` the OSRM stack already downloads into an in-memory
foot graph and exposes a tiny HTTP API: `nearest(lat,lng)`, `shortestPath(a,b,
excludedEdges)`, and ideally `cycleNearTarget(start, targetM)` so the heavy search
lives next to the graph. Reuse `apps/job_worker/osrm/data/region.osm.pbf`.

**Be honest about the cost:** building a *correct foot-routable* graph from a PBF
— foot-access tags (`foot=no`/`access`/`highway` filtering), barriers, splitting
ways at intersections into routable edges — is most of P1. It's a slice of what
OSRM/GraphHopper do at build time, **not a trivial parse**, so use an existing OSM
graph library rather than hand-rolling it. And **prototype in Python first** (see
Phases): `osmnx.graph_from_point(..., network_type='walk')` yields a ready foot
graph plus `networkx` shortest-path / edge-disjoint helpers in a few lines, so the
*algorithm* can be validated in hours before committing to the Go graph build.

## Architecture + fallback chain

- New `graph_cycle.ts` core in `apps/web/src/lib/routes/generate/`, transport-
  agnostic; the SvelteKit route + the Lambda both pass it the sidecar URL.
- **Generate order:** graph-cycle FIRST (when the sidecar is configured) →
  `round_trip` + multi-distance fallback → loop-poor UX. The v2 polygon generator
  is likely **retired** once graph-cycle ships (it's strictly weaker), or kept as
  a cheap middle tier — decide after the spike.
- Selection + the loop-poor shortfall banner are reused unchanged.

## Phases + effort

- **P0 — Python spike (de-risk the algorithm, ~½–1 day)**: `osmnx` foot graph +
  `networkx` edge-disjoint-path cycles + the `areaEfficiency` / distance scoring.
  Prove it traces a clean loop at `37.6518` (where 432 polygon placements found
  nothing) and on dense/medium starts. **Gate everything below on this** — it
  answers "does graph-cycle search actually beat geometry here?" before any prod
  infra is touched.
- **P1 — Go graph sidecar (~3–4 days)**: the validated approach as a prod service —
  PBF → foot graph (via an OSM graph library, not hand-rolled) +
  `nearest`/`shortestPath`/`cycleNearTarget` HTTP API, validated against OSRM. The
  graph build is the bulk of this.
- **P2 — integration (~2 days)**: `graph_cycle.ts` + handler wiring
  (graph-cycle-first + fallback chain) + selection reuse + unit tests (mocked
  sidecar).
- **P3 — ship (~2–3 days)**: e2e + measure across density tiers + Lambda parity +
  **deploy the sidecar to prod (Fly, alongside OSRM/GraphHopper)** + docs/§137 +
  sub-processor note (the sidecar is our infra, same posture as OSRM — no new
  third party).

**Total ≈ 8–10 days** (P0 a fraction of that). The new prod graph sidecar — not
the algorithm — is the real cost; the **P0 spike answers the only question that
matters before you pay it**.

## Risks + mitigations

- **New prod service.** A graph sidecar must run + be operated in prod (Fly),
  with the PBF kept in sync with the OSRM/GraphHopper extracts. Mitigate: reuse
  the exact same PBF + the existing Fly + job_worker patterns; one extract feeds
  all three engines.
- **Disjoint-path failures in sparse graphs** (no second path back). Mitigate:
  this is the genuine loop-poor signal → fall through to round_trip + the
  shortfall UX. No regression vs today.
- **Latency** of many shortest-path computations. Mitigate: do the search in the
  sidecar (native, next to the graph); cap candidate count; cache per-start.
- **Coverage** must match where users start. Mitigate: same regional PBF as OSRM
  governs coverage; outside it, fall back.
- **Scope creep into a full routing engine.** Mitigate: disjoint-paths only;
  budgeted-DFS is explicitly a *later* upgrade, not part of this build (P0–P3).

## Open decisions (resolve before building)

1. **Prod sidecar stack** — Go (matches `job_worker`; recommended) once the P0
   `osmnx` spike validates the algorithm. Don't ship `osmnx`/Python to prod (a new
   runtime to operate); it's a spike tool only.
2. **Does graph-cycle replace the v2 polygon generator** or layer above it?
3. **Where the cycle search runs** — in the sidecar (recommended, native) vs in
   the Node handler driving sidecar `shortestPath` calls (simpler, more chatty).
4. **Prod cost/ops** of a third map sidecar — acceptable, or co-locate with OSRM?

## Recommendation

Build it — operating on the **real street graph** (rather than guessing geometry)
is the only thing that can trace the neighbourhood loop the user wants, proven by
the fact that a loop exists at the reported start which 432 geometric placements
could not find. Disjoint-path cycles are the recommended graph method (budgeted
DFS is a later upgrade). **But run the P0 Python spike first** (`osmnx` +
edge-disjoint-path prototype, validated at `37.6518` and on dense/medium starts) —
it confirms in hours whether graph-cycle search actually beats geometry, before
you commit to the prod graph sidecar that is the real cost here, not the algorithm.
