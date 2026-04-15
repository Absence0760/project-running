# Project Overview

This is a SvelteKit web template deployed to GitHub Pages.

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
    components/     # RunMap, ElevationProfile, ImportRoute, RouteBuilder
    stores/         # auth.svelte.ts (Supabase Auth store)
    data.ts         # All Supabase queries (fetchRuns, searchPublicRoutes, etc.)
    types.ts        # Run, Route, Integration type overlays on generated DB types
    database.types.ts  # Generated Supabase types (regenerate after migrations)
    supabase.ts     # Supabase client init
    mock-data.ts    # Fallback data when Supabase is empty
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
    explore/        # Public route discovery (search, distance/surface filters)
    settings/       # Account, integrations, preferences
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
## Deployment

- **GitHub Pages**: push to `main` triggers `.github/workflows/deploy.yml`, which builds and deploys automatically
- The `build/.nojekyll` file is created at build time to bypass Jekyll processing

## Pull Request Guidelines

- Target branch: `main`
- Keep PRs focused; one feature or fix per PR
- Draft PRs are fine for work-in-progress
