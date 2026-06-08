# Run app — orientation for AI sessions

You're in a cross-platform running app monorepo: Flutter (Android + iOS), native Swift (Apple Watch), native Kotlin + Compose-for-Wear (Wear OS), SvelteKit (web), and Supabase (Postgres + Auth + Storage + Edge Functions). Full product context lives in [docs/](docs/) — this file is the index plus the non-obvious things that cost time to rediscover.

## Read first

The `docs/` tree is grouped into topical folders, by concern rather than by platform:

- **`docs/architecture/`** — system map, monorepo setup, ADR log (`decisions.md`), house conventions, schema codegen
- **`docs/product/`** — roadmap, parity matrix, feature specs, competitor analysis, open follow-ups
- **`docs/backend/`** — schema / RPCs / RLS reference, backend scaling, the `metadata.md` + `settings.md` registries, the `derived_state.md` cache contract
- **`docs/features/`** — per-feature deep dives: run recording, training, clubs, workout execution, integrations, paywall, web auth, end-to-end flows
- **`docs/testing/`** — testing guide + `test_inventory.md`, manual / mobile-e2e recipes, dev accounts, coverage snapshot, dev/prod isolation
- **`docs/ops/`** — deployment hub, releasing, backup/restore, local Protomaps tiles
- **`docs/custom_watch/`** — ultra-marathon-watch hardware research (research-tier; see `decisions.md § 71`)

Start with whichever row below is closest to the task you've been given:

