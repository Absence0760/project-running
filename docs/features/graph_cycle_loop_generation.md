# Graph-cycle loop generation (v3) — BUILT

**Status: BUILT (2026-06-10) — code-complete + live-validated; prod deploy is operator-gated.** The durable fix for
"Generate a route by distance" producing *clean neighbourhood loops* everywhere,
not just where the street grid happens to be roughly circular. Successor to the
polygon generator ([route_loop_generation.md](route_loop_generation.md), v2, now
retired) and the GraphHopper `round_trip` fallback
([decisions §137](../architecture/decisions.md)). Written 2026-06-10 after a user
observed that even with good distance accuracy, the generated route "still didn't
use the loop in the neighbourhood."

**What shipped (see § Built results):** the `apps/graph_cycle` Go sidecar (foot
graph from the OSM PBF + disjoint-path cycle search + HTTP API), `graph_cycle.ts`
wired graph-cycle-FIRST into `handleGenerate` with the `round_trip` fallback, the
polygon path deleted, `GRAPH_CYCLE_URL`/`GRAPH_CYCLE_API_KEY` threaded through the
SvelteKit `+server.ts` and the generate-route Lambda in parity, unit + e2e tests,
a CI job, and a `release-graph-cycle.yml`. **Operator-gated remainder:** the Fly
app create + volume + PBF seed + secret + first deploy (see § Deploy handoff).

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

## P0 spike — results (2026-06-10, green-light)

Ran the P0 spike (Overpass foot graph + Dijkstra + disjoint-path cycle search +
`areaEfficiency`, pure stdlib — `osmnx` wraps the same Overpass→graph step).
Verdict: **build it.**

| Start | result | areaEff | |
|---|---|---|---|
| Medium (Reston) | 5246 m (+5%) | **0.60** | clean round loop ✓ |
| Dense (Arlington) | 4391 m (−12%) | **0.42** | clean loop ✓ |
| Sparse (report `37.6518`) | 4942 m (−1%) | 0.06 | spur — no clean 5 km loop ✗ |

- **Graph-cycle search decisively beats geometry** where loops exist — real clean
  loops (areaEff 0.42–0.60, confirmed visually) vs the v2 polygon generator's
  *zero* at the same starts.
- **The sparse report start is genuinely loop-poor** — a 4th independent
  confirmation. Strict edge-disjoint paths fail at *every* far-point there
  (`p2_strict = 0`: a bottlenecked network with no second way back), and even with
  edge reuse the best shape is areaEff 0.06 (a spur). No generator can conjure a
  loop the streets don't contain.
- **Bonus — it answers the loop-poor case for free.** Sweeping targets at that
  start, the search reports the *largest clean loop achievable*: ~4.5 km (areaEff
  0.22), clean up to ~4 km, then collapsing to spurs at 5 km. That is exactly the
  data the deferred loop-poor 3-way probe needs, so graph-cycle **subsumes that
  follow-up**.

Two P1 implementation notes the spike surfaced: (1) use **penalised edge reuse**
(~×8), not strict edge removal — strict disjointness fails in bottlenecked sparse
networks; (2) wire the largest-clean-loop the search already finds into the
loop-poor UX.

## Built — results (P1–P3, 2026-06-10)

P1–P3 are code-complete. The validated P0 algorithm was ported verbatim into a
standalone Go sidecar; the only remaining work is the operator-gated Fly deploy.

**What landed:**
- **P1 — `apps/graph_cycle` Go sidecar.** Two-pass OSM PBF parse (`paulmach/osm`)
  → in-memory foot graph (OSRM-foot-profile-equivalent access filtering, CSR
  adjacency, uniform-grid nearest-node index); sparse radius-capped Dijkstra with
  penalised (×8) edge reuse; `SearchCycle` (direction-sampled far-points,
  disjoint-path cycles, `areaEfficiency` scoring, in-band→roundest else
  closest-to-target selection + largest-clean-loop); HTTP API
  (`/health` · `/cycle` · `/route` · `/nearest`) behind an in-process,
  fail-closed `X-Engine-Key` guard. Distroless image + `fly.toml` +
  `docker-compose` + `Makefile` + CI `test-graph-cycle` job. ~40 Go unit tests.
