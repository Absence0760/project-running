# Local Protomaps tile server (dev only)

The web app, mobile apps, and the Wear OS watch all consume map tiles. In production those tiles come from MapTiler — generous free tier, but a per-request meter that becomes a real cost line at scale. This doc explains how to run a self-hosted **Protomaps** stack locally so dev sessions, integration tests, and demo builds don't burn the production quota.

The production migration is a separate decision (see [decisions.md § 68](../architecture/decisions.md#68-tile-rendering-honours-an-env-override-so-local-dev-can-use-self-hosted-protomaps-without-touching-prod-code-paths)) and isn't covered here. This is the dev path.

## TL;DR

```bash
# One-time: needs Docker installed + running.
npm run dev:tiles:fetch    # grabs a ~1MB US-states sample
npm run dev:tiles:up       # boots tileserver-gl in Docker

# Copy the printed env vars into each app's .env.local, then run:
#   apps/web:        npm run dev --workspace=apps/web
#   apps/mobile_*:   flutter run -d <device>
#   apps/watch_wear: ./gradlew installDebug -PPUBLIC_TILE_URL_TEMPLATE=...

# When you're done:
npm run dev:tiles:down
```

(The `dev:tiles:*` scripts are thin wrappers around `bin/protomaps-dev.sh` —
either invocation works.)

The fetched sample only contains US-state polygons — enough to verify the wire end-to-end, not enough to render real run locations. For dev sessions in your actual area, generate a regional extract from the daily Protomaps world build (see "Getting a real PMTiles file" below).

## What it does

Boots `tileserver-gl` in a Docker container that serves a regional PMTiles extract on `http://localhost:8080`. The same endpoint serves both wire formats:

| Surface | Endpoint | Format |
|---|---|---|
| Web (MapLibre GL JS) | `/styles/basic/style.json` | vector + style |
| Mobile + Wear OS | `/styles/basic/{z}/{x}/{y}.png` | server-rasterised PNG |

Tileserver-gl uses MapLibre Native to rasterise vector tiles on demand, so all four surfaces (web, Android, iOS twin, Wear OS) point at the same dev server with nothing more than an env override.

## Prerequisites

- Docker daemon running (`sudo systemctl start docker` on Fedora)
- ~50 MB free in `$XDG_CACHE_HOME/protomaps-dev` (default cache dir) for the PMTiles file + style + config
- A free port — default 8080, override with `PROTOMAPS_PORT=…`

The script downloads everything else on first run.

## The bootstrap script

`bin/protomaps-dev.sh` exposes seven subcommands. The root `package.json` wraps them with `dev:tiles:*` npm scripts for consistency with the existing `dev:db:*` Supabase lifecycle (the two are the closest analogue — both are long-running Docker sidecars).

| npm script | Direct invocation | What it does |
|---|---|---|
| `npm run dev:tiles:fetch` | `bin/protomaps-dev.sh fetch` | Downloads a 1MB US-states sample PMTiles into `$PROTOMAPS_HOME` — enough to smoke-test the wire end-to-end, not enough to render real run locations. |
| `npm run dev:tiles:up` | `bin/protomaps-dev.sh start` | Generates config + style files, boots the container with `--restart unless-stopped`, waits for readiness, prints the env-var snippets to paste into each app's `.env.local`. Fails loudly if the PMTiles file isn't found or lives outside `PROTOMAPS_HOME`. On wait-timeout, auto-tails the last 30 lines of container output. |
| `npm run dev:tiles:restart` | `bin/protomaps-dev.sh restart` | Stop + start. Use when swapping a PMTiles file or after editing the config. |
| `npm run dev:tiles:down` | `bin/protomaps-dev.sh stop` | Kills + removes the container. PMTiles file stays cached for next time. |
| `npm run dev:tiles:status` | `bin/protomaps-dev.sh status` | Reports whether the container is running and where. |
| `npm run dev:tiles:logs` | `bin/protomaps-dev.sh logs` | Tails the container logs (`docker logs -f`). |
| `npm run dev:tiles:env` | `bin/protomaps-dev.sh env` | Prints the env-var snippet without starting/stopping anything. |

### Configuration

| Env var | Default | Effect |
|---|---|---|
| `PMTILES_FILE` | `$PROTOMAPS_HOME/world.pmtiles` | Path to the `.pmtiles` file tileserver-gl will serve. Point at any PMTiles you have on disk. |
| `DEFAULT_SAMPLE_URL` | Protomaps R2 US-states sample (~1MB) | URL the `fetch` subcommand pulls from. Override with any direct `.pmtiles` URL — e.g. a fresh daily world build (~80GB) from `https://build.protomaps.com/$(date +%Y%m%d).pmtiles`. |
| `PROTOMAPS_PORT` | `8080` | Host port. Bind to something else if 8080 is taken. |
| `PROTOMAPS_HOME` | `$XDG_CACHE_HOME/protomaps-dev` | Cache dir for the PMTiles file + the generated config + style. Surviving across runs means the second `start` is instant. |
| `DOCKER_IMAGE` | `maptiler/tileserver-gl:v5.6.0` | Pinned to a known-good release — `:latest` is deliberately avoided so a tag drift doesn't silently break our config. Bump manually when verified. |

### Getting a real PMTiles file

The script's `fetch` subcommand pulls a ~1MB US-states sample — enough to verify the wire end-to-end, but it doesn't contain road or place data, and obviously doesn't cover anywhere outside the US. For real dev sessions:

1. **Regional extract** (your area, MB to GB depending on size). Install the `pmtiles` Go CLI once:
   ```bash
   go install github.com/protomaps/go-pmtiles@latest    # or: brew install pmtiles
   ```
   Then slice a bbox out of the daily world build:
   ```bash
   pmtiles extract https://build.protomaps.com/$(date +%Y%m%d).pmtiles \
     ~/.cache/protomaps-dev/world.pmtiles --bbox=MIN_LON,MIN_LAT,MAX_LON,MAX_LAT
   ```

2. **Full world build** (~80GB):
   ```bash
   curl -L -o ~/.cache/protomaps-dev/world.pmtiles \
     https://build.protomaps.com/$(date +%Y%m%d).pmtiles
   ```

3. **Your own file** — point `PMTILES_FILE=/path/to/file.pmtiles` and re-run `start`.

Re-run `bin/protomaps-dev.sh start` after dropping a new file in; the container hot-mounts `$PROTOMAPS_HOME` so a fresh PMTiles is picked up on next restart.

## Env overrides — per app

Once `bin/protomaps-dev.sh start` succeeds, paste the printed snippets into each app's `.env.local`. The override pattern is uniform: when the var is set, the app routes tile requests through the local server; when it's empty or absent, the app falls back to MapTiler.

| App | Env var | Format |
|---|---|---|
| `apps/web` | `PUBLIC_TILE_STYLE_URL` | Full URL to a MapLibre `style.json` — typically `http://localhost:8080/styles/basic/style.json`. |
| `apps/mobile_android` + `apps/mobile_ios` | `TILE_URL_TEMPLATE` | `{z}/{x}/{y}` template with placeholders — typically `http://localhost:8080/styles/basic/{z}/{x}/{y}.png`. |
| `apps/watch_wear` | `PUBLIC_TILE_URL_TEMPLATE` (BuildConfig — pass `-PPUBLIC_TILE_URL_TEMPLATE=…` to gradle) | same shape as mobile |

### Android-emulator gotcha

The Android emulator's loopback alias for the host machine is `10.0.2.2` — `localhost` from inside the emulator points at the emulator's own VM, not your laptop. If you're running an emulator, swap `localhost` for `10.0.2.2` in the mobile + Wear OS values. The bootstrap script's `env` output makes a note of this.

### Why three different env var names

Each platform has its own dotenv-style convention; renaming all three to one name would mean breaking a different community-known convention every time. The shapes also differ — web wants a style.json URL, mobile/Wear want a tile-URL template — so a single unified var would have to carry both shapes and explain which is which. Three narrow names is cleaner.

## How the apps consume the override

### Web (`apps/web/src/lib/map-style.svelte.ts` + `map-style-url.ts`)

The reactive `getMapStyle()` / `setMapStyle(...)` signal still drives the user's chosen style in production. `mapStyleUrl()` accepts an optional `overrideUrl` arg that wins outright — `mapStyleUrlFromEnv(...)` reads `import.meta.env.PUBLIC_TILE_STYLE_URL` and threads it in. Every `RunMap.svelte` / `PrivacyZonePicker.svelte` / `RouteHeatmap.svelte` / live-event spectator imports `mapStyleUrlFromEnv` and gets the dev override for free.

### Mobile (`apps/mobile_android/lib/widgets/live_run_map.dart`)

File-level `resolveTileUrl(env)` reads `TILE_URL_TEMPLATE` first, falls back to the MapTiler URL keyed by `MAPTILER_KEY`. The widget's `_tileUrl` getter delegates to this helper. The iOS twin is byte-identical.

### Wear OS (`apps/watch_wear/.../ui/TileSource.kt`)

File-level `buildTileUrl(z, x, y, template, maptilerKey, styleSlug)` does the same: non-blank template wins, otherwise build the MapTiler URL. The `enabled` flag now lights up when EITHER `PUBLIC_TILE_URL_TEMPLATE` OR `PUBLIC_MAPTILER_KEY` is non-empty, so the dev path doesn't need a MapTiler key sitting around.

## Tests

Eleven web + eight mobile + twelve Wear OS unit tests pin the URL builder behaviour against the empty/blank/non-empty override matrix. See:

- `apps/web/src/lib/map-style.test.ts`
- `apps/mobile_android/test/live_run_map_tile_url_test.dart` (+ iOS twin)
- `apps/watch_wear/android/app/src/test/kotlin/com/runapp/watchwear/ui/TileUrlBuilderTest.kt`

## Operational notes

### Disk footprint

| Region slug | Size | Worth running |
|---|---:|---|
| `monaco` (default) | ~10 MB | Smoke testing, CI, just-verify-the-wire |
| `london` | ~150 MB | Realistic dev for runs in central London |
| `bay-area` | ~250 MB | West Coast dev |
| `north-america` | ~10 GB | Full continent — overkill for dev |

### CI

The bootstrap script is **dev-only**. CI doesn't run a tile server — every existing test that touches map rendering was already mocked or asserted against URLs, never live tile bytes. The new tests cover the URL builder in isolation; no integration test depends on tiles actually returning bytes.

### Production

The web + mobile + Wear OS code in production calls the same URL builders — they just see an empty override and fall through to MapTiler. The only production change is: no production change. Flip the env back in a future migration when self-hosted Protomaps is deployed on S3/CloudFront. See [decisions.md § 68](../architecture/decisions.md#68-tile-rendering-honours-an-env-override-so-local-dev-can-use-self-hosted-protomaps-without-touching-prod-code-paths).

### Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `docker daemon is not running` | Docker service stopped | `sudo systemctl start docker` |
| Container won't bind 8080 | Port collision (Supabase Studio uses 54323, the local Supabase API is 54321 — neither conflicts; check `lsof -i :8080`) | Set `PROTOMAPS_PORT=8081` and re-run `start` |
| Web map renders but mobile is blank | Forgot the `10.0.2.2` alias inside the emulator | Update `TILE_URL_TEMPLATE` in mobile `.env.local` |
| Wear OS doesn't pick up the override after editing `.env.local` | BuildConfig values are baked at compile time | `./gradlew installDebug -PPUBLIC_TILE_URL_TEMPLATE=…` rebuilds with the new value |
| `PMTiles download failed` | Region slug doesn't exist, or build.protomaps.com is down | Try a different region or set `PMTILES_URL` to a known-good extract |

## Why not Vercel-style edge caching in dev

Tile cost at scale is real (`competitors.md`), but in dev the volume is irrelevant — the per-developer hit rate on MapTiler's free tier is in the dozens, not millions. The reason to bother with local Protomaps now is twofold:

1. **It surfaces drift early.** When the production migration eventually lands, having every dev session already running on Protomaps style means we won't discover style-incompatibility bugs at launch.
2. **It un-gates demo builds.** A demo with the MapTiler key embedded is a leak waiting to happen. Demo builds + integration test fixtures can both point at the local server without ever needing a production key.

If you don't need either of those, MapTiler in dev is fine — the override is opt-in.
