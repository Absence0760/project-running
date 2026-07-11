# Run app — monorepo setup guide

A step-by-step guide to bootstrapping the monorepo from scratch, understanding the workspace structure, and running each app locally.

---

**Contents:** [Prerequisites](#prerequisites) · [Initial setup](#initial-setup) · [Workspace structure](#workspace-structure) · [Melos workspace config](#melos-workspace-config) · [Web app package management](#web-app-package-management) · [Running each app locally](#running-each-app-locally) · [Environment variables](#environment-variables) · [Package dependency graph](#package-dependency-graph) · [Code style and lint](#code-style-and-lint) · [CI/CD](#cicd) · [Common tasks](#common-tasks)

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Flutter | 3.19+ | `flutter.dev/docs/get-started/install` |
| Dart | 3.3+ | Bundled with Flutter |
| Melos | 7.x | `dart pub global activate melos` |
| Node.js | 20 LTS | `nodejs.org` |
| Xcode | 15+ | Mac App Store (macOS only) |
| Android Studio | Hedgehog+ | `developer.android.com/studio` |

---

## Initial setup

```bash
# Clone the repo
git clone https://github.com/your-org/run-app.git
cd run-app

# Bootstrap Flutter workspace — links local packages, fetches dependencies
melos bootstrap

# Install web app dependencies
cd apps/web && pnpm install && cd ../..

# Verify everything is wired up (use `melos exec`, not `melos run` —
# Melos 7's per-script lookup is broken; see root CLAUDE.md gotcha)
melos exec -- dart analyze
cd apps/web && pnpm check
```

---

## Workspace structure

```
run-app/
├── apps/
│   ├── mobile_ios/          # Flutter iOS target (lib/+test/ byte-identical to mobile_android, decisions §39)
│   ├── mobile_android/      # Flutter Android target
│   ├── watch_ios/           # Native SwiftUI (Xcode project)
│   ├── watch_wear/          # Native Kotlin + Compose-for-Wear (not Flutter)
│   ├── watch_garmin/        # Native Monkey C / Connect IQ data field for existing Garmin watches (research-tier Vector 1 spike)
│   ├── custom_watch/        # Rust + Embassy firmware for the ultra-marathon watch (research-tier, tier-1 bench prototype)
│   ├── graph_cycle/         # Go street-graph cycle-search sidecar for route loop generation
│   ├── web/                 # SvelteKit 2 + Svelte 5 runes
│   ├── backend/             # Supabase project — migrations, functions, seed
│   └── job_worker/          # Go background worker (Fly.io)
├── packages/
│   ├── core_models/         # Shared Dart data types + generated row DTOs
│   ├── gpx_parser/          # GPX/KML/KMZ/GeoJSON parsing
│   ├── run_recorder/        # Live GPS recording state machine
│   ├── api_client/          # Typed Supabase client for Flutter apps
│   └── ui_kit/              # Shared Flutter widgets
├── infra/                   # Terraform stacks for AWS web hosting
├── melos.yaml               # root, governs Flutter workspace
├── package.json             # root, JS workspaces for apps/web + apps/backend (pnpm locally, npm in CI)
├── analysis_options.yaml    # root Dart analyser config
└── README.md
```

---

## Melos workspace config

```yaml
# melos.yaml
name: run-app

packages:
  - apps/mobile_ios
  - apps/mobile_android
  - apps/watch_wear
  - packages/**

command:
  bootstrap:
    usePubspecOverrides: true   # links local packages without publishing

scripts:
  # Run all tests across all packages
  test:
    run: melos exec -- flutter test
    description: Run tests in all Flutter packages

  # Analyse all packages
  analyze:
    run: melos exec -- flutter analyze
    description: Dart analysis across all packages

  # Build individual targets
  build:ios:
    run: flutter build ipa --no-codesign
    packageFilters:
      scope: mobile_ios

  build:android:
    run: flutter build appbundle
    packageFilters:
      scope: mobile_android

  # watch_wear is NOT a Melos package — it's pure Kotlin / Compose-for-Wear
  # with its own Gradle build (decisions.md §15). Build it with:
  #   cd apps/watch_wear/android && ./gradlew assembleDebug

  # Format all Dart code
  format:
    run: melos exec -- dart format .
```

---

## Web app package management

The web app lives outside Melos (different language) but in the same Git repo. It uses **pnpm** as its package manager (matching the upstream web template).

```bash
# Install web app dependencies
cd apps/web
pnpm install
```

---

## Running each app locally

Root-level `pnpm` shortcuts wrap the per-app commands so the common cases are one line from the repo root. Run `pnpm run` to see the full list; the groups are:

- `dev:core` — quick core stack (Supabase + tiles + Ollama check + adb reverse)
- `dev:full` — the full backend in one shot (the `dev:core` stack **plus** the Go job worker, backgrounded, and the OSRM / GraphHopper engines when their graphs are built); then run a `dev:run:*` for your platform. `dev:full:status` / `:logs` / `:down` manage it
- `dev:db:*` — supabase local stack (`up`, `down`, `reset`, `status`, `studio`, `mailpit`, `psql`, `logs`)
- `dev:run:*` — `web`, `web:preview`, `fns`, `android`, `ios`, `worker`, `osrm`
- `emu:android:*` / `emu:ios:*` — Android emulator / iOS simulator helpers (`emu:ios:*` are macOS-only)
- `watch:*` — custom-watch firmware (`doctor`, `build`, `test`, `flash`, `logs`, `sim`, `sim:gui` — thin aliases for `bin/watch-*.sh`; `test` and `sim` need no board)
- `build:*` — `web`, `android`, `ios`, `worker`
- `check:*` / `gen:*` / `test:*` — analyzers, type generators, test runners
- `setup:install` / `setup:flutter` — first-time bootstrap

The per-app recipes below show what each shortcut wraps, plus the device-targeting flags you'll usually want.

### iOS app

```bash
# From the repo root:
pnpm dev:run:ios            # wraps `cd apps/mobile_ios && flutter run`

# Or target a specific simulator (macOS-only):
pnpm emu:ios:list           # wraps `xcrun simctl list devices available`
pnpm emu:ios:launch         # wraps `flutter emulators --launch apple_ios_simulator`
cd apps/mobile_ios && flutter devices
cd apps/mobile_ios && flutter run -d {device-id}
```

### Android app

```bash
# Start an emulator first:
pnpm emu:android:list
pnpm emu:android:launch Pixel_8_API_34

# Then run:
pnpm dev:run:android        # wraps `cd apps/mobile_android && flutter run`
```

### Apple Watch app

```bash
# Open Xcode project directly
open apps/watch_ios/WatchApp.xcodeproj

# Select scheme: WatchApp
# Select destination: Apple Watch simulator paired with your iOS simulator
# Cmd+R to run
```

The watch app must be run alongside the iOS app — use the "Run" scheme that launches both. In Xcode: Product → Scheme → Edit Scheme → add the iOS app as a pre-action.

### Wear OS app

Native Kotlin + Compose-for-Wear, not Flutter — open in Android Studio:

```bash
# Start a Wear OS emulator (Device Manager → Create → Wear OS Large Round, API 34)
# Then in Android Studio: open apps/watch_wear and Run.
```

### Custom watch firmware

Rust + Embassy, research-tier ([decisions.md § 71/§ 80](decisions.md)) — no Melos, no npm workspace, just cargo behind the `bin/watch-*.sh` wrappers:

```bash
pnpm watch:doctor           # once per machine: verify toolchain + board detection
pnpm watch:flash            # build + flash a connected nRF52840 DK + stream defmt logs
pnpm watch:test             # host-side unit tests, no board
pnpm watch:sim              # boot the firmware on an emulated DK (Renode), no board
pnpm watch:sim:gui          # same, plus the live watch-screen window
pnpm watch:monitor          # second terminal: interactive Renode monitor (runMacro $btn1..4)
```

Full walkthrough in [apps/custom_watch/local_testing.md](../../apps/custom_watch/local_testing.md).

### Web app

```bash
# First time only:
cp apps/web/.env.example apps/web/.env.local
# Fill in PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_MAPTILER_KEY

pnpm setup:install          # workspace bootstrap
pnpm dev:run:web            # wraps `pnpm -C apps/web dev`, opens http://localhost:7777
pnpm dev:run:web:preview    # built site on http://localhost:8888
```

### Backend (Edge Functions)

```bash
# Install Supabase CLI (Fedora: RPM from GitHub releases per ~/CLAUDE.md;
# macOS: `brew install supabase/tap/supabase`)

pnpm dev:db:up              # wraps `cd apps/backend && supabase start` —
                            # brings up Postgres + Auth + Storage + Studio
pnpm dev:run:fns            # wraps `supabase functions serve --env-file .env.local`

# Functions available at http://localhost:54321/functions/v1/{function-name}
# Studio UI: pnpm dev:db:studio   (http://127.0.0.1:54323)
# Mail catcher: pnpm dev:db:mailpit (http://127.0.0.1:54324)
# psql shell: pnpm dev:db:psql
# Reset to a clean seed: pnpm dev:db:reset
```

### Job worker (Go)

```bash
# Local Supabase must be up first:
pnpm dev:db:up
pnpm dev:run:worker         # wraps `cd apps/job_worker && go run .`
pnpm dev:run:osrm           # optional: docker-compose the local OSRM stack
```

---

## Environment variables

### Flutter apps

Environment variables for Flutter are injected at build time via `--dart-define`. Never hardcode keys in source.

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=MAPTILER_KEY=your-maptiler-key
```

For local development, create a `launch.json` in VS Code or a run configuration in Android Studio with these values pre-filled.

```json
// .vscode/launch.json
{
  "configurations": [
    {
      "name": "iOS (dev)",
      "type": "dart",
      "program": "apps/mobile_ios/lib/main.dart",
      "args": [
        "--dart-define=SUPABASE_URL=${env:SUPABASE_URL}",
        "--dart-define=SUPABASE_ANON_KEY=${env:SUPABASE_ANON_KEY}",
        "--dart-define=MAPTILER_KEY=${env:MAPTILER_KEY}"
      ]
    }
  ]
}
```

### Web app

```bash
# apps/web/.env.local
PUBLIC_SUPABASE_URL=https://xxx.supabase.co
PUBLIC_SUPABASE_ANON_KEY=eyJ...
PUBLIC_MAPTILER_KEY=your-maptiler-key
STRAVA_CLIENT_ID=12345
STRAVA_CLIENT_SECRET=abc...   # server-side only — no PUBLIC_ prefix
```

### Edge Functions

```bash
# apps/backend/.env.local (used by supabase functions serve)
STRAVA_CLIENT_ID=12345
STRAVA_CLIENT_SECRET=abc...
PARKRUN_USER_AGENT=RunApp/1.0 (contact@threkir.com)
```

### GitHub Actions secrets

| Secret | Used by |
|---|---|
| `SUPABASE_URL` | All CI jobs |
| `SUPABASE_ANON_KEY` | Flutter builds, web build |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function deploy |
| `MAPTILER_KEY` | Flutter builds, web build |
| `STRAVA_CLIENT_SECRET` | Edge Function deploy |
| `AWS_DEPLOY_ROLE_ARN_PROD` | Web deployment — IAM role assumed via OIDC when a `web@*` GitHub Release is published (see [releasing.md § Web (AWS deploy)](../ops/releasing.md#web-aws-deploy)) |
| `AWS_DEPLOY_ROLE_ARN_PREVIEW` | Web deployment — same shape for the preview env (push to `main`) |
| `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `PUBLIC_MAPTILER_KEY`, `PUBLIC_REVENUECAT_WEB_CHECKOUT_URL`, `PUBLIC_REVENUECAT_WEB_PORTAL_URL`, `PUBLIC_SENTRY_DSN` | Web build — inlined into `.env.production` before `npm run build` |

---

## Package dependency graph

Each Flutter app imports from shared packages. Packages do not import from apps.

```
mobile_ios ──────┐
mobile_android ──┤──→ ui_kit ──→ core_models
watch_wear ──────┘         └──→ gpx_parser
                           └──→ run_recorder ──→ core_models
                           └──→ api_client ──→ core_models
```

The web app (`apps/web`) has no dependency on Dart packages — it calls the Supabase REST API directly via the JavaScript client.

### Adding a new shared package

```bash
# 1. Create the package
flutter create --template=package packages/my_package

# 2. Add to consuming app's pubspec.yaml
# apps/mobile_ios/pubspec.yaml
dependencies:
  my_package:
    path: ../../packages/my_package

# 3. Re-bootstrap to link it
melos bootstrap
```

---

## Code style and lint

### Dart / Flutter

All packages share a single `analysis_options.yaml` at the repo root, included by reference in each package.

```yaml
# analysis_options.yaml (root)
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_single_quotes: true
    require_trailing_commas: true
    sort_pub_dependencies: true
    always_use_package_imports: true
```

```yaml
# packages/core_models/analysis_options.yaml
include: ../../analysis_options.yaml
```

### TypeScript / SvelteKit

Type checking is handled by `svelte-check`:

```bash
cd apps/web
pnpm check        # Type-check all Svelte and TypeScript files
pnpm check:watch  # Watch mode
```

Svelte 5 runes syntax (`$state`, `$derived`, `$effect`, `$props`) is used throughout — not the legacy options API.

---

## CI/CD

Full pipeline defined in `.github/workflows/ci.yml`. Seventeen jobs run on every PR + push to `main`:

| Job | Runner | What it does |
|---|---|---|
| `test-packages` | ubuntu-latest | `melos bootstrap` → scoped `flutter test` on `run_recorder` + `mobile_android` + `api_client` + `gpx_parser` |
| `test-worker` | ubuntu-latest | `go vet ./...` + `go test ./...` for `apps/job_worker` (incl. the GDPR Art 20 export-completeness guard) |
| `test-graph-cycle` | ubuntu-latest | `go vet ./...` + `go test ./...` for the `apps/graph_cycle` street-graph cycle-search sidecar |
| `parity-types` | ubuntu-latest | `supabase start` → `npm run gen:types:check` |
| `build-web` | ubuntu-latest | `npm run build --workspace=apps/web` — SvelteKit compile check, no deploy |
| `parity-matrix` | ubuntu-latest | `dart run scripts/check_parity_matrix.dart` — keeps `docs/product/parity.md` honest |
| `build-watch-wear` | ubuntu-latest | Gradle build of `apps/watch_wear` (Compose-for-Wear smoke) |
| `build-firmware` | ubuntu-latest | `cargo build` + clippy + host tests of `apps/custom_watch` (Rust + Embassy, `thumbv7em-none-eabihf`) |
| `build-mobile-android` | ubuntu-latest | `flutter build appbundle` |
| `twin-parity` | ubuntu-latest | `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` + `test/` |
| `schema-codegen-drift` | ubuntu-latest | re-run `gen_dart_models.dart` (regenerates `db_rows.dart` + `DbRows.kt`), fail if working tree dirty |
| `api-client-integration` | ubuntu-latest | `packages/api_client` integration suite against local Supabase |
| `edge-functions` | ubuntu-latest | Deno test for every function in `apps/backend/supabase/functions/` |
| `pgtap-rls` | ubuntu-latest | `supabase test db` for the pgtap RLS suite |
| `e2e-web` | ubuntu-latest | Playwright sharded 14-way over `apps/web/tests-e2e/` |
| `e2e-web-livehub` | ubuntu-latest | Playwright against the real Go live-hub WebSocket binary (unsharded) |
| `e2e-web-sso` | ubuntu-latest | Playwright over the OAuth / SSO login path against a local mock OIDC server (unsharded) |

Branch protection requires a single status check — the **`CI gate`** aggregator job, which `needs:` every job above (so adding a job auto-gates merges once it's listed); `ci-gate-docs.yml` reports an equivalently-named `CI gate` for docs-only PRs.

iOS builds + Edge Function deploys run from `.github/workflows/release-ios.yml` and `release-backend.yml` on tag, not on PR. See [releasing.md](../ops/releasing.md) for the release-time pipeline.

---

## Common tasks

### Run all tests

```bash
# All Flutter packages — Melos 7 needs `melos exec`, not `melos run` (CLAUDE.md gotcha)
pnpm test:flutter           # wraps `melos exec -- flutter test`

# Targeted Flutter subset (when you don't want every package):
melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test

# Web
pnpm test:web:unit          # tsx --test on apps/web/src/lib/**/*.test.ts
pnpm test:web:e2e           # Playwright
pnpm test:web:e2e:ui        # Playwright in headed mode

# Go worker
pnpm test:worker            # wraps `cd apps/job_worker && go test ./...`
```

### Check for lint issues across all packages

```bash
pnpm check:flutter          # wraps `melos exec -- dart analyze`
pnpm check:web              # wraps `pnpm -C apps/web check`
```

### Add a dependency to a specific package

```bash
cd packages/gpx_parser
flutter pub add xml
```

### Update all package dependencies

```bash
melos exec -- flutter pub upgrade
cd apps/web && pnpm update
```

### Regenerate schema types after a migration

```bash
# Both generators in one go (requires `pnpm dev:db:up` to be running):
pnpm gen:all                # = pnpm gen:types && pnpm gen:dart

# Or individually:
pnpm gen:types              # TypeScript → apps/web/src/lib/database.types.ts
pnpm gen:dart               # Dart → packages/core_models/lib/src/generated/db_rows.dart

# Verify the TS file is in sync with the local DB (matches the CI check)
pnpm gen:types:check
```

### Regenerate app icons after editing the mark

The app icon is a single vector master at `assets/icon.svg`. Every platform's
raster icon (web favicon / touch / PWA, iOS + watchOS app-icon sets, Android +
Wear OS mipmaps, the Garmin launcher) is generated from it — never hand-edited.
After changing `assets/icon.svg`, regenerate them all in one command:

```bash
# Requires inkscape + ImageMagick 7 (the opt-in asset-pipeline tools).
./assets/gen-icons.sh
```

The script is deterministic and idempotent: it re-renders each target at its
committed pixel size (iOS/watchOS icons come out opaque truecolor, no alpha, as
the App Store requires). The web header + PWA use `apps/web/static/logo-mark.svg`
and `wordmark.svg`, which are separate hand-authored vector lockups derived from
the same mark — edit those directly.

### Deploy Edge Functions

```bash
# One per directory under apps/backend/supabase/functions/
# (clip-public-track, delete-account, events-checkout, events-connect-onboard,
#  export-data, parkrun-import, refresh-tokens, revenuecat-webhook,
#  strava-import, strava-webhook, stripe-events-webhook)
for fn in apps/backend/supabase/functions/*/; do
  name=$(basename "$fn")
  [ "$name" = "_shared" ] && continue
  supabase functions deploy "$name" --project-ref {project-ref}
done
```

Three of these (`refresh-tokens`, `strava-webhook`, `export-data`) have been
superseded by the Go worker but are kept deployed as the rollback path — see
[api_database.md](../backend/api_database.md) for the per-function status.

### Apply a database migration

Every schema change has to flow through both client type generators so the TypeScript and Dart row classes stay in sync. The workflow is:

```bash
# 1. Create migration file (must be cwd'd into apps/backend — the CLI looks for config.toml there)
cd apps/backend && supabase migration new add_metadata_to_runs

# 2. Edit the generated SQL file in apps/backend/supabase/migrations/
# 3. Apply locally (from repo root)
pnpm dev:db:reset

# 4. + 5. Regenerate both client row-type files
pnpm gen:all

# 6. Commit the migration SQL + both regenerated files together
git add apps/backend/supabase/migrations apps/web/src/lib/database.types.ts \
        packages/core_models/lib/src/generated/db_rows.dart

# 7. Push to production
cd apps/backend && supabase db push --project-ref {project-ref}
```

CI runs `npm run gen:types:check` in the `parity-types` job; if you forget to regenerate, the build fails with a diff against the committed `database.types.ts`. The Dart side is gated too: the `schema-codegen-drift` job re-runs `gen_dart_models.dart` (which regenerates `db_rows.dart` and the Kotlin `DbRows.kt`) and fails the PR if the committed files drift. On top of that, `dart analyze` will flag any stale column references you left behind in `api_client`.

See [schema_codegen.md](schema_codegen.md) for how the generators work, when they trip, and how to test drift detection.

---

*Last updated: 2026-06-14 — root-level `pnpm dev:*` script set*
