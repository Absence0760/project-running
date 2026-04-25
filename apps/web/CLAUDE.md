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
    components/     # RunMap, ElevationProfile, ImportRoute, RouteBuilder, CoachChat, ConfirmDialog, ToastContainer, ProGate,
                    # WorkoutEditor, RunTrackPreview, TrackPreview, PlanCalendar, RouteExplorer, CalendarHeatmap, LicenseList,
                    # ClubEditor, EventEditor, PlanEditor, RunEditor (modal-hosted creation forms)
    stores/         # auth.svelte.ts (Supabase Auth store), toast.svelte.ts (toast notifications)
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
  routes/
    +layout.svelte  # App shell with sidebar nav (auth guard)
    dashboard/      # Weekly mileage, PBs, calendar heatmap
    runs/           # Run history with source + activity type filters
    runs/[id]/      # Run detail with map, elevation, splits
    routes/         # User's saved routes
    routes/new/     # Route builder (MapLibre + OSRM)
    routes/[id]/    # Route detail
    clubs/          # Social layer — browse + My clubs
    clubs/new/      # Create a club (visibility + join policy)
    clubs/[slug]/   # Club home: feed (threaded) / events / members, pending-requests + invite-link panels for admins
    clubs/[slug]/events/new/      # Admin: create event (one-off OR weekly/biweekly/monthly recurrence)
    clubs/[slug]/events/[id]/     # Event detail + per-instance RSVP + per-event updates
    clubs/join/[token]/           # Public invite-link landing (redeems via join_club_by_token RPC)
    plans/          # Training plans list
    plans/new/      # New-plan wizard with live preview
    plans/[id]/     # Plan detail: progress ring, today card, week grid
    plans/[id]/workouts/[wid]/   # Workout detail with structured-interval breakdown
    coach/          # Standalone Coach chat — plan switcher (?plan=<id>), configurable runs window (10/20/50/100), grounded-in context strip
    api/coach/+server.ts         # Coach endpoint. Default provider: Claude (ANTHROPIC_API_KEY). Set COACH_PROVIDER=openai + OPENAI_BASE_URL for local Ollama.
    explore/        # Public route discovery (search, distance/surface filters)
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
- Page width: list / detail pages cap at `72rem`, settings tabs at `64rem`, focused single-form pages at `40–48rem`. Padding is `var(--space-xl) var(--space-2xl)`, left-aligned (no `margin: 0 auto`). See [conventions § Web page padding](../../docs/conventions.md#web-page-padding).

## Create-flow modal pattern

Every create surface (`/clubs`, `/plans`, `/runs`, `/clubs/[slug]`) opens a modal hosting a reusable editor component (`ClubEditor`, `PlanEditor`, `RunEditor`, `EventEditor`). Each editor takes `oncreated(item)` and `oncancel()` callbacks; the host decides whether to close + refresh or navigate to the new entity.

The standalone `/new` routes (`/clubs/new`, `/plans/new`, `/runs/new`, `/clubs/[slug]/events/new`) are kept as **thin page wrappers** around the same editor components so deep links and browser back work unchanged. When you add a new editor, follow this same shape — never duplicate the form between the modal and the standalone route.

The modal markup is currently inlined in each list page (backdrop + centered card + close button + scrollable body). If a fifth modal lands, extract a generic `<Modal>` component before duplicating again.
## Deployment

- **GitHub Pages**: push to `main` triggers `.github/workflows/deploy.yml`, which builds and deploys automatically
- The `build/.nojekyll` file is created at build time to bypass Jekyll processing

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
