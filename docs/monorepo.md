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

# Verify everything is wired up
melos run analyze
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

  build:wear:
    run: flutter build apk
    packageFilters:
      scope: watch_wear

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

### iOS app

```bash
# Open simulator
open -a Simulator

# Run from workspace root
cd apps/mobile_ios
flutter run -d iPhone

# Or target a specific simulator
flutter devices
flutter run -d {device-id}
```

### Android app

```bash
# Start emulator from Android Studio, then:
cd apps/mobile_android
flutter run -d emulator-5554
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

```bash
# Start a Wear OS emulator in Android Studio:
# Device Manager → Create → Wear OS → Wear OS Large Round (API 34)

cd apps/watch_wear
flutter run -d {wear-emulator-id}
```

### Web app

```bash
cd apps/web

# Install dependencies
pnpm install

# Copy environment file
cp .env.example .env.local
# Fill in PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, PUBLIC_MAPTILER_KEY

pnpm dev
# Opens at http://localhost:7777
```

### Backend (Edge Functions)

```bash
# Install Supabase CLI
brew install supabase/tap/supabase

# Start local Supabase stack (Postgres + Auth + Storage)
supabase start

# Serve Edge Functions locally with hot reload
supabase functions serve --env-file .env.local

# Functions available at http://localhost:54321/functions/v1/{function-name}
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
| `VERCEL_TOKEN` | Web deployment |
| `VERCEL_ORG_ID` | Web deployment |
| `VERCEL_PROJECT_ID` | Web deployment |

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
| `test-packages` | ubuntu-latest | All PRs | `melos bootstrap` → `melos run test` → `melos run analyze` |
| `build-ios` | macos-latest | All PRs | `flutter build ipa --no-codesign` |
| `build-android` | ubuntu-latest | All PRs | `flutter build appbundle` |
| `build-watch-swift` | macos-latest | All PRs | `xcodebuild` for WatchKit scheme |
| `build-web` | ubuntu-latest | All PRs | `pnpm install` → `pnpm check` → `pnpm build` |
| `deploy-web` | Via Vercel | Push to `main` | Automatic via Vercel GitHub integration |
| `deploy-functions` | ubuntu-latest | Push to `main` | `supabase functions deploy --all` |

---

## Common tasks

### Run all tests

```bash
melos run test
```

### Check for lint issues across all packages

```bash
melos run analyze
cd apps/web && pnpm check
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

### Deploy Edge Functions

```bash
supabase functions deploy strava-webhook --project-ref {project-ref}
supabase functions deploy strava-import --project-ref {project-ref}
supabase functions deploy parkrun-import --project-ref {project-ref}
supabase functions deploy refresh-tokens --project-ref {project-ref}
```

### Apply a database migration

```bash
# Create migration file
supabase migration new add_metadata_to_runs

# Edit the generated SQL file in supabase/migrations/
# Then apply locally
supabase db reset

# Push to production
supabase db push --project-ref {project-ref}
```

---

*Last updated: April 2026*
