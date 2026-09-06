# backend — AI session notes

Supabase project for the Run app. Postgres schema, Row-Level Security, Storage buckets, Edge Functions (Deno), and the TypeScript / Dart row-type generators all anchor here. **If you're about to run any `supabase` CLI command, your working directory must be this folder** — the CLI resolves migrations, functions, and config relative to `supabase/config.toml`, which only lives here. The top-level `supabase/` directory at the repo root is the CLI's local state (`.branches`, `.temp`); never write migrations there.

## Layout

```
apps/backend/
├── package.json              # scripts: gen:types, gen:types:check
├── .env.example              # placeholder template (committed)
├── .env.development          # ready-to-run local defaults (committed, non-secret)
├── .env.local                # your real secrets / overrides (gitignored, wins)
└── supabase/
    ├── config.toml           # local-stack config — ports, auth, email
    ├── seed.sql              # test user + 12 runs + 5 routes + integrations + gym/nutrition
    ├── migrations/                # full list at `ls supabase/migrations/`.
    │   │                          # Apr 2026 batch laid the schema foundation
    │   │                          # (initial_schema → funding); May 2026 added the
    │   │                          # social layer (notifications, kudos/comments,
    │   │                          # photos, segments, follows, privacy zones, plan
    │   │                          # templates) plus subscription paywall + coach
    │   │                          # messages; June 2026 brought the route + run-
    │   │                          # match pipeline (geom LineString, is_starred,
    │   │                          # routes_within_box, run_match_pipeline,
    │   │                          # routes_intersecting_track, source_track_url
    │   │                          # CAS) and the pg_cron + rate-limit + Vault
    │   │                          # tooling.
    │   └── 20260611_001_run_matched_tracks_cas.sql  # latest at time of writing
    └── functions/
        ├── .env                  # committed local-dev env the CLI auto-loads into
        │                         # the edge runtime on `supabase start` (auth-email
        │                         # hook secret + Mailpit SMTP; non-secret values only)
        ├── _shared/database.ts     # the tree's ONLY reach into apps/web: re-exports the
        │                           # generated `Database` type + the `DbClient` alias
        ├── _shared/{rate_limit,sentry,strava,body_limit,redirect_allowlist}.ts
        ├── auth-email/{index,handler,lib,smtp}.ts   # GoTrue send-email hook → localized auth mail
        ├── clip-public-track/index.ts
        ├── delete-account/index.ts
        ├── export-data/index.ts
        ├── parkrun-import/index.ts
        ├── refresh-tokens/index.ts
        ├── revenuecat-webhook/index.ts
        ├── strava-import/index.ts + backfill.ts
        ├── strava-webhook/index.ts
        ├── events-connect-onboard/{index,lib}.ts   # Stripe Connect host onboarding
        ├── events-checkout/{index,lib}.ts           # destination-charge Checkout
        └── stripe-events-webhook/{index,lib}.ts     # the one idempotent order webhook
```

## Local stack

Start every session with `supabase start` in this directory. Ports are fixed via `config.toml`:

| Service | URL |
|---|---|
| REST API | `http://127.0.0.1:54321/rest/v1` |
| Edge Functions | `http://127.0.0.1:54321/functions/v1/{name}` |
| Database | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Studio | `http://127.0.0.1:54323` |
| Mailpit (sent-email inspector) | `http://127.0.0.1:54324` |

Confirm it's running with `supabase status`. The gotcha I keep hitting: `supabase status` returns an error if you run it from the repo root (it looks for `config.toml` in the cwd). `cd` here first.

**Reset the database** with `supabase db reset`. This drops and recreates the local DB, replays every migration in `supabase/migrations/`, runs `seed.sql`, and leaves you at a known-good state. Use this between destructive experiments.

## The test users

`seed.sql` provisions three users. `runner@test.com` is the one to sign in as;
`alex@test.com` and `morgan@test.com` exist so the social surfaces (feed, follows,
kudos, blocks, club membership) have a second and third party to act as.

