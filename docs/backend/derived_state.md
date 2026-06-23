# Derived state — the cache contract

Several columns and tables in the schema are **denormalised caches**: their
value is a function of other rows, maintained eagerly by a trigger so reads
don't recompute it. Each one is a "the cache must equal this query" invariant
that lives only in a trigger body — easy to break silently (the
`refresh_personal_records_for_user` function has already been clobbered twice by
bare-body `create or replace` rewrites; see [`apps/backend/CLAUDE.md` § Bare-body
trap](../../apps/backend/CLAUDE.md)).

This file is the registry of record for those caches: for each one, the
**authoritative recompute** (the query the cache must always equal), the
**trigger / writer** that maintains it, a **manual rebuild** command, and the
**pgtap** that pins it. When you touch a trigger that maintains one of these,
re-read its row here and confirm the recompute still holds — and never edit the
authoritative query in one place without the other.

F9 (audit-db-optimization) is the reason this file exists; it also flagged that
several of these had no written contract and one (`user_coach_usage`) had a
retention cron referenced in a comment that was never created.

---

## `personal_records`

- **What it caches:** per-user best efforts (fastest time per distance bracket,
  embedded best efforts within longer runs), de-duplicated against DNF runs.
- **Authoritative recompute:** the body of `refresh_personal_records_for_user(p_user_id)`
  — the cumulative result of the widened brackets (`20260528000002`),
  embedded-best efforts (`20260529000002`), DNF exclusion (`20260530000001`),
  mile bracket (`20261021_001`), and the auth guard (`20260904_001`),
  consolidated by `20261009_001`. The live body is the **latest** migration that
  touches the function — read it, don't reconstruct from the originals.
- **Maintained by:** trigger on `runs` insert/delete calling the refresher.
- **Manual rebuild:** `select refresh_personal_records_for_user(id) from auth.users;`
- **Pinned by:** `personal_records_cache_invariants_test.sql` (mutate a run, assert
  the cache matches the authoritative query), plus the brackets / DNF / embedded /
  mile suites.
- **Trap:** this function is the canonical bare-body casualty. Any new migration
  that does `create or replace function refresh_personal_records_for_user` must
  patch the **latest** body, not rewrite from scratch.

## `routes.run_count`

- **What it caches:** how many *public* runs are matched to a route. Private
  runs are deliberately excluded so a public viewer can't infer that private
  activity occurred against a route (`20260716_001`).
- **Authoritative recompute:** `count(*) from runs where route_id = <route> and
  is_public = true and is_route_visible_to(route_id, user_id)`.
- **Maintained by:** `routes_run_count_trigger()` (AFTER INSERT/DELETE/UPDATE OF
  route_id on `runs`), gated on `is_public = true` + route visibility
  (`20260628_001` + `20260716_001`).
- **Known drift (accepted):** the trigger fires on `route_id` change, not on an
  `is_public` flip, so a run toggled public↔private after creation does not
  re-count until its `route_id` is next touched (`20260716_001`). The function
  carries the flip delta logic defensively, but the watch-list intentionally
  omits `is_public`.
- **Manual rebuild:** `update routes r set run_count = (select count(*) from runs
  where route_id = r.id and is_public = true);` (a bare `count(*)` would
  overcount by including private runs and leave the cache permanently above
  what the trigger maintains).

## `gym_workouts.set_count` / `gym_workouts.volume_kg`

- **What it caches:** the number of sets in a workout and its total
  `sum(reps * weight_kg)`. Lets the `activities` view's lift branch read flat
  columns instead of two correlated subqueries per workout row (F7).
- **Authoritative recompute:** for a workout `w`,
  `count(*)` and `sum(coalesce(reps,0) * coalesce(weight_kg,0))` over
  `gym_sets where workout_id = w.id` (0 when there are no sets).
- **Maintained by:** `gym_sets_maintain_totals()` (AFTER INSERT/UPDATE/DELETE on
  `gym_sets`), which calls `refresh_gym_workout_totals(workout_id)` for the
  affected workout(s). The refresh recomputes from scratch (not an increment) so
  a partial-update bug can't accumulate drift; an UPDATE that moves a set between
  workouts refreshes both. Migration `20261214_001`.
- **Manual rebuild:** `select refresh_gym_workout_totals(id) from gym_workouts;`
- **Pinned by:** `gym_workout_totals_test.sql` (insert/update/delete a set, assert
  both the columns and the view summary track the recompute).

