# Local testing — Web app (SvelteKit)

The web app is a SvelteKit 2 + Svelte 5 project at `apps/web/`. It uses pnpm as its package manager.

---

## Prerequisites

| Tool | Install |
|---|---|
| Node.js 20 LTS | `nodejs.org` |
| pnpm 9.x | `npm install -g pnpm` |
| Local backend running | See `local_testing_backend.md` |
| MapTiler API key | Free at maptiler.com/cloud (for map tiles) |

---

## Setup

```bash
cd apps/web

# Install dependencies
pnpm install

# Create environment file
cp .env.example .env.local
```

Edit `.env.local` with your local backend values:

```bash
PUBLIC_SUPABASE_URL=http://localhost:54321
PUBLIC_SUPABASE_ANON_KEY=<publishable-key-from-supabase-status>
PUBLIC_MAPTILER_KEY=<your-maptiler-key>
```

---

## Seed the database

Before running the web app for the first time, seed the local database with test data:

```bash
cd apps/backend
supabase db reset
```

This creates a test user and populates all tables. Log in with:

- **Email:** `runner@test.com`
- **Password:** `testtest`

See `local_testing_backend.md` for details on what the seed includes.

---

## Running

```bash
pnpm dev
```

Opens at **http://localhost:7777**.

---

## Other commands

| Command | What it does |
|---|---|
| `pnpm dev` | Dev server with hot reload on `:7777` |
| `pnpm build` | Production build |
| `pnpm preview` | Preview production build on `:8888` |
| `pnpm check` | Type-check all Svelte and TypeScript files |
| `pnpm check:watch` | Type-check in watch mode |


---

## Project structure

```
apps/web/
├── src/
│   ├── routes/                    # SvelteKit file-based routing
│   │   ├── +layout.svelte         # Root layout
│   │   ├── +page.svelte           # Landing page (/)
│   │   ├── login/                 # Auth page (email/password + Google/Apple OAuth)
│   │   ├── auth/callback/         # OAuth redirect handler
│   │   ├── dashboard/             # Stats, mileage chart (week/month/year), heatmap, PRs, source filter
│   │   ├── routes/                # Route builder + library
│   │   │   ├── new/               # Full-screen route builder
│   │   │   └── [id]/              # Route detail with GPX/KML export + share link
│   │   ├── runs/                  # Run history with source filtering
│   │   │   └── [id]/              # Run detail: GPS trace with replay, elevation, splits, HR
│   │   ├── live/[id]/             # Live spectator view (public, no auth)
│   │   ├── share/
│   │   │   ├── route/[id]/        # Public shared route page
│   │   │   └── run/[id]/          # Public shared run page
│   │   └── settings/
│   │       ├── integrations/      # Connect/disconnect Strava, Garmin, parkrun, HealthKit
│   │       └── account/           # Profile, parkrun number, units, CSV export
│   ├── lib/
│   │   ├── supabase.ts            # Browser Supabase client
│   │   ├── supabase-server.ts     # Server-side Supabase client
│   │   ├── types.ts               # TypeScript interfaces
│   │   ├── routing.ts             # OSRM road-snapping API
│   │   ├── elevation.ts           # Open-Meteo elevation lookups
│   │   ├── gpx.ts                 # GPX + KML export generator
│   │   ├── import.ts              # GPX/KML/KMZ/GeoJSON file parser
│   │   ├── data.ts                # Supabase data access layer
│   │   ├── stores/
│   │   │   └── auth.svelte.ts         # Supabase auth store (OAuth + session)
│   │   └── components/
│   │       ├── RouteBuilder.svelte    # MapLibre map with waypoints
│   │       ├── RunMap.svelte          # MapLibre GPS trace viewer
│   │       ├── ElevationProfile.svelte # SVG elevation chart
│   │       ├── CalendarHeatmap.svelte # GitHub-style activity heatmap
│   │       └── ImportRoute.svelte    # Drag-and-drop route file import modal
│   ├── app.html
│   ├── app.css
│   └── app.d.ts
├── svelte.config.js
├── vite.config.ts
├── tailwind.config.ts
└── package.json
```

---

## Conventions

- Use **Svelte 5 runes** syntax (`$state`, `$derived`, `$effect`, `$props`) — not the legacy options API
- TypeScript throughout — `lang="ts"` on all `<script>` blocks
- Scoped CSS in `.svelte` files — no global utility classes

---

## Troubleshooting

### Map showing grey tiles or not loading

Your MapTiler API key is missing or invalid. Sign up at maptiler.com/cloud for a free key and add it to `.env.local` as `PUBLIC_MAPTILER_KEY`.

### "Failed to fetch" errors in the browser

The local Supabase backend isn't running. Start it first — see `local_testing_backend.md`.

### Type errors after pulling changes

```bash
pnpm check
```

If types are out of sync with the backend schema, update `src/lib/types.ts` to match.

### Port 7777 already in use

Another instance of the dev server is running. Kill it or use a different port:

```bash
pnpm dev --port 3000
```

---

*Last updated: April 2026*