- Email: `runner@test.com`
- Password: `testtest`
- Runs and routes across five `source` values (`app`, `strava`, `parkrun`, `healthkit`, `race`).
  **No count is stated here on purpose.** `seed.sql` carries a dozen-plus separate
  `insert into runs` statements — several `insert … select` that fan out a range —
  each staged for one e2e scenario, so any figure a reader could carry away would be
  stale by the next spec that needs a row. Re-derive against a reset stack:
  `psql "$DB_URL" -c "select source, count(*) from runs r join auth.users u on u.id = r.user_id where u.email = 'runner@test.com' group by 1"`
  (251 runs / 45 routes in total, 225 / 43 of them this user's, measured 2026-09-05).
- 2 connected integrations, a profile with `preferred_unit = 'km'`
- Phase 4 multi-modal data: 3 gym workouts (23 sets, progressive overload so PR badges fire), 16 food-log entries spanning today + the prior 6 days, a 4-point body-metrics weight series, and `height_cm` / `date_of_birth` / `gender` + `nutrition_activity_level` / `nutrition_goal` prefs so `/nutrition` macro targets compute. These rows are `now()`-relative (unlike the fixed-date runs) so `/gym` + `/nutrition` stay populated on any reset.
- Owns **Richmond Run Club** with one club-owned template of each kind so the club's Templates tab is populated: a training plan (`Beginner 5K — Club Plan`, `is_template` + `club_id`, 2 weeks of workouts), a session plan (`Post-Run Recovery Flow`, blocks + items), and a gym routine (`Club Strength — Lower Body`, exercises + planned sets). Fixed ids → idempotent across resets.
- The active **Richmond Half 2026** training plan (id `a1a1eada-aaaa-…`) is **authored against fixed 2026 seed dates** (start `2026-03-29` .. race `2026-06-20`, 84 days) but a post-insert `DO` block at the end of the plan section **slides the whole window + every `plan_workouts.scheduled_date` forward by a `now()`-relative offset** (today maps to the seeded week-2 Wednesday, day 17 of 83), so the single active plan always covers TODAY with a FUTURE race on every reset — the dashboard plan-hero / `/plans` progressbar / current-week strip stay mid-plan. The shift runs **after** the two `completed_run_id` linkage UPDATEs, so those FKs survive (a pure date shift never touches them). e2e specs that look a row up by its literal seed date (`workout-runner-surfaces`, `workout-edit-intervals`, `calendar`) go through `tests-e2e/fixtures/plan-today.ts` → `seedDateToLive('2026-04-..')` / `liveMonthLabel(...)`, which re-applies the same offset read back off `training_plans.start_date`. If you change the anchor (the `current_date - 17` in seed.sql), nothing else needs editing — the helpers derive the offset live.

Use it for any manual testing that needs authenticated data. The web app auto-fills the email on the login page in dev mode (see `apps/web/src/routes/login/+page.svelte`).

## Schema and row-type codegen

**Every migration in `supabase/migrations/` must be followed by regenerating both client row-type files.** Do it before committing the migration, not as a follow-up:

```bash
# 1. After `supabase db reset` picks up the new migration:
cd apps/backend
npm run gen:types                       # apps/web/src/lib/database.types.ts
# 2. From repo root:
cd ../..
dart run scripts/gen_dart_models.dart   # packages/core_models/lib/src/generated/db_rows.dart
```

CI's `parity-types` job checks `database.types.ts`. The `schema-codegen-drift` job regenerates and diffs both `db_rows.dart` and `DbRows.kt` — all three are gated on PRs to `main`.

Details, troubleshooting, and drift-detection test recipe: [../../docs/architecture/schema_codegen.md](../../docs/architecture/schema_codegen.md).

## Migrations

### Naming convention

`{YYYYMMDD}_{NNN}_{description}.sql` — date, three-digit ordinal within the day, underscore-separated description. Matches the existing files exactly.

**Gotcha with multiple migrations on the same day:** Supabase's CLI parses the migration *version* as the longest numeric prefix before the first underscore — i.e. `YYYYMMDD` only. The `_NNN_` ordinal is purely cosmetic and does **not** disambiguate. Two files with different `NNN` on the same day both register as version `YYYYMMDD` and the second `supabase db reset` fails with `duplicate key value violates unique constraint "schema_migrations_pkey"`. Walk across consecutive dates instead (`20260506_001_*`, `20260507_001_*`, `20260508_001_*`). If you genuinely need same-day disambiguation in one PR, swap to a 14-digit `YYYYMMDDhhmmss_description.sql` scheme — `supabase migration new` emits this by default — and rename **every** sibling on the same date so each parses to a unique numeric version (e.g. `20260528000001_notifications.sql`, `20260528000002_personal_records_widen_brackets.sql`, `20260528000003_runs_external_id_per_user_unique.sql`). Mixing the two schemes on the same date breaks alphabetical sort: `20260528000002` (14-digit) sorts *before* `20260528_001` (8-digit underscore form) because `0` (48) < `_` (95) at position 9, so the rename must be all-or-nothing per date.

This bit again in run 26820381977: `20260601_001_notifications_realtime.sql` (added 2026-06-01) collided with the pre-existing `20260601_001_runs_metadata_activity_type_required.sql` and took down all five stack-starting jobs at the slow `supabase start` step. The fix renamed *only the new* file to `20260601000001_notifications_realtime.sql` — the runs_metadata sibling was left at `20260601` because it had already been applied to prod under that version, and renaming an already-applied migration makes the next `db push` try to re-run it. That forces the one tolerated exception to "all-or-nothing per date": a 14-digit file coexisting with an 8-digit `_001` sibling on the same date. It is safe here only because the two migrations are independent (a `notifications` publication change vs a `runs` CHECK constraint), so the apply-order/version-order mismatch the mixing creates is harmless; the 14-digit version is also deliberately *greater* than `20260601` so it never re-orders relative to that already-applied sibling (it still sorts below the later `20260602…` migrations, but this repo forward-dates routinely, so applying a not-yet-recorded migration that pre-dates the remote's max is the normal deploy path, not a hazard). **A new guard makes this fail in milliseconds instead of at `supabase start`:** `apps/backend/scripts/check_migration_versions.mjs` parses every migration's version key the way the CLI does and fails on any collision; it runs as the "Migration version keys are unique" step ahead of the stack start in the `parity-types` CI job, and `check_migration_versions.test.mjs` pins the parse + detection logic. Run it locally with `node apps/backend/scripts/check_migration_versions.mjs` before pushing a new migration.

One consequence stopped being harmless on CLI v2.95.4: incremental `supabase migration up` (and `--include-all`) now refuses with "Remote migration versions not found in local migrations directory", because the CLI compares the remote history (version-sorted: `20260601` before `20260601000001`) positionally against local files (filename-sorted: `20260601000001_…` before `20260601_001_…`, since `0` < `_`). Fresh applies (`supabase start` / `db reset`) are unaffected. Do NOT "fix" this by renaming the 8-digit file — prod recorded it as `20260601` (see above). To apply new migrations to the local stack, mirror the CLI manually: run the file via psql inside a transaction, then `insert into supabase_migrations.schema_migrations(version, name) values ('<leading digits before first underscore>', '<rest of filename>')` in the same transaction (this is how `20270311`–`20270324` were applied locally, 2026-07-02/03). **Confirmed 2026-07-13:** the first CI backend deploy's `supabase db push` tripped this same check against prod (under CLI 2.84.2 *and* 2.109.1 — it is not a version regression), erroring on `20260601` even though the prod ledger has zero real orphans. `supabase migration repair --status reverted 20260601` is NOT the fix — it would make `db push` try to re-run the already-applied `runs_metadata` migration. Instead, the release workflow no longer uses `db push`: **`scripts/apply-pending-migrations.sh`** is the automated form of the manual workaround above (applies every not-yet-recorded migration in a transaction + records its ledger row, in version order; idempotent). `.github/workflows/release-backend.yml` calls it via the `SUPABASE_DB_URL` secret. So a `backend@*` release now applies migrations without ever hitting the alignment check. The only durable way to make `db push` itself work would be renaming all ~355 8-digit files to 14-digit — disproportionate, and it churns every `YYYYMMDD_NNN` reference across the repo.

### Creating one

```bash
cd apps/backend
supabase migration new add_activity_type_to_runs
# Opens nothing — just creates the empty file. Edit it, then:
supabase db reset    # replays everything from scratch, including the new one
```

### What belongs where

- **Table changes** (`create table`, `alter table ... add/drop column`, constraints, indexes): in a migration. Both row-type generators rely on these files.
- **RLS policies and grants**: in a migration. These are schema-level state.
- **Storage buckets and their RLS**: in a migration, via `insert into storage.buckets` + `create policy on storage.objects`. See `20260410_001_runs_to_storage.sql` for the canonical example.
- **Test data / fixtures**: in `seed.sql`, not a migration. `supabase db reset` runs `seed.sql` after migrations.
- **Functions / views**: in a migration (`create or replace function ...`). See `20260406_001_database_functions.sql` for `weekly_mileage` and `personal_records`.

### Online-safety: NOT VALID on high-volume tables

Migrations run on an empty local/CI DB where every lock is instant, and on the
**populated prod** DB via `db push` where a table-scanning statement is
downtime. A single-step `ADD CONSTRAINT … CHECK/FK` on a big table (`runs`,
`notifications`, …) scans every row under a blocking lock; a `SET NOT NULL`, a
volatile-default `ADD COLUMN`, an `ALTER COLUMN … TYPE`, or an unbatched
whole-table `UPDATE` do the same. The online forms — `ADD … NOT VALID` then a
separate `VALIDATE CONSTRAINT`, per-table FK splits, batched backfills — plus a
lock reference, the #409/#410/#411 worked examples, and a pre-merge checklist
live in **[../../docs/backend/migration_locks.md](../../docs/backend/migration_locks.md)**.
Read it before writing a migration that adds a constraint or touches many rows.
`scripts/check_migration_online_safety.mjs` (in the `parity-types` CI job,
alongside the version-keys guard) fails **two** shapes on a guarded table, and
both are ways of scanning it under a lock that blocks writers: a CHECK/FK added
without `NOT VALID` (`blocking_add`), and a `VALIDATE CONSTRAINT` in the **same
file** as the DDL whose lock is still held (`same_txn_validate`) — because a
migration file is applied inside one transaction, so the `ADD … NOT VALID`'s own
`ACCESS EXCLUSIVE` is still held while the `VALIDATE` scans, and the split buys
nothing until it is a split across FILES ([decisions § 1180](../../docs/architecture/decisions.md)).
Run it locally with `node apps/backend/scripts/check_migration_online_safety.mjs`.
It scans **every** committed migration on every run, and the already-applied
violations are grandfathered by name in `GRANDFATHERED_VIOLATIONS` — a
`{filename, kind, table, constraint}` tuple, with `kind` in the key so an
exemption for a blocking add cannot silently also cover a same-transaction
validate in the same file — so **adding a migration needs no edit to the guard**
([decisions § 775](../../docs/architecture/decisions.md)). That list is for
migrations already applied to prod, which cannot be edited; if the guard fails
on a migration you are still writing, **split it** rather than naming it there.
**`jobs` is in the guarded set** (#394 follow-up): a bare `DROP CONSTRAINT
jobs_kind_chk` + `ADD CONSTRAINT … CHECK (…)` widening now fails CI just like the
`notifications` case, because the Go `job_worker` polls `jobs` continuously and
a blocking validation scan stalls job processing — so a new `kind` allow-list
entry must use `ADD … NOT VALID` in one migration and `VALIDATE CONSTRAINT` in a
**later** one. The read-only `/audit/migration-locks` command classifies the
*existing* migrations by lock impact.

### Widening a `kind` CHECK also needs `NOT VALID` — don't `DROP` + bare `ADD`

The online-safety rule above bites hardest on a pattern that keeps recurring:
widening an enum-style `kind` allowlist by dropping the old CHECK and re-adding
it. `notifications_kind_check` has been rebuilt this way over and over, and
`jobs_kind_chk` on nearly every new job kind — always as `drop constraint …;
alter table … add constraint … check (kind in (…))`, with **no `NOT VALID`**.
The bare `ADD CONSTRAINT … CHECK` re-scans the whole table under a blocking
lock — the exact downtime the two-step avoids — and these are the two worst
tables to do it on: `notifications` is the archetypal high-write, unbounded
table (every kudos / comment / follow / RSVP / achievement inserts a row) and
`jobs` is polled continuously by the Go worker (a stalled `ADD CONSTRAINT`
stalls job draining). Already-applied migrations aren't editable; this is a
forward-guard for the **next** kind addition. Use the two-step:

```sql
-- Migration 1 — <version>_widen_notifications_kind.sql
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (kind in (…)) not valid;                        -- instant, no scan
```

```sql
-- Migration 2 — a SEPARATE FILE, so the scan gets its own transaction with no
-- stronger lock held. In migration 1's file it would scan under the
-- ACCESS EXCLUSIVE that file is still holding, and buy nothing.
alter table notifications validate constraint notifications_kind_check;
```

**Two files, not two statements.** Writing both halves into one migration is a
`same_txn_validate` violation and fails CI — the guard walks each file in order
and reports a VALIDATE that scans while an earlier statement in the same file
still holds a write-blocking lock on that table. The fix when it fires on a
migration you are writing is to move the `VALIDATE` into its own file, not to add
a `GRANDFATHERED_VIOLATIONS` entry ([decisions § 1180](../../docs/architecture/decisions.md)).

Model it on the `20261124_001_content_length_caps.sql` → `20270503_001_free_text_length_caps.sql`
pair, which adds `NOT VALID` in one migration and validates in a later one. Do
**not** model it on `20260621_001_runs_track_url_path_check.sql`: this file used
to cite that as a split, and it is not one — it adds and validates in the same
transaction, and is one of the entries grandfathered as `same_txn_validate`. Re-emit
the **complete** union each time — a CHECK rebuild replaces the whole allowlist,
so the same "bare-body strips prior fixes" trap applies (see below).
`check_migration_online_safety.mjs` catches both halves on both tables —
`notifications` and `jobs` are each in its `GUARDED_TABLES` set, so a missing
`NOT VALID` trips `blocking_add` and a same-file `VALIDATE` trips
`same_txn_validate`.

### Migrations that reference postgis / pg_trgm objects must set search_path themselves

Hosted `supabase db push` sessions do not reliably have `extensions` on the
search_path (fresh projects lack it for direct connections), and the CLI runs
`RESET ALL` before applying **each** file — so neither an `alter role postgres set
search_path …` on the remote nor a set in an earlier migration carries over.
Unqualified references to extension-schema objects (`geography`, `geometry`,
`ST_*`, `gin_trgm_ops`, `similarity`, `<->`) then fail with SQLSTATE 42704
(`type "geography" does not exist`) even though the same file applies cleanly on
the local stack. Any migration using these must start with:

```sql
set search_path = public, extensions;
```

Every existing postgis/pg_trgm migration carries this header (added 2026-07-11
when the first prod `db push` hit the error). Function-level
`set search_path = …` clauses on `security definer` functions are a separate,
runtime concern — they don't satisfy this apply-time requirement.

### The Dart generator's parser is narrow

It understands `create table`, `alter table ... add column`, and `alter table ... drop column`. It ignores everything else (indexes, policies, RPCs, storage, `$$...$$` function bodies). If you use a SQL form the parser doesn't cover — a `create type ... as enum`, an `alter table ... alter column ... type`, a column-renaming `alter table ... rename column` — the generator will silently skip it and your Dart row classes will drift. Two options:

1. Reorganise the migration into a `drop column` + `add column` pair that the generator *can* parse. Works for renames in this pre-launch codebase.
2. Grow `_parseAlterTable` in `scripts/gen_dart_models.dart` to handle the new form. Add a test case if the parser is getting complex.

### Bare-body `create or replace function` strips prior fixes

**Whenever a migration does `create or replace function X`, write the COMPLETE desired body — do NOT write from scratch as if `X` had just been created.** PostgreSQL replaces the entire function definition every time, so any guard / clause / rate-limit call added by an earlier migration gets silently dropped when a later migration bare-bodies the function with a partial rewrite.

How this bites: `20260904_001_pr_refresh_restore_auth_guard` restored a JWT-role guard on `refresh_personal_records_for_user` by writing a fresh body — and unwittingly dropped the widened brackets (`20260528000002`), embedded-best efforts (`20260529000002`), and DNF exclusion (`20260530000001`) that earlier persona-fix migrations had added. Same cascade hit `clone_plan_template`: `20260721_001` legitimately stripped publisher fitness data from the clone, but in doing so dropped the auto-complete-active-plan UPDATE (`20260529000004`). The Round 3 cleanup commit `f134c807` added two consolidation migrations (`20261009_001` + `20261010_001`) to roll everything together — that's the pattern to follow. Same trap, again: `20261107_001` hardened `lock_subscription_columns` (session_user bypass) by re-emitting the body and dropped the `billing_issue_at` write-lock that `20260729_001` had added — letting a user clear their own renewal-failure banner. Repaired by the forward migration `20261112_001` (full body restored) and pinned at the pgtap layer in `rls_paywall_test.sql` so the cheap backend job catches the next drop, not just the web e2e.

**Before writing `create or replace function X`:**

1. `grep -ln "function X" apps/backend/supabase/migrations/*.sql` to find every prior touch.
2. Read the LATEST one — that's the live body in the DB.
3. Patch what you need on top of that body; don't go back to the original.
4. If the function is well-trodden (PR refresher, kudos / comments policies, `is_run_visible_to`, etc.), strongly consider whether your fix should be a brand-new sibling migration at the end of the chain rather than threading through the existing rewrites.

This same trap applies to bare-body `drop policy + create policy` replacements where a sibling migration's policy gets lost — see the RLS gotcha below.

### Every `create view` must end with `revoke all` + `grant select`

Supabase's default privileges hand `anon`/`authenticated` FULL table privileges (insert/update/delete/…) on every object created in the `public` schema. For a VIEW that is an RLS bypass: a simple single-table view is auto-updatable, and writes through it are authorised as the view owner (`postgres`), skipping the base table's RLS entirely — an anon `POST /rest/v1/public_race_listings` really did insert a `race_listings` row (2026-07-03, fixed in `20270324_001` + ADR §201). A bare `grant select on <view> to anon, authenticated;` does NOT remove the default write grants. The pattern for every new view:

```sql
revoke all on public.<view> from public, anon, authenticated;
grant select on public.<view> to <intended audience>;
```

`view_write_privileges_test.sql` pins this with an information_schema catch-all, so a view created without the reset fails the pgtap job.

### Every new TABLE must grant its own client surface

The mirror-image trap of the view rule above, and the one that actually bit. The `postgres`-owned default ACL for tables in `public` is `anon=Dxtm / authenticated=Dxtm / service_role=Dxtm` — TRUNCATE, REFERENCES, TRIGGER, MAINTAIN, and **none** of SELECT/INSERT/UPDATE/DELETE. So a `create table` in a migration produces a table no app role can read or write; RLS never even gets consulted, PostgREST just returns `42501 permission denied for table …`. This is the same class as the 2026-07-13 prod onboarding incident that produced `20270408_001_restore_role_grant_matrix.sql`, which made the whole matrix explicit — from that migration on, **the grant is the migration's job**. `20270411_001` created `global_segments` + `global_segment_efforts` three days later, granted EXECUTE on its two RPCs, and never granted the tables: the entire catalogue feature 42501'd from every client (only the SECURITY DEFINER leaderboard RPC worked, because it runs as the owner), and it broke two pgtap suites at fixture setup. Fixed forward in `20270512_001`. End every new table with the surface its policies were written against:

```sql
grant select on public.<table> to anon;                              -- if publicly readable
grant select, insert, update, delete on public.<table> to authenticated;  -- only the verbs a policy covers
grant select, insert, update, delete on public.<table> to service_role;   -- always the full set
```

Two catch-alls fail the pgtap job when this is skipped: `role_grant_matrix_test.sql` on the read side (every public base table must be readable by `authenticated`, table- or column-level) and `global_segment_grants_test.sql` on the write side (every public base table must carry full `service_role` DML — the check a zero-grant table trips).

### A column-level `revoke` is a no-op under a table-level grant

The mirror-image of the rule above, and the one that ships looking correct.
Postgres resolves a privilege from the BROADEST grant, so
`revoke select (secret) on t from authenticated` while `authenticated` still
holds `select` on the whole table reports `REVOKE`, writes no column ACL, and
leaves `has_column_privilege` true. `20260707_001` documents the trap in its
own header; `20261229_001` and `20270213_001` shipped it anyway, and on
`instructor_payout_accounts` — whose own-row SELECT policy is permissive — the
host could read their raw Stripe Connect account id for the life of the table
(repaired by `20270621_001`, decisions § 781). Always the two-step:

```sql
revoke select on public.<table> from anon, authenticated;
grant select (col, col, ...) on public.<table> to anon, authenticated;
```

Two things enforce it. `apps/backend/scripts/check_migration_column_revoke_noop.mjs`
(in the `parity-types` CI job, beside the version-key and online-safety guards)
replays the migration set and fails on a column revoke whose role still holds
the table-level privilege at the end — it carries no allowlist, because a
repair is a later migration rather than a bookkeeping edit here. And
`column_grant_lockdown_registry_test.sql` pins the resulting STATE: every
withheld column of a column-locked table must be registered with the reason it
is withheld, so a column added after a lockdown (deny-by-default, since a
re-grant is cumulative) or a table-wide `grant select` landing on a locked
table both fail the pgtap job.

### A lockdown that withholds `authenticated` must reach the `server_only` fixture

`revoke execute ... from public, anon` is the house form (above). When a routine
should reach no client role at all — the cron and job-queue family, the privacy
oracles, the derived-cache refreshers, the secret deleters — `authenticated`
goes on the revoke list too, and the pgtap suite's claim about that lives in the
`server_only` fixture at the top of
`apps/backend/supabase/tests/anon_execute_contract_test.sql`. Assertions (5) and
(6) there are exactly as complete as that list: a routine it omits is a routine
nothing asserts anything about.

**It is derived now, so you do not edit it by hand — you run the guard and paste
what it asks for.** `apps/backend/scripts/check_server_only_registry.mjs`
replays every migration and fails the PR when a routine some migration revokes
from `authenticated` is missing from the fixture, when a row names a routine no
migration revokes, or when `keeps_service_role` disagrees with the grant the
migrations state. It was hand-kept until `20270710` and had drifted to 26 rows
against a family of 42, two of the missing sixteen sitting in the cron family
the fixture is the positive control for (decisions § 1233).

The derivation reads the migration TEXT and the pgtap assertions read the
CATALOGUE, deliberately: a fixture derived from `pg_proc.proacl` would make (5)
assert that routines without the privilege do not have the privilege.
`keeps_service_role` comes from the replay for the same reason — on the CI image
every fresh routine arrives with a `service_role` entry by name, so a `true`
read off the catalogue there would say nothing.

What the guard cannot demand is a revoke no migration wrote. That half is
assertions (7) and (8) in the same file: every `public` routine `cron.job`
schedules must be withheld from both client roles, with the population read off
the schedule rather than off any list, so a new cron routine whose migration
forgets `authenticated` fails even though nothing in the repo states it should
be withheld.

### Every new function must pin `search_path`

`create function` / `create or replace function` bodies must carry `set search_path = public` (add `, extensions` if the body references postgis/pg_trgm objects) — for SECURITY DEFINER functions it's a hijack defence, for plain invoker functions it silences the Supabase security advisor's "Function Search Path Mutable" lint and keeps resolution independent of the caller's session. The backfill was `20270415_001` (via `ALTER FUNCTION … SET`, never a body rewrite); `function_search_path_test.sql` is a pg_proc catch-all that fails the pgtap suite on any unpinned public function. The eight `public_*` views the same advisor flags as "Security Definer View" are intentional and stay definer — see decisions.md §244 before "fixing" them.

### `drop policy if exists "wrong-name"` is a silent no-op

When you replace an RLS policy, the `drop policy if exists "name"` is keyed by EXACT name. A wrong name (typo, stale guess, name that was changed by a later migration) silently does nothing — your new policy then gets created ALONGSIDE the original, and at evaluation Postgres OR's them: the more permissive policy wins. The restrictive new policy you thought you added is bypassed.

**Before replacing a policy, grep the current authoritative name:**

```bash
grep -B 1 "on user_follows for insert" apps/backend/supabase/migrations/*.sql | tail
```

Pick the latest `create policy "..." on user_follows for insert` you find — that's the name to drop. Don't guess. Cost me an extra iteration on Round 3 W1 (the user_blocks finding): I dropped `"user_follows owner insert"` thinking that was the name; the real one was `"users follow on their own behalf"` from `20260521_001_user_follows.sql`. Both policies coexisted afterwards and the test that expected a block-induced 42501 saw the insert succeed via the un-touched original.

### New policies wrap auth.* in `(select ...)`; new FKs ship with a covering index

Two pgtap catch-alls enforce the performance-advisor posture (decisions §245): `rls_initplan_test.sql` fails on any policy expression calling `auth.uid()` / `auth.jwt()` / `auth.role()` / `current_setting()` bare — write `(select auth.uid())` so it hoists into a once-per-statement InitPlan instead of re-evaluating per row — and `fk_covering_index_test.sql` fails on any public-schema foreign key without a covering index (add the `<table>_<column>` index in the same migration as the FK). The backfills were `20270416_001` (mechanical `ALTER POLICY` over all 261 policies) + `20270417_001` (41 indexes). The advisor's "multiple permissive policies" warnings are accepted by design — see §245 before consolidating policies over it.

### CI green ≠ migration applied

Older `supabase/setup-cli` versions on CI **silently skip** migrations that collide on the `YYYYMMDD` version key (rather than erroring like the local CLI). A `Result: PASS` on the pgtap CI job does NOT prove your migration ran. The Round 2 persona-fix migrations sat in `main` for weeks "passing" CI before anyone noticed they hadn't been applied in any environment. **Always verify a new migration with `cd apps/backend && supabase db reset --local` locally before trusting CI.** If the local CLI errors with `duplicate key value violates unique constraint "schema_migrations_pkey"`, CI is probably just hiding the same error.

## Edge Function test gotchas

### A test that passes with its handler deleted is not a test, and CI now checks

Nothing in a Deno pure-helper suite is hidden by access control, so the ways an assertion goes vacuous here are different from the pgtap ones above: a `try/catch` that swallows its own `assert`, an equality between two of the subject's own outputs (which any constant satisfies), a negative source grep that an empty file satisfies for free, and a claim about the clock that makes none about the work. All four were live in this tree — 21 of 581 tests, including every one of `ipBucketKey`'s anti-spoofing assertions ([decisions.md § 788](../../docs/architecture/decisions.md)).

`apps/backend/scripts/check_edge_function_test_vacuity.mjs` enforces it in the `edge-functions` job. It replaces every non-test module under `supabase/functions` with a neutered twin — same exported names, same runtime shapes, no behaviour and no source text — blanks the four non-TypeScript artifacts a test reads *as its subject* (`config.toml`, both `.env` files, the migrations), and re-runs the suite. Run it locally with `node apps/backend/scripts/check_edge_function_test_vacuity.mjs` (~8 s, no stack needed) or `--report` to list survivors with file and line.

Two things to know before you touch it:

- **When you write a negative — `assert(!SRC.includes(...))`, an empty `offenders` array — pin the positive first.** "Nothing re-spells the parse" and "no file was read" are the same result, and the second is the likelier regression.
- **The neutered twin must keep every export's shape.** A stub that threw, or that turned an `async function` into a sync one, would make a vacuous test fail for a reason it never earned and hide it — so the guard fails when a baseline test case is *absent* from the mutant report, not only when one survives. If you change `edge_function_neuter.mjs`, `node --test apps/backend/scripts/check_edge_function_test_vacuity.test.mjs` is what proves it stayed lossless.

A survivor whose subject genuinely is not in this tree goes in `EXPECTED_SURVIVORS` with its reason, and a stale entry fails the guard too — but prefer widening `NEUTERED_ARTIFACTS` to name the artifact instead, since an argued exemption reads exactly like a vacuous test.

## pgtap test gotchas

### A refusal assertion needs a row to refuse, and CI now checks that it has one

Under RLS a refused SELECT does not error — it returns no rows. So `is_empty(...)` / `is(<count>, 0, ...)` is what a refusal looks like AND what a fixture that never inserted looks like, what a `WHERE` clause matching nothing looks like, and what a typo'd uuid looks like. Two assertions in `rls_route_conditions_test` sat green for months asserting an empty table reads empty (decisions.md § 741). **Whenever you write "principal X cannot see Y", file Y first and read it back from a session that may see it** — the `isnt_empty` positive control is what turns the refusal into a measurement.

`apps/backend/scripts/check_pgtap_refusal_assertions.mjs` enforces it in the `pgtap-rls` job by mutation: it re-runs each such assertion with the mechanism that could be hiding a row taken away, and fails if it still passes. There are two mechanisms and therefore two operators, picked per assertion by what it reads ([decisions.md § 745](../../docs/architecture/decisions.md)):

- **A base table** is guarded by row-level security, so every RLS-enabled table gains one extra permissive `SELECT` policy for the span of that one statement, revealing only the rows the test's own transaction wrote ([decisions.md § 753](../../docs/architecture/decisions.md)). It used to be a role change to the BYPASSRLS owner, which revealed the whole table — so a kill said a subject existed in the database rather than that the test built one. File your fixture at the top level or inside `lives_ok`; both count.
- **A view or an RPC filters in its own SQL**, which RLS never touched, so the relation itself is swapped for a permissive definition inside a savepoint. The replacements live in `apps/backend/scripts/pgtap_definer_neutralisers.mjs`, one per relation, each keeping every predicate that says *which* rows the assertion asked about and dropping every predicate that says *whether the caller may see them*. **Do not assume the catalogue tells you which relations need this**: eight of the twenty-four are `SECURITY INVOKER`, and filter with a `= auth.uid()` or an `is_public = true` written into the body.

Run it locally with the stack up (`node apps/backend/scripts/check_pgtap_refusal_assertions.mjs`, tens of seconds; it prints the assertion and file counts it actually reached), `--validate-operators` to prove each replacement still reveals a subject its real relation hides, or `--static-only` with no DB for the half that fails any `throws_ok` pinning neither a SQLSTATE nor a message.

An assertion whose empty result is genuinely a real answer (a trigger that correctly did not fire) goes in `EXPECTED_SURVIVORS` with its reason — a stale entry fails the guard too, so the list cannot outlive what it excuses. Conversely, an assertion whose refusal is real but whose wording the guard's vocabulary cannot match (`excluded from search` is a privacy floor in one test and a category filter in the next) opts in with a comment on the line above it:

```sql
-- refusal: the under-18 floor is a child-protection access control, not a search filter
select is((select count(*)::int from search_user_profiles('Minor Searchable')), 0,
  'declared minor stays excluded from search');
```

### UUIDs must be 32 valid hex chars (0-9 a-f) in 8-4-4-4-12 layout

Synthetic UUID literals like `'99999999-9999-9999-9999-99999dnfaaaa'` (contains non-hex `n`) or `'11111111-1111-1111-1111-111111ddd01'` (trailing segment is only 11 chars) error at first insert with `invalid input syntax for type uuid`. The whole test then reports "Bad plan: you planned N tests but ran 0" — easy to miss in a long pgtap summary because no individual test is marked as failing. **Use only `0-9 a-f` in synthetic UUIDs, and count the trailing segment** (12 hex chars). Patterns I've used safely: `99999999-9999-9999-9999-9999ddddaa01`, `88888888-8888-8888-8888-888888aaaaaa`, `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01`.

### `INSERT INTO runs (...)` needs `metadata.activity_type`

Migration `20260601_001_runs_metadata_activity_type_required.sql` added a CHECK constraint that rejects runs without `metadata.activity_type`. Any pgtap test that seeds a row in `runs` must include `metadata` with at least `{"activity_type":"run"}`:

```sql
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values (..., 'app', '{"activity_type":"run"}');
```

Or with `jsonb_build_object`: `jsonb_build_object('activity_type', 'run', ...other keys...)`. Forgetting it errors test setup before any assertion runs → "Bad plan" again.

### An authenticated fixture write needs `select tests.confirm_consent();`

The GDPR Art 8 write gate (`20270424000004_consent_write_gate.sql`) is a fail-closed BEFORE INSERT trigger on `runs` / `routes` / `gym_workouts` / `food_log` / `body_metrics`: an `authenticated` caller whose `user_profiles.age_confirmed_at` is NULL is rejected with `42501 consent required: confirm age and terms before writing user data`. A real account is never in that state — the client creates the profile on first sign-in and `confirm_age_and_terms()` stamps it — but a fixture that only does `insert into auth.users` produces exactly that unreal user, and the gate correctly refuses it. Nothing creates a `user_profiles` row on an `auth.users` insert (there is no `handle_new_user` trigger in this schema, despite what a couple of older test comments claimed).

So any pgtap fixture that switches to `authenticated` and then writes one of those five tables must first call:

```sql
select tests.confirm_consent();
```

It stamps `age_confirmed_at` + `terms_accepted_at` on every `auth.users` row that lacks them, creating the `user_profiles` row when the fixture never made one, and cleans up the `lifecycle_email` welcome job its inserts trigger so suites that assert on `jobs` are unaffected. **Call it after any `user_profiles` insert of your own** (it upserts, your plain insert would collide), and before the first `set local role authenticated`.

The helper is defined in `seed.sql`, not a migration — deliberately. `seed.sql` runs only on `supabase start` / `db reset`, so there is no production-reachable way to forge consent. Tests that assert the gate *fires* (`consent_write_gate_test.sql`, `age_confirmation_gate_test.sql`) simply don't call it. The Playwright equivalent is the `age_confirmed_at` / `terms_accepted_at` stamp in `createSagaUsers` (`apps/web/tests-e2e/fixtures/saga-users.ts`); service-role seeding from a spec is never gated, because `auth.uid()` is null for it.

### `set local "request.jwt.claims"` needs double quotes

The parameter name contains a dot, so PostgreSQL requires double quotes around it in `SET LOCAL`. Unquoted form `set local request.jwt.claims = '...'` is parsed differently and silently fails to set the JWT context — `auth.uid()` returns NULL, your RLS test passes (or fails) for the wrong reason. Always:

```sql
set local "request.jwt.claims" = '{"sub":"...","role":"authenticated"}';
```

Companion line: `set local role authenticated;` (or `anon` / `service_role`). The double-quoted form is what every working RLS pgtap test in `apps/backend/supabase/tests/` uses — copy that pattern.

### Common column-name typos that cost a `db reset`

- `user_follows` columns are `follower_id` + `followee_id` — **not** `followed_id`.
- `run_comments` author is `author_id` — **not** `user_id`.
- `clubs` visibility lives on `is_public` (boolean) — **not** a `visibility` text column. The owner is `owner_id` — **not** `created_by`.
- `events` has no `kind` column. Don't add one in test fixtures.
- `race_sessions` has a temporal-invariant CHECK: `status='running'` requires `started_at IS NOT NULL`. A test fixture inserting `running` without `started_at` errors at first insert.

When in doubt, `grep "create table $TABLE" apps/backend/supabase/migrations/*.sql` and read the latest schema before writing the test.

## Edge Functions

Sixteen functions live under `supabase/functions/`. All are wired up.

**Every Supabase client is bound to the generated schema, and there is exactly one path to it.** Build clients as `createClient<Database>(url, key)` and type every client-shaped parameter `DbClient`, both from `_shared/database.ts` — never `ReturnType<typeof createClient>` (that captures the DEFAULT generic instantiation, so a real client is not assignable to it) and never a bare `SupabaseClient` (that is `SupabaseClient<any>`, which typechecks nothing; `delete-account` looked like the best-typed file in the tree for exactly that reason). Service-role and user-scoped clients are the SAME type — they differ only in which key built them, and RLS is enforced by Postgres at request time — so the parameter *name* carries the privilege distinction, not the type.

`_shared/database.ts` re-exports `apps/web/src/lib/database.types.ts`, the single committed output of `npm run gen:types`. **Do not generate a second copy into this tree**: it would need a second drift check and would rot between them. Everything it re-exports is `export type`, so nothing crosses the boundary at runtime; keep it that way, or `database.types.ts`'s runtime `Constants` export starts riding into sixteen deploy bundles. Its supabase-js import is at `?target=deno` because the module lands in `clip-public-track`'s graph (decisions § 699); `_shared/offline_worker_boot_guard.test.ts` walks that graph and will say so if you change it.

**The tree typechecks, and CI enforces it** (decisions § 762). Run `deno check $(find supabase/functions -type f -name '*.ts' | sort)` from `apps/backend` before you push — the `Edge Function typecheck` step in the `edge-functions` job runs the same expression over every `.ts`, test files included, and `scripts/edge_functions_typecheck_coverage.test.mjs` fails when a file lands outside it. A `.from()` or `.rpc()` complaint is the generated type saying the column or argument name does not exist: find the right one in the migrations, don't cast it away.

**API keys are read through `_shared/api_keys.ts`, never inline.** `secretKey()` / `publishableKey()` prefer the new-generation JSON-by-name env vars (`SUPABASE_SECRET_KEYS` / `SUPABASE_PUBLISHABLE_KEYS`) and fall back to the legacy `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_ANON_KEY` — the legacy vars keep being injected after a project migrates but serve a stale value once legacy keys are disabled (supabase/supabase#37648). Raw `fetch` calls authenticated with the secret key build headers via `secretKeyHeaders()` (an `sb_secret_…` key must NOT be sent as an `Authorization` bearer — decisions §280). Where the table below lists `SUPABASE_SERVICE_ROLE_KEY` under Env vars, read "the secret key, resolved through the helper".

Test coverage breakdown:

- **Pure helpers** — `_shared/webhook_security.ts`, `_shared/body_limit.ts`, `_shared/redirect_allowlist.ts`, `revenuecat-webhook/lib.ts`, and the four paid-events libs (`events-connect-onboard/lib.ts`, `events-checkout/lib.ts`, `events-cancel/lib.ts`, `stripe-events-webhook/lib.ts`) are covered by deno tests across the `*.test.ts` files. The `edge-functions` CI job runs `deno test --no-check supabase/functions/` which recurses and picks up every `*.test.ts`, so the new files are gated automatically. `--no-check` there is not a gap: the separate `Edge Function typecheck` step above it checks the same files with `deno check`, so the suite stays fast without the tree going unchecked.
- **HTTP-level handler envelopes** — `_shared/handler_envelope.test.ts` covers the five webhook / cron / hook handlers that bypass the platform `verify_jwt` gate (refresh-tokens / strava-webhook / revenuecat-webhook / stripe-events-webhook / auth-email). Gated on `SUPABASE_TEST_URL`. The same `edge-functions` CI job stops the auto-started edge runtime (which ignores `.env.local`) and re-launches `supabase functions serve --env-file` so the secret-gated branches are reachable instead of 503'ing.
- **…and mutation-checked by a second operator.** The vacuity guard above neuters the module tree the TEST PROCESS imports, and this file imports none of it — its subject is a separately booted host reached over HTTP — so it scored those cases neither killed nor survived. `apps/backend/scripts/check_served_envelope_mutations.mjs` mutates the SERVED tree one gate at a time and requires the case naming that gate to fail (decisions § 815); `functions serve` re-reads a changed module on the next request, so it costs no second host and no second stack. **Coverage runs on three edges and it took all three**: `unmeasuredCases` (every case that RAN is named by a mutation), `phantomKills` (every named case ran), and — since decisions § 1320 — the static `declaredCases` + `unnamedDeclaredCases` census, because `parseJunit` drops deno's `<skipped/>` entries, so a case whose `ignore:` gate is never false in CI was in neither runtime set and measured by nothing while reading as green. **Adding a case to `handler_envelope.test.ts` therefore means adding a mutation for it in the same change**, or an `UNMEASURED_CASES` entry saying why one is not owed; `staleExemptions` fails when that reason stops describing the file. The census is static, so `node --test apps/backend/scripts/check_served_envelope_mutations.test.mjs` catches it with no stack booted.
- **Happy-path with valid HMAC / freshness / dedupe / side effect** — covered for the two webhooks whose write is reproducible against the local stack: `revenuecat-webhook` is driven through INITIAL_PURCHASE → dedupe-replay → EXPIRATION → lifetime → lifetime-protected PRODUCT_CHANGE and the written `user_profiles.subscription_tier` is read back; `stripe-events-webhook` covers three of its four event types: `account.updated` mirrors the capability flags into `instructor_payout_accounts` + dedupes a replay; the donation lifecycle drives `checkout.session.completed` (metadata.kind='donation') → paid + `charge.refunded` → refunded through the `donations` ledger + dedupes the completed replay; the event-order `checkout.session.expired` CAS's an `event_orders` row pending→canceled. All use a self-signed `ci-*` secret (mirrored into the CI env-file) and an ephemeral user, so the seed user is never mutated, and all additionally need `SUPABASE_SERVICE_ROLE_KEY` (exported from `supabase status` in the boot step) to plant + read the row — without it they skip. What's still **not** covered: the `checkout.session.completed` event-order seat path (needs the recurrence `instance_start` + `event_pricing` + capacity-trigger fixtures — overlaps the destination-charge Checkout round-trip) + a genuine Stripe/RevenueCat-originated delivery (operator `sk_test_` / `whsec_` keys — see local_testing_stubs.md § Stripe Connect).

| Function | Status | Trigger | Auth | Env vars |
|---|---|---|---|---|
| `auth-email` | **Working** — GoTrue's send-email auth hook: renders + sends every auth email (signup confirm, recovery, magic link / email OTP, invite, email change incl. the secure double-send, reauthentication) from a six-locale catalogue mirroring the Go worker's (`email_i18n.go` shape, identical layout), over the worker's `SMTP_*` env contract via a minimal Deno SMTP client. Locale: `user_settings.prefs.locale` → `user_metadata.locale` → `en` (settings read is auxiliary — a failure falls back, never blocks the auth flow). Unknown action types render an informational default rather than failing the hook. Verify links are byte-compatible with GoTrue's own (`/auth/v1/verify?token={token_hash}&type=…`), built from `API_EXTERNAL_URL` when set (committed `supabase/functions/.env` pins it to `http://127.0.0.1:54321` — the runtime-injected `SUPABASE_URL` is the browser-unreachable `http://kong:8000` locally), else `SUPABASE_URL` (correct in prod). Local hook wiring: `config.toml [auth.hook.send_email]` + the committed `supabase/functions/.env`; prod needs the Dashboard → Auth → Hooks config (see docs/features/email.md § GoTrue auth emails). | POST from GoTrue (the send-email hook) | Standard Webhooks signature over the raw body (`webhook-id`/`webhook-timestamp`/`webhook-signature`, HMAC-SHA256 keyed by the `v1,whsec_…` secret, ±5 min freshness, `\|`-separated rotation). `verify_jwt = false` in `config.toml`; fails closed (no secret → 503, bad/missing signature → 401). | `SEND_EMAIL_HOOK_SECRET`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`, `API_EXTERNAL_URL` (local only), `SUPABASE_SERVICE_ROLE_KEY` |
| `parkrun-import` | **Working** (scraper) | Client POST with `{ athleteNumber }` | User JWT → `supabase.auth.getUser()` | `PARKRUN_USER_AGENT` |
| `refresh-tokens` | **Deprecated** — kept deployed as a rollback path. Production has been migrated to the Go worker's `kind='token_refresh'` dispatch (`apps/job_worker/internal/handler_token_refresh.go`, scheduled by migration `20260821_001_token_refresh_cron.sql`). The per-integration refresh loop lives in `refresh-tokens/lib.ts` (`refreshExpiringStravaTokens`) and delegates the actual refresh to the shared `_shared/strava.ts` `refreshStravaToken`, so it writes via the **CAS** `set_integration_tokens_cas` (not the unconditional `set_integration_tokens`) — a concurrent CAS-protected refresh can't be clobbered by this sweep (issue #362). The 4xx→`disconnected_at` side effect is wired through the helper's `onPermanentFailure` callback. | Same as before if invoked directly. | Same shared `CRON_SECRET` (timing-safe compare); service role for DB writes. `verify_jwt = false` in `config.toml`. | `CRON_SECRET`, `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` |
| `strava-import` | **Working** — OAuth exchange + 90-day backfill + `sync` action for already-connected users (`lookbackDays` 1..365, both clients offer 90 / 180 / 365); GPS streams uploaded to the `runs` Storage bucket and deduped against existing Strava activity IDs. The page walk lives in `backfill.ts` so its exits are testable without `Deno.serve`; a truncation records the window still to walk on `integrations.sync_cursor` and the response carries `complete` + `resumable` (decisions § 766 + § 768). The `connect` path also pins `redirect_uri` against `STRAVA_ALLOWED_REDIRECTS` (required — function returns 503 if unset) and rejects scope grants missing `activity:read_all`. The parse + the whole-string comparison live in `_shared/redirect_allowlist.ts`, shared with the three Stripe-events functions; `_shared/redirect_allowlist.test.ts` pins both branches plus source guards that the gate is still called, still before the token exchange (decisions § 750). | Client POST with `{ action: 'connect', code, scope, redirect_uri }` (after the OAuth redirect) or `{ action: 'sync', lookbackDays? }` | User JWT | `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_ALLOWED_REDIRECTS` (required for `connect`) |
| `strava-webhook` | **Deprecated** — kept deployed as a rollback path. Production has been migrated to the Go service's `POST /v1/strava/webhook` endpoint (`apps/job_worker/internal/stravahook/server.go`) which validates + dedupes + enqueues a `kind='strava_event'` job; the worker handler (`handler_strava_event.go`) does the activity fetch + Storage upload + runs insert async. Same `webhook_events` dedupe table on the `provider='strava'` partition, same `metadata.strava_id` dedupe key — the two paths can co-exist during cutover. | Same as before if hit directly. | Shared `?secret=` URL guard, `hub.verify_token` on GET, service role for DB writes. `verify_jwt = false`. | `STRAVA_VERIFY_TOKEN`, `STRAVA_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` |
| `export-data` | **Deprecated** — kept deployed as a rollback path. Production traffic now hits the Go service's **queued** rail — `POST /v1/export/jobs` + `GET /v1/export/jobs/latest` (`apps/job_worker/internal/dataexport/`, decisions §717 + §724) — same JWT auth, same tiered rate limit, same Storage path, but the signed URL is minted at read time and nothing holds the caller's connection open for the build. Its synchronous `POST /v1/export` was deleted with §724, which makes THIS function the only synchronous export rail left. **Since 2026-08-21 this rail streams** (decisions §703): the archive is pushed to Storage through a chunked tus upload (`/storage/v1/upload/resumable`, 6 MiB chunks) and every section is serialised page by page, so it has **no run cap and no per-section row ceiling** — unlike the Go rail, which still buffers and still caps at 5000 runs / 50,000 rows. Its one bound is the 150 s request clock, spent through an explicit 120 s `ExportBudget`; a section it cuts short is named in `manifest.json`'s `incomplete`. Any build failure aborts the tus session, so a failed export leaves no object at all. Artifacts land in the **`exports`** bucket (migration `20270602_001`) rather than `runs`, whose 25 MB per-object cap was a tighter ceiling on a full-history archive than either removed cap; that bucket carries **no `storage.objects` policies** (signed-URL-only per `20260816_001`), is drained by `delete-account` and swept at 7 days by `cleanup_stale_export_blobs`. **Operator step before prod:** the project-level Storage upload limit (50 MB default) is the lower of the two ceilings until raised. | Same as before if invoked directly. | User JWT | — |
| `revenuecat-webhook` | **Working** — replay-protected (7-day freshness window via `validateFreshness` default + `event.id` dedupe via `webhook_events`, migration `20260623_001`). RevenueCat retries an undelivered event for up to 3 days, so the 7-day window comfortably brackets every legitimate retry; both webhooks share the same default to keep the security model uniform. | POST from RevenueCat (INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION) | HMAC-SHA256 of raw body in `x-revenuecat-hmac` (timing-safe compare against `REVENUECAT_WEBHOOK_SECRET`). `verify_jwt = false` in `config.toml`. | `REVENUECAT_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` |
| `delete-account` | **Working** — recursive Storage prefix walk drains `{user_id}/exports/` blobs alongside top-level tracks; the mandatory bucket loop covers `runs` + `exports` (migration `20270602_001`) + `run-photos` + `route-photos` + `club-photos` (plus best-effort `avatars`). The third-party sweep (Strava / Garmin / RevenueCat / FCM) also closes the host's Stripe Connect Express account (`DELETE /v1/accounts/{id}`, best-effort, outcome in `third_party_outcomes.stripe_connect_delete`) before the `instructor_payout_accounts` row cascades away with the account id. Records per-table deleted-row counts (jobs / rate_limits / reports / segments + the four Storage buckets) into `deletion_audit_log.notes` as compact JSON on the `ok` path — `result='ok'` disambiguates notes-as-counts from notes-as-error, so no schema change. After the cascade it also enqueues the account-deletion **receipt** email (a `lifecycle_email` `account_deleted` job carrying `{email, locale}` inline, **no `user_id`** so the pre-cascade job-drain doesn't sweep it; worker dedups via the non-cascading `account_deletion_receipts` table, migration `20270217_001`, decisions §121). | Client POST (user action) | User JWT + service role for admin delete | `SUPABASE_SERVICE_ROLE_KEY` |
| `clip-public-track` | **Working** — server-side privacy-zone clipping for non-owner viewers. Downloads the gzipped track via service-role, runs `clip_track_for_user`, returns clipped points. Replaces the dropped public-runs Storage policy (decisions §33, audit/storage High). | Anon or user JWT POST with `{ run_id }` | `verify_jwt = false` (decisions §280 — a logged-out caller's bearer is the non-JWT publishable key); in-handler authorization is the trust boundary: RLS gates the row read via the anon-key client, per-IP rate limit for anon, per-user for authenticated | — |
| `events-connect-onboard` | **Working** (pure libs tested; **live Connect onboarding UNVERIFIED — needs operator sk_test_ keys**). Creates/reuses a Stripe Express account for the host, persists its id in `instructor_payout_accounts`, returns a hosted Account Link URL. `charges_enabled` flips later via `stripe-events-webhook` `account.updated` — never written here. SAQ A (Stripe-hosted onboarding). club_events.md slice P1. | Client POST (host) | User JWT → `auth.getUser()`; service role for the own-row write; `checkRateLimit` fail-closed | `STRIPE_SECRET_KEY`, `STRIPE_EVENTS_ALLOWED_REDIRECTS`, `SUPABASE_SERVICE_ROLE_KEY` |
| `events-checkout` | **Working** (pure libs tested; **live Checkout round-trip UNVERIFIED — needs operator sk_test_ keys**). Validates visibility + `event_pricing` (modality `in_person` only; `virtual` → 400) + not-cancelled + sales window + host `charges_enabled` + capacity precheck (going + non-expired pending), then opens a **destination-charge** Checkout Session (`application_fee_amount` + `transfer_data.destination` = host account) keyed on the pending order, with `expires_at` derived from that order's `created_at` so a retry replays byte-identically, and inserts a `pending` `event_orders` row holding a 15-min soft reservation. Returns `{ checkout_url, order_id }`. SAQ A (no card form). | Client POST (buyer) `{ event_id, instance_start }` | User JWT → `auth.getUser()`; service role for the ledger write; `checkRateLimit` fail-closed | `STRIPE_SECRET_KEY`, `STRIPE_EVENTS_ALLOWED_REDIRECTS`, `SUPABASE_SERVICE_ROLE_KEY` |
| `events-cancel` | **Working** (pure libs tested; **live refund round-trip UNVERIFIED — needs operator sk_test_ keys**). Buyer self-cancel of their OWN paid/pending registration (slice P2). **INITIATES only — never writes `event_orders.status`** (the webhook stays the sole writer). Pure `lib.ts` decides via `resolveRefundEligibility` + `cancelAction`: `pending` → expire the Checkout Session at Stripe (→ `checkout.session.expired`); refund-eligible `paid` **or `partially_refunded`** → create a Stripe refund via `buildRefundParams` (`reverse_transfer: true` **and** `refund_application_fee: true` — Stripe couples them on a destination charge, and the second alone paid the host our fee on top of the ticket they kept, decisions § 769; stable idempotency key `events-cancel:<order_id>`, → `charge.refunded`) and stamp `event_orders.refund_initiated_at`; `paid` inside the no-refund window → 409 `policy_no_refund` (keeps the seat). 503 `stripe_not_configured` when the key is unset (fail-closed). On a Stripe refund error it clears the optimistic stamp + 502s. SAQ A. | Client POST (buyer) `{ event_id, instance_start }` | User JWT → `auth.getUser()`; service role for the own-row lookup + the refund stamp; `checkRateLimit` fail-closed | `STRIPE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY` |
| `stripe-events-webhook` | **Working** (pure libs tested incl. signature/idempotency/CAS; **live signed delivery UNVERIFIED — needs operator whsec_ keys**). The SOLE, idempotent, service-role-only writer of `event_orders.status`. HMAC-verified on the **raw** body (Stripe-Signature `t=…,v1=…` over `${t}.${body}`, 5-min freshness/replay gate). Insert-first dedupe into `webhook_events` (provider `'stripe'`, `event.id`) → 23505 = 200 skip. Every event object is narrowed once through `readCheckoutSession` / `readCharge` / `readConnectAccount`, whose source shapes are pinned to `Stripe.Checkout.Session` / `Stripe.Charge` / `Stripe.Account` by compile-time assignability assertions over a **type-only** SDK import (decisions § 785 — measured at +230 eszip bytes against a value import's +2.6 MB). Handles six types: `checkout.session.completed` (**only once `payment_status` says the money arrived** — a delayed-notification method completes the Session `unpaid`; then CAS pending→paid + confirm-time capacity recheck + seat the `going` attendee with `order_id`; oversold → leave paid + log + flag for MANUAL refund), `checkout.session.async_payment_succeeded` (the same path, for the money that lands days later), `checkout.session.async_payment_failed` (CAS pending→failed; no seat was ever issued for it), `checkout.session.expired` (CAS pending→canceled, release slot), `charge.refunded` (CAS paid→refunded + release the seat — the P2 self-cancel coupling; a replayed event finds it already refunded and no-ops), `account.updated` (mirror `charges_enabled`/`payouts_enabled`/`details_submitted`). Unknown types → 200 ignored. **The Stripe endpoint must subscribe to the two async types** or a delayed payment's real outcome never arrives. | POST from Stripe | HMAC-SHA256 over raw body in `Stripe-Signature` vs `STRIPE_EVENTS_WEBHOOK_SECRET`. `verify_jwt = false` in `config.toml`. | `STRIPE_EVENTS_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` |

The original eight are short — 25 to 115 lines each. Read the file, not an abstraction; they don't share helpers (other than `_shared/rate_limit.ts` for the throttle). The three paid-events functions follow the `revenuecat-webhook` precedent precisely: a pure `lib.ts` (param builders / decisions / signature verifier, dependency-free) + a thin `index.ts` that holds all Stripe SDK calls, constructed with `Stripe.createFetchHttpClient()`. **Import Stripe from `_shared/stripe.ts`, never from the esm.sh URL** — that URL's declarations resolve to `any` (esm.sh renames the module its ambient declaration declares, decisions § 765), so a direct import does not fail, it just stops checking; `_shared/stripe_boundary.test.ts` fails on one. The params helpers stay Stripe-free on purpose (`events-checkout/lib.ts` is imported by `stripe-events-webhook`, which must not grow the `?target=deno` polyfill tree, § 699), so each call site carries an `AssertNoUnknownParamKeys` line — assignability alone lets a misspelled optional field through. `events-checkout/lib.ts` owns the ONE `capacityDecision` helper; `stripe-events-webhook/lib.ts` re-exports it so the create-time precheck and the confirm-time recheck use identical capacity math (divergence would oversell).

**`webhook_events` provider partitions:** `revenuecat`, `strava`, and now `stripe` (the `stripe-events-webhook` dedupe key — insert-first on `(provider='stripe', event_id)` where `event_id` is the Stripe event id). The provider-agnostic 30-day prune (`cleanup-stale-webhook-events`, migration `20260623_001`) already bounds the new partition — no per-provider cleanup needed.

### Rate limiting

User-facing functions guard with `check_rate_limit` via the shared helper:

```ts
import { checkRateLimit } from '../_shared/rate_limit.ts';
// ...after auth.getUser():
const denied = await checkRateLimit(supabase, user.id, 'parkrun-import', 4, 3600);
if (denied) return denied; // 429 with Retry-After header
```

Backed by `rate_limits (user_id, bucket, window_start, count)` (migration `20260604_001`) with fixed-window bucketing — `floor(epoch / window) * window` keys all hits in the same wall-clock window to the same row. `check_rate_limit` is SECURITY DEFINER so EFs only need the function grant, not direct table access. Cron job `cleanup-stale-rate-limits` sweeps rows >24 h old hourly.

For paywalled paths use the tiered variant (migration `20260605_001`):

```ts
const denied = await checkRateLimitTiered(supabase, user.id, 'parkrun-import',
  /* free */ 4, /* pro */ 16, 3600);
```

The SQL function reads `user_profiles.subscription_tier` and the rate-limit row in one transaction, so EF latency stays constant. Lifetime is treated as pro; missing or unknown tier values fall back to free as the conservative default.

The helper fails open on RPC error — a transient DB blip won't manifest as a wave of 429s — and only emits 429 on a real deny.

Don't apply this to `refresh-tokens` (cron, no user.id), `revenuecat-webhook` (HMAC-validated, RC-side), or `strava-webhook` (Strava-side, URL-secret guarded).

### Common shape

Every function that takes a user request follows the same pattern:

```ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
  const authHeader = req.headers.get('Authorization')!;
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // ... work ...
  return Response.json({ ok: true });
});
```

The client in the function is authenticated *as the user* (RLS applies) because the request's `Authorization` header is forwarded. If you need to bypass RLS — background jobs, webhooks from third parties, cross-user lookups — use `SUPABASE_SERVICE_ROLE_KEY` instead of `SUPABASE_ANON_KEY`. `refresh-tokens` and `strava-webhook` are the two functions that do this.

### Running a function locally

```bash
# Start the stack + function host (from apps/backend)
supabase start
supabase functions serve --env-file .env.development   # or .env.local for your real keys

