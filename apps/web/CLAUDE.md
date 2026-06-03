# apps/web — AI session notes

**The web app is the canonical feature surface for the whole product.** Every user-facing feature lives here unless it is physically impossible in a browser (live GPS recording, device sensors, haptics, OS share sheets — see the exceptions table in [../../docs/architecture/decisions.md § 24](../../docs/architecture/decisions.md)). Mobile (Flutter Android / iOS) and watch (Wear OS Kotlin / watchOS Swift) clients *mirror* this surface and *add* things only a device in hand or on the wrist can do.

**Working rule:** when you're asked to build a feature, build it here first. When you're asked to fix drift between web and mobile, close it by bringing web up to parity with mobile (not the reverse) unless the feature is a physical exception. See [../../docs/product/parity.md](../../docs/product/parity.md) for the live matrix — rows where this app is `✗` or `Partial` on a non-exception feature are the backlog.

**Multi-modal expansion (Phase 4, planned):** the product expands from running-only to running + gym + nutrition inside one app per platform ([decisions.md § 63](../../docs/architecture/decisions.md#63-single-app-multi-modal-expansion-run--gym--nutrition-under-one-nav-one-db)). On web that means `Run` / `Gym` / `Nutrition` as sibling sidebar sections plus a unified `Home` and `History`. Don't pre-emptively add gym / nutrition surfaces until the Phase 4 nav + data-model foundation lands; see [roadmap.md § Phase 4](../../docs/product/roadmap.md#phase-4--multi-modal-gym--nutrition) for sequencing.

Deployed to AWS — S3 (static SvelteKit build) + CloudFront + Route 53 for everything except `/api/coach`, which deploys as a Node 24 Lambda Function URL routed by a separate CloudFront behaviour. Terraform-provisioned (modules + per-env stacks under `infra/`), runtime secrets via sops + AWS KMS, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the rationale and [deployment.md](deployment.md) for the full plan.

## Stack

- **Framework**: SvelteKit 2 with Svelte 5 (runes/next)
- **Language**: TypeScript
- **Package manager**: npm via the root workspace (`npm run <script> --workspace=apps/web`). The repo bootstrapped with pnpm originally and `apps/web/pnpm-lock.yaml` still exists; CI and the canonical build path are npm — see [decisions.md § 7](../../docs/architecture/decisions.md). Either works locally; just don't mix.
- **Adapter**: `@sveltejs/adapter-static` for the bulk; `/api/coach/+server.ts` is reused as the body of a hand-rolled Node 24 Lambda handler (no SvelteKit AWS adapter — see [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages))
- **Styling**: normalize.css + custom CSS in `src/app.css`
- **Icons**: unplugin-icons with `@iconify-json/material-symbols`
- **Markdown**: mdsvex

## Folder Structure

```
src/
  lib/
    components/     # Modal + SplitPane (primitives), Avatar (shared img-or-initial avatar; per-site size/font/bg props), RunMap, ElevationProfile (Android-style interactive chart), ImportRoute, RouteBuilder, CoachChat,
                    # ConfirmDialog, ToastContainer, ProGate, WorkoutEditor, RunTrackPreview, TrackPreview, PlanCalendar, RouteExplorer,
                    # CalendarHeatmap, PersonalHeatmap (geographic heatmap of the user's own tracks on /runs/heatmap — distinct from RouteHeatmap's public community map), LicenseList, ClubEditor, EventEditor, PlanEditor (editable preview), PlanMetaEditor, RunEditor
                    # (modal-hosted creation forms), PrivacyZonePicker (MapLibre map picker for owner zones, decisions §33),
                    # TrainingLoadChart (90-day fitness/fatigue/form trio on /dashboard, decisions §34),
                    # PeriodSummary (week/month/all-time stats + run list — used by dashboard modal AND /dashboard/period/...; the dashboard "This Week" + "All time"/Longest-run stat cards open it),
                    # RunSocial (kudos + comments on a run — mounted on /share/run/[id], /runs/[id]; feed uses fetchEngagementSummaries chips instead),
                    # RunShareView (the public run share body — extracted so /share/run/[id] (standalone page) and the /feed modal can both render it without duplicating layout),
                    # RunPhotos (gallery for run_photos — mounted on /runs/[id] and /share/run/[id]; owner gates upload + delete; decisions §36),
                    # SegmentsPanel + RunSegmentEfforts (segment leaderboards on /routes/[id] + per-run effort chips on /runs/[id]; decisions §37),
                    # NotificationBell (compact bell icon next to the profile button in the sidebar footer — unread badge + popover for kudos/comments/follows; full inbox lives on /u/[me]?tab=notifications; decisions §38).
                    # NotificationsList (the inbox body — All / Unread tabs, per-row dismiss, bulk Mark-all-read; mounted under the Notifications tab on /u/[id] when isSelf).
                    # SocialFeed, SocialPeople, SocialClubs — the three tab panels of /social. SocialPeople is the only top-level surface for finding other runners (name search + suggested-from-clubs). decisions §54.
    stores/         # auth.svelte.ts (Supabase Auth store), toast.svelte.ts (toast notifications), notifications.svelte.ts (unread badge for the sidebar bell — decisions §38)
    # Loose lib modules are grouped into topical subfolders: core/ (data + supabase client),
    # training/ routes/ segments/ social/ integrations/ backup/ share/ settings/ runs/ format/ util/ billing/.
    # Only types.ts + database.types.ts stay at the lib root (gen:types writes database.types.ts there; the
    # twin parity-pair paths in docs/architecture/conventions.md + shared-library-syncer.md track the new locations).
    core/data.ts         # All Supabase queries (fetchRuns, searchPublicRoutes, etc.)
    types.ts        # Run, Route, Integration type overlays on generated DB types
    database.types.ts  # Generated Supabase types (regenerate after migrations)
    core/supabase.ts     # Supabase client init
    core/mock-data.ts    # Fallback data when Supabase is empty
    format/units.svelte.ts # Reactive km/mi preference signal + unit-aware formatters (distance/pace/elevation)
    format/time.ts         # Pure, locale/unit-independent time formatters (formatRelativeTime, formatDuration, formatDate, formatDateShort) — unit-tested in time.test.ts. NOT in mock-data.ts (which is fallback data only).
    i18n/                  # Web i18n runtime (decisions §108). store.svelte.ts = reactive locale signal + `m(key, params)` + initLocale (call once in +layout). locale.ts = pure negotiation (negotiateLocale / dirForLocale, unit-tested). messages.ts = `Messages = typeof en` type. locales/{en,de,fr,es,ja,pt-BR}.ts = catalogues (en static, rest lazy-imported). Add a user-facing string: add the key to en.ts + every locale (satisfies Messages enforces parity; messages_parity.test.ts guards it), then `{m('key')}` at the call site. Detection is CLIENT-SIDE (no Accept-Language SSR — the site is statically prerendered).
    routes/map-style.svelte.ts  # Reactive map-style preference signal (used by RunMap)
    settings/settings.ts     # `loadSettings()` + `effective<T>()` helpers over user_settings + user_device_settings. Now offline-first via settings_cache.ts (cache-first read, write-through, drain-on-refresh pending queue, sign-out drop). Mirrors mobile SettingsService — decisions §72 / §79.
    settings/settings_cache.ts  # `LocalStoragePrefsCache` + `InMemoryPrefsCache` (test seam) + pure `applyPrefsChanges`. User- + device-scoped keys (`settings_cache_universal_<userId>`, `..._device_<userId>_<deviceId>`, `..._pending_<userId>_<deviceId>`). 40-test contract in `settings_cache.test.ts`.
    settings/theme.ts        # light/dark/auto theme toggle, persisted in localStorage
    training/training.ts     # VDOT, Riegel, plan generator, week phasing, predictionConfidence (race-predictor data-quality grade)
    training/training.test.ts  # node:test suite for the training engine — `npx tsx --test`
    training/plan_adherence.ts  # pure weeklyDrift (>20% over/under plan) + missedWorkoutAdvice (make-up/skip a missed long run). Web-first; mounted on /plans/[id]. 11 unit tests.
    training/plan_progress.ts   # pure orderedPlanPhases (base→build→peak→taper marker) + longestCompletedLongRunMetres. Mounted on the /plans/[id] header. 8 unit tests.
    integrations/strava-zip.ts   # Strava bulk-export ZIP importer (parses CSV + per-activity GPX/TCX)
    integrations/garmin-zip.ts   # Garmin bulk import (single .fit OR Account Data .zip; routes inner .gpx/.tcx via parseRouteFile)
    integrations/garmin-fit.ts   # Single FIT-buffer parser (lazy-loads fit-file-parser to keep the integrations bundle small)
    util/push.ts         # Web push subscribe / unsubscribe (registers /sw.js, persists to user_device_settings.prefs.push_subscription)
    util/exif_strip.ts   # Lossless JPEG marker-walk that drops the APP1 (EXIF/XMP, incl. GPS) segment before photo upload. TS twin of mobile exif_strip.dart; called inside addRunPhoto so a geotagged original never reaches the run-photos bucket ahead of the server worker's async strip.

    routes/privacy.ts      # PrivacyZone type + clipPointsToZones (pure JS, used for owner preview); server-side clipping for non-owner views goes through clip_track_for_user RPC. Decisions §33.
    coach/          # Transport-agnostic core for the /api/coach handler. handler.ts (entry), providers.ts (Anthropic + OpenAI streaming), context.ts (builds the runner profile + plan + recent-runs JSON dump), types.ts, system_prompt.ts. Wrapped twice — once by src/routes/api/coach/+server.ts (SvelteKit dev), once by apps/web/lambda/coach/src/index.ts (production AWS Lambda). Decisions §53.
    training/training_load.ts  # TRIMP / distance-proxy stress score + 90-day daily EWMA → fitness/fatigue/form trio. Pure functions, 10 unit tests. Mounted via TrainingLoadChart on /dashboard. Decisions §34.
    segments/segments.ts     # Pure compute for segment efforts — haversine cumulative distance + timestamp interpolation. 8 unit tests. Used by RunSegmentEfforts on /runs/[id] for client-side auto-effort generation. Decisions §37.
    segments/pace_segments.ts  # NRC-style pace heatmap helpers (`paceBucketForSpeed`, `ageBandFor`, `buildPaceSegments`, `hasTrackTimestamps`). TS port of `apps/mobile_android/lib/widgets/pace_segments.dart` — keep in lockstep. Mounted via the `activity` prop on `RunMap.svelte` (run-detail + share-run); routes never carry timestamps so they fall through to the legacy single line. 11 unit tests in `pace_segments.test.ts`.
    routes/track_projection.ts  # Pure projection helper for the SVG track-preview thumbnails (`projectTrack` with cos(midLat) longitude correction so a square loop renders square at any latitude). Mirrors the `projectTrack` helper in `apps/mobile_android/lib/widgets/track_preview.dart` — keep in lockstep. Used by `TrackPreview.svelte` and `RunTrackPreview.svelte`. 4 unit tests in `track_projection.test.ts`. See [decisions.md § 51](../../docs/architecture/decisions.md).
    routes/route_history.ts  # "Past efforts on this route" panel data (10 unit tests in route_history.test.ts). Mounted on /routes/[id] under the map.
    routes/distance_bands.ts  # Race-distance bands (5K/10K/Half/Marathon/Ultra) for the /routes/heatmap discovery browser — single source of truth for the windows mirrored generically by discoverable_routes_in_bbox (p_dist_min[]/p_dist_max[]). 9 unit tests in distance_bands.test.ts. Web-only (no Dart twin). Decisions §100.
  routes/
    +layout.svelte  # App shell with collapsible sidebar (state persisted in localStorage as `sidebar_collapsed`). Sidebar shape: Dashboard · History · Routes · Coach · Social (5 items).
    social/         # Top-level social hub. ARIA tab strip (Feed default, People, Clubs) with ?tab= URL state. Hosts the SocialFeed + SocialPeople + SocialClubs components.
    feed/           # Thin client-side redirect to `/social?tab=feed`. Kept alive for the sitemap entry, the bell-popover CTA, mobile push deep links, and any external links pinned to the old URL.
    u/[id]/         # Public user profile — display_name, avatar, follower/following counts, recent public runs, Follow toggle. Honours ?tab=runs|followers|following|notifications (notifications gated to isSelf — decisions §38). Identifier is auth.users.id (uuid); URL-safe handles deferred (decisions §31). The activity feed used to live here as a self-only tab; it's now under /social and any legacy ?tab=feed deep link bounces over.
    dashboard/      # Weekly mileage, PBs, calendar heatmap. "This Week" stat card opens PeriodSummary in a modal.
    dashboard/period/[type]/[date]/  # Standalone period summary — thin wrapper around PeriodSummary, kept for deep links
    runs/           # Run history with source + activity type filters
    runs/heatmap/   # Personal run-track heatmap — the user's OWN tracks (PersonalHeatmap.svelte + lib/run_heatmap.ts). Distinct from the public /routes/heatmap community map. Persona #53.
    runs/[id]/      # Run detail with map, elevation, splits
    routes/         # Tabbed: My routes (saved) + Explore routes (community discovery via RouteExplorer). ?tab=explore deep-links the second tab.
    routes/new/     # Route builder (MapLibre + OSRM)
    routes/[id]/    # Route detail
    clubs/          # Thin client-side redirect to `/social?tab=clubs` (preserves `?tab=browse` as `clubs-sub=browse`). The /clubs/[slug] + /clubs/new + /clubs/[slug]/events/* + /clubs/join/[token] sub-routes are unchanged — only the top-level browse landing moved.
    clubs/new/      # Create a club (visibility + join policy)
    clubs/[slug]/   # Club home: feed (threaded) / events / routes / members tabs, pending-requests + invite-link panels for admins. Routes tab lists routes where club_id = this club; admins can create new (links to /routes/new?club=<id>) or transfer one of their personal routes in.
    clubs/[slug]/events/new/      # Admin: create event (one-off OR weekly/biweekly/monthly recurrence)
    clubs/[slug]/events/[id]/     # Event detail + per-instance RSVP + per-event updates
    clubs/join/[token]/           # Public invite-link landing (redeems via join_club_by_token RPC)
    coaching/                     # Coach-athlete roster hub (persona #46): mint/revoke invite links + athlete & coach lists
    coaching/athletes/[id]/       # Coach run-review surface: a linked athlete's recent runs (public+private, RLS §98) + active-plan compliance. fetchAthleteRuns / fetchAthletePlanOverview
    coaching/accept/[token]/      # Public coach-invite landing (redeems via redeem_coach_invite RPC)
    plans/          # Training plans list
    plans/new/      # New-plan wizard with editable week-by-week preview (click a week to expand the day-by-day editor; edits persist on submit)
    plans/[id]/     # Plan detail: progress ring, today card, week grid + Edit-plan button (PlanMetaEditor) for owner-only meta edits (name, days/week, goal time, rules)
    plans/[id]/workouts/[wid]/   # Workout detail with structured-interval breakdown
    coach/          # Standalone Coach chat — plan switcher (?plan=<id>), configurable runs window (10/20/50/100), grounded-in context strip
    api/coach/+server.ts         # Coach endpoint. Default provider: Claude (ANTHROPIC_API_KEY). Set COACH_PROVIDER=openai + OPENAI_BASE_URL for local Ollama.
    explore/        # Thin redirect to /routes?tab=explore (kept so old links / Android deep links still resolve)
    settings/       # Tabbed layout: account, preferences, integrations, devices, upgrade (donate)
    share/run/[id]/ # Public run share page (no auth required)
    share/route/[id]/ # Public route share page (no auth required)
    live/[id]/      # Live spectator tracking. Real Go live-hub WebSocket path via lib/runs/live_hub.ts when PUBLIC_LIVE_HUB_URL is set; Supabase Realtime channel as fallback when unset; the demo animation is only the no-signal filler. WS path e2e-tested by tests-e2e/live/spectator_websocket.spec.ts (dedicated playwright.livehub.config.ts — boots the real hub binary).
    login/          # Email/password + OAuth sign-in
    auth/callback/  # OAuth redirect handler
  app.css           # Global styles + CSS variables
  app.d.ts          # App-level TypeScript declarations
lambda/
  coach/            # AWS Lambda Function URL handler for /api/coach in production.
                    # src/index.ts wraps $lib/coach/handler with awslambda.streamifyResponse +
                    # HttpResponseStream so SSE streams pass through CloudFront. build.mjs
                    # bundles via esbuild → dist/coach.zip (Anthropic SDK + supabase-js
                    # inlined, ~537 KB). CI's release-web.yml updates the Lambda code on every
                    # web@* tag. See decisions.md §53.
```

## Development

```bash
# From the repo root (matches CI):
npm install                              # workspace bootstrap
npm run dev --workspace=apps/web         # Dev server on :7777
npm run build --workspace=apps/web       # Production build
npm run preview --workspace=apps/web     # Preview build on :8888
npm run check --workspace=apps/web       # Type-check
```

(`pnpm i / pnpm dev` from inside `apps/web/` still work locally because of the historical `pnpm-lock.yaml`, but CI runs the npm path.)

## Conventions

- Use Svelte 5 runes syntax (`$state`, `$derived`, `$effect`, `$props`) — not the legacy options API
- TypeScript throughout; `lang="ts"` on all `<script>` blocks
- `@sveltejs/adapter-static` is the only SvelteKit adapter (output dir: `build/`); the coach endpoint is a separate Lambda artifact built from `src/routes/api/coach/+server.ts`
- `BASE_PATH` is empty in production (CloudFront serves at the root). It's only set on a non-root Pages-style mirror, which we no longer use.
- Buttons: don't define `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-outline`, `.btn-danger`, or `.btn-sm` locally — they live in `app.css` globally. Page-specific variants (`.btn-google`, `.btn-save`, etc.) extend the base. See [conventions § Web buttons](../../docs/architecture/conventions.md#web-buttons).
- Modals: don't define `.modal-backdrop`, `.modal`, `.modal-header`, `.modal-close`, `.modal-body`, `.modal-wide`, or `.modal-narrow` locally — they live in `app.css` globally. Every create / edit dialog (clubs, plans, runs, events, goals, device overrides, workout editor, import route, ConfirmDialog) uses the same shape. See [conventions § Web modals](../../docs/architecture/conventions.md#web-modals).
- Page width: list / detail pages **uncapped** (fill the screen), settings tabs cap at `64rem`, focused single-form pages at `40–48rem`. Padding is `var(--space-xl) var(--space-2xl)`, left-aligned (no `margin: 0 auto`). See [conventions § Web page padding](../../docs/architecture/conventions.md#web-page-padding).
- **Pure logic in `.svelte.ts` files can't be unit-tested with raw tsx.** Files with `$state` / `$derived` / `$effect` need the Svelte 5 compiler in the loop; `npx tsx --test src/lib/foo.svelte.test.ts` instantly errors with `ReferenceError: $state is not defined`. If you want unit tests for pure logic that currently lives in a `.svelte.ts` file, **extract the pure parts to a sibling `.ts` file (no runes)** — that's what `route_history.ts` / `pace_segments.ts` / `track_projection.ts` already do next to their `.svelte` callers. Reactive state / signal initialisation stays in the `.svelte.ts` shell. The pure `.ts` sibling becomes node:test-runnable via `npx tsx --test` (see `apps/web/src/lib/*.test.ts`). The fallback is Playwright e2e, but unit-testing the pure layer is much cheaper. **Do not leave half-finished `.svelte.test.ts` files behind** — if the runes-in-tsx attempt fails, either extract the pure logic or skip the unit test and rely on e2e.

## Create-flow modal pattern

Every create surface (`/clubs`, `/plans`, `/runs`, `/clubs/[slug]`) opens a modal hosting a reusable editor component (`ClubEditor`, `PlanEditor`, `RunEditor`, `EventEditor`). Each editor takes `oncreated(item)` and `oncancel()` callbacks; the host decides whether to close + refresh or navigate to the new entity.

The standalone `/new` routes (`/clubs/new`, `/plans/new`, `/runs/new`, `/clubs/[slug]/events/new`) are kept as **thin page wrappers** around the same editor components so deep links and browser back work unchanged. When you add a new editor, follow this same shape — never duplicate the form between the modal and the standalone route.

The modal shell uses the canonical `.modal-backdrop` / `.modal` / `.modal-header` / `.modal-close` / `.modal-body` classes from `app.css`. Pages and components must not redefine those locally — only field-level layout (e.g. a `.goal-editor-body { display: grid }` for a specific dialog's contents). See [conventions § Web modals](../../docs/architecture/conventions.md#web-modals).
## Deployment

Production plan + cost / observability / rollback: [deployment.md](deployment.md). Hosted on **AWS** (S3 + CloudFront + Lambda + Route 53), Terraform-provisioned (`infra/`), sops + AWS KMS for runtime secrets, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the choice rationale.

Tag `web@*` triggers `.github/workflows/release-web.yml` which: builds the static site → uploads to the prod S3 bucket → updates the coach Lambda → invalidates CloudFront. Push to `main` deploys to the `preview.threkir.com` environment.

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