- **P2 — web wiring.** `graph_cycle.ts` (sidecar client mirroring `graphhopper.ts`)
  wired **graph-cycle-FIRST → round_trip fallback** in `handleGenerate`; the v2
  polygon generator deleted; `GRAPH_CYCLE_URL`/`GRAPH_CYCLE_API_KEY` threaded
  through the SvelteKit `+server.ts` and the generate-route Lambda in parity;
  unit tests for the client + the full fallback chain; the e2e
  `generate-loop.spec.ts` reframed onto graph-cycle.
- **P3 — `release-graph-cycle.yml`** (deploys the Fly app on a `graph-cycle@*`
  tag, mirroring `release-osrm.yml`), Terraform Lambda-env wiring, docs (this
  doc + decisions §137 + the sub-processor changelog).

**Live measurement** (local Virginia extract, 405 MB → **14.2 M nodes / 29.4 M
edges**, graph built in **27.7 s**; 5 km target):

| Start | tier | result | areaEff | latency | largest clean loop |
|---|---|---|---|---|---|
| Richmond downtown `37.5407,-77.4360` | dense | 4715 m (−6%) | **0.574** | 537 ms | 6530 m @ 0.49 |
| The Fan `37.5545,-77.4620` | dense residential | 4451 m (−11%) | **0.502** | 482 ms | 6323 m @ 0.26 |
| Report start `37.6518,-77.3614` | sparse / loop-poor | 5676 m (+14%) | 0.145 | 260 ms | 12822 m @ **0.637** |

The dense starts trace genuinely round loops (areaEff 0.50–0.57) where the v2
polygon sweep found *zero*. The report start is confirmed loop-poor a 5th way:
the best ~5 km cycle barely clears the 0.12 spur floor (0.145), and the only
truly round loop there needs ~12.8 km — exactly the data the deferred loop-poor
probe wanted, surfaced for free as `largestClean`. Per-request latency (82–537 ms
on a 14 M-node graph) sits comfortably inside the few-seconds budget.

### Loop-poor 3-way choice — BUILT (2026-06-13)