# Hit one
curl -X POST http://127.0.0.1:54321/functions/v1/parkrun-import \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -d '{"athleteNumber": "A123456"}'
```

Getting a JWT for the seed user:

```bash
curl -X POST "http://127.0.0.1:54321/auth/v1/token?grant_type=password" \
  -H "apikey: $(supabase status -o json | jq -r .ANON_KEY)" \
  -H "Content-Type: application/json" \
  -d '{"email":"runner@test.com","password":"testtest"}' \
  | jq -r .access_token
```

`supabase functions serve` reloads on file change. Logs go to the terminal it's running in.

### Testing without real credentials

Strava, parkrun, and Google each require real API credentials to test their happy paths. Options:

1. **Mock the upstream HTTP call.** Deno's `fetch` can be stubbed — wrap it in a helper, import from a conditional module. Fiddly for a 40-line function; usually not worth it.
2. **Point at a local fixture server.** Drop a tiny `python -m http.server` in a fixtures directory and override `STRAVA_OAUTH_URL` (doesn't exist yet — the functions hardcode `https://www.strava.com/...`). Would need a small refactor to make URLs injectable.
3. **Use a sandbox Strava account.** Strava has a real sandbox but registration is a multi-day process.
4. **Don't test the happy path locally; test only the auth rejection branch.** Send a request with a bogus JWT and assert 401. Covers the common shape; skips the integration detail.

