# apps/web — AI session notes

**The web app is the canonical feature surface for the whole product.** Every user-facing feature lives here unless it is physically impossible in a browser (live GPS recording, device sensors, haptics, OS share sheets — see the exceptions table in [../../docs/decisions.md § 24](../../docs/decisions.md)). Mobile (Flutter Android / iOS) and watch (Wear OS Kotlin / watchOS Swift) clients *mirror* this surface and *add* things only a device in hand or on the wrist can do.

**Working rule:** when you're asked to build a feature, build it here first. When you're asked to fix drift between web and mobile, close it by bringing web up to parity with mobile (not the reverse) unless the feature is a physical exception. See [../../docs/parity.md](../../docs/parity.md) for the live matrix — rows where this app is `✗` or `Partial` on a non-exception feature are the backlog.

Deployed to AWS — S3 (static SvelteKit build) + CloudFront + Route 53 for everything except `/api/coach`, which deploys as a Node 20 Lambda Function URL routed by a separate CloudFront behaviour. Terraform-provisioned (modules + per-env stacks under `infra/`), runtime secrets via sops + AWS KMS, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the rationale and [deployment.md](deployment.md) for the full plan.

## Stack

- **Framework**: SvelteKit 2 with Svelte 5 (runes/next)
- **Language**: TypeScript
- **Package manager**: npm via the root workspace (`npm run <script> --workspace=apps/web`). The repo bootstrapped with pnpm originally and `apps/web/pnpm-lock.yaml` still exists; CI and the canonical build path are npm — see [decisions.md § 7](../../docs/decisions.md). Either works locally; just don't mix.
- **Adapter**: `@sveltejs/adapter-static` for the bulk; `/api/coach/+server.ts` is reused as the body of a hand-rolled Node 20 Lambda handler (no SvelteKit AWS adapter — see [decisions.md § 53](../../docs/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages))
- **Styling**: normalize.css + custom CSS in `src/app.css`
- **Icons**: unplugin-icons with `@iconify-json/material-symbols`
- **Markdown**: mdsvex

## Folder Structure