| If the task is... | Start with |
|---|---|
| Anything at all, first time in a session | [docs/architecture/architecture.md](docs/architecture/architecture.md) — the map |
| Adding / changing a feature | [docs/product/roadmap.md](docs/product/roadmap.md) — what's shipped, what's planned, and the unphased competitor-parity backlog |
| Checking which platforms a feature ships on | [docs/product/parity.md](docs/product/parity.md) — feature × platform matrix, single source of truth for drift |
| Touching the database or a client row type | [docs/architecture/schema_codegen.md](docs/architecture/schema_codegen.md) — generators + CI drift check |
| Touching a jsonb metadata key | [docs/backend/metadata.md](docs/backend/metadata.md) — the registry of known keys |
| Touching a user setting / preference | [docs/backend/settings.md](docs/backend/settings.md) — universal + per-device prefs registry |
| Touching a trigger-maintained cache (PRs, route run_count, gym totals, coach usage) | [docs/backend/derived_state.md](docs/backend/derived_state.md) — the cache=authoritative-query contract per derived cache + retention |
| Touching the recording pipeline | [docs/features/run_recording.md](docs/features/run_recording.md) — state machine, filters, auto-pause |
| Touching the web auth flow | [docs/features/web_app_auth.md](docs/features/web_app_auth.md) |
| Touching Edge Functions or the Supabase stack | [apps/backend/CLAUDE.md](apps/backend/CLAUDE.md) — functions, migrations, CLI gotchas |
| Understanding an end-to-end user journey | [docs/features/flows.md](docs/features/flows.md) — sign-in, record, sync, spectator |
| Adding a test | [docs/testing/testing.md](docs/testing/testing.md) — what's covered, patterns, how to run |
| Manually verifying a shipped feature | [docs/testing/manual_testing.md](docs/testing/manual_testing.md) — per-platform recipes for every shipped capability |
| Running every feature locally (including stubbed payments) | [docs/testing/local_testing_stubs.md](docs/testing/local_testing_stubs.md) — Stripe test mode, RevenueCat sandbox, Apple/Play IAP, Ollama-for-Coach |
| Adding mobile e2e tests in CI | [docs/testing/mobile_e2e.md](docs/testing/mobile_e2e.md) — Android integration_test on Ubuntu (~free), iOS on macOS (~$$), Firebase Test Lab pre-release |
| Which features have e2e tests today + what dev accounts unblock the rest | [docs/testing/e2e_dev_accounts.md](docs/testing/e2e_dev_accounts.md) — coverage table + 11-item dev-account checklist (Google, Stripe, Anthropic, …) |
| Keeping local dev isolated from prod | [docs/testing/dev_prod_isolation.md](docs/testing/dev_prod_isolation.md) — Vite + Playwright guard rules, the `ALLOW_PROD_URL_IN_DEV` override, what's enforced vs not |
| Touching the clubs / events / social layer | [docs/features/clubs.md](docs/features/clubs.md) — surfaces, schema pointers, what's deferred |
| Touching email / notification delivery (welcome, receipts, reminders, digest) | [docs/features/email.md](docs/features/email.md) — job kinds, SMTP transport, i18n catalogue, what's shipped vs planned, prod ops |
| Touching training plans (VDOT, Riegel, generator, week grid) | [docs/features/training.md](docs/features/training.md) — engine shape, pace derivation, what's deferred |
| Implementing the live structured-workout execution loop | [docs/features/workout_execution.md](docs/features/workout_execution.md) — specced runner state machine + UI + persistence |
| Building the Phase 4 gym / nutrition surfaces (or the multi-modal nav / Home) | [docs/features/multi_modal.md](docs/features/multi_modal.md) — mobile-first, anti-clutter layout + IA contract; data foundation (`gym_workouts`/`gym_sets`/`food_log` + the `activities` view) is shipped (migration `20261204_001`; the vestigial `runs.kind` discriminator was dropped in `20261206_001`, F1/D1 — the view injects the literal per UNION branch) |
| Wiring a new integration (Strava, Garmin, parkrun, HealthKit) | [docs/features/integrations.md](docs/features/integrations.md) |
| Running one of the apps locally | `apps/<app>/local_testing.md` — one per app (e.g. [apps/mobile_android/local_testing.md](apps/mobile_android/local_testing.md), [apps/backend/local_testing.md](apps/backend/local_testing.md)) |
| Backend schema, RLS, RPCs, Storage buckets | [docs/backend/api_database.md](docs/backend/api_database.md) |
| Setting up the monorepo / melos / workspaces | [docs/architecture/monorepo.md](docs/architecture/monorepo.md) |
| "Why did you do it this way?" | [docs/architecture/decisions.md](docs/architecture/decisions.md) — ADR log |
| "Should we build our own watch hardware?" | [docs/custom_watch/README.md](docs/custom_watch/README.md) — research baseline for an ultra-marathon watch (vision, competitive landscape, BOM, prototyping cost tiers, performance path, firmware architecture). Current default of not starting hardware work + the triggers that would change it are recorded in [decisions.md § 71](docs/architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely). The 2026-05-28 §71 amendment permits owner-personal tier-1 bench-prototype work; the active firmware workspace lives at [apps/custom_watch/](apps/custom_watch/README.md) and the live parts shopping list at [docs/custom_watch/parts.md](docs/custom_watch/parts.md). Firmware language locked to Rust + Embassy per [§ 80](docs/architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance) |
| House style (naming, comments, error handling) | [docs/architecture/conventions.md](docs/architecture/conventions.md) |
| Cutting a release (tag conventions, secrets, rollback) | [docs/ops/releasing.md](docs/ops/releasing.md) |
| Where each service runs in production / cost / DR / rollback | [docs/ops/deployment.md](docs/ops/deployment.md) — hub; per-service plans live alongside each `apps/<x>/deployment.md` |
| Touching AWS infra (web hosting) | [infra/README.md](infra/README.md) — Terraform stacks (bootstrap, dns, github-oidc, modules/web-stack, envs/{prod,preview}), sops + KMS for runtime secrets, first-deploy walkthrough; see [decisions.md § 53](docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages) for the rationale |
| Deploying / rotating preview or prod (operator scripts) | [bin/README.md](bin/README.md) — wraps the AWS / sops / terraform sequences (`aws-preflight`, `deploy-preview`, `sops-init`, `secret-set`, `preview-status`, `lambda-logs`, `key-rotate`, `onboard-operator`, `disaster-recovery`) so first-deploy + rotation flows fit on a few commands. Read-only by default; mutating ones prompt or take `--auto-approve`. |
| Adding a paywalled feature | [docs/features/paywall.md](docs/features/paywall.md) — tiers, feature registry, BYPASS_PAYWALL, RevenueCat |
| Running map tiles locally (no MapTiler quota burn) | [docs/ops/protomaps_local_setup.md](docs/ops/protomaps_local_setup.md) — `bin/protomaps-dev.sh start` boots a self-hosted tileserver-gl in Docker; web / mobile / Wear OS pick up the override via env vars. See [decisions.md § 68](docs/architecture/decisions.md#68-tile-rendering-honours-an-env-override-so-local-dev-can-use-self-hosted-protomaps-without-touching-prod-code-paths) for the design |

Per-app notes (framework specifics, what's real vs stubbed, app-specific gotchas). **Each non-web app's CLAUDE.md opens with a "Scope — read before writing code" section** that spells out what to build there vs. what to push to web first per [decisions.md § 24](docs/architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive). Read it before adding a feature on a non-web client.
- [apps/web/CLAUDE.md](apps/web/CLAUDE.md) — SvelteKit 2 + Svelte 5 runes; **canonical feature surface** for the whole product
- [apps/mobile_android/CLAUDE.md](apps/mobile_android/CLAUDE.md) — most mature Flutter target; mirrors web + adds device-led capabilities
- [apps/mobile_ios/CLAUDE.md](apps/mobile_ios/CLAUDE.md) — Flutter; **`lib/` and `test/` are byte-identical to `mobile_android`** ([decisions.md § 39](docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase)); platform-specific behaviour dispatches via `Platform.isIOS` inside the unified files
- [apps/watch_wear/CLAUDE.md](apps/watch_wear/CLAUDE.md) — native Kotlin + Compose-for-Wear, functional (not Flutter); wrist-only complement, NOT a pocket-app mirror
- [apps/watch_ios/CLAUDE.md](apps/watch_ios/CLAUDE.md) — native SwiftUI, functional; wrist-only complement, NOT a pocket-app mirror
- [apps/watch_garmin/CLAUDE.md](apps/watch_garmin/CLAUDE.md) — native **Monkey C / Connect IQ** data field for existing Garmin watches; **research-tier, strategic Vector 1 spike** (is our UX better than Garmin's native UI?), not a parity client. See [decisions.md § 87](docs/architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware) + [§ 107](docs/architecture/decisions.md#107-vector-1-starts-as-a-connect-iq-data-field-grade-adjusted-pace-not-a-full-watch-app)
- [apps/custom_watch/CLAUDE.md](apps/custom_watch/CLAUDE.md) — Rust + Embassy firmware for the ultra-marathon watch research effort; **research-tier, tier-1 bench prototype only**, see [decisions.md § 71](docs/architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) + [§ 80](docs/architecture/decisions.md#80-tier-1-firmware-uses-embassy-on-rust-on-the-nordic-nrf52840--chosen-for-memory-safety-tooling-and-async-ergonomics-not-for-performance). Strategy + BOM + cost tiers + parts list live at [docs/custom_watch/](docs/custom_watch/README.md)

## Audit commands

Project-curated slash commands for security / privacy / invariant audits live under `.claude/commands/audit/`. Invoke as `/audit/<name>` (e.g. `/audit/rls`, `/audit/privacy-zones`). `/audit/all` runs the full sweep in parallel. Each is read-only on the codebase — they report findings, they don't fix without confirmation. **Findings are persisted to `reviews/`** (gitignored working notes — `reviews/audit-<name>.md` for audits, `reviews/persona-<name>.md` for persona hunts; lifecycle in [`reviews/README.md`](reviews/README.md)), not just chat. See [`.claude/commands/audit/README.md`](.claude/commands/audit/README.md) for the index + when to run each.

## /safe-edit — coder ↔ reviewer loop for non-trivial changes

For security-sensitive, schema, or recording-stack changes — anything where a second pass of "did the diff actually honour the project's invariants" is worth ~2-3x the token cost — use `/safe-edit <task>`. It implements the change, then runs the `code-reviewer` agent against the working diff (cross-checking decisions ADRs, layering contract, twin invariant, paywall gates, fail-closed defaults, comment / abstraction discipline), applies any concrete findings, re-reviews once, and hands off to the user for the commit decision. Hard cap at 2 review cycles. Don't use it on typos, doc tweaks, or any < ~10-line diff that touches no invariant — just edit those directly.

## /check — review + test-gap + doc-hygiene before declaring done

Every non-trivial dev change goes through **review → unit tests → e2e tests** before it's done. The `/check` slash command runs the three relevant agents in parallel against the working diff and reports gaps:

- `code-reviewer` — does the change honour project invariants? (same agent `/safe-edit` uses)
- `test-gap-checker` — did the diff add unit tests + e2e tests where the rule says it should? Web e2e = Playwright (`apps/web/tests-e2e/`). Backend e2e = pgtap (`apps/backend/supabase/tests/`) or Deno tests next to the Edge Function. Mobile / watch have **no e2e equivalent** by design — see `docs/testing/testing.md § What's not covered`.
- `doc-hygiene-checker` — same as the Docs hygiene rule below.

Cheaper than `/safe-edit` (single pass, no review-and-fix loop), advisory only — the user decides which findings to apply. Use it before every commit on a non-trivial change. Skip on typos / comment edits / dep bumps.

The full rule + per-source-type test surface is in [`docs/architecture/conventions.md` § Test hygiene](docs/architecture/conventions.md#test-hygiene--review-then-unit-then-e2e).

## /improve-round — ship one improvement to an area, then self-audit

`/improve-round [area]` is the repeatable "do another round" loop: pick (or take) one area of the app, ship a genuinely useful, bounded improvement **web-first** in path-scoped per-piece commits (tests + twin parity + i18n + docs each in their own commit), then run the `code-reviewer` agent against the commit range and fix every finding — **verifying any numeric claim by computing it** before applying — until clean, capped at two review cycles. Unlike `/check` (advisory, working-diff, no fixes) and `/safe-edit` (one task, coder↔reviewer loop), this one *chooses the work*, commits as it goes, and closes the audit loop itself. Omit the arg to let it survey for a high-value target (a missing signal, a feature interconnection that doesn't exist yet, or a shipped-but-inconsistent surface) and propose it before building. Definition in [`.claude/commands/improve-round.md`](.claude/commands/improve-round.md).

## Always recommend the long-term solution

When there's a choice between a quick patch and the durable fix, **lead with the durable one** — the root cause, the reusable abstraction, the consistent pattern, the proper schema change — not the band-aid. This applies to every recommendation: a one-off conversion vs. a shared component, papering over a failing test vs. fixing the bug it caught, a local workaround vs. closing the underlying gap, copy-paste vs. extracting the shared helper.

- **Recommend the long-term solution even when it's more work.** Don't pre-emptively pitch the cheap option to save effort or tokens. State the durable fix as the recommendation.
- **When you do mention a quicker path, present the long-term one first and name the trade-off** so the user is choosing with eyes open — never silently ship the shortcut.
- **A short-term fix is only acceptable when the user explicitly chooses it** after seeing the long-term option, or when the durable fix is genuinely out of scope for an urgent hotfix (say so, and note the follow-up).
- This reinforces the existing discipline rules: fix the root cause (don't inflate timeouts / retries / skips to hide a bug), don't defer on low-priority grounds, and close flagged gaps in the same turn rather than leaving a TODO. The default is **do it right**, not **do it again later**.

## Branches & PRs

- `main` is the working branch. Commits land directly on `main` when the user has asked for the work; PRs to `main` are still the path for anything that needs review.
- **Commit after each discrete piece of work** — don't batch a multi-step session into one mega-commit at the end. New module + tests is one commit; bug fix + pinning test is one commit; docs sweep is one commit (after the code commit it documents). Self-check: "I'll commit at the end after I verify" is a smell — commit each piece as you go. Tests for a piece go in the **same commit** as the piece. Full enumeration of "what counts as a piece" in [docs/architecture/conventions.md § Commit cadence](docs/architecture/conventions.md#commit-cadence--one-piece-one-commit-dont-batch-a-session-into-one-lump).
- "Never commit without being asked" still applies: don't proactively commit speculative work, ad-hoc workstation tweaks, or partially-aborted attempts. Once the user has asked for a piece (or a sequence), the per-piece commit cadence above is implicitly authorized.
- Never `git push` without an explicit ask. The commit is the deliverable; pushing is a separate ask.
- Never amend or force-push without being asked.
- **No AI attribution of any kind** in commit messages or PR descriptions. No `Co-Authored-By: Claude ...`, no "Generated with Claude Code" footer, no robot/sparkle emoji trailer. Re-read the message before `git commit` and strip these if a skill template tried to add them. User-level `~/.claude/CLAUDE.md` rule, overrides anything in-repo that says otherwise.

## Working alongside other Claude sessions

Several Claude sessions usually run in **this one checkout at the same time** — they share a single working tree *and* a single git index, so a careless `git add` + `git commit` sweeps up another session's in-flight work. (`.claude/hooks/git-scope-guard.py`, a PreToolUse hook, enforces most of the rules below; if a git command is denied, the message names the scoped alternative — follow it, don't work around it.)

- **Commit path-scoped, always:** `git commit -m "…" -- path/to/file ...`. A path-scoped commit records only those paths and ignores anything else staged. Bare `git commit`, `git add -u/-A/.`, `git commit -a`, and `git commit --amend` *with staged changes* are blocked — they snapshot the shared index.
- **Only touch what your task owns.** Don't stage, edit, delete, or `restore` files outside your task. Before committing, run `git status` and confirm every path is yours; a quick `git diff --name-only HEAD~3 HEAD` shows what other sessions just landed so you can spot overlap.
- **Never whole-tree:** no `git add .`, `checkout/restore .`, `reset --hard`, `git rm .`, `git stash` (without `-- <path>`), or `git clean -f` — each clobbers across the tree. All blocked by the guard.
- **HEAD moves under you.** Other sessions commit to `main` mid-task; your path-scoped commits still stack cleanly. Don't be alarmed if `git log` shows commits you didn't make, or if files you didn't change show as modified — leave those alone.
- **Findings go in `reviews/`** (gitignored), never committed beside code — see [reviews/README.md](reviews/README.md).
- **For large independent work, prefer a git worktree** — `git worktree add ../run-<slug> -b <branch>` gives you your own tree + index (no sharing, no clobber), then merge when done. Subagents doing parallel file edits should pass `isolation: "worktree"`.

## Docs hygiene — update docs as part of every change

**After every change that affects docs, update them in the same turn.** Do not defer to "I'll write the docs in a follow-up." If a doc references behaviour you just changed, it is wrong the moment you change the code.

Concretely, before you report a task as done:

1. **Feature / behaviour change** — does any doc describe the old behaviour? Update it. Candidates: `roadmap.md`, `features.md`, `parity.md` (flip cells for every platform the change affects), `architecture.md`, the matching `apps/<app>/local_testing.md`, and the per-app CLAUDE.md.
2. **Schema change** — regenerate both type files (`npm run gen:types` + `dart run scripts/gen_dart_models.dart`). Update `api_database.md` if a column, index, or RLS policy moved. See [schema_codegen.md](docs/architecture/schema_codegen.md).
3. **New convention or house rule** — add it to `docs/architecture/conventions.md`.
4. **Non-obvious decision or trade-off** — append an entry to `docs/architecture/decisions.md`. One paragraph. Don't rewrite history entries.
5. **Process / tooling change** — update `monorepo.md` (common tasks) and this file (if it's something a future session will hit as a gotcha).
6. **Roadmap checkbox** — tick it in `roadmap.md` the moment the work merges, not weeks later.

If you're unsure whether a doc change is warranted, err on the side of editing — a one-line update is better than drift. If the user tells you to skip doc updates for speed, respect that, but note the skipped update in your end-of-turn summary.

## Gotchas (things that cost me time to rediscover)

### Tools and workspace

- **Supabase lives under `apps/backend/supabase/`**, not at the repo root. If you ever see a top-level `supabase/` directory appear, it's the CLI's local state cache (`.branches`, `.temp`); don't write migrations there. Always `cd apps/backend` before `supabase <cmd>` (or use `--workdir`).
- **`melos run <script>` is broken on Melos 7** — scripts in `melos.yaml` aren't picked up (Melos 7 moved script definitions into package `pubspec.yaml` files). Use `melos exec -- <cmd>` for ad-hoc workspace-wide commands. Example: `melos exec -- dart analyze`.
- **`dart analyze` exits non-zero on `info`-level lints.** `mobile_android` carries ~480 info-level lints today (the bulk are `always_use_package_imports` + `avoid_relative_lib_imports` interacting with the byte-identical-twin convention, plus `deprecated_member_use` from `withOpacity` → `withValues`). All acknowledged tech debt. Treat `info` as noise; only act on `warning`/`error`.
- **Two package managers.** `apps/web` and `apps/backend` are npm workspaces (run `npm` commands from repo root or the app dir). Flutter packages are managed by Melos. Don't cross the streams.
- **`supabase gen types typescript --local` writes "Connecting to db 5432" to stdout**, not stderr. The `gen:types` script in `apps/backend/package.json` pipes through `grep -v '^Connecting to db'` to strip it. If you rewrite the script, keep the filter.
- **Seed user**: `runner@test.com` / `testtest`. Lives in `apps/backend/supabase/seed.sql`. Use it for any manual testing.
- **Local Supabase ports**: API 54321, DB 54322, Studio 54323, Mailpit 54324. The SvelteKit web dev server runs on **7777**, preview on 8888.

### Schema and row types

- **Every migration requires two regenerations.** TypeScript: `npm run gen:types`. Dart: `dart run scripts/gen_dart_models.dart`. Both outputs are committed. CI runs `gen:types:check` in the `parity-types` job and will fail PRs that skip it. See [docs/architecture/schema_codegen.md](docs/architecture/schema_codegen.md).
- **The Dart generator only understands `create table`, `alter table ... add column`, `alter table ... drop column`.** Everything else (indexes, functions, RLS, storage buckets, `$$...$$` bodies) is ignored. If you need a new SQL form, grow the parser in `scripts/gen_dart_models.dart` — don't hand-edit `db_rows.dart`.
- **Narrow unions live client-side AND in CHECK constraints** — `RunSource`, `RouteSurface`, `IntegrationProvider`, `PreferredUnit`, `SubscriptionTier`, `ClubRole`, `ActivityType` are overlaid as TS unions in `apps/web/src/lib/types.ts` via `Omit & {...}` AND enforced by CHECK constraints (see `apps/backend/supabase/migrations/20260505_001_narrow_union_check_constraints.sql` for the first four, `20260429_001_subscription_paywall.sql` for `subscription_tier`, `20260428_001_role_permissions.sql` for `role`, `20261207_001_promote_activity_type_is_dnf.sql` for `activity_type`). The TS union and the CHECK must stay in lockstep — updating one without the other lets one client write a value the other rejects (postgres 23514 `check_violation`). The `parity-types` CI job runs `apps/web/scripts/check_constraint_unions.mjs` to fail PRs that drift; if you add a new union+CHECK pair, append it to the `PAIRS` array in that script. Dart treats these columns as raw `String` (no Dart enum to update), but invalid writes are still rejected at the DB. If you add a new value: update the migration, regenerate types, update the TS union.
- **`runs.track` is not a column.** The GPS trace lives as a gzipped JSON file in the `runs` Storage bucket at `{user_id}/{run_id}.json.gz`; the row stores `track_url`. Never try to read `row.track` — it's `row.track_url` + a lazy download via `fetchTrack()`. See [docs/architecture/decisions.md](docs/architecture/decisions.md) for why.
- **`Run.metadata` is a `jsonb` bag** with no schema. It currently holds `activity_type`, `steps`, `event` (parkrun), `position` (parkrun), `age_grade`, and — client-only — a synthesised `track_url` key stuck there by `_runFromRow` for convenience. If you add a new metadata key, write a roadmap note; there is no type-level protection on these.

### Styling and conventions

- **No emojis anywhere** unless explicitly requested. Not in code, not in docs, not in commit messages, not in responses.
- **Default to zero comments.** Only write a comment if it explains a non-obvious *why* (hidden constraint, subtle invariant, workaround for a known bug). Never `// used by X`, never task-tracking references, never explain *what* well-named code already says.
- **Don't summarise what you just did** at the end of every response when the user can read the diff — keep end-of-turn text to 1–2 sentences (what changed, what's next).
- **No preemptive abstractions.** Three similar lines is better than a premature helper. If a `bug fix` PR contains a refactor, split it.
- **No backwards-compat shims**, no `// removed X` comments, no renamed-to-underscore-prefix unused variables. If something's unused, delete it.
- **Layered resilience is a product contract.** Basics always work. Design every new feature so a failure at a higher layer (L4 auxiliary effect, L3 route overlay, L2 map, etc.) cannot break a lower one (L1 GPS/pedometer distance, L0 clock). Wrap each auxiliary effect (TTS, network ping, platform channel, third-party widget) in its own try/catch + `debugPrint` — never widen to a single outer catch, never swallow silently, and never let an auxiliary failure cancel a core `setState`. See [docs/architecture/conventions.md § Layered resilience](docs/architecture/conventions.md#layered-resilience) and the L0–L4 table in [docs/features/run_recording.md § Layering](docs/features/run_recording.md#layering) before touching the recording stack.
- **TS↔Dart parity helpers must stay in lockstep.** Several pure-logic modules exist on both web and mobile and must match — algorithm, edge cases, outputs, test counts. The pairs are: `training`, `segments`, `privacy`, `recurrence`, `pace_segments`, `training_load`, `fitness`, `rate_limit_errors`, `runner_handle`, `distance_bands` (web `routes/distance_bands.ts` ↔ mobile `distance_bands.dart`), `exif_strip` (web `util/exif_strip.ts` `stripJpegExif` ↔ mobile `exif_strip.dart`), `grade_adjusted_pace` (web `runs/grade_adjusted_pace.ts` ↔ mobile `grade_adjusted_pace.dart`), `gym_prs` (web `gym/gym_prs.ts` ↔ mobile `gym_prs.dart`), `nutrition_targets` (web `nutrition/nutrition_targets.ts` ↔ mobile `nutrition_targets.dart`), `lift_load` (web `gym/lift_load.ts` `liftsFromSetHistory` ↔ mobile `lift_load.dart`), `exercise_calories` (web `nutrition/exercise_calories.ts` ↔ mobile `exercise_calories.dart`), `age_grade` (web `runs/age_grade.ts` ↔ mobile `age_grade.dart`; their embedded factor tables `age_grade_tables.ts` ↔ `age_grade_tables.dart` are generated from `scripts/age_grade/` and stay identical by construction — never hand-edit them), plus the `track_projection.ts` ↔ `projectTrack` helper inside `track_preview.dart`. The `shared-library-syncer` agent (under `.claude/agents/`) detects divergence proactively after edits — invoke it whenever you touch one side of a pair.

## Layout cheat-sheet

```
apps/
  backend/           → Supabase project (config.toml, migrations/, functions/, seed.sql)
    package.json     → has the gen:types scripts
  web/               → SvelteKit 2 + Svelte 5 runes
    src/lib/database.types.ts  (generated, committed)
    src/lib/types.ts            (Run/Route/Integration/UserProfile overlays)
    src/lib/coach/              (transport-agnostic core for /api/coach)
    lambda/coach/               (production AWS Lambda wrapper, decisions §53)
  mobile_android/    → Flutter; real screens, stores, sync, tile cache
  mobile_ios/        → Flutter; lib/ + test/ kept byte-identical to mobile_android (see decisions.md § 39)
  watch_wear/        → native Kotlin + Compose-for-Wear (not Flutter)
  watch_ios/         → native SwiftUI Xcode project, functional
  watch_garmin/      → native Monkey C / Connect IQ data field for existing Garmin watches (research-tier, strategic Vector 1 spike; decisions §87 + §107)
  custom_watch/      → Rust + Embassy firmware for the ultra-marathon watch research effort (research-tier, tier-1 bench prototype only; decisions §71 amendment + §80, 2026-05-28)
  job_worker/        → Go background-job worker (drains the `jobs` queue; first kind is map_match)
packages/
  core_models/       → Dart domain classes + generated row DTOs
    lib/src/generated/db_rows.dart  (generated by scripts/gen_dart_models.dart)
  api_client/        → Typed Supabase client for Flutter apps
  gpx_parser/        → Pure Dart GPX/KML/KMZ/GeoJSON parser
  run_recorder/      → Live GPS recording state machine (used by both mobile apps via the unified Dart codebase)
  ui_kit/            → Shared Flutter widgets
docs/                → The canonical reference — read these first
infra/               → Terraform stacks for AWS web hosting (decisions §53)
  bootstrap/         → state bucket + DDB lock (one-time)
  modules/web-stack/ → reusable per-env: S3 + CloudFront + Lambda + KMS
  dns/               → Route 53 hosted zone + ACM cert
  github-oidc/       → OIDC provider + per-env deploy roles
  envs/{prod,preview}/ → root modules for each environment
scripts/
  gen_dart_models.dart  → Dart row-class generator
.github/workflows/
  ci.yml             → PR: test-packages, build-web, parity-types
                       Push to main: + build-ios, build-android, build-watch-swift
                       Release: deploy-functions
```

## If something in this file is wrong

Edit it. This file is committed — an out-of-date orientation is worse than none.
