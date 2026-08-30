# AI route assistant — natural-language route requests + descriptions

**Status: BOTH HALVES BUILT. Component B (description) ships on web + both mobile twins; Component A (NL → constraints) ships on web.** A thin LLM layer that *bookends* the route
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

## What's shipped (Component A — request → constraints)

A "Describe the route you want" box on `/routes/new` calls `/api/coach/route-request` (`claude-opus-4-8`, **forced tool_choice** `extract_route_constraints`), which extracts a strictly validated constraints object the existing deterministic generator consumes. The LLM never routes; `route_request/constraints.ts` (`validateConstraints`) is the single trust boundary — every field (distance band, shape, surface, avoid-highways, road-design preference) is clamped/whitelisted before it reaches the generator, so a hallucinated value collapses to a safe default. Pro-gated server-side on `is_pro()`, **fail-closed** (unknown Pro status → 503; non-Pro → 403 upsell); purely additive — the manual generator form is untouched on any failure. The box populates distance + surface and surfaces shape / avoid-highways / preference / assumptions as a review hint.

**Road-design preference (2026-08-30, decisions § 797).** `preference` is `'quiet' | 'scenic' | 'cul_de_sac'` — the generator's own `RoutePreference` vocabulary, whitelisted against a `ReadonlySet` exactly as `shape` and `surface` are, so the model cannot invent a fourth. It is the one field whose absence is carried as `null` rather than defaulted: the others fall back to something the runner would plausibly have picked, whereas a defaulted preference would bias every generated route toward a design nobody asked for. When the model names none, one is **derived** from what it did name — `avoid_highways` → `quiet`, then a `trail` surface → `scenic`, with the stated road constraint outranking the surface inference — and the derivation is recorded in `assumptions` so the review panel shows it. `cul_de_sac` is never derived, only asked for: it inverts part of the loop score ([graph_cycle_loop_generation.md § Extension](graph_cycle_loop_generation.md)), so inferring it would hand a runner dead-end spurs. `avoidHighways` stays on the object beside `preference` — the form checkbox binds to the boolean, the generate body carries the enum. Files: `route_request/handler.ts` + `route_request/constraints.ts` + `route_request_client.ts` + the `/api/coach/route-request` SvelteKit endpoint + the coach Lambda `/route-request` dispatch. Tests: `constraints.test.ts` (clamp/validate) + `handler.test.ts` (pre-Supabase branches) + Playwright `route-request.spec.ts` (mocked endpoint).

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
  truth; a hallucinated constraint is dropped, not executed. Shipped as the
  three whitelisted enums (`shape`, `surface`, `preference`) plus the clamped
  distance band — the `prefer` half is the generator's `RoutePreference`.
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
- **Privacy.** The NL request + a coarse place label go to Anthropic — the *same*
  sub-processor as the coach, but **not the same processing purpose**, and that
  distinction cost us a real gap: both endpoints shipped with **no consent gate at
  all** while `/api/coach` had one (issue #734). Reusing `coach_consent_at` was
  not the fix — the copy the user accepted described the Coach using their
  *training data*, so treating it as covering a typed route request would have
  retroactively widened their agreement. Both endpoints now require
  `AI_DISCLOSURE_VERSION_ROUTE_AI` of the versioned consent record
  (`ai_disclosure_version`, migration `20270511_001`), and a user holding only the
  older Coach-scoped acceptance gets a 403 with
  `code: "ai_disclosure_required"` until they accept the widened disclosure in
  Settings → Account. The dev `BYPASS_PAYWALL` flag deliberately does **not**
  reach this gate — it skips a billing check, not a lawful basis. See
  [api_database.md](../backend/api_database.md) and decisions § 571.
- **Where a runner accepts it.** One disclosure component per platform, rendered
  by every host that writes the record: web's `AiDisclosureNotice.svelte` (the
  `/coach` first-use dialog + Settings → Account) and mobile's
  `widgets/ai_disclosure_notice.dart` (the Coach gate, a Settings → Account tile,
  and the route-detail fallback notice, which offers it inline and re-runs the
  enhancement on acceptance). Mobile writes `record_ai_disclosure_consent()`
  directly — the v1 `record_coach_consent()` wrapper has no client left — and
  offers the acceptance whenever the record is not current, missing or stale, so
  the route-detail notice always leads somewhere that can act on it. Both
  platforms branch on the 403 body's `code`, never on the bare status: the
  paywall answers 403 on the same endpoint, and a consent gap shown as a Pro
  upsell sends a runner to buy something that would not unlock it. The templated
  description keeps rendering underneath (decisions § 573).
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