The `edge-functions` CI job now exercises the five handler envelopes (refresh-tokens / strava-webhook / revenuecat-webhook / stripe-events-webhook / auth-email) end-to-end on every PR — see the "Edge Functions" section above. The four JWT-gated handlers (delete-account / export-data / parkrun-import / strava-import) are 401'd by the platform gateway before the handler body runs, so option 4 is degenerate for them and there's no equivalent CI coverage. (clip-public-track left this set with the §280 key migration: it now runs `verify_jwt = false` and authorizes in-handler, since logged-out spectators send the non-JWT publishable key as the bearer.) The happy paths (valid HMACs / fresh event timestamps / real OAuth) still fall through to options 1-3 above when you need them.

### Deploying functions to production

For the full production plan — Supabase Cloud project setup, region, custom domain, secrets, observability, DR — see [deployment.md](deployment.md).

Handled by CI in `.github/workflows/ci.yml`'s `deploy-functions` job on GitHub release (published). Do not deploy manually in dev — you'll clobber whatever's live. If you need to run a one-off deploy, ask first.

Manual deploy syntax (for reference):

```bash
supabase functions deploy parkrun-import --project-ref "${SUPABASE_PROJECT_REF}"
# Requires SUPABASE_ACCESS_TOKEN in the env.
```

