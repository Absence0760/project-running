# Run app — orientation for AI sessions

You're in a cross-platform running app monorepo: Flutter (Android + iOS), native Swift (Apple Watch), Flutter (Wear OS), SvelteKit (web), and Supabase (Postgres + Auth + Storage + Edge Functions). Full product context lives in [docs/](docs/) — this file is the index plus the non-obvious things that cost time to rediscover.

## Read first

The docs are organised by concern, not by platform. Start with whichever is closest to the task you've been given:

| If the task is... | Start with |
|---|---|
| Anything at all, first time in a session | [docs/architecture.md](docs/architecture.md) — the map |
| Adding / changing a feature | [docs/roadmap.md](docs/roadmap.md) — what's shipped, what's planned |
| Touching the database or a client row type | [docs/schema_codegen.md](docs/schema_codegen.md) — generators + CI drift check |
| Touching a jsonb metadata key | [docs/metadata.md](docs/metadata.md) — the registry of known keys |
| Touching the recording pipeline | [docs/run_recording.md](docs/run_recording.md) — state machine, filters, auto-pause |
| Touching the web auth flow | [docs/web_app_auth.md](docs/web_app_auth.md) |
| Touching Edge Functions or the Supabase stack | [apps/backend/CLAUDE.md](apps/backend/CLAUDE.md) — functions, migrations, CLI gotchas |
| Understanding an end-to-end user journey | [docs/flows.md](docs/flows.md) — sign-in, record, sync, spectator |
| Adding a test | [docs/testing.md](docs/testing.md) — what's covered, patterns, how to run |
| Wiring a new integration (Strava, Garmin, parkrun, HealthKit) | [docs/integrations.md](docs/integrations.md) |
| Running one of the apps locally | [docs/local_testing_*.md](docs/) — one per platform |
| Backend schema, RLS, RPCs, Storage buckets | [docs/api_database.md](docs/api_database.md) |
| Setting up the monorepo / melos / workspaces | [docs/monorepo.md](docs/monorepo.md) |
| "Why did you do it this way?" | [docs/decisions.md](docs/decisions.md) — ADR log |
| House style (naming, comments, error handling) | [docs/conventions.md](docs/conventions.md) |

