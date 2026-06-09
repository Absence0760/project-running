# project-running

Cross-platform running + gym + nutrition app: Flutter (Android + iOS), native
Apple Watch (SwiftUI) and Wear OS (Compose), a SvelteKit web app, and a
Supabase backend. The full product + architecture docs live in [docs/](docs/);
AI-session orientation is in [CLAUDE.md](CLAUDE.md).

## Quick start (local dev)

Everything runs against a **local stack** — no cloud accounts and no API keys.
The repo ships working dev config (committed, local-stack-only): local
Supabase, local [Protomaps](docs/ops/protomaps_local_setup.md) map tiles, and a
local [Ollama](https://ollama.com) model for the AI Coach. **There are no env
files to copy or edit.**

### Prerequisites

- **Docker** — runs Supabase + the map-tile server
- **[Supabase CLI](https://supabase.com/docs/guides/cli)**
- **Node 20+** and **pnpm** (`npm i -g pnpm`)
- **Flutter 3.x** + **Melos** (`dart pub global activate melos`) — for the mobile apps
- **[Ollama](https://ollama.com)** — optional, only for the AI Coach
- **adb** (Android platform-tools) — only to run the mobile app on a device/emulator

### Three commands

```bash
npm run setup        # install deps + generate Flutter platform dirs (run once)
npm run dev:up       # start Supabase (seeded) + map tiles + adb reverse + Ollama check
npm run dev:run:web  # web app on http://localhost:7777   (or: npm run dev:run:android)
```

That's it. The committed dev defaults (a `.env.development` in each app) point
every client at the local stack, on `127.0.0.1` so the same values work on an
emulator **and** a physical device (`dev:up` runs `adb reverse` for any
attached device). The mobile app auto-logs in as the seed user.

**Seed login:** `runner@test.com` / `testtest`

`dev:up` is idempotent — re-run it any time (e.g. after replugging a phone,
which clears the `adb reverse` forwards).

**Want the whole backend in one shot?** `npm run dev:all:services` is the
superset of `dev:up` — it also starts the Go job worker (live tracking +
background jobs) and, when their graphs are built, the OSRM / GraphHopper
routing engines. It backgrounds everything and returns, so you then run the
same `dev:run:*` command for whichever platform you're testing. Manage it with
`dev:all:services:status` / `:logs` / `:down`.

### Using real external services

The committed defaults are deliberately key-free (Protomaps instead of
MapTiler, Ollama instead of Anthropic). To use a real key (MapTiler, Anthropic,
Strava, RevenueCat), put it in a **gitignored `.env.local`** next to the
committed file — it overrides the defaults. Never commit real secrets.

### Handy tasks

```bash
npm run dev:db:reset     # wipe + reseed the local database (+ run GPS tracks)
npm run dev:db:studio    # open Supabase Studio
npm run dev:db:mailpit   # open the local mail inspector
npm run dev:tiles:up     # start / dev:tiles:down stop the map-tile server
npm run dev:run:ios      # Flutter app on an iOS simulator/device
npm run dev:run:worker   # Go background-job worker (live tracking, exports)
```

The same committed-defaults pattern covers every client: **web**, **mobile**
(iOS + Android, the `.env.development` asset loaded only in debug), **Wear OS**
(`.env.development` applied by the debug build type), and the
**Apple Watch** (the DEBUG-only direct-sync path defaults to the local stack) —
all point at `127.0.0.1` and are compiled/loaded only in dev/debug, never in a
release build. The iOS **simulator** and Wear OS reach `127.0.0.1` directly /
via `adb reverse`; a **physical iOS device** needs your Mac's LAN IP instead of
`127.0.0.1` (it can't `adb reverse`).

Running on a **physical device**, or want the emulator/`adb reverse` details?
See [apps/mobile_android/local_testing.md](apps/mobile_android/local_testing.md).
Per-app notes live in each `apps/<app>/local_testing.md`, and what's real vs
stubbed locally (payments, push, coach) is in
[docs/testing/local_testing_stubs.md](docs/testing/local_testing_stubs.md).
