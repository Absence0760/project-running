# Audit commands

Project-curated slash commands for running security, privacy, and invariant audits across the monorepo. Each is read-only by default — they report findings, they don't apply fixes without explicit confirmation.

Invoke from a Claude Code session as `/audit/<name>`.

## Index

### Security

| Command | What it checks |
|---|---|
| [/audit/auth](auth.md) | Every server-side trust boundary (SvelteKit `+server` / Edge Functions / Lambda) verifies the caller before doing work on user data |
| [/audit/rls](rls.md) | RLS policies + `SECURITY DEFINER` RPCs across every migration |
| [/audit/storage](storage.md) | Storage bucket policies + path guessability + signed-URL TTL |
| [/audit/edge-functions](edge-functions.md) | Every Edge Function for JWT verification, input validation, HMAC |
| [/audit/xss](xss.md) | User-content rendering paths — `{@html}`, `flutter_markdown`, sanitization |
| [/audit/secrets](secrets.md) | Server-only secrets that may have leaked into client bundles or git |
| [/audit/public-rows](public-rows.md) | Column-level overshare on `is_public = true` rows |
| [/audit/paywall](paywall.md) | Pro-tier features actually gate at the API boundary, not just the UI |

### Privacy

| Command | What it checks |
|---|---|
| [/audit/privacy-zones](privacy-zones.md) | Every non-owner surface routes through `fetchClippedTrackForRun` / `clipRouteForViewer` (decisions §33) |
| [/audit/pii-in-logs](pii-in-logs.md) | PII / location / health / secrets leaking into server logs, error bodies, or an external sink (SOC 2 / GovRAMP) |

### Invariants

| Command | What it checks |
|---|---|
| [/audit/twin-parity](twin-parity.md) | `apps/mobile_android` and `apps/mobile_ios` `lib/`+`test/` are byte-identical |
| [/audit/schema-drift](schema-drift.md) | Generated TS/Dart row types match migrations + CHECK ↔ TS unions in lockstep |
| [/audit/metadata-keys](metadata-keys.md) | Every `runs.metadata.<key>` access matches `docs/backend/metadata.md` registry |
| [/audit/architecture-guards](architecture-guards.md) | Run every architecture-guard test suite + summarize failures |
| [/audit/layered-resilience](layered-resilience.md) | L0–L4 try/catch contract on the run-recording stack |
| [/audit/db-design](db-design.md) | Professional data-architecture standards across **all three persistence layers** — Postgres relational design + mobile JSON file-stores + watch local storage. Scope arg: `backend` / `mobile` / `watch` / `all` |
| [/audit/db-performance](db-performance.md) | Postgres indexing + query shapes — missing / redundant / unused indexes, composite ordering, N+1, seq-scan-at-scale (query-perf lens, complements db-design) |
| [/audit/migration-locks](migration-locks.md) | Online-DDL safety — which migrations take a blocking lock / rewrite a table and would cause downtime on `supabase db push` to populated prod |

### Health

| Command | What it checks |
|---|---|
| [/audit/deps](deps.md) | Cross-toolchain dependency CVEs (npm, flutter pub, Deno, Actions) |
| [/audit/licenses](licenses.md) | Dependency-license inventory across every toolchain — copyleft / unknown / attribution-missing legal risk for a shipped proprietary app (SOC 2 / GovRAMP) |
| [/audit/infra](infra.md) | AWS Terraform stacks under `infra/` — IAM least-privilege, encryption, drift hygiene, cost + DR guardrails |
| [/audit/cost-controls](cost-controls.md) | Per-user + global spend ceilings across coach, AWS, Supabase, Anthropic; no single failure can produce a runaway bill |

### Compliance (international launch)

| Command | What it checks |
|---|---|
| [/audit/gdpr](gdpr.md) | Lawful basis, consent banner gap, DSAR coverage, retention, cross-border transfers, EU rep, age gate, breach plan |
| [/audit/data-export-completeness](data-export-completeness.md) | Every personal-data column + Storage object reaches the export (GDPR Art 20 + CCPA right-to-know) |
| [/audit/account-deletion-completeness](account-deletion-completeness.md) | Every personal-data table + Storage prefix + third-party link cleared by `delete-account` (GDPR Art 17 + Apple/Play mandate) |
| [/audit/third-party-data-flows](third-party-data-flows.md) | Outputs a sub-processor table for the Privacy Policy + GDPR Art 30 RoPA |
| [/audit/cookie-consent](cookie-consent.md) | Every third-party SDK / fetch gated on consent for EU users (ePrivacy Art 5(3)) |
| [/audit/regional-availability](regional-availability.md) | Signup + Pro + AI coach reachable per country; locale + currency defaults |
| [/audit/accessibility](accessibility.md) | WCAG 2.2 AA across web + mobile + watch; EAA in force from 2025-06-28 |
| [/audit/app-store-privacy](app-store-privacy.md) | iOS Privacy Nutrition Labels + Play Data Safety + manifest disclosures match binary behaviour |
| [/audit/i18n-readiness](i18n-readiness.md) | Hard-coded English strings, en-US formatting, missing RTL across all platforms |

