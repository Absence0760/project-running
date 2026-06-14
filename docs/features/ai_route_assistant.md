# AI route assistant — natural-language route requests + descriptions

**Status: BOTH HALVES BUILT (web).** A thin LLM layer that *bookends* the route
generator: turn a plain-English request into generation constraints, and turn a
generated route into a plain-English description. Written 2026-06-10. Pairs with
the route generators ([route_loop_generation.md](route_loop_generation.md),
[graph_cycle_loop_generation.md](graph_cycle_loop_generation.md)) and their
preference layer.

- **Component B (description) — shipped (web).** `/routes/[id]` renders a
  localised templated sentence instantly and, for Pro users, calls
  `/api/coach/route-describe` (`claude-opus-4-8`) for an AI paragraph, falling
  back to the template on every failure (`decisions.md § 151`). The
  `route_describe/handler.ts` + `route_describe_client.ts` + Lambda
  `/route-describe` dispatch.
- **Component A (request) — shipped (web, 2026-06-14).** A "Describe the route
  you want" box on `/routes/new` calls `/api/coach/route-request`
  (`claude-opus-4-8`, **forced tool_choice**), which extracts a strictly
  validated constraints object the existing generator consumes. The LLM never
  routes; `route_request/constraints.ts` (`validateConstraints`) is the single
  trust boundary — every field is clamped/whitelisted before it can reach the
  generator. Pro-gated, fail-closed; the manual form is unaffected on any
  failure. Files: `route_request/handler.ts` + `route_request/constraints.ts` +
  `route_request_client.ts` + the `/api/coach/route-request` SvelteKit endpoint
  + the coach Lambda `/route-request` dispatch. The NL box populates distance +
  surface and surfaces shape / avoid-highways / assumed fields as a review hint.
  Tests: `constraints.test.ts` (clamp/validate) + `handler.test.ts`
  (pre-Supabase branches) + Playwright `route-request.spec.ts` (mocked
  endpoint).

## Core principle: the LLM is the interface, not the router

Route generation is a **deterministic graph problem**, and LLMs are unreliable at
spatial/graph reasoning — they can't emit valid road-following coordinates, hit a
precise distance, or avoid hallucinating streets. So the LLM **never generates
geometry**. It does the two things it's genuinely good at — understanding intent
and writing prose:

```
NL request ─(LLM extract)→ constraints ─(graph engine)→ real loop ─(LLM)→ description
```

The engine owns correctness; the LLM owns intent and expression.

## Component A — natural language → constraints

*"A quiet 5k avoiding the highway, through the park"* → a validated constraint
object the generator already understands:

    { targetDistanceM: 5000, unit: 'km',
      avoid: ['motorway','trunk','primary'],
      prefer: ['residential','park'],
      culDeSacs: false, start: <current | named place> }

- **Structured extraction / tool-use**, not free text. Reuse the existing
  Anthropic transport in `apps/web/src/lib/coach/` (`providers.ts`) + the coach
  Lambda (decisions §53). Force a tool / JSON-schema response so the output is a
  typed constraint object, never prose.
- **Validate before trusting.** Parse the LLM output against the same schema the
  generate endpoint enforces (clamp distance to the slider range, whitelist the
  `avoid`/`prefer` tag sets, reject unknowns). The engine stays the source of
  truth; a hallucinated constraint is dropped, not executed.
- **Ambiguity** → fill from sensible defaults and surface what was assumed ("5 km
  loop from your location, avoiding main roads"); let the user adjust. Don't block.

## Component B — route → plain-English description

A generated route → *"A 5.2 km loop up Oak St into Forest Hills, a gentle climb to
the water tower, then a flat return along the river path."*

- Input is **structured**: ordered street names (from OSM / the graph), distance,
  elevation profile + total vert, features passed (parks/water), turn count. The
  LLM summarises that — it isn't inventing the route.
- **Templated fallback** (no LLM): "5.2 km loop · 71 m gain · mostly residential"
  from the same structured data, so the feature degrades to a cheap deterministic
  string when the LLM is unavailable or cost-gated.

## Architecture + reuse

- Server-side, beside the generate handler. Reuses the **existing coach
  infrastructure** — the Anthropic provider, the streaming Lambda, the paywall
  plumbing — so no new transport and no new sub-processor.
- A text box on `/routes/new` ("describe your run") feeds Component A → the
  generate endpoint → Component B renders the description under the route.
- **Generator-agnostic**: it sets constraints + describes results regardless of
  which engine (round_trip / polygon / graph-cycle) is underneath.

## Guardrails

- **Cost + paywall.** LLM calls cost money + latency. The AI Coach is already
  Pro-gated ([paywall.md](paywall.md)); gate the NL/description LLM calls the same
  way, with the templated description as the free default. Cache by request text.
- **Privacy.** The NL request + start coordinates go to Anthropic — the *same*
  sub-processor and posture as the coach (already disclosed). No new third party,
  but record the start-location egress in the sub-processor list.
- **Injection.** The surface is small (the output is a constraint object the engine
  re-validates), but hold the line: never let extracted text reach a shell, a SQL
  query, or `{@html}`; only typed, whitelisted fields cross into the engine.

## Phases + effort

- **P1 — description first (cheap, low-risk, ~1–2 days)**: structured route summary
  → templated string + an optional LLM-prose upgrade. Ships value without the
  harder NL parsing and exercises the route→text data path.
- **P2 — NL → constraints (~2–3 days)**: the tool-use extraction + schema
  validation + the `/routes/new` text box, wired to the generate endpoint.
- **P3 — ship (~1–2 days)**: paywall gating, caching, sub-processor note, e2e
  (mocked LLM), docs.

**Total ≈ 4–7 days.** Independent of the v3 graph work — it layers on whatever
generator exists — but far more expressive once the preference layer
([graph_cycle_loop_generation.md § Extension](graph_cycle_loop_generation.md))
lets `avoid`/`prefer` actually bite.

## Recommendation

Build **Component B (description) first** — cheap, reuses the existing AI infra,
has a deterministic fallback, and delivers a visible "nice" feature with zero
correctness risk. Then **Component A (NL → constraints)** once the preference layer
exists to honour `avoid`/`prefer` (until then the constraints are mostly distance,
which the slider already covers). Keep the hard line throughout: **the LLM
translates and describes; the graph engine routes.**
