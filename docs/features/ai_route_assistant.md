# AI route assistant — natural-language route requests + descriptions

**Status: Component B (description) SHIPPED — web + mobile. Component A (NL →
constraints) is still a PROPOSAL.** A thin LLM layer that *bookends* the route
generator: turn a plain-English request into generation constraints, and turn a
generated route into a plain-English description. Written 2026-06-10. Pairs with
the route generators ([route_loop_generation.md](route_loop_generation.md),
[graph_cycle_loop_generation.md](graph_cycle_loop_generation.md)) and their
preference layer.

## What's shipped (Component B — route → description)

The "Describe this route" affordance ships on **web and both mobile twins**.
On a route with no stored description the route-detail surface shows a
"Describe this route" action; tapping it renders the **templated baseline
instantly** (offline, no model — `describeRoute` parts → a localised,
unit-aware sentence) and then, **for Pro users only**, calls the Pro-gated
`/api/coach/route-describe` endpoint (`claude-opus-4-8`) for an AI-written
paragraph that replaces the baseline, with an AI-attribution line. Gating is
**fail-closed** end to end:

- **Server**: the endpoint enforces `is_pro()` and degrades to the templated
  text on every failure (`decisions.md § 151`).
- **Web**: `localisedTemplate` (`apps/web/src/lib/routes/route_description.ts`)
  + `route_describe_client.ts` on `/routes/[id]`.
- **Mobile**: the `describeRoute` twin helper
  (`apps/mobile_android/lib/route_description.dart`) feeds an in-screen
  localised template built from the ARB catalogue + `UnitFormat`; the tap runs
  a client-side Pro check (`isPro()`, unknown → not-Pro) and only Pro users hit
  the endpoint via `route_describe_client.dart`. A non-Pro tap surfaces the
  upgrade hint over the templated text; a model failure keeps the templated
  baseline and shows a non-blocking error — the route view never breaks.

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
