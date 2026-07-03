-- Missing indexes on foreign-key columns that reference the high-write,
-- high-delete `runs` (and `routes`) tables. Without these, every run delete
-- (user-initiated delete, re-import replace, backup restore) and every route
-- delete has to sequential-scan each child table to find the rows whose FK
-- needs the ON DELETE CASCADE / SET NULL fix-up. `runs` is one of the largest,
-- highest-write tables in the schema, so the cost compounds on every delete.
--
--   * runs.route_id                 -> routes    (NO ACTION; route-detail
--                                                  "runs on this route" read +
--                                                  routes_run_count trigger's
--                                                  count(*) where route_id = …)
--   * personal_records.run_id       -> runs      (ON DELETE SET NULL)
--   * plan_workouts.completed_run_id -> runs      (ON DELETE SET NULL)
--   * event_results.run_id          -> runs      (ON DELETE SET NULL)
--   * notifications.run_id          -> runs      (ON DELETE CASCADE)
--
-- All partial (`where … is not null`) to match the house style already used for
-- runs_event_id_idx / runs_race_listing_idx and to keep the index small on the
-- many rows that carry no reference.
--
-- Lock trade-off: these are plain (non-CONCURRENT) builds. `CREATE INDEX
-- CONCURRENTLY` cannot run through the Supabase CLI migration path — the CLI
-- wraps each migration in a transaction/pipeline and a concurrent build errors
-- with SQLSTATE 25001 ("cannot be executed within a pipeline"). A plain build
-- takes a brief ACCESS EXCLUSIVE lock on the table for the duration of the
-- build; for a truly zero-downtime prod build, run the equivalent
-- `CREATE INDEX CONCURRENTLY` manually against prod in a maintenance window and
-- `supabase migration repair` this version as applied. This matches how every
-- prior FK index on `runs` was landed in this repo.

create index if not exists runs_route_id_idx
  on runs (route_id) where route_id is not null;

create index if not exists personal_records_run_id
  on personal_records (run_id) where run_id is not null;

create index if not exists plan_workouts_completed_run_id
  on plan_workouts (completed_run_id) where completed_run_id is not null;

create index if not exists event_results_run_id
  on event_results (run_id) where run_id is not null;

create index if not exists notifications_run_id
  on notifications (run_id) where run_id is not null;
