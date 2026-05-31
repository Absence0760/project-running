# .claude/ — Claude Code tooling

Project-specific agents and slash commands wired into Claude Code sessions for this monorepo (Flutter mobile + native watch + SvelteKit web + Supabase + Go worker). Each agent and command targets concrete files, conventions, and invariants of *this* codebase — `apps/mobile_{android,ios}/`'s byte-identical twin, `runs.metadata` jsonb registry, the L0–L4 layered-resilience contract, the CHECK ↔ TS-union pairs, etc.

Browse [`agents/`](agents/) and [`commands/`](commands/) for the full list; the index below is a quick map.

## Agents (`agents/`)

Multi-step, read-only or edit-capable specialists. Most are invoked by a slash command in `commands/`, but a few are used directly (e.g. `mobile-twin-mirror`, `shared-library-syncer`).

Agents are grouped into subfolders by role (Claude Code discovers them recursively and keys them by `name:`, so the folder is purely organizational): dev-workflow utilities sit flat in `agents/`, the GDPR/security/privacy/legal/i18n audit agents in [`agents/auditors/`](agents/auditors/), and the 19 `runner-*` persona bug-hunters (each exercises the app from one runner archetype) in [`agents/personas/`](agents/personas/). The table below lists the flat + auditor agents; browse `agents/personas/` for the persona roster.

| Agent | What it does |
|---|---|
| [`code-reviewer`](agents/code-reviewer.md) | Reviews the working diff against `decisions.md` ADRs, the layering contract, twin invariant, paywall gates, fail-closed defaults, comment/abstraction discipline. Invoked by `/safe-edit` and `/check`. |
| [`doc-hygiene-checker`](agents/doc-hygiene-checker.md) | Surveys the doc set listed in `CLAUDE.md § Docs hygiene` against the diff and reports which need updating. |
| [`test-gap-checker`](agents/test-gap-checker.md) | Reads the working diff and reports missing unit / e2e coverage per `docs/architecture/conventions.md § Test hygiene`. |
| [`migration-coordinator`](agents/migration-coordinator.md) | Applies a new Supabase migration locally, runs both type generators, runs the CHECK ↔ TS-union guard. Invoked by `/safe-migration`. |
| [`mobile-twin-mirror`](agents/mobile-twin-mirror.md) | Mirrors `apps/mobile_android/lib/`+`test/` edits into `apps/mobile_ios/` and verifies the byte-identical invariant (decisions §39). Run after every Dart edit. |
| [`shared-library-syncer`](agents/shared-library-syncer.md) | Detects divergence on the documented TS↔Dart parity pairs (training, segments, privacy, recurrence, pace_segments, training_load, fitness, track_projection). |
| [`metadata-key-keeper`](agents/metadata-key-keeper.md) | Verifies every `runs.metadata.<key>` access in a diff is documented in `docs/backend/metadata.md`. |
| [`repo-security-auditor`](agents/auditors/repo-security-auditor.md) | Read-only security sweep. Knows the project's RLS / SECURITY DEFINER / Edge Function / Storage / XSS / paywall conventions. Backend for most `/audit/*` security commands. |
| [`compliance-auditor`](agents/auditors/compliance-auditor.md) | Read-only auditor for GDPR / CCPA / DSAR / cookie-consent / regional-availability / accessibility posture. Backend for the compliance `/audit/*` commands. |
| [`i18n-readiness-auditor`](agents/auditors/i18n-readiness-auditor.md) | Finds hard-coded English strings, en-US formatting, missing RTL, missing Accept-Language across web + mobile + watch. |
| [`app-store-privacy-auditor`](agents/auditors/app-store-privacy-auditor.md) | Verifies iOS Privacy Nutrition Labels + Play Data Safety + Wear OS + watchOS privacy disclosures match what the binaries actually do. |
| [`intl-legal-doc-reviewer`](agents/auditors/intl-legal-doc-reviewer.md) | Pre-counsel pass on legal pages (ToS, Privacy, Cookie Notice, Refund) against GDPR / UK GDPR / LGPD / PIPEDA / Quebec Law 25 / Australian Privacy Act / PIPA / DPDPA + EU/UK/AU consumer law. **Not a substitute for a licensed attorney.** |
| [`ui-polisher`](agents/ui-polisher.md) | Redesigns a page / screen / component across web (SvelteKit), mobile (Flutter twin), Wear OS, watchOS. Invoked by `/polish-ui`. |

## Commands (`commands/`)

User-invocable slash commands. Most chain one or more agents.

| Command | What it does |
|---|---|
| [`/check`](commands/check.md) | Pre-commit gate: runs `code-reviewer` + `test-gap-checker` + `doc-hygiene-checker` in parallel against the working diff. Advisory output. |
| [`/safe-edit`](commands/safe-edit.md) | Coder ↔ reviewer loop for non-trivial changes: implement → review → fix → review → ready-to-commit. Hard cap of two review cycles. |
| [`/safe-migration`](commands/safe-migration.md) | Schema work with `migration-coordinator` in the loop — apply locally, regen both type files, run the CHECK ↔ TS-union guard, propose doc updates. |
| [`/polish-ui`](commands/polish-ui.md) | Polish a page / screen / component to the running app's quality bar via the `ui-polisher` agent. |
| [`/release-readiness`](commands/release-readiness.md) | Pre-tag gate for the chosen app (web / android / ios / watch / worker). Checks CI green on main, twin parity, schema drift, untracked files, last-tag delta. Read-only. |
| [`/dep-bump-twin`](commands/dep-bump-twin.md) | Mirrors a Dependabot mobile-deps PR's pubspec changes from `apps/mobile_android` to `apps/mobile_ios` so the byte-identical twin survives the merge. |
| [`/audit/*`](commands/audit/README.md) | Focused security / privacy / invariant / compliance audits. `/audit/all` runs the full sweep in parallel. See [`commands/audit/README.md`](commands/audit/README.md) for the full index. |

## Modifying these

When you add a new convention, ADR, or invariant, look here too — most agents read a specific section of `CLAUDE.md`, `docs/architecture/decisions.md`, or `docs/architecture/conventions.md`. If you add a new rule there, the relevant agent's prompt usually needs a corresponding update. Same goes for the agent list in the project's root `CLAUDE.md` and the agent description shown to the user.
