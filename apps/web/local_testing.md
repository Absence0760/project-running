# Local testing — Web app (SvelteKit)

The web app is a SvelteKit 2 + Svelte 5 project at `apps/web/`. It uses pnpm as its package manager.

---

## Prerequisites

| Tool | Install |
|---|---|
| Node.js 20 LTS | `nodejs.org` |
| pnpm 9.x | `npm install -g pnpm` |
| Local backend running | See [../backend/local_testing.md](../backend/local_testing.md) |
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

See [../backend/local_testing.md](../backend/local_testing.md) for details on what the seed includes.

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
| `npx tsx --test src/lib/training.test.ts` | Run the training-engine unit tests (21 tests, ~150ms) |


---

## Testing external integrations

Each integration below is independent — you can skip the ones you're not touching. The seed user (`runner@test.com` / `testtest`) is the easiest baseline; sign in with email and add the integration on top.

### OAuth: Google sign-in + linking

The web app supports Google as a sign-in provider on `/login` and as a *link* on `/settings/account` (attaches Google to an existing account).

**Setup**
1. Google Cloud → APIs & Services → Credentials → create an **OAuth client ID** (type: Web application). Authorized redirect URIs: `http://localhost:7777/auth/callback` *and* the Supabase callback URL printed by `supabase status` (looks like `http://localhost:54321/auth/v1/callback`).
2. Local Supabase: edit `apps/backend/supabase/config.toml`, find `[auth.external.google]`, set `enabled = true` and paste `client_id` + `secret`. Restart the local stack (`supabase stop && supabase start` from `apps/backend/`).
3. For the **link-on-existing-account** flow, also flip on **Manual linking** in `[auth]` (`enable_manual_linking = true` in `config.toml`). Without this, `linkIdentity()` returns `manual_linking_disabled`.

**Test path**
1. Sign-up flow: `/login` → "Continue with Google" → consent screen → land back on `/dashboard` as a brand-new user. Verify a row in `auth.identities` (Studio at `:54323` → schema `auth` → table `identities`).
2. Linking flow: sign in with email → `/settings/account` → **Link Google** → consent for the *same* Google account → return to settings. The "Sign-in Methods" card should now list two rows (email + Google) with the same `user_id`.
3. Unlink flow: click **Unlink** on Google → confirm. Row disappears; the **Unlink** button on the remaining email identity is disabled with the "you need at least one" tooltip.

**Common failures**
- *"redirect_uri_mismatch"* on the Google consent screen → the URL in your browser doesn't match what's authorised in the Google client. Add it.
- *Returns to `/login` with no session* → Supabase callback URL not in the Google client's allow-list, or `config.toml` not reloaded after editing.

### OAuth: Apple sign-in + linking

Same pattern as Google. Apple requires a paid developer account and a more involved setup (Service ID + key + signed JWT secret) — skip for local-only testing unless you specifically need to verify Apple paths.

**Setup**
1. Apple Developer portal: create a Services ID, configure Sign in with Apple, add `http://localhost:7777/auth/callback` and the Supabase callback as Return URLs, generate a Sign in with Apple key, and produce a JWT secret (Supabase docs have the snippet).
2. `[auth.external.apple]` in `config.toml`: `enabled = true`, `client_id = <services_id>`, `secret = <jwt-secret>`.
3. Manual linking enabled (same flag as above).

**Test path**: identical to Google — sign in fresh, then a separate run of "Link Apple" on an email account. **Apple-specific gotcha**: Apple often returns an `@privaterelay.appleid.com` email; the linked-identity row will show that, not the user's real email. That's expected.

### AI coach (Anthropic and Ollama)

The coach endpoint at `/api/coach/+server.ts` supports two providers, picked by `COACH_PROVIDER` in `.env.local`.

**Prod path — Anthropic (default)**
1. `COACH_PROVIDER=anthropic` (or unset), `ANTHROPIC_API_KEY=sk-ant-...`.
2. Visit `/coach` → confirm the "Grounded in:" strip lists your active plan (or "No active plan"), the runs count, and HR-zone status.
3. Send a message ("How's my pace?") → response arrives within ~3s. The usage bar at the bottom shows cache numbers (`read N · wrote N · in N · out N`); the second message in the same conversation should show non-zero `read` (cache hit).
4. Switch the **Last N runs** chip to a different value and send another message. `runs_limit` is reflected in the prompt; the chip count updates immediately.
5. With multiple plans, the header `<select>` lets you swap; URL gains `?plan=<id>` and the chat resets.

**Local path — Ollama**
1. `ollama pull llama3.2` (or any model you have). Confirm `ollama serve` is running on `:11434`.
2. In `.env.local`:
   ```
   COACH_PROVIDER=openai
   OPENAI_BASE_URL=http://localhost:11434/v1
   OPENAI_API_KEY=ollama
   OPENAI_MODEL=llama3.2
   ```
3. `pnpm dev` (restart so Vite picks up env changes), open `/coach`, send a message. Responses are slower and lower-quality; that's expected for a 7–8B local model.
4. Switch back to Anthropic by setting `COACH_PROVIDER=anthropic` and restarting — no other changes needed.