## Secrets and env vars

Three committed-vs-local files, the repo-wide convention (decisions §137): `.env.example` is the placeholder template; `.env.development` is the committed, non-secret, ready-to-run local defaults you serve `--env-file .env.development` against; `.env.local` (gitignored) holds your real keys and is the file you point `--env-file` at when you need them — it wins. Keep all three in sync when you add a new variable. A fourth, special-purpose file: `supabase/functions/.env` (committed, un-ignored explicitly in the root `.gitignore`) is the ONE env file the CLI auto-loads into the **auto-started** edge runtime on `supabase start` — it carries only the auth-email hook's local-dev secret + the Mailpit SMTP endpoint so GoTrue auth mail works without a manual `functions serve`. Its `SEND_EMAIL_HOOK_SECRET` must stay in lockstep with `config.toml [auth.hook.send_email].secrets`.

Supabase Edge Functions read env vars via `Deno.env.get('NAME')`. At runtime in local dev, `--env-file .env.development` (or `.env.local`) on `supabase functions serve` is what populates them. In production, variables are set via `supabase secrets set` against the linked project — a separate flow from `.env.local`.

Variables currently used:

- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` — injected by the runtime; you do not set these in `.env.local` for local dev.
- `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` — Strava OAuth credentials.
- `STRAVA_VERIFY_TOKEN` — shared secret for the webhook GET handshake (sent by Strava in `hub.verify_token`).
- `STRAVA_WEBHOOK_SECRET` — shared secret the caller presents in the `X-Webhook-Secret` header (preferred) or the callback URL's query string (`?secret=...`). Strava's subscription API only accepts a URL, so the query path is the only one Strava itself can use — and it writes the secret into every function log line, which is why the header wins when present and why moving Strava off the query path is an owed ops item (`docs/ops/deployment.md` § Owed, decisions §567). Either way it is the only auth available on POST events (Strava doesn't sign payloads). Required: function fails closed without it; also refuses below a 32-char floor.
- `CRON_SECRET` — shared bearer token the pg_cron schedule passes to `refresh-tokens` so an unauthenticated caller can't trigger Strava token-refresh churn on every integration in the table. Required: function fails closed without it.
- `TRUSTED_CLIENT_IP_HEADER` — names the ONE request header the deployment's own edge overwrites, and therefore the only one `_shared/rate_limit.ts`'s `ipBucketKey` will read to identify an anon caller. Optional; defaults to `cf-connecting-ip`, which is correct for hosted Supabase (it runs behind Cloudflare, which overwrites the header on every request). **Set it on any self-hosted / non-Cloudflare deployment** to whatever the front proxy overwrites (`x-real-ip` for a typical nginx). Unset on such a topology is fail-closed, not open: every anon caller collapses into one shared bucket and contends for the same window, because keying off a header the caller controls is not a rate limit at all.
- `PARKRUN_USER_AGENT` — identifies us to parkrun's server. Be polite.
- `RUNSIGNUP_API_KEY` / `RUNSIGNUP_API_SECRET` — RunSignUp partner credential the `race-results-import` + `race-listings-sync` functions use for the RunSignUp leg. Required for that leg: both functions return `503 provider_not_configured` when either is unset (fail-closed; the parkrun + manual-paste race paths work without them). **The RunSignUp import leg is also athlete-scoped (issue #360):** `race-results-import` rejects `400 runsignup_athlete_id_required` unless the request carries the runner's `runSignUpUserId` or a `bib` (an unscoped `get-results` returns the whole finisher field), and rejects `400 ambiguous_match` in the `matchRunId` path unless exactly one result maps. Gates are the pure `runSignUpScopeGate` / `matchResultGate` in the EF's `lib.ts`.
- `ULTRASIGNUP_API_KEY` / `ULTRASIGNUP_API_SECRET` — UltraSignup partner credential. **Setting these does not enable the `race-results-import` UltraSignup leg**: it refuses unconditionally with `503 provider_not_configured` + `reason: 'results_unattributable'` on both the import branch and the probe, because the endpoint it reads is an ATHLETE history feed carrying no race identifier and every row it returns would be stamped with the target listing's race (decisions § 975). `race-listings-sync` still gates on them normally.
- `CHRONOTRACK_CLIENT_ID`, `CHRONOTRACK_USER_ID`, `CHRONOTRACK_PASSWORD` — ChronoTrack Live (CTLive) credentials for the `race-results-import` `provider:'chronotrack'` leg. All three required together: any unset → `503 provider_not_configured` (fail-closed; parkrun + manual paste still work).
- `RACE_IMPORT_USER_AGENT` — polite identifier for the RunSignUp / UltraSignup / ChronoTrack results fetch (defaults to `RunApp/1.0`).
- `REVENUECAT_WEBHOOK_SECRET` — HMAC secret the `revenuecat-webhook` verifies the request body against. Required: function fails closed without it.
- `STRIPE_SECRET_KEY` — Stripe platform secret key (sk_test_ in P1 — **TEST MODE ONLY, never a live key**). Used by `events-connect-onboard` (account + Account Link create), `events-checkout` (destination-charge Checkout Session), `events-cancel` (refund create / Checkout Session expire — slice P2 buyer self-cancel), and `delete-account` (Connect Express account DELETE on erasure — unset with an account present → `stripe_connect_delete: 'failed'`, never a false `skipped`). Required for the events functions: all fail closed (503 `stripe_not_configured`) without it. Server-only; never client-readable.
- `STRIPE_CONNECT_CLIENT_ID` — Stripe Connect application id (ca_…). Configured on the platform account for Express + Account Links; held as an env var for any future Standard-OAuth path (open question #4). Not passed per-call in P1.
- `STRIPE_EVENTS_WEBHOOK_SECRET` — Stripe webhook signing secret (whsec_…) the `stripe-events-webhook` verifies the Stripe-Signature HMAC against. SEPARATE from `REVENUECAT_WEBHOOK_SECRET` and a separate endpoint. Required: function fails closed (503 `webhook_not_configured`) without it.
- `STRIPE_EVENTS_ALLOWED_REDIRECTS` — comma-separated allow-list of origins accepted for Account Link return/refresh + Checkout success/cancel URLs (the strava-import open-redirect defence). Required: `events-connect-onboard` + `events-checkout` 503 when empty.
- `REVENUECAT_SECRET_API_KEY` — RevenueCat REST secret key `delete-account` uses to DELETE the subscriber on erasure. Optional — unset → `revenuecat_delete: 'skipped'`.
- `FCM_SERVER_KEY` — Firebase Cloud Messaging server key `delete-account` uses to batch-invalidate Android push tokens. Optional — unset → `fcm_remove: 'skipped'`.
- `DELETION_AUDIT_KEY` — HMAC key for the `deletion_audit_log` pseudonymous user-id hash. Optional but recommended; unset → legacy salted SHA-256.
- `VAPID_PRIVATE_KEY` — web-push private signing key (public half is `PUBLIC_VAPID_PUBLIC_KEY` in `apps/web/.env.example`). **Consumed by the Go worker, not an Edge Function:** the `web_push` job handler (migration `20261219_001`) signs encrypted Web Push messages with it. Set on the **worker** as `VAPID_PRIVATE_KEY` + `VAPID_PUBLIC_KEY` + `VAPID_SUBJECT` (see `apps/job_worker/CLAUDE.md`); unset → `web_push` jobs finish done while leaving the notification rows pending.
- `SEND_EMAIL_HOOK_SECRET` — the Standard Webhooks signing secret GoTrue's send-email hook is configured with (`v1,whsec_<base64>`; `|`-separated for rotation). `auth-email` verifies every hook POST against it. Required: the function fails closed (503) without it. Locally it's the committed dev value in `config.toml [auth.hook.send_email].secrets`, mirrored in the committed `supabase/functions/.env`.
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` — the SMTP transport for `auth-email`, same variable names the Go worker's mailer uses. Local dev: `host.docker.internal:54325` (Mailpit as seen from inside the edge runtime container), no AUTH. Production: the real relay (465 = implicit TLS, 587 = STARTTLS) with username/password. `auth-email` 503s (fail-closed) when `SMTP_HOST` or `SMTP_FROM` is unset.
- `API_EXTERNAL_URL` — host-reachable API origin `auth-email` builds its verify links from, mirroring GoTrue's `api_external_url`. REQUIRED locally (`http://127.0.0.1:54321`, committed in `supabase/functions/.env`): the local runtime's injected `SUPABASE_URL` is the Docker-internal `http://kong:8000`, and a link built from it is unreachable from any browser (broke the reset-password e2es in CI run 28707481878). Unset in prod, where the injected `SUPABASE_URL` is already the public project URL. The name can't be `SUPABASE_`-prefixed — the CLI reserves that prefix and silently drops such vars from env files (`supabase secrets set` rejects them too).
- `SENTRY_DSN`, `APP_RELEASE` — Sentry error reporting (every EF via `_shared/sentry.ts`). Optional in local dev.