Per-app notes (framework specifics, what's real vs stubbed, app-specific gotchas):
- [apps/mobile_android/CLAUDE.md](apps/mobile_android/CLAUDE.md) — most mature Flutter target
- [apps/mobile_ios/CLAUDE.md](apps/mobile_ios/CLAUDE.md) — Flutter, mostly stubbed
- [apps/watch_wear/CLAUDE.md](apps/watch_wear/CLAUDE.md) — Flutter Wear OS, single-file stub
- [apps/watch_ios/CLAUDE.md](apps/watch_ios/CLAUDE.md) — native SwiftUI, functional
- [apps/web/CLAUDE.md](apps/web/CLAUDE.md) — SvelteKit 2 + Svelte 5 runes

## Branches & PRs

- `dev` is the working branch. `main` is the PR target.
- Never commit without being asked. When asked, never amend or force-push without being asked.
- Don't push to `main` directly; PRs only.
- The `Co-Authored-By` line on commits uses `Claude Opus 4.6 (1M context) <noreply@anthropic.com>`.

## Docs hygiene — update docs as part of every change

**After every change that affects docs, update them in the same turn.** Do not defer to "I'll write the docs in a follow-up." If a doc references behaviour you just changed, it is wrong the moment you change the code.

Concretely, before you report a task as done:

1. **Feature / behaviour change** — does any doc describe the old behaviour? Update it. Candidates: `roadmap.md`, `features.md`, `architecture.md`, the matching `local_testing_*.md`, and the per-app CLAUDE.md.
2. **Schema change** — regenerate both type files (`npm run gen:types` + `dart run scripts/gen_dart_models.dart`). Update `api_database.md` if a column, index, or RLS policy moved. See [schema_codegen.md](docs/schema_codegen.md).
3. **New convention or house rule** — add it to `docs/conventions.md`.
4. **Non-obvious decision or trade-off** — append an entry to `docs/decisions.md`. One paragraph. Don't rewrite history entries.
5. **Process / tooling change** — update `monorepo.md` (common tasks) and this file (if it's something a future session will hit as a gotcha).
6. **Roadmap checkbox** — tick it in `roadmap.md` the moment the work merges, not weeks later.

If you're unsure whether a doc change is warranted, err on the side of editing — a one-line update is better than drift. If the user tells you to skip doc updates for speed, respect that, but note the skipped update in your end-of-turn summary.

## Gotchas (things that cost me time to rediscover)

### Tools and workspace

- **Supabase lives under `apps/backend/supabase/`**, not at the repo root. The root-level `supabase/` directory is just the CLI's local state (`.branches`, `.temp`), don't write migrations there. Always `cd apps/backend` before `supabase <cmd>` (or use `--workdir`).
- **`melos run <script>` is broken on Melos 7** — scripts in `melos.yaml` aren't picked up (Melos 7 moved script definitions into package `pubspec.yaml` files). Use `melos exec -- <cmd>` for ad-hoc workspace-wide commands. Example: `melos exec -- dart analyze`.
- **`dart analyze` exits non-zero on `info`-level lints.** `mobile_android` has ~76 info-level lints (mostly `always_use_package_imports` and deprecated `withOpacity`) that are acknowledged tech debt. Treat `info` as noise; only act on `warning`/`error`.
- **Two package managers.** `apps/web` and `apps/backend` are npm workspaces (run `npm` commands from repo root or the app dir). Flutter packages are managed by Melos. Don't cross the streams.
- **`supabase gen types typescript --local` writes "Connecting to db 5432" to stdout**, not stderr. The `gen:types` script in `apps/backend/package.json` pipes through `grep -v '^Connecting to db'` to strip it. If you rewrite the script, keep the filter.
- **Seed user**: `runner@test.com` / `testtest`. Lives in `apps/backend/supabase/seed.sql`. Use it for any manual testing.
- **Local Supabase ports**: API 54321, DB 54322, Studio 54323, Mailpit 54324. The SvelteKit web dev server runs on **7777**, preview on 8888.

### Schema and row types

- **Every migration requires two regenerations.** TypeScript: `npm run gen:types`. Dart: `dart run scripts/gen_dart_models.dart`. Both outputs are committed. CI runs `gen:types:check` in the `parity-types` job and will fail PRs that skip it. See [docs/schema_codegen.md](docs/schema_codegen.md).
- **The Dart generator only understands `create table`, `alter table ... add column`, `alter table ... drop column`.** Everything else (indexes, functions, RLS, storage buckets, `$$...$$` bodies) is ignored. If you need a new SQL form, grow the parser in `scripts/gen_dart_models.dart` — don't hand-edit `db_rows.dart`.
- **Narrow unions live client-side** — `RunSource`, `RouteSurface`, `IntegrationProvider`, `PreferredUnit`, `SubscriptionTier` are not enforced by the DB (no CHECK constraints). They're overlaid in `apps/web/src/lib/types.ts` via `Omit & {...}`. If you add a new value, add it to the union; if you want the DB to enforce it, add a CHECK constraint in a migration and drop the overlay.
- **`runs.track` is not a column.** The GPS trace lives as a gzipped JSON file in the `runs` Storage bucket at `{user_id}/{run_id}.json.gz`; the row stores `track_url`. Never try to read `row.track` — it's `row.track_url` + a lazy download via `fetchTrack()`. See [docs/decisions.md](docs/decisions.md) for why.
- **`Run.metadata` is a `jsonb` bag** with no schema. It currently holds `activity_type`, `steps`, `event` (parkrun), `position` (parkrun), `age_grade`, and — client-only — a synthesised `track_url` key stuck there by `_runFromRow` for convenience. If you add a new metadata key, write a roadmap note; there is no type-level protection on these.

### Styling and conventions

- **No emojis anywhere** unless explicitly requested. Not in code, not in docs, not in commit messages, not in responses.
- **Default to zero comments.** Only write a comment if it explains a non-obvious *why* (hidden constraint, subtle invariant, workaround for a known bug). Never `// used by X`, never task-tracking references, never explain *what* well-named code already says.
- **Don't summarise what you just did** at the end of every response when the user can read the diff — keep end-of-turn text to 1–2 sentences (what changed, what's next).
- **No preemptive abstractions.** Three similar lines is better than a premature helper. If a `bug fix` PR contains a refactor, split it.
- **No backwards-compat shims**, no `// removed X` comments, no renamed-to-underscore-prefix unused variables. If something's unused, delete it.

## Layout cheat-sheet

```
apps/
  backend/           → Supabase project (config.toml, migrations/, functions/, seed.sql)
    package.json     → has the gen:types scripts
  web/               → SvelteKit 2 + Svelte 5 runes
    src/lib/database.types.ts  (generated, committed)
    src/lib/types.ts            (Run/Route/Integration/UserProfile overlays)
  mobile_android/    → Flutter, most mature; real screens, stores, sync, tile cache
  mobile_ios/        → Flutter, skeleton screens only (Phase 1 unfinished)
  watch_wear/        → Flutter Wear OS, single-file simulated stub
  watch_ios/         → native SwiftUI Xcode project, functional
packages/
  core_models/       → Dart domain classes + generated row DTOs
    lib/src/generated/db_rows.dart  (generated by scripts/gen_dart_models.dart)
  api_client/        → Typed Supabase client for Flutter apps
  gpx_parser/        → Pure Dart GPX/KML/KMZ/GeoJSON parser
  run_recorder/      → Live GPS recording state machine (used by mobile_android)
  ui_kit/            → Shared Flutter widgets
docs/                → The canonical reference — read these first
scripts/
  gen_dart_models.dart  → Dart row-class generator
.github/workflows/
  ci.yml             → PR: test-packages, build-web, parity-types
                       Push to main: + build-ios, build-android, build-watch-swift
                       Release: deploy-functions
```

## If something in this file is wrong

Edit it. This file is committed — an out-of-date orientation is worse than none.
