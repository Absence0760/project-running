# apps/web — AI session notes

**The web app is the canonical feature surface for the whole product.** Every user-facing feature lives here unless it is physically impossible in a browser (live GPS recording, device sensors, haptics, OS share sheets — see the exceptions table in [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md)). Mobile (Flutter Android / iOS) and watch (Wear OS Kotlin / watchOS Swift) clients *mirror* this surface and *add* things only a device in hand or on the wrist can do.

**Working rule:** when you're asked to build a feature, build it here first. When you're asked to fix drift between web and mobile, close it by bringing web up to parity with mobile (not the reverse) unless the feature is a physical exception. See [../../docs/product/parity.md](../../docs/product/parity.md) for the live matrix — rows where this app is `✗` or `Partial` on a non-exception feature are the backlog.

**Multi-modal expansion (Phase 4, in progress):** the product expands from running-only to running + gym + nutrition inside one app per platform ([decisions.md § 63](../../docs/architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)). On web that's `Gym` + `Nutrition` sidebar sections plus the unified `Home` and `History`. The web **gym** (`/gym`) and **nutrition** (`/nutrition`, `/nutrition/log`) surfaces have shipped; the cross-modality layer (lift→load, Coach context, History timeline) is live. **These are now ungated** (2026-06-04, §63 amendment): the Gym + Nutrition sidebar items are always present, and the `/dashboard` lift cards + `/history` chips/timeline self-hide purely on **data presence** — matching mobile. The `multi_modal_nav` flag is retired (dormant in `settings.md`, read by nothing — don't add new reads). New gym/nutrition UI should follow the same data-presence self-hiding pattern (no empty card / zeroed stat), not a flag. Don't ship nutrition ahead of the gym-engagement validation gate (decision D3). See [roadmap.md § Phase 4](../../docs/product/roadmap.md#phase-4--multi-modal-gym--nutrition) + [multi_modal.md](../../docs/features/multi_modal.md) for sequencing.

Deployed to AWS — S3 (static SvelteKit build) + CloudFront + Route 53 for everything except `/api/coach`, which deploys as a Node 24 Lambda Function URL routed by a separate CloudFront behaviour. Terraform-provisioned (modules + per-env stacks under `infra/`), runtime secrets via sops + AWS KMS, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the rationale and [deployment.md](deployment.md) for the full plan.

## Stack

