-- Training-load + fitness snapshots.
--
-- Time-series store for the Phase 3 Pro-tier features that track
-- adaptation over time: VDOT (Daniels' Running Formula), VO2 max (Cooper
-- estimate from pace + HR), and the ATL / CTL / TSB trio (acute load,
-- chronic load, training-stress balance) that drives the recovery
-- advisor. One row per computation — the recovery / pace-predictor
-- views read the latest snapshot, the trend charts read the full
-- history scoped to a window.
--
-- Today the schema is ready; no endpoint computes or writes to this
-- table yet. The Pro-tier (`decisions.md § 23`) markets "priority
-- processing" and "unlimited AI Coach" — the VO2 / recovery features
-- themselves are a future add, tracked under `roadmap.md § Phase 3 —
-- Premium tier`.
--
-- Design notes:
--   - `numeric(5, 2)` for scalar metrics — two decimals is plenty for
--     VDOT (typically 30–85) and VO2 max (20–85 ml/kg/min). Loads can
--     be larger, so ATL / CTL / TSB get `numeric(8, 2)`.
--   - `qualifying_run_count` lets the UI say "based on N runs" — if
--     it's low the numbers are noisy and the advisor should hedge.
--   - `source` distinguishes server-computed from client-computed so
--     we can see which is authoritative per row when both exist.

create table fitness_snapshots (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users(id) on delete cascade,
  -- When this snapshot was computed (server time). The advisor reads
  -- "the most recent snapshot" per user — partition + index accordingly.
  computed_at            timestamptz not null default now(),
  -- Daniels' VDOT — a single number summarising current race fitness.
  vdot                   numeric(5, 2),
  -- Cooper-formula VO2 max (ml/kg/min).
  vo2_max                numeric(5, 2),
  -- Training loads — exponentially weighted moving averages of per-run
  -- training stress scores. ATL = 7-day, CTL = 42-day, TSB = CTL - ATL.
  -- A negative TSB means the runner is loaded up (expected during a
  -- build block); a large positive TSB means they've tapered.
  acute_load             numeric(8, 2),
  chronic_load           numeric(8, 2),
  training_stress_bal    numeric(8, 2),
  -- How many runs contributed to this snapshot. The UI should hedge
  -- the advice text when this is small ("based on only N runs — take
  -- with a grain of salt").
  qualifying_run_count   integer not null default 0,
  -- Free-form notes on which inputs drove the estimate (e.g. which
  -- race, which HR-zone assumption). Useful for debugging discrepancies
  -- when a user says "this is wrong".
  source                 text not null default 'server'
                          check (source in ('server', 'client')),
  notes                  text,
  created_at             timestamptz not null default now()
);

-- The advisor + trend charts both key off "latest snapshot per user"
-- and "snapshots in a time window". This index covers both shapes.
create index fitness_snapshots_user_time
  on fitness_snapshots (user_id, computed_at desc);

alter table fitness_snapshots enable row level security;

-- Users only see their own snapshots.
create policy fitness_snapshots_self_select on fitness_snapshots
  for select using (user_id = auth.uid());

-- Writes come from two paths: the server-side recompute job (service
-- role, bypasses RLS) and any future client-side fallback estimator.
-- The client policy allows a signed-in user to insert rows keyed to
-- their own id.
create policy fitness_snapshots_self_insert on fitness_snapshots
  for insert with check (user_id = auth.uid());

-- Delete is allowed so a user can wipe their training-load history
-- without going through the full `delete-account` path.
create policy fitness_snapshots_self_delete on fitness_snapshots
  for delete using (user_id = auth.uid());

-- Convenience RPC: latest snapshot for the caller. The UI can query
-- the table directly but this gives callers a single round-trip for
-- the common "dashboard header card" case.
create or replace function latest_fitness_snapshot()
returns fitness_snapshots
language sql
stable
security invoker
as $$
  select *
  from fitness_snapshots
  where user_id = auth.uid()
  order by computed_at desc
  limit 1;
$$;

grant execute on function latest_fitness_snapshot() to authenticated;
