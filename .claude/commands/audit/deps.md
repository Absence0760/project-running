---
description: Cross-toolchain dependency audit (npm + flutter pub + Deno imports + GitHub Actions pinning)
---

Sweep dependencies across every package manager in this monorepo for known CVEs and version drift.

## What this is

The repo has at least four dependency trees:

- **npm workspaces** — `apps/web`, `apps/backend` (root `package.json` orchestrates)
- **Flutter / Dart** — `apps/mobile_android`, `apps/mobile_ios`, every package under `packages/` (managed by Melos)
- **Deno** — `apps/backend/supabase/functions/*` (no lockfile — version drift policed only by URL pinning)
- **Native** — `apps/watch_wear` (Gradle), `apps/watch_ios` (SwiftPM/Xcode), `apps/job_worker` (Go modules)
- **GitHub Actions** — `.github/workflows/*.yml` (action SHA pinning vs `@v1` floating tags)

## What to check

1. **npm.** Run `npm audit --workspace=apps/web` and `npm audit --workspace=apps/backend`. Collect high/critical findings. For each: package, version, CVE, fix version. The most recent fix in this repo was `@sveltejs/kit` 2.57.0 → 2.59.0 (commit 42ba6e8) — that's the canonical resolution shape.
2. **Flutter.** Run `cd apps/mobile_android && flutter pub outdated --mode=null-safety`. Note packages with security-related upgrades pending. Then run the same in `packages/api_client`, `packages/core_models`, `packages/run_recorder`, `packages/gpx_parser`, `packages/ui_kit`. The byte-identical iOS twin shares the same pubspec — no separate run needed.
3. **Deno.** Grep `apps/backend/supabase/functions/` for `https://deno.land/x/`, `npm:`, `https://esm.sh/`. List the unpinned imports (no `@x.y.z`). Each unpinned import is a supply-chain risk — flag for SHA / version pinning.
4. **GitHub Actions.** Grep `.github/workflows/` for `uses: <action>@<ref>`. Floating refs (`@main`, `@v1`) are supply-chain risks for actions that can be force-pushed by the action publisher; SHA pins (`@<sha>`) are the safer default for security-sensitive workflows (anything that can deploy or read secrets). Flag floating refs in workflows that touch `${{ secrets.* }}`.
5. **Native.** Less frequent but worth a glance:
   - `apps/watch_wear/build.gradle.kts` — Kotlin / Compose version
   - `apps/watch_ios/*/Package.resolved` — SwiftPM
   - `apps/job_worker/go.mod` + `go.sum` — `go list -m -u all` for outdated modules
6. **`update-all` parity.** This workstation has an `update-all` function (per `~/CLAUDE.md`) that handles dnf / flatpak / rustup / cargo / pipx / npm globals / ollama. None of those are in the repo, but if the user runs them, the repo's local toolchains may drift relative to system tools. Flag if `npm` / `flutter` / `dart` / `deno` system versions are newer than the repo expects.

## Report

- **Critical** — known-exploited CVE in a path the app actually uses (not a transitive in dev-only).
- **High** — a CVE with a fix available in a non-major bump.
- **Medium** — version drift with no CVE but the upgrade is overdue.
- **Low** — unpinned Deno imports, floating GitHub Actions refs.

For each: package + version + advisory link + the file to change + the upgrade command.

## Useful starting points

- `package.json` (root) — workspace orchestration
- `apps/web/package.json`, `apps/backend/package.json`
- `melos.yaml` — Flutter workspace
- `apps/backend/supabase/functions/*/index.ts` — Deno imports
- `.github/workflows/*.yml`

Read-only audit. Recommend upgrades; don't apply them without instruction (a major bump is its own conversation).