**Common failures**
- *503 with "Coach is not configured"* → `ANTHROPIC_API_KEY` missing while `COACH_PROVIDER=anthropic`.
- *502 "coach upstream 4xx"* on Ollama path → model name mismatch (try `ollama list`) or Ollama not running.
- *429 with daily-limit message* → free-tier 10/day cap. Either set `BYPASS_PAYWALL=true` in `.env.local`, or flip the seed user's `subscription_tier` to `pro` in Studio.

### Cross-platform syncing (web ↔ mobile)

There's no separate sync service — every client writes to the same Supabase project and RLS scopes data by `user_id`. Linking Google or Apple just means multiple sign-in methods point at the same `user_id`, so any device signed in with any of them sees the same runs.

**Test path — emulator on the same machine**
1. Run web on `:7777` and the local Supabase stack on `:54321`.
2. Run `apps/mobile_android` in an Android emulator (see `apps/mobile_android/local_testing.md`). Point its Supabase URL at **`http://10.0.2.2:54321`** — Android's emulator alias for the host's loopback. `localhost` from inside the emulator is the emulator itself.
3. Sign in on both clients as `runner@test.com`. Record a run on Android (or use the manual-add modal on web).
4. Refresh `/runs` on web (or pull-to-refresh on Android) — the row should appear on the other side. Watch the `runs` table in Studio (`:54323`) for the live insert.

**Test path — real phone over LAN**
1. Web + Supabase running on your laptop. Note your LAN IP (`ipconfig getifaddr en0` on macOS).
2. Phone on the same Wi-Fi. Configure the mobile app's Supabase URL as `http://<lan-ip>:54321`.
3. Add `http://<lan-ip>:54321` to `[auth] additional_redirect_urls` in `config.toml` if you're testing OAuth from the phone.

**Test path — hosted Supabase project**
Easiest for cross-network testing: web `.env.local` and the mobile app both point at the same hosted project URL + anon key. No emulator gymnastics.

### Strava import

`/settings/integrations` connects via OAuth and pulls activities into `runs`.

**Setup**
1. Strava developer portal → create an app → set "Authorization Callback Domain" to `localhost`. Copy the client ID + secret.
2. `.env.local`:
   ```
   PUBLIC_STRAVA_CLIENT_ID=<id>
   STRAVA_CLIENT_ID=<id>
   STRAVA_CLIENT_SECRET=<secret>
   ```
3. Backend Edge Functions need the secret too — see `apps/backend/local_testing.md`.

**Test path**
1. `/settings/integrations` → **Connect Strava** → Strava OAuth screen → return.
2. Click **Sync now** → activities populate. Filter `/runs` by Source: Strava to verify.
3. Disconnect → row removed from `integrations`; subsequent sync attempts return "not connected".

### parkrun import

No OAuth — the user types their parkrun athlete number into `/settings/account`.

**Test path**
1. Set `parkrun_number` on the profile form (any 6-digit number works for testing the wire-up; real numbers are needed for actual results).
2. `/settings/integrations` → **Sync parkrun** → results pull in tagged with `metadata.event = 'parkrun'` and `metadata.position = N`.
3. Verify a row on `/runs` with the **parkrun** source pill.

### RevenueCat (Pro tier checkout)

Optional — only needed if you're touching the paywall flow. Without `PUBLIC_REVENUECAT_WEB_API_KEY`, `/settings/upgrade` falls back to a "coming soon" toast.

**Test path**
1. Set `PUBLIC_REVENUECAT_WEB_API_KEY` in `.env.local` to your RevenueCat sandbox key.
2. `/settings/upgrade` → **Get Pro** → RevenueCat checkout opens.
3. Use a test card; on completion the user's `subscription_tier` flips to `pro` and the coach's daily cap is bypassed.

**Bypass for non-paywall work**: set `BYPASS_PAYWALL=true` in `.env.local` to skip every tier check server-side without involving RevenueCat at all.

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
│   │   ├── coach/                 # Standalone AI coach with plan switcher + runs-limit chip
│   │   └── settings/
│   │       ├── integrations/      # Connect/disconnect Strava, Garmin, parkrun, HealthKit
│   │       ├── account/           # Profile, parkrun number, sign-in methods, CSV export
│   │       ├── preferences/       # Units, pace format, map style, HR zones, privacy, theme
│   │       ├── devices/           # Per-device setting overrides
│   │       └── upgrade/           # Pro-tier checkout (RevenueCat)
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
│   │       ├── RouteBuilder.svelte      # MapLibre map with waypoints
│   │       ├── RunMap.svelte            # MapLibre GPS trace viewer (reactive to map_style)
│   │       ├── ElevationProfile.svelte  # Responsive SVG elevation chart
│   │       ├── CalendarHeatmap.svelte   # GitHub-style activity heatmap
│   │       ├── PlanCalendar.svelte      # Plan-week calendar grid
│   │       ├── CoachChat.svelte         # AI coach UI (provider-agnostic via /api/coach)
│   │       ├── ImportRoute.svelte       # Drag-and-drop route file import modal
│   │       ├── ClubEditor.svelte        # Modal-host create form for clubs
│   │       ├── EventEditor.svelte       # Modal-host create form for club events
│   │       ├── PlanEditor.svelte        # Modal-host create form for training plans
│   │       └── RunEditor.svelte         # Modal-host create form for manual runs
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

The local Supabase backend isn't running. Start it first — see [../backend/local_testing.md](../backend/local_testing.md).

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

*Last updated: April 2026 — added "Testing external integrations" section.*
