# apps/web — AI session notes

**The web app is the canonical feature surface for the whole product.** Every user-facing feature lives here unless it is physically impossible in a browser (live GPS recording, device sensors, haptics, OS share sheets — see the exceptions table in [../../docs/decisions.md § 24](../../docs/decisions.md)). Mobile (Flutter Android / iOS) and watch (Wear OS Kotlin / watchOS Swift) clients *mirror* this surface and *add* things only a device in hand or on the wrist can do.

**Working rule:** when you're asked to build a feature, build it here first. When you're asked to fix drift between web and mobile, close it by bringing web up to parity with mobile (not the reverse) unless the feature is a physical exception. See [../../docs/parity.md](../../docs/parity.md) for the live matrix — rows where this app is `✗` or `Partial` on a non-exception feature are the backlog.

Deployed to GitHub Pages for the static site; Vercel adapter is used when a server runtime is needed (the `/api/coach/+server.ts` Claude endpoint, for example).

## Stack

- **Framework**: SvelteKit 2 with Svelte 5 (runes/next)
- **Language**: TypeScript
- **Package manager**: pnpm
- **Adapters**: `@sveltejs/adapter-static` (GitHub Pages), `@sveltejs/adapter-vercel` (Vercel)
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
                    # NotificationBell (compact bell icon next to the profile button in the sidebar footer — unread badge + popover for kudos/comments/follows; /notifications full-list view; decisions §38).
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
    training_load.ts  # TRIMP / distance-proxy stress score + 90-day daily EWMA → fitness/fatigue/form trio. Pure functions, 10 unit tests. Mounted via TrainingLoadChart on /dashboard. Decisions §34.
    segments.ts     # Pure compute for segment efforts — haversine cumulative distance + timestamp interpolation. 8 unit tests. Used by RunSegmentEfforts on /runs/[id] for client-side auto-effort generation. Decisions §37.
  routes/
    +layout.svelte  # App shell with collapsible sidebar (state persisted in localStorage as `sidebar_collapsed`)
    feed/           # Activity feed — recent public runs from people you follow (decisions §31). Cursor-paginated on (started_at, id).
    u/[id]/         # Public user profile — display_name, avatar, follower/following counts, recent public runs, Follow toggle. Identifier is auth.users.id (uuid); URL-safe handles deferred (decisions §31).
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
    notifications/  # Inbox for kudos / comments / replies / follows (decisions §38). All / Unread tabs, per-row dismiss, bulk Mark all read.
    settings/       # Tabbed layout: account, preferences, integrations, devices, upgrade (donate)
    share/run/[id]/ # Public run share page (no auth required)
    share/route/[id]/ # Public route share page (no auth required)
    live/[id]/      # Live spectator tracking (simulated)
    login/          # Email/password + OAuth sign-in
    auth/callback/  # OAuth redirect handler
  app.css           # Global styles + CSS variables
  app.d.ts          # App-level TypeScript declarations
```

## Development

```bash
pnpm i          # Install dependencies
pnpm dev        # Dev server on :7777
pnpm build      # Production build
pnpm preview    # Preview build on :8888
pnpm check      # Type-check
```

## Conventions

- Use Svelte 5 runes syntax (`$state`, `$derived`, `$effect`, `$props`) — not the legacy options API
- TypeScript throughout; `lang="ts"` on all `<script>` blocks
- Prefer `@sveltejs/adapter-static` for GitHub Pages output (output dir: `build/`)
- `BASE_PATH` env var is set to `/<repo-name>` during CI builds for correct asset paths
- Buttons: don't define `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-outline`, `.btn-danger`, or `.btn-sm` locally — they live in `app.css` globally. Page-specific variants (`.btn-google`, `.btn-save`, etc.) extend the base. See [conventions § Web buttons](../../docs/conventions.md#web-buttons).
- Modals: don't define `.modal-backdrop`, `.modal`, `.modal-header`, `.modal-close`, `.modal-body`, `.modal-wide`, or `.modal-narrow` locally — they live in `app.css` globally. Every create / edit dialog (clubs, plans, runs, events, goals, device overrides, workout editor, import route, ConfirmDialog) uses the same shape. See [conventions § Web modals](../../docs/conventions.md#web-modals).
- Page width: list / detail pages **uncapped** (fill the screen), settings tabs cap at `64rem`, focused single-form pages at `40–48rem`. Padding is `var(--space-xl) var(--space-2xl)`, left-aligned (no `margin: 0 auto`). See [conventions § Web page padding](../../docs/conventions.md#web-page-padding).

## Create-flow modal pattern

Every create surface (`/clubs`, `/plans`, `/runs`, `/clubs/[slug]`) opens a modal hosting a reusable editor component (`ClubEditor`, `PlanEditor`, `RunEditor`, `EventEditor`). Each editor takes `oncreated(item)` and `oncancel()` callbacks; the host decides whether to close + refresh or navigate to the new entity.

The standalone `/new` routes (`/clubs/new`, `/plans/new`, `/runs/new`, `/clubs/[slug]/events/new`) are kept as **thin page wrappers** around the same editor components so deep links and browser back work unchanged. When you add a new editor, follow this same shape — never duplicate the form between the modal and the standalone route.

The modal shell uses the canonical `.modal-backdrop` / `.modal` / `.modal-header` / `.modal-close` / `.modal-body` classes from `app.css`. Pages and components must not redefine those locally — only field-level layout (e.g. a `.goal-editor-body { display: grid }` for a specific dialog's contents). See [conventions § Web modals](../../docs/conventions.md#web-modals).
## Deployment

- **GitHub Pages**: push to `main` triggers `.github/workflows/deploy.yml`, which builds and deploys automatically
- The `build/.nojekyll` file is created at build time to bypass Jekyll processing

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
