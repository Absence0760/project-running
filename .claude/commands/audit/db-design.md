---
description: Audit every persistence layer against professional data-architecture standards — Postgres backend (relational design) + mobile file-stores + watch local storage
argument-hint: [backend|mobile|watch|all] (optional scope, default all)
---

Audit whether the project's data is **professionally designed and follows
industry standards** — across all three places it's persisted, not just the
backend.

## The three layers this covers

The product stores data in three structurally different places, and "is this
well-designed?" is judged by a different rubric in each. **Yes — this audit
runs against the mobile and watch local storage too**, not only Postgres; they
just aren't relational databases, so they're held to offline-first /
constrained-device standards instead of normalization + foreign keys.

| Scope arg | Layer | Storage tech | Judged against |
|---|---|---|---|
| `backend` | Postgres | relational DB | normalization, FK integrity, indexing, constraints, enum modelling, naming, retention, migration hygiene |
| `mobile` | Flutter local stores | flat JSON files (`apps/mobile_android/lib/local_*_store.dart`, byte-identical iOS twin) | on-disk schema versioning, atomic/crash-safe writes, corruption tolerance, convergent sync, server-schema parity, at-rest encryption |
| `watch` | Wear OS + watchOS | Jetpack DataStore (`apps/watch_wear/.../SessionStore.kt`, `recording/CheckpointStore.kt`); UserDefaults + FileManager (`apps/watch_ios/WatchApp/CheckpointStore.swift`) | write-amplification budget, checkpoint durability across crash/battery-death, storage ceiling, bridge-payload parity, sensitive-data-at-rest |
| `all` (default) | all three | — | each layer against its own rubric, one consolidated report |

## Goal

This is a **design-quality** audit, distinct from the security/invariant
sweeps:
- Not "is there an auth hole" — that's `/audit/rls` + `/audit/auth`.
- Not "do the generated types match the migrations" — that's `/audit/schema-drift`.
- Not "is `runs.metadata` documented" — that's `/audit/metadata-keys`.

It asks: would a professional data architect sign off on this schema and these
stores? Normalization, referential integrity, indexing, constraint coverage,
enum modelling, naming consistency, retention for high-write tables, jsonb
discipline (backend); crash-atomic writes, on-disk schema migration, sync
convergence, server-schema parity, encryption-at-rest (mobile + watch).

## What to check

Run the lens(es) the scope arg selects. The full per-lens checklist lives in
the agent (`data-architecture-auditor`); the headline checks:

- **backend (L-REL):** tables below 3NF without a documented reason; queried/
  constrained keys trapped in `runs.metadata` jsonb; inconsistent `ON DELETE`;
  missing CHECK/UNIQUE (`integrations.provider` has none); enum-as-text-CHECK
  vs real-enum inconsistency; missing indexes on hot FKs; timestamp/owner/
  boolean naming drift; high-write tables (`live_run_pings`, `race_pings`,
  `rate_limits`, `webhook_events`, `notifications`) without a retention plan;
  duplicate tables (`race_pings` vs `live_run_pings`); trigger-cache contracts.
- **mobile (L-FILE):** no version stamp / forward-migration in the persisted
  JSON; non-atomic `writeAsString` (crash loses the file — `in_progress.json`
  is highest-stakes); a directory walk that `jsonDecode`s with no per-file
  corruption isolation; newer-wins applied inconsistently or with an ambiguous
  clock source; fields dropped on deserialize (no server-schema parity);
  unbounded `synced_ids.json` / `pending_remote_deletes.json`; plaintext GPS/HR
  at rest; durability divergence across the five `Local*Store`s.
- **watch (L-DEV):** hot-path writes to a growing DataStore value (full-file
  rewrite amplification); checkpoint cadence vs data-loss window on a 10-hour
  run; unbounded on-watch accumulation (track points, tile cache); watch↔phone
  bridge-payload shape disagreement; sensitive data outgrowing the
  "DataStore sandbox is fine for Phase 1" assumption.

## Report

Group by lens, then by severity (**Critical / High / Medium / Low** — the
data-architecture rubric in the agent, where Critical = guaranteed data loss/
corruption under a normal event). Each finding: `[Lens] file:line`, the
industry standard violated, the concrete failure mode, and the fix scope (note
twin-doubling for mobile). Cross-reference `decisions.md §<n>` and the existing
`reviews/audit-db-optimization.md` (corroborate overlaps, don't duplicate).
Read-only — report only, don't fix without explicit confirmation.

## Useful starting points

- `apps/backend/supabase/migrations/` + `seed.sql` — the relational schema
- `reviews/audit-db-optimization.md` — the prior data-model audit (F1–F20); many backend findings will corroborate it
- `apps/mobile_android/lib/local_run_store.dart` (+ `local_gym_store` / `local_food_store` / `local_gear_store` / `local_route_store`) — the file-store reference
- `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/{SessionStore,recording/CheckpointStore}.kt`
- `apps/watch_ios/WatchApp/{CheckpointStore,RunFormat}.swift`
- `docs/architecture/decisions.md` §39 (twin), §63 (multi-modal), §73/§122 (local stores); `apps/backend/CLAUDE.md` (migration hygiene)

## Delegate to

Use the `data-architecture-auditor` agent. Pass the scope as the prompt's first
sentence:
- `all` → `"Audit all three persistence layers against professional data-architecture standards."`
- `backend` → `"Audit the backend relational schema."`
- `mobile` → `"Audit the mobile Flutter local file-stores."`
- `watch` → `"Audit the Wear OS + watchOS local storage."`

That agent carries the three lenses and the per-layer industry-standard
checklists baked in, so it won't re-derive them. For `all`, you may spawn one
agent per lens in parallel and consolidate.

## Output → `reviews/`

Persist findings to `reviews/audit-db-design.md` (gitignored working notes —
see [`reviews/README.md`](../../../reviews/README.md)), one finding per entry
with a `[ ]` status box, grouped by lens then severity. Per-lens runs may use
`reviews/audit-db-design-{mobile,watch}.md`. If the file exists from a prior
run, update it in place (`[x]` resolved with fix commit, `[~]` deferred) rather
than overwriting. The audit is otherwise read-only; writing this one findings
file is the allowed exception.