```
src/
  lib/
    components/     # Modal + SplitPane (primitives), RunMap, ElevationProfile (Android-style interactive chart), ImportRoute, RouteBuilder, CoachChat,
                    # ConfirmDialog, ToastContainer, ProGate, WorkoutEditor, RunTrackPreview, TrackPreview, PlanCalendar, RouteExplorer,
                    # CalendarHeatmap, LicenseList, ClubEditor, EventEditor, PlanEditor (editable preview), PlanMetaEditor, RunEditor
                    # (modal-hosted creation forms), PrivacyZonePicker (MapLibre map picker for owner zones, decisions §33),
                    # TrainingLoadChart (90-day fitness/fatigue/form trio on /dashboard, decisions §34),
                    # PeriodSummary (week/month stats + run list — used by dashboard modal AND /dashboard/period/...),
                    # RunSocial (kudos + comments on a run — mounted on /share/run/[id], /runs/[id]; feed uses fetchEngagementSummaries chips instead),
                    # RunShareView (the public run share body — extracted so /share/run/[id] (standalone page) and the /feed modal can both render it without duplicating layout),
                    # RunPhotos (gallery for run_photos — mounted on /runs/[id] and /share/run/[id]; owner gates upload + delete; decisions §36),
                    # SegmentsPanel + RunSegmentEfforts (segment leaderboards on /routes/[id] + per-run effort chips on /runs/[id]; decisions §37),
                    # NotificationBell (compact bell icon next to the profile button in the sidebar footer — unread badge + popover for kudos/comments/follows; full inbox lives on /u/[me]?tab=notifications; decisions §38).
                    # NotificationsList (the inbox body — All / Unread tabs, per-row dismiss, bulk Mark-all-read; mounted under the Notifications tab on /u/[id] when isSelf).
    stores/         # auth.svelte.ts (Supabase Auth store), toast.svelte.ts (toast notifications), notifications.svelte.ts (unread badge for the sidebar bell — decisions §38)
    data.ts         # All Supabase queries (fetchRuns, searchPublicRoutes, etc.)
    types.ts        # Run, Route, Integration type overlays on generated DB types
    database.types.ts  # Generated Supabase types (regenerate after migrations)
    supabase.ts     # Supabase client init
    mock-data.ts    # Fallback data when Supabase is empty
    units.svelte.ts # Reactive km/mi preference signal + formatters
    map-style.svelte.ts  # Reactive map-style preference signal (used by RunMap)
    settings.ts     # `loadSettings()` + `effective<T>()` helpers over user_settings + user_device_settings
    theme.ts        # light/dark/auto theme toggle, persisted in localStorage
    training.ts     # VDOT, Riegel, plan generator, week phasing
    training.test.ts  # node:test suite for the training engine — `npx tsx --test`
    strava-zip.ts   # Strava bulk-export ZIP importer (parses CSV + per-activity GPX/TCX)
    garmin-zip.ts   # Garmin bulk import (single .fit OR Account Data .zip; routes inner .gpx/.tcx via parseRouteFile)
    garmin-fit.ts   # Single FIT-buffer parser (lazy-loads fit-file-parser to keep the integrations bundle small)
    push.ts         # Web push subscribe / unsubscribe (registers /sw.js, persists to user_device_settings.prefs.push_subscription)
    privacy.ts      # PrivacyZone type + clipPointsToZones (pure JS, used for owner preview); server-side clipping for non-owner views goes through clip_track_for_user RPC. Decisions §33.
    coach/          # Transport-agnostic core for the /api/coach handler. handler.ts (entry), providers.ts (Anthropic + OpenAI streaming), context.ts (builds the runner profile + plan + recent-runs JSON dump), types.ts, system_prompt.ts. Wrapped twice — once by src/routes/api/coach/+server.ts (SvelteKit dev), once by apps/web/lambda/coach/src/index.ts (production AWS Lambda). Decisions §53.
    training_load.ts  # TRIMP / distance-proxy stress score + 90-day daily EWMA → fitness/fatigue/form trio. Pure functions, 10 unit tests. Mounted via TrainingLoadChart on /dashboard. Decisions §34.
    segments.ts     # Pure compute for segment efforts — haversine cumulative distance + timestamp interpolation. 8 unit tests. Used by RunSegmentEfforts on /runs/[id] for client-side auto-effort generation. Decisions §37.
    pace_segments.ts  # NRC-style pace heatmap helpers (`paceBucketForSpeed`, `ageBandFor`, `buildPaceSegments`, `hasTrackTimestamps`). TS port of `apps/mobile_android/lib/widgets/pace_segments.dart` — keep in lockstep. Mounted via the `activity` prop on `RunMap.svelte` (run-detail + share-run); routes never carry timestamps so they fall through to the legacy single line. 11 unit tests in `pace_segments.test.ts`.
    track_projection.ts  # Pure projection helper for the SVG track-preview thumbnails (`projectTrack` with cos(midLat) longitude correction so a square loop renders square at any latitude). Mirrors the `projectTrack` helper in `apps/mobile_android/lib/widgets/track_preview.dart` — keep in lockstep. Used by `TrackPreview.svelte` and `RunTrackPreview.svelte`. 4 unit tests in `track_projection.test.ts`. See [decisions.md § 51](../../docs/decisions.md).
    route_history.ts  # "Past efforts on this route" panel data (10 unit tests in route_history.test.ts). Mounted on /routes/[id] under the map.
  routes/
    +layout.svelte  # App shell with collapsible sidebar (state persisted in localStorage as `sidebar_collapsed`)
    feed/           # Activity feed — public runs from people you follow, time-windowed to last 14 days (FEED_WINDOW_DAYS in data.ts). Cursor-paginated on (started_at, id) at 20-per-page. Full-width card grid with per-entry track preview. Toolbar: activity-segmented + author searchable combobox + window hint. Cards open RunShareView in a modal. (decisions §31)
    u/[id]/         # Public user profile — display_name, avatar, follower/following counts, recent public runs (open in a modal), Follow toggle. Honours ?tab=runs|followers|following|notifications (notifications gated to isSelf — decisions §38). Identifier is auth.users.id (uuid); URL-safe handles deferred (decisions §31).
    dashboard/      # Weekly mileage, PBs, calendar heatmap. "This Week" stat card opens PeriodSummary in a modal.
    dashboard/period/[type]/[date]/  # Standalone period summary — thin wrapper around PeriodSummary, kept for deep links
    runs/           # Run history with source + activity type filters
    runs/[id]/      # Run detail with map, elevation, splits
    routes/         # Tabbed: My routes (saved) + Explore routes (community discovery via RouteExplorer). ?tab=explore deep-links the second tab.
    routes/new/     # Route builder (MapLibre + OSRM)
    routes/[id]/    # Route detail
    clubs/          # Social layer — browse + My clubs
    clubs/new/      # Create a club (visibility + join policy)
    clubs/[slug]/   # Club home: feed (threaded) / events / routes / members tabs, pending-requests + invite-link panels for admins. Routes tab lists routes where club_id = this club; admins can create new (links to /routes/new?club=<id>) or transfer one of their personal routes in.
    clubs/[slug]/events/new/      # Admin: create event (one-off OR weekly/biweekly/monthly recurrence)
    clubs/[slug]/events/[id]/     # Event detail + per-instance RSVP + per-event updates
    clubs/join/[token]/           # Public invite-link landing (redeems via join_club_by_token RPC)
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
    live/[id]/      # Live spectator tracking (simulated)
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
- Buttons: don't define `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-outline`, `.btn-danger`, or `.btn-sm` locally — they live in `app.css` globally. Page-specific variants (`.btn-google`, `.btn-save`, etc.) extend the base. See [conventions § Web buttons](../../docs/conventions.md#web-buttons).
- Modals: don't define `.modal-backdrop`, `.modal`, `.modal-header`, `.modal-close`, `.modal-body`, `.modal-wide`, or `.modal-narrow` locally — they live in `app.css` globally. Every create / edit dialog (clubs, plans, runs, events, goals, device overrides, workout editor, import route, ConfirmDialog) uses the same shape. See [conventions § Web modals](../../docs/conventions.md#web-modals).
- Page width: list / detail pages **uncapped** (fill the screen), settings tabs cap at `64rem`, focused single-form pages at `40–48rem`. Padding is `var(--space-xl) var(--space-2xl)`, left-aligned (no `margin: 0 auto`). See [conventions § Web page padding](../../docs/conventions.md#web-page-padding).

## Create-flow modal pattern

Every create surface (`/clubs`, `/plans`, `/runs`, `/clubs/[slug]`) opens a modal hosting a reusable editor component (`ClubEditor`, `PlanEditor`, `RunEditor`, `EventEditor`). Each editor takes `oncreated(item)` and `oncancel()` callbacks; the host decides whether to close + refresh or navigate to the new entity.

The standalone `/new` routes (`/clubs/new`, `/plans/new`, `/runs/new`, `/clubs/[slug]/events/new`) are kept as **thin page wrappers** around the same editor components so deep links and browser back work unchanged. When you add a new editor, follow this same shape — never duplicate the form between the modal and the standalone route.

The modal shell uses the canonical `.modal-backdrop` / `.modal` / `.modal-header` / `.modal-close` / `.modal-body` classes from `app.css`. Pages and components must not redefine those locally — only field-level layout (e.g. a `.goal-editor-body { display: grid }` for a specific dialog's contents). See [conventions § Web modals](../../docs/conventions.md#web-modals).
## Deployment

Production plan + cost / observability / rollback: [deployment.md](deployment.md). Hosted on **AWS** (S3 + CloudFront + Lambda + Route 53), Terraform-provisioned (`infra/`), sops + AWS KMS for runtime secrets, OIDC-deployed from GitHub Actions. See [decisions.md § 53](../../docs/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the choice rationale.

Tag `web@*` triggers `.github/workflows/release-web.yml` which: builds the static site → uploads to the prod S3 bucket → updates the coach Lambda → invalidates CloudFront. Push to `main` deploys to the `preview.runonward.app` environment.

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
