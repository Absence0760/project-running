# Run app — monorepo setup guide

A step-by-step guide to bootstrapping the monorepo from scratch, understanding the workspace structure, and running each app locally.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Flutter | 3.19+ | `flutter.dev/docs/get-started/install` |
| Dart | 3.3+ | Bundled with Flutter |
| Melos | 3.x | `dart pub global activate melos` |
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
│   ├── mobile_ios/          # Flutter iOS target
│   ├── mobile_android/      # Flutter Android target
│   ├── watch_ios/           # Native Swift WatchKit (Xcode project)
│   ├── watch_wear/          # Flutter Wear OS target
│   ├── web/                 # SvelteKit web app
│   └── backend/             # Supabase Edge Functions
├── packages/
│   ├── core_models/         # Shared Dart data types
│   ├── gpx_parser/          # GPX/KML/GeoJSON parsing
│   ├── run_recorder/        # Live GPS recording logic
│   ├── api_client/          # Supabase REST client
│   └── ui_kit/              # Shared Flutter widgets
├── tooling/
│   ├── melos.yaml
│   ├── package.json         # npm workspace root
│   └── analysis_options.yaml
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

- `dev:db:*` — supabase local stack (`up`, `down`, `reset`, `status`, `studio`, `mailpit`, `psql`, `logs`)
- `dev:run:*` — `web`, `web:preview`, `fns`, `android`, `ios`, `worker`, `osrm`
- `emu:android:list` / `emu:android:launch <name>` — Flutter emulators
- `build:*` — `web`, `android`, `ios`, `worker`
- `check:*` / `gen:*` / `test:*` — analyzers, type generators, test runners
- `setup:install` / `setup:flutter` — first-time bootstrap

The per-app recipes below show what each shortcut wraps, plus the device-targeting flags you'll usually want.

### iOS app

```bash
# From the repo root:
pnpm dev:run:ios            # wraps `cd apps/mobile_ios && flutter run`

# Or target a specific simulator:
open -a Simulator
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
PARKRUN_USER_AGENT=RunApp/1.0 (contact@runapp.com)
```

### GitHub Actions secrets

| Secret | Used by |
|---|---|
| `SUPABASE_URL` | All CI jobs |
| `SUPABASE_ANON_KEY` | Flutter builds, web build |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function deploy |
| `MAPTILER_KEY` | Flutter builds, web build |
| `STRAVA_CLIENT_SECRET` | Edge Function deploy |
| `AWS_DEPLOY_ROLE_ARN_PROD` | Web deployment — IAM role assumed via OIDC for tag `web@*` (see [releasing.md § Web (AWS deploy)](releasing.md#web-aws-deploy)) |
| `AWS_DEPLOY_ROLE_ARN_PREVIEW` | Web deployment — same shape for the preview env (push to `main`) |
| `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `PUBLIC_MAPTILER_KEY`, `PUBLIC_REVENUECAT_WEB_API_KEY`, `PUBLIC_SENTRY_DSN` | Web build — inlined into `.env.production` before `npm run build` |

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

Full pipeline defined in `.github/workflows/ci.yml`. Key jobs:

| Job | Runner | Trigger | What it does |
|---|---|---|---|
| `test-packages` | ubuntu-latest | PR + push to main + release | `melos bootstrap` → `melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test` → `melos exec -- dart analyze` |
| `build-web` | ubuntu-latest | PR + push to main + release | `npm ci` → `npm run lint` → `npm run build` |
| `parity-types` | ubuntu-latest | PR + push to main + release | `supabase start` → `npm run gen:types:check` |
| `build-ios` | macos-latest | Push to main | `flutter build ipa --no-codesign` |
| `build-android` | ubuntu-latest | Push to main | `flutter build appbundle` |
| `build-watch-swift` | macos-latest | Push to main | `xcodebuild` for WatchKit scheme |
| `deploy-functions` | ubuntu-latest | Release (published) | `supabase functions deploy` per function |

---

## Common tasks

### Run all tests

```bash
# All Flutter packages — Melos 7 needs `melos exec`, not `melos run` (CLAUDE.md gotcha)
pnpm test:flutter           # wraps `melos exec -- flutter test`

# Targeted Flutter subset (when you don't want every package):
melos exec --scope="run_recorder" --scope="mobile_android" -- flutter test

# Web
pnpm test:web:unit          # node:test on apps/web/src/lib/*.test.ts
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

### Deploy Edge Functions

```bash
supabase functions deploy strava-webhook --project-ref {project-ref}
supabase functions deploy strava-import --project-ref {project-ref}
supabase functions deploy parkrun-import --project-ref {project-ref}
supabase functions deploy refresh-tokens --project-ref {project-ref}
```

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

CI runs `npm run gen:types:check` in the `parity-types` job; if you forget to regenerate, the build fails with a diff against the committed `database.types.ts`. There is no equivalent CI gate for the Dart generator yet — it's on the roadmap but, for now, `dart analyze` will flag any stale column references you left behind in `api_client`.

See [schema_codegen.md](schema_codegen.md) for how the generators work, when they trip, and how to test drift detection.

---

*Last updated: May 2026 — root-level `pnpm dev:*` script set*