## CLI gotchas I've hit

- **Run every `supabase` command from `apps/backend/`.** The CLI looks for `config.toml` in the cwd and fails or misleads otherwise.
- **`supabase db reset` blows away local data.** The seed repopulates it. If you had manual experiments in the local DB, export them first — the seed will not restore them.
- **`supabase gen types typescript --local` writes `Connecting to db 5432` to stdout** before the real output. The `gen:types` npm script pipes through `grep -v '^Connecting to db'` to strip it. Don't remove that filter.
- **`supabase functions serve` does not autoload `.env.development` / `.env.local`**. You must pass `--env-file .env.development` (or `.env.local` for your real keys) explicitly. A missing env var shows up as a `Deno.env.get('X')!` assertion failure at runtime — the `!` eats the error. The one auto-loaded file is `supabase/functions/.env`, which the CLI reads into the **auto-started** runtime on `supabase start` (committed here for the auth-email hook — see "Secrets and env vars").
- **Docker must be running.** All local Supabase services run under Docker. If `supabase start` hangs or errors weirdly, check `docker ps`.
- **`deno.lock` lives at the repo root and is committed.** Newer Supabase CLIs write it during `supabase db reset` / `functions serve` to pin Edge Function dependency resolutions (e.g. `https://esm.sh/@supabase/supabase-js@2 → 2.105.1` plus integrity hashes for every transitive Deno URL). The file is created inside the CLI's Docker container as `root:root`, so after a fresh resolution you may need to `sudo chown` it before staging. Treat it like `package-lock.json`: review the diff on dependency-version changes, but otherwise let it ride.
- **Only `remote` + `redirects` in that lockfile are load-bearing.** Its third section, `workspace`, is a transcription of the npm workspace's `package.json` dependency specs that nothing resolves against — it is there only because the lockfile sits at the root of an npm workspace. It therefore drifts on every web dep bump; **`pnpm sync:deno-lock` re-syncs it** (deno writes it, because the ranges are canonicalized — `^0.45.8` comes back as `~0.45.8` — so hand-editing produces a file deno immediately rewrites) and CI's `parity-types` job fails on drift. Needs deno, but no network, no `node_modules` and no Docker. See [decisions.md § 706](../../docs/architecture/decisions.md). If a `supabase db reset` leaves a dirty `deno.lock` whose diff is confined to that section, this is why.

## Before reporting a task done

- If you added or changed a migration: run `supabase db reset` locally, then regenerate both row-type files, then commit the migration + both generated files in one change.
- If you added or changed an Edge Function: deploy-ability has not been tested locally. The user will notice on `main` deploy. Leave a note in the PR description about what you couldn't verify.
- If you added a new env var: update `.env.example` and this file's "Variables currently used" list.
- If you added a new function: update the table in the "Edge Functions" section above. Status column should be honest — stub, partial, or working.
- If you changed `runs.metadata` key usage: update [../../docs/backend/metadata.md](../../docs/backend/metadata.md). The schema generators can't catch drift in there.