## `user_coach_usage`

- **What it caches:** per-(user, UTC day) AI-coach message count. The cap RPCs
  (`increment` / `get` / `decrement_coach_usage`, `20261002_001`) read a rolling
  24h sum across today's bucket plus yesterday's when the window straddles UTC
  midnight.
- **Authoritative read:** `sum(message_count) where user_id = ? and usage_date >=
  (now() - interval '24 hours')::date`. The table is the source of truth — there
  is no separate cache to reconcile, but it IS denormalised time-bucketed state
  with a retention obligation.
- **Retention:** `cleanup_stale_user_coach_usage()` deletes buckets older than 7
  days (a margin over the ~2-day rolling read window), scheduled hourly via
  pg_cron `cleanup-stale-user-coach-usage`. Migration `20261215_001` — this is
  the cron that `20261002_001`'s comment referenced but that was never created
  (F9). Without it the table grows one row per user per day forever.
- **Manual rebuild:** none — it is the source of truth, not a derived copy. The
  retention purge is the only maintenance.
- **Pinned by:** `user_coach_usage_retention_test.sql` (stale bucket purged, fresh
  bucket + cap read survive).

## `fitness_snapshots`

- **What it stores:** an append-only time series of computed fitness metrics
  (VDOT, VO2 max, the ATL/CTL/TSB load trio) — one row per computation, source
  tagged `'server'` | `'client'`. The advisor reads the **latest** row per user;
  trend charts read a window. Migration `20260507_001`.
- **Contract:** this is NOT a single-value cache (no "the cache must equal this
  query" invariant — each row is an immutable historical computation). It is
  derived-from-runs state with an **unbounded-growth** risk: no endpoint writes
  it yet, but once a background job emits one snapshot per user per day, the table
  accumulates indefinitely (`computed_at` indexes reads, nothing purges).
- **Retention obligation (when a writer ships):** the snapshot writer must land
  with a retention policy — keep the latest-per-user plus a downsampled history
  window (e.g. daily for 90 days, weekly beyond), or a `cleanup_stale_*` cron in
  the `derived_state` pattern above. Do not ship the writer without it; add the
  cron + a pgtap mirroring `user_coach_usage_retention_test.sql`. Until a writer
  exists this is a documented obligation, not live code.

---

## `challenges.participant_count`

- **What it caches:** how many participants a challenge has (rows in
  `challenge_participants` for that challenge). Lets the ranked Browse feed
  (`browse_public_challenges`) score + paginate without aggregating participants
  at read time (`20270308_001`).
- **Authoritative recompute:** `count(*) from challenge_participants where
  challenge_id = <challenge>`.
- **Maintained by:** `sync_challenge_participant_count()` (AFTER INSERT/DELETE on
  `challenge_participants`), SECURITY DEFINER — a runner joining a challenge they
  don't own has no UPDATE grant on the `challenges` row (the update RLS policy is
  creator/club-admin only), so the recompute must bypass it. Recompute-from-`count(*)`
  (not ±1) is self-healing — the cache can't drift.
- **Known drift (accepted):** the column is writable by the challenge's
  creator/club-admin via the normal `challenges` UPDATE policy (no column lock).
  The client never writes it (`createChallenge`/`updateChallenge` omit it) and the
  next join/leave recomputes from source, so a hand-forged value self-heals and
  only ever skews the ranking of the forger's own public challenge.
- **Manual rebuild:** `update challenges c set participant_count = (select count(*)
  from challenge_participants p where p.challenge_id = c.id);`
- **Pinned by:** `challenge_browse_test.sql` (asserts cache == count(*) on insert +
  decrement on delete).

---

## Adding a new derived cache

When you add a trigger-maintained denormalised column or a derived table:

1. Add a row to this file: authoritative recompute, trigger/writer, manual
   rebuild, retention (if it grows), pgtap.
2. Recompute from scratch in the trigger where it's cheap (one parent's children)
   rather than incrementing — drift-proof beats a micro-optimisation.
3. Add a pgtap that mutates the source and asserts the cache equals the
   authoritative query. That test is what catches the next bare-body clobber.
4. If the cache is a growing table (per-day / per-event rows), give it a
   `cleanup_stale_*` SECURITY DEFINER purge + a pg_cron schedule in the same
   migration. An unbounded high-write table is a cost surprise waiting to happen.
