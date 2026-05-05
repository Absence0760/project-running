# Audit commands

Project-curated slash commands for running security, privacy, and invariant audits across the monorepo. Each is read-only by default — they report findings, they don't apply fixes without explicit confirmation.

Invoke from a Claude Code session as `/audit/<name>`.

## Index

### Security

| Command | What it checks |
|---|---|
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
| [/audit/privacy-zones](privacy-zones.md) | Every non-owner surface routes through `clipTrackForUser` (decisions §33) |

### Invariants

| Command | What it checks |
|---|---|
| [/audit/twin-parity](twin-parity.md) | `apps/mobile_android` and `apps/mobile_ios` `lib/`+`test/` are byte-identical |
| [/audit/schema-drift](schema-drift.md) | Generated TS/Dart row types match migrations + CHECK ↔ TS unions in lockstep |
| [/audit/metadata-keys](metadata-keys.md) | Every `runs.metadata.<key>` access matches `docs/metadata.md` registry |
| [/audit/architecture-guards](architecture-guards.md) | Run every architecture-guard test suite + summarize failures |
| [/audit/layered-resilience](layered-resilience.md) | L0–L4 try/catch contract on the run-recording stack |

### Health

| Command | What it checks |
|---|---|
| [/audit/deps](deps.md) | Cross-toolchain dependency CVEs (npm, flutter pub, Deno, Actions) |
| [/audit/infra](infra.md) | AWS Terraform stacks under `infra/` — IAM least-privilege, encryption, drift hygiene, cost + DR guardrails |
| [/audit/cost-controls](cost-controls.md) | Per-user + global spend ceilings across coach, AWS, Supabase, Anthropic; no single failure can produce a runaway bill |

### Dispatcher

| Command | What it does |
|---|---|
| [/audit/all](all.md) | Spawns the full sweep in parallel + consolidated report. Optional arg: `security` / `invariants` / `deps`. |

## Conventions

- Every audit is **read-only by default**. The deliverable is a findings report, not a diff.
- Findings are grouped by severity: **Critical / High / Medium / Low**.
- Each command is a **self-contained prompt** — runnable from a fresh session with no prior context.
- Cross-references decisions: paths follow `docs/decisions.md §<n>` so a finding can be traced to the rule it violates.

## Agent delegation

Every command in **Security** and **Privacy** delegates to the `repo-security-auditor` agent (under `.claude/agents/`). That agent has the four trust boundaries baked in (DB↔client, Edge Function↔caller, Storage↔URL, client-bundle↔runtime) plus the audit-area routing table — it picks up the project's conventions without re-reading them every run. `/audit/all` spawns one auditor instance per area in parallel.

Diff-time enforcement is handled by complementary agents:
- `mobile-twin-mirror` — mirrors mobile_android → mobile_ios after Dart edits
- `shared-library-syncer` — proactive on edits to TS↔Dart parity helpers (`training`, `segments`, `privacy`, `recurrence`, `pace_segments`, `training_load`, `fitness`, `track_projection`)
- `metadata-key-keeper` — diff-time sweep of `runs.metadata.<key>` writes vs the registry
- `schema-change-coordinator` — applies a migration + regen + check + doc updates
- `doc-hygiene-checker` — surveys docs after a change for stale references

These audit commands are for periodic broad sweeps and pre-deploy checks; the diff-time agents handle per-PR enforcement.

## When to run

- **Before a release** — `/audit/all` once, fix Critical/High before tagging.
- **After a sweeping refactor** — at minimum `/audit/architecture-guards` + `/audit/twin-parity` + `/audit/schema-drift`.
- **After adding a new Edge Function** — `/audit/edge-functions`.
- **After a new migration** — `/audit/rls` + `/audit/schema-drift` + `/audit/public-rows`.
- **After bumping a dependency major** — `/audit/deps` + `/audit/secrets`.
- **After editing anything under `infra/`** — `/audit/infra` before `terraform apply`.
- **Periodically (monthly)** — `/audit/all` to catch slow-moving drift.
