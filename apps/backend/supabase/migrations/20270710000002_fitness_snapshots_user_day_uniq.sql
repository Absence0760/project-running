-- The guarantee itself: one fitness snapshot per runner per UTC day.
--
-- Its own file so the ACCESS EXCLUSIVE the build takes is a short window of
-- its own rather than an extension of `20270710000001`'s, and so a build that
-- trips on a duplicate leaves that migration applied and this one retryable.
-- `CONCURRENTLY` is unavailable here — it cannot run inside a transaction
-- block and the apply path wraps every migration file in one.
--
-- The blast radius of the build is `fitness_snapshots` alone, and nothing but
-- the dashboard's own fitness card reads or writes it: no view, no RPC, no
-- trigger on another table, and no Edge Function names it. The card degrades
-- to "not enough data yet" while the build holds.
--
-- Plain columns rather than an expression, because PostgREST's `on_conflict`
-- takes a column list — this is the shape a browser upsert can name. NULLs are
-- distinct in a unique index, which costs nothing here: `20270710000001`
-- removed the legacy NULLs and its BEFORE INSERT trigger makes a new one
-- unreachable.
create unique index fitness_snapshots_user_day_uniq
  on fitness_snapshots (user_id, snapshot_day);

comment on index fitness_snapshots_user_day_uniq is
  'One snapshot per runner per UTC day. Upsert target for the /dashboard '
  'mount write: on_conflict=user_id,snapshot_day. Before it, every mount '
  'inserted, and fetchFitnessSnapshots(60) returned a fortnight of duplicates '
  'in place of the multi-month trend.';