The largest-achievable-loop probe + the explicit 3-way choice (the original v2
deferral, then "subsumed" by graph-cycle's `largestClean`) is now wired
end-to-end. `largestClean.distanceM` from the sidecar is threaded through
`parseLargestCleanM` → `fetchGraphCycle` (now returns `{ loop, largestCleanM }`)
→ `handleGenerate` → the 200 body as `largestLoopM` — attached **only** when the
served loop is a round_trip out-and-back fallback AND the largest clean loop is
>5% larger than what was served (so we never offer a "better" loop the same size
as the fallback). The `+server.ts` / Lambda pass the body through verbatim.
`RouteBuilder` reads `largestLoopM` and emits it via `ongeneratemismatch`;
`/routes/new` replaces the single "use X instead" affordance with the three
honest choices: **(a)** generate the largest real loop nearby ("best loop near
you is ~X km" — re-runs generation at that distance), **(b)** accept the
achievable out-and-back distance, **(c)** try a different start (clears the route
and drops into start-picking). When the graph search reports no `largestClean`,
choice (a) is hidden and the user still gets (b) + (c). Unit-pinned in
`graph_cycle.test.ts` (threading + the >5% gate) and `generate-loop.spec.ts`
(the 3-way surfacing + best-loop re-generate).

In the same change, the round_trip-fallback **in-band selection** was tightened
toward target: `select.ts` now scores in-band candidates by roundness *discounted
by distance-from-target* (`inBandScore`) instead of pure "roundest wins", which
had surfaced a +8–11% loop in dense grids when a near-target in-band loop existed.
The graph-cycle multi-distance radius race is the sidecar's own selection; the
web-side fix is the round_trip fallback's selection contract.

## Deploy handoff (operator-gated)

Everything up to the Fly deploy is shipped. To go live (needs Fly + sops access):

1. `flyctl volumes create graph_cycle_data --app graph-cycle --region lhr --size 10`
2. `cd apps/graph_cycle && flyctl deploy --app graph-cycle`
3. Seed the PBF (the SAME extract OSRM uses): `flyctl ssh sftp shell --app graph-cycle` → `put data/region.osm.pbf /data/region.osm.pbf`
4. Set the shared secret equal to the Lambda's `GRAPH_CYCLE_API_KEY` (sops): `flyctl secrets set GRAPH_CYCLE_API_KEY=<value> --app graph-cycle`
5. Add `GRAPH_CYCLE_URL=https://graph-cycle.fly.dev` + the `GRAPH_CYCLE_API_KEY` secret to the generate-route Lambda env (Terraform var + sops; the wiring is in `infra/` — supply the values and `terraform apply`).
6. `flyctl machine restart <id> --app graph-cycle` to parse the PBF, then confirm `/health` reports `nodes > 0` and a `/cycle` call returns a loop.

Until step 5's `GRAPH_CYCLE_URL` is set, `handleGenerate` simply skips graph-cycle
and serves round_trip — no regression. See `apps/graph_cycle/README.md` for the
full recipe.

## Goal / success criteria

- Trace a **real loop on the local street network** of length ≈ ±10% of target,
  with low self-overlap and no gratuitous out-and-back tails (high enclosed-area
  efficiency), **including on irregular grids** where v2 returns nothing.
- Adapt per-location (the loop's shape is whatever the streets allow).
- Latency: a few seconds (user-initiated). Falls back gracefully where no cycle
  near target exists (genuinely loop-poor → round_trip out-and-back + the
  loop-poor 3-way choice, see § Loop-poor 3-way choice).
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
   concatenate them into a **cycle**. **P0 finding:** strict *removal* of the
   `S→F` corridor disconnects the return in bottlenecked sparse networks
   (`p2_strict = 0` at the report start), so **penalise** those edges (~×8) rather
   than removing them — the return prefers disjoint roads but may reuse a lone
   connector where there's no alternative. Disjointness is what kills the
   out-and-back tail `round_trip` leaves; edge-disjoint still permits **node
   reuse** (a figure-8) which the shape score below penalises. (Suurballe's gives
   the optimal *strict* edge-disjoint pair, but penalised reuse is the robust
   choice given the spike.)
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
graph library rather than hand-rolling it. (The **P0 spike already validated the
algorithm** on a live Overpass foot graph + stdlib Dijkstra — see § P0 results — so
P1 is purely the prod graph build, with no remaining algorithm risk.)

## Architecture + fallback chain

- New `graph_cycle.ts` core in `apps/web/src/lib/routes/generate/`, transport-
  agnostic; the SvelteKit route + the Lambda both pass it the sidecar URL.
- **Generate order:** graph-cycle FIRST (when the sidecar is configured) →
  `round_trip` + multi-distance fallback → loop-poor UX. **Retire the v2 polygon
  generator** when graph-cycle ships — the P0 spike showed graph-cycle beats it at
  every start (clean loops areaEff 0.42–0.60 vs polygon's zero), so it adds no
  coverage as a middle tier.
- Selection + the loop-poor shortfall banner are reused unchanged.

## Phases (all DONE — see § Built results)

- **P0 — spike — ✅ DONE (2026-06-10, green-lit)**: validated the algorithm on a
  live Overpass foot graph + stdlib Dijkstra/disjoint-path search (§ P0 results).
- **P1 — Go graph sidecar — ✅ DONE**: `apps/graph_cycle` — PBF → foot graph
  (`paulmach/osm`) + `nearest`/`route`/`cycle` HTTP API, in-process guard,
  distroless image + Fly config; ~40 Go tests; adversarial-reviewed + fixed.
- **P2 — integration — ✅ DONE**: `graph_cycle.ts` + handler wiring
  (graph-cycle-first + round_trip fallback) + selection reuse + unit tests (mocked
  sidecar); polygon retired; `+server.ts` / Lambda parity; e2e reframed.
- **P3 — ship — ✅ DONE (code) / operator-gated (deploy)**: live measurement (VA
  extract), Lambda + Terraform wiring, `release-graph-cycle.yml`, docs/§137 +
  sub-processor note. The Fly app create + volume + PBF seed + secret + first
  deploy need operator access (§ Deploy handoff).

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

## Decisions

**Resolved (by the P0 spike / analysis):**
- **Prod sidecar stack = Go** (matches `job_worker`). `osmnx`/Python was the spike
  tool only — don't ship a Python runtime to prod.
- **Retire the v2 polygon generator** once graph-cycle ships — it beat polygon at
  every spike start, so polygon adds no coverage. Keep `round_trip` (+ multi-
  distance) as the sole fallback.
- **Algorithm = penalised-reuse disjoint-path cycles** (not strict removal) — the
  spike proved strict disjointness fails in bottlenecked sparse networks.

**Resolved at P1 kickoff (2026-06-10):**
- **Where the cycle search runs** → **in the Go sidecar** (`cycleNearTarget` =
  `POST /cycle`): native, next to the graph, one HTTP round-trip per request
  instead of dozens of Node-driven `shortestPath` calls.
- **Prod cost/ops** → **standalone Fly app** (`graph-cycle`), not co-located on the
  OSRM machine. OSRM runs the upstream image with `osrm-routed` as its only
  process; a standalone app mirrors the GraphHopper sidecar exactly and shares the
  same PBF, at the cost of one small auto-stop machine.

## Built — what to read instead of this proposal

The proposal above is the original design record. For the as-shipped system see:
**§ Built results** + **§ Deploy handoff** (above), `apps/graph_cycle/README.md`
(the sidecar), and [decisions §137 amendment](../architecture/decisions.md). The
algorithm was ported verbatim from the P0 spike; nothing in the design changed at
build time beyond the two resolved decisions and the review fixes.

## Extension: route-design preferences (a layer on the graph)

A follow-on to the P0–P3 core — **not** part of it. Once the graph search traces
real loops, user preferences fall out of the substrate as **edge weights, filters,
and scoring terms, not new algorithms**:

- **Hard filters** exclude edges. *Avoid highways* = drop OSM
  `highway=motorway/trunk/primary` (+ their `_link`s) from the search graph.
  Over-filtering can disconnect the graph and force a `null` (loop-poor) → fall
  back; apply as a soft weight first, hard-exclude only on explicit ask.
- **Soft weights** bias the per-edge shortest-path cost. *Stick to neighbourhoods*
  = cheap `residential`/`living_street`, expensive arterials; *quiet / scenic* =
  cheaper near `leisure=park` / `natural=water` / lower road class; *elevation
  preference* = weight by per-edge grade. The disjoint-path search then routes
  through the preferred streets on its own — no special-casing.
- **Post-hoc scoring** ranks candidate loops by a weighted multi-objective:
  distance error + `areaEfficiency` + preference terms (km on quiet roads,
  park/water adjacency, total vert vs a target). "Design principles" live here —
  they're weights in one tunable scoring function.

**Cul-de-sacs are the deliberate exception.** A cul-de-sac is an out-and-back spur
— exactly what `areaEfficiency` penalises and what the user disliked elsewhere. So
*add cul-de-sacs* is an explicit opt-in mode that **inverts** part of the score:
permit a capped number/length of short stubs into quiet dead-ends, crediting
quietness/distance instead of penalising the spur. Separate scoring path, off by
default.

**Some of this needs no v3.** The avoid-highways / prefer-residential pair is
mostly a GraphHopper **custom model** (weight by road class); a `round_trip`
variant honours it today as a cheap interim.

### Avoid-highways / prefer-residential — BUILT (2026-06-14, web-only)

The cheap half shipped as a `round_trip` custom-model variant, no v3 required:

- **UI** — a "Quiet roads (avoid highways)" checkbox in the distance panel on
  `/routes/new`. Off → today's request; on → the page passes `'quiet'` as a fourth
  `generateLoop(target, start, end, preference)` arg, which `RouteBuilder.svelte`
  forwards as `preference` on the `POST /api/routes/generate` body.
- **Server** — `handler.ts` threads the preference through `parseGenerateRequest`
  (an unrecognised value is silently dropped, never a 400). When a known preference
  is set it **skips the graph-cycle sidecar** (which doesn't yet honour preferences
  and would return a clean-but-arterial loop) and runs a custom-model `round_trip`:
  `graphhopper.ts#buildCustomModel('quiet')` emits a `priority` model that
  multiplies `road_class` MOTORWAY/TRUNK/PRIMARY by 0.1/0.2/0.4 and
  RESIDENTIAL/LIVING_STREET by 1.4/1.5. `fetchRoundTrip` then **POSTs**
  `buildRoundTripBody` (with `ch.disable: true`, required for custom models)
  instead of the plain GET.
- **Graceful fallback** — soft weights only (never 0) so the model can't disconnect
  the graph into a `no_route`; and if the preference-aware race still yields nothing
  (engine rejects the model, or no loop), the handler **retries the whole race once
  without the preference**. A preference is an enhancement, never a way to deny a
  buildable route.
- **Out of scope** — mobile (route generation is a web-canonical surface, no mobile
  route builder); and the harder preference set below, which needs v3.

**The full set (scenic, elevation-aware, cul-de-sac mode, multi-objective ranking)
still needs the graph search**, where we own the edges + the scoring.

**Remaining effort:** ~2–3 days on top of a working graph-cycle generator —
scenic/park-adjacency and cul-de-sac mode are the harder half. The natural-language
front-end that *sets* these preferences from a plain-English request is its own
proposal: [ai_route_assistant.md](ai_route_assistant.md).