- **Framework**: SvelteKit 2 with Svelte 5 (runes/next)
- **Language**: TypeScript
- **Package manager**: npm via the root workspace (`npm run <script> --workspace=apps/web`). The repo bootstrapped with pnpm originally and a root `pnpm-lock.yaml` is still maintained beside `package-lock.json` — most CI jobs install with `npm ci`, the Playwright / live-hub / SSO lanes with `pnpm install --frozen-lockfile`, so both lockfiles are committed and the security overrides must agree across them ([decisions § 730](../../docs/architecture/decisions.md)). There is no `apps/web/pnpm-lock.yaml`. The canonical build path is npm — see [decisions.md § 7](../../docs/architecture/decisions.md). Either works locally; just don't mix.
- **Adapter**: `@sveltejs/adapter-static` for the bulk; `/api/coach/+server.ts` is reused as the body of a hand-rolled Node 24 Lambda handler (no SvelteKit AWS adapter — see [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages))
- **Styling**: custom CSS in `src/app.css`
- **Icons**: self-hosted Material Symbols webfont, rendered as ligatures (`<span class="material-symbols">close</span>`), subset to the icons this tree names — regenerate with `pnpm gen:icon-font` after adding one, see [decisions.md § 780](../../docs/architecture/decisions.md) and [conventions.md § Material Symbols icons](../../docs/architecture/conventions.md#material-symbols-icons).
- **Markdown**: mdsvex

## Folder Structure

**The per-file inventory is [`folder_structure.md`](folder_structure.md)** — what every route, component, store and lib module under `src/` is for. Grep it before adding a route or component, so you extend what exists rather than minting a parallel copy of it.

## Development

```bash
# From the repo root (matches CI):
npm install                              # workspace bootstrap
npm run dev --workspace=apps/web         # Dev server on :7777
npm run build --workspace=apps/web       # Production build
npm run preview --workspace=apps/web     # Preview build on :8888
npm run check --workspace=apps/web       # Type-check src/ + .svelte (svelte-check)
npm run check:e2e-types --workspace=apps/web  # Type-check tests-e2e/ (tsc; § 749)
npm run check:node-types --workspace=apps/web # Type-check scripts/ + lambda/ + svelte.config.js (§ 752)
npm run check:sw-types --workspace=apps/web   # Type-check static/sw.js under the WebWorker lib (§ 752)
npm run test:tsconfig-coverage --workspace=apps/web  # No compilable file under apps/web is outside all four roots
```

`apps/web` has four `tsc` roots and needs them: SvelteKit generates the app's
`include` (`src/`, `test/`, `tests/`, `vite.config.*`) and TypeScript does not
merge `include` across `extends`, so anything outside it belongs to no program
until a root says so. `tsconfig.tests-e2e.json` covers the Playwright tree,
`tsconfig.node.json` the scripts, the Lambda handlers and `svelte.config.js`,
and `tsconfig.service-worker.json` `static/sw.js` — separate from the Node one
because a service worker's globals come from the `WebWorker` lib, which cannot
share a program with `DOM`. A new tree under `apps/web` fails
`scripts/tsconfig_coverage.test.mjs` until it is put in one of them.

(`pnpm i / pnpm dev` from inside `apps/web/` still work locally because of the historical `pnpm-lock.yaml`, but CI runs the npm path.)

## Conventions

- Use Svelte 5 runes syntax (`$state`, `$derived`, `$effect`, `$props`) — not the legacy options API
- TypeScript throughout; `lang="ts"` on all `<script>` blocks
- `@sveltejs/adapter-static` is the only SvelteKit adapter (output dir: `build/`); the coach endpoint is a separate Lambda artifact built from `src/routes/api/coach/+server.ts`
- `BASE_PATH` is empty in production (CloudFront serves at the root). It's only set on a non-root Pages-style mirror, which we no longer use.
- Buttons: don't define `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-outline`, `.btn-danger`, or `.btn-sm` locally — they live in `app.css` globally. Page-specific variants (`.btn-google`, `.btn-save`, etc.) extend the base. See [conventions § Web buttons](../../docs/architecture/conventions.md#web-buttons).
- Modals: don't define `.modal-backdrop`, `.modal`, `.modal-header`, `.modal-close`, `.modal-body`, `.modal-wide`, or `.modal-narrow` locally — they live in `app.css` globally. Every create / edit dialog (clubs, plans, runs, events, goals, device overrides, workout editor, import route, ConfirmDialog) uses the same shape. See [conventions § Web modals](../../docs/architecture/conventions.md#web-modals).
- Cards: for an **elevated** panel (resting shadow + hover lift — the dashboard / nutrition / history-timeline style) use the global `.card-elevated` from `app.css`; don't re-declare a local copy. **Flat** panels (settings / plans / coaching / …) keep their own page-scoped shadowless `.card` — there is deliberately no global `.card`, and you must never add a `box-shadow` to a bare global `.card` name (it would cascade into ~17 flat pages). See [conventions § Web cards](../../docs/architecture/conventions.md#web-cards--card-elevated-is-the-shared-elevated-panel).
- Forms: don't re-declare field chrome (input / textarea / select / label / fieldset / focus ring / radio row / actions / error) in an editor — add `class="editor-form"` to the form root and let the shared `app.css` layer style them; keep only bespoke layout (grids, chips, set tables) scoped. The bordered checkbox option-card is `.toggle-row`. Native checkbox/radio colour comes from the global `accent-color` rule. Mind the Svelte-scoping gotcha (a scoped `label`/`input` rule out-specifies the global layer — delete local copies on migration; prefix inline-label overrides with `.editor-form`). See [conventions § Web forms](../../docs/architecture/conventions.md#web-forms--editor-form-is-the-shared-field-layer).
- Page width: list / detail pages **uncapped** (fill the screen), settings tabs cap at `64rem`, focused single-form pages at `40–48rem`. Padding is `var(--page-padding-y) var(--page-padding-x)`, left-aligned (no `margin: 0 auto`) — read the tokens, not the `--space-*` values behind them, so the narrow-viewport gutter reaches the page. See [conventions § Web page padding](../../docs/architecture/conventions.md#web-page-padding).
- **`<input type="number" bind:value>` yields a `number`, not a string.** Svelte coerces a numeric input's `bind:value` to `number | null`, even when the bound field is declared `string`. Feeding that straight into a string parser blows up — this is the bug that made *every* weighted gym workout silently fail to save (`parseWeightToKg`'s `.trim()` threw `"raw.trim is not a function"`, uncaught, before the try/catch). When a numeric `<input>` value flows into a string-typed helper, coerce at the boundary (the web `parseWeight` wrapper now does `typeof raw === 'number' ? String(raw) : raw`), or use `inputmode="numeric|decimal"` on a `type="text"` input to keep it a string. `parseFloat`-style parsers tolerate the number; `.trim()`/`.replace()` parsers do not.
- **Pure logic in `.svelte.ts` files can't be unit-tested with raw tsx.** Files with `$state` / `$derived` / `$effect` need the Svelte 5 compiler in the loop; `npx tsx --test src/lib/foo.svelte.test.ts` instantly errors with `ReferenceError: $state is not defined`. If you want unit tests for pure logic that currently lives in a `.svelte.ts` file, **extract the pure parts to a sibling `.ts` file (no runes)** — that's what `route_history.ts` / `pace_segments.ts` / `track_projection.ts` already do next to their `.svelte` callers. Reactive state / signal initialisation stays in the `.svelte.ts` shell. The pure `.ts` sibling becomes node:test-runnable via `npx tsx --test` (see `apps/web/src/lib/*.test.ts`). The fallback is Playwright e2e, but unit-testing the pure layer is much cheaper. **Do not leave half-finished `.svelte.test.ts` files behind** — if the runes-in-tsx attempt fails, either extract the pure logic or skip the unit test and rely on e2e.

## Create-flow modal pattern

Every create surface (`/clubs`, `/plans`, `/runs`, `/history`, `/clubs/[slug]`, `/gym`, `/nutrition`) opens a modal hosting a reusable editor component (`ClubEditor`, `PlanEditor`, `RunEditor`, `EventEditor`, `GymEditor`, `FoodLogEditor`). `/history`'s Log menu hosts all three of RunEditor / GymEditor / FoodLogEditor; `/runs` hosts the RunEditor Add-run modal. Each editor takes an `oncreated` (and where applicable `oncancel`) callback; the host decides whether to close + refresh or navigate to the new entity.

The standalone `/new`-style routes (`/clubs/new`, `/plans/new`, `/runs/new`, `/clubs/[slug]/events/new`, `/nutrition/log`) are kept as **thin page wrappers** around the same editor components so deep links and browser back work unchanged. When you add a new editor, follow this same shape — never duplicate the form between the modal and the standalone route.

The modal shell uses the canonical `.modal-backdrop` / `.modal` / `.modal-header` / `.modal-close` / `.modal-body` classes from `app.css`. Pages and components must not redefine those locally — only field-level layout (e.g. a `.goal-editor-body { display: grid }` for a specific dialog's contents). See [conventions § Web modals](../../docs/architecture/conventions.md#web-modals).
## Deployment

Production plan + cost / observability / rollback: [deployment.md](deployment.md). Hosted on **AWS** (S3 + CloudFront + Lambda + Route 53), Terraform-provisioned (`infra/`), sops + AWS KMS for runtime secrets, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the choice rationale.

**Publishing a `web@*` GitHub Release** triggers `.github/workflows/release-web.yml` which: builds the static site → uploads to the prod S3 bucket → updates the coach Lambda → invalidates CloudFront → attaches the build zip back onto the Release. A bare `web@*` tag push does **not** deploy — the published Release is the gate (`gh release create web@1.2.3 …`, the Releases UI, or the /release skill), consistent with every other `release-*.yml`. Push to `main` deploys to the `preview.threkir.com` environment.

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