### Dispatcher

| Command | What it does |
|---|---|
| [/audit/all](all.md) | Spawns the full sweep in parallel + consolidated report. Optional arg: `security` / `invariants` / `deps` / `compliance`. |

## Conventions

- Every audit is **read-only by default**. The deliverable is a findings report, not a diff.
- Findings are grouped by severity: **Critical / High / Medium / Low**.
- Each command is a **self-contained prompt** — runnable from a fresh session with no prior context.
- Cross-references decisions: paths follow `docs/architecture/decisions.md §<n>` so a finding can be traced to the rule it violates.

## Agent delegation

| Audit area | Agent it delegates to |
|---|---|
| Security + Privacy (rls, storage, edge-functions, xss, secrets, public-rows, paywall, privacy-zones) | `repo-security-auditor` |
| Compliance (gdpr, data-export-completeness, account-deletion-completeness, third-party-data-flows, cookie-consent, regional-availability, accessibility, pii-in-logs, licenses) | `compliance-auditor` |
| App-store disclosure (app-store-privacy) | `app-store-privacy-auditor` |
| i18n (i18n-readiness) | `i18n-readiness-auditor` |
| Data-architecture design + query perf + migration locks (db-design, db-performance, migration-locks) | `data-architecture-auditor` |
| Legal-doc review (when drafting `/privacy`, `/terms`, etc.) | `intl-legal-doc-reviewer` (non-US), `us-legal-doc-reviewer` (US — global agent) |

Each auditor has the relevant trust boundaries + project conventions baked in so a `/audit/<name>` invocation runs without re-reading them. `/audit/all` spawns one auditor instance per area in parallel.

Diff-time enforcement is handled by complementary agents:
- `mobile-twin-mirror` — mirrors mobile_android → mobile_ios after Dart edits
- `shared-library-syncer` — proactive on edits to TS↔Dart parity helpers (`training`, `segments`, `privacy`, `recurrence`, `pace_segments`, `training_load`, `fitness`, `track_projection`)
- `metadata-key-keeper` — diff-time sweep of `runs.metadata.<key>` writes vs the registry
- `migration-coordinator` — applies a migration + regen + check + doc updates
- `doc-hygiene-checker` — surveys docs after a change for stale references

These audit commands are for periodic broad sweeps and pre-deploy checks; the diff-time agents handle per-PR enforcement.

## Where findings go

Write findings to `reviews/` (gitignored working notes), one file per audit
area — not to chat-only output and not to `docs/`. When you start fixing a
finding, mark it `[x]` in its `reviews/` file in the same commit as the fix,
and keep deferred items as `[~]` with a reason. Delete a `reviews/` file once
it's spent or stale. Full lifecycle in [`reviews/README.md`](../../../reviews/README.md).

## When to run

- **Before a release** — `/audit/all` once, fix Critical/High before tagging.
- **Before opening signup to a new country / region** — `/audit/all compliance` once; fix every Critical / High before publishing the country expansion.
- **After a sweeping refactor** — at minimum `/audit/architecture-guards` + `/audit/twin-parity` + `/audit/schema-drift`.
- **After adding a new Edge Function or SvelteKit server route** — `/audit/auth` + `/audit/edge-functions`.
- **After a new migration** — `/audit/rls` + `/audit/schema-drift` + `/audit/public-rows` + `/audit/migration-locks` (before `supabase db push` to prod).
  - Plus `/audit/data-export-completeness` + `/audit/account-deletion-completeness` if the migration touches personal data.
  - Plus `/audit/db-performance` if it adds an index or a hot query path.
- **After adding a new third-party SDK / API call** — `/audit/third-party-data-flows` + `/audit/cookie-consent` + `/audit/secrets`.
- **After adding a new Edge Function / server route / job handler, or new logging** — `/audit/pii-in-logs` (no PII / token / coordinate in logs or the Sentry sink).
- **After bumping a dependency major or adding a new dependency** — `/audit/deps` + `/audit/secrets` + `/audit/licenses`.
- **After editing anything under `infra/`** — `/audit/infra` before `terraform apply`.
- **Before submitting a binary to App Store / Play** — `/audit/app-store-privacy`.
- **When drafting or revising legal pages** — `intl-legal-doc-reviewer` (non-US) and / or the global `us-legal-doc-reviewer` (US).
- **Periodically (monthly)** — `/audit/all` to catch slow-moving drift.
