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
- **Eligible sources:** `app`, `watch`, `strava`, `garmin`, `healthkit`,
  `healthconnect`, `parkrun`, `race` — every valid `runs.source` value. `parkrun`
  (weekly certified 5K) and `race` (chip-timed official results) were added by
  `20270424_001` (#378); before that both were silently excluded, so a fastest 5K
  run at parkrun never earned a PR. `award_achievements_for_user` uses the
  identical source list so distance badges and PRs agree on what counts.
- **Eligible activity types:** the **run family** — every `runs.activity_type`
  except `cycle` (`20270514_001`). A bicycle covers a PR bracket at speeds no
  runner reaches, so before that migration a 5 km ride at 9:00 permanently
  displaced the runner's genuine 25:00 5K, and an 80 km ride earned the 50 km
  `distance_single` platinum badge. The rule is the client's, not a new one:
  `recap.ts` / `recap.dart` gate every "longest" / "fastest" claim on
  `isRunFamily = (activity_type ?? 'run') !== 'cycle'`. The split is deliberate
  — **`award_achievements_for_user` applies it to `distance_single` only**;
  `distance_lifetime` and the streak stay cross-modal, matching the same
  helper's cross-modal totals and the client `computeRunStreaks`, which is fed
  every activity type. Already-granted badges are never revoked (the awarder is
  insert-on-conflict-do-nothing and has never revoked anything).
- **Authoritative recompute:** the body of `refresh_personal_records_for_user(p_user_id)`
  — the cumulative result of the widened brackets (`20260528000002`),
  embedded-best efforts (`20260529000002`; read from the promoted
  `runs.fastest_*_s` columns since `20270325_001`), DNF exclusion
  (`20260530000001`), mile bracket (`20261021_001`), the auth guard
  (`20260904_001`), consolidated by `20261009_001`, the parkrun/race source
  widening (`20270424_001`), and the positive-time filters (`20270706000003`).
  The live body is the **latest** migration that
  touches the function — read it, don't reconstruct from the originals.
- **Every candidate time is positive** (`20270706000003`, decisions § 1078).
  `runs_duration_s_check` is `duration_s >= 0` on purpose — a run imported with
  a distance and no time is a row we store — and the whole-run branch had no
  positivity filter at all, so a zero-second run in a PR bracket became the
  FASTEST candidate for it and reached this cache, where
  `personal_records_best_time_s_check` refused it. That refusal happens inside
  an AFTER trigger on `runs`, so the 23514 failed the INSERT of the run:
  measured, an ordinary session could not save
  `(duration_s => 0, distance_m => 5000, source => 'app')` at all. The four
  embedded-best branches read `>= 0` and are tightened with it. The bound
  belongs here rather than on the column — not having run 5 km in zero seconds
  is a PR-eligibility rule, not a storage rule.
- **Maintained by:** statement-level AFTER INSERT/UPDATE/DELETE triggers on
  `runs` (`20270315_001`; per-row until then) calling the refresher once per
  statement per affected `user_id` from the transition tables — a bulk import
  of N runs costs one full recompute per chunk, not N. The UPDATE path only
  refreshes users whose `distance_m` / `duration_s` / `source` / `user_id` /
  `is_dnf` / `fastest_{5k,10k,half_marathon,marathon}_s` values actually
  changed (the old trigger's OF column list, moved in-function because
  transition tables forbid column lists; `metadata` left the watch list with
  the embedded-best promotion, `20270325_001`, and `activity_type` joined it
  with the run-family filter, `20270514_001` — a re-typed run changes what the
  authoritative query returns, so it has to re-derive), and refreshes both the
  old and new owner on a `user_id` change. `trigger_award_achievements_runs`
  watches `activity_type` for the same reason.
- **Manual rebuild:** `select refresh_personal_records_for_user(id) from auth.users;`
- **Pinned by:** `personal_records_cache_invariants_test.sql` (mutate a run, assert
  the cache matches the authoritative query), `personal_records_statement_trigger_test.sql`
  (multi-row statements refresh once per affected user and still land the
  authoritative result), `personal_records_run_family_test.sql` (a bike ride
  holds no PR and no single-run distance badge; a re-type re-derives the cache),
  `personal_records_positive_times_test.sql` (a zero-second run saves and sets
  nothing, a zero embedded best sets nothing, both with positive controls),
  plus the brackets / DNF / embedded / mile suites.
- **Trap:** this function is the canonical bare-body casualty. Any new migration
  that does `create or replace function refresh_personal_records_for_user` must
  patch the **latest** body, not rewrite from scratch.

## `routes.run_count`

- **What it caches:** how many *public* runs are matched to a route. Private
  runs are deliberately excluded so a public viewer can't infer that private
  activity occurred against a route (`20260716_001`).
- **Authoritative recompute:** `count(*) from runs where route_id = <route> and
  is_public = true and private.is_route_visible_to(route_id, user_id)`.
- **Maintained by:** `routes_run_count_trigger()` (AFTER INSERT/DELETE/UPDATE OF
  route_id on `runs`), gated on `is_public = true` + route visibility
  (`20260628_001` + `20260716_001`). Since `20270526_001` it calls
  `refresh_route_run_count(route_id)` for each affected route — the
  authoritative query above, run from scratch — instead of applying a ±1 delta.
  The delta form could not be made correct: it decided whether a decrement was
  owed by re-evaluating `is_route_visible_to` on the OLD row at trigger time,
  which reads the route's **current** visibility, not the visibility in force
  when the increment happened. A route that had since gone private answered
  "was never counted", so the run detached without giving the count back and
  the counter stayed permanently high with nothing to revisit it. That answer
  is not derivable from the row's own OLD image, so recompute is the only
  correct read.
- **Known drift (accepted):** the trigger fires on `route_id` change, not on an
  `is_public` flip, so a run toggled public↔private after creation does not
  re-count until its `route_id` is next touched (`20260716_001`); a flip on the
  *route* is likewise unwatched. Since the trigger recomputes rather than
  increments, that drift **heals** on the next `route_id` touch instead of
  compounding on top of a stale value.
- **Manual rebuild:** `select refresh_route_run_count(id) from routes;` (batch it
  by id range on a populated database — `20270526_001`'s backfill is the worked
  form). A bare `count(*)` would overcount by including private runs and runs
  whose author cannot see the route, leaving the cache permanently above what
  the trigger maintains.
- **Client writes are discarded (`20270704000003`):** the column carried no lock,
  and the `popular` lens of `discoverable_routes_in_bbox` gates on
  `featured OR run_count > 0` while `hidden_gems` excludes a route with any —
  so an author setting their own route's count promoted it into a map every
  viewer sees. `routes_freeze_managed_columns` discards a client's value, along
  with `is_featured` / `featured_at` and the three derived geometries.
- **Pinned by:** `routes_run_count_test.sql` (match, private-run exclusion, move
  between routes, delete, the went-private-then-detached decrement, the
  visibility gate, and the self-heal on the next touch — each asserted against
  the authoritative query, on a route the earlier assertions have not already
  skewed).

## `routes.geom_public`

- **What it caches:** the route's polyline **as a non-owner is allowed to see
  it** — the owner's privacy zones already clipped off (`20270509_001`). It
  exists so a public spatial predicate has zone-aware geometry to run against:
  `routes_within_box` is granted to `anon`, and running its `ST_Intersects`
  over the raw `geom` while returning the route id made it a membership oracle
  that traced the in-zone tail box by box (decisions §566). This is a privacy
  boundary, not a performance cache — a stale or missing value must never fall
  back to `geom`.
- **Authoritative recompute:** the LineString over
  `clip_track_for_user(routes.user_id, routes.waypoints)`, or `NULL` when that
  clip leaves fewer than two valid points. `privacy_aware_route_geom(waypoints,
  user_id)` **is** that query — it calls `clip_track_for_user` rather than
  re-implementing the zone walk, precisely so the cached geometry cannot drift
  away from what `clip_route_for_viewer` serves.
- **Consumers (read the cache, do NOT recompute):** `routes_within_box`, which
  fails closed on `geom_public is not null` with no `geom` fallback.
  `nearby_routes` is deliberately not a consumer — its predicate and ordering
  run on the zone-aware `start_point` (`20260925_001`).
- **Maintained by:** the same trigger pair as `start_point` —
  `routes_set_geom()` (BEFORE INSERT OR UPDATE OF waypoints on `routes`, folded
  into the existing `geom` trigger so the two columns can't be written by
  different paths) and `user_settings_recompute_route_start_points()` (AFTER
  UPDATE OF prefs on `user_settings`, short-circuited when `privacy_zones` is
  unchanged), which recomputes `start_point` and `geom_public` in one pass over
  the owner's routes. Both are SECURITY DEFINER.
- **Known drift (accepted):** the routes trigger watches `waypoints` only, so a
  `user_id` change would leave the value computed against the previous owner's
  zones. Routes never change hands today; the same assumption already underpins
  `start_point`.
- **Client writes are discarded (`20270704000003`):** that same `OF waypoints`
  watch meant a write touching only this column was never recomputed, so
  `update routes set geom_public = geom` from the route's own author stood —
  putting the in-zone tail back inside a box oracle `anon` may query.
  `routes_freeze_managed_columns` restores the previous value first and the
  derivation trigger then recomputes if `waypoints` really changed; it is named
  to sort ahead of `routes_geom_trigger`, so on INSERT it nulls the client's
  geometry and the derivation computes the real one.
- **Manual rebuild:** `update routes r set geom_public =
  privacy_aware_route_geom(r.waypoints, r.user_id) where r.geom is not null;`
  (batch it by id range on a populated database — `20270509_001`'s backfill is
  the worked form).
- **Pinned by:** `routes_within_box_geom_public_test.sql` — asserts the raw
  `geom` crosses the head box, that an anon `routes_within_box` sweep over that
  box returns nothing, that the out-of-zone body still answers, and that a
  later zone change re-clips routes saved before it.

## `gym_workouts.set_count` / `gym_workouts.volume_kg`

- **What it caches:** the number of sets in a workout and its total
  `sum(reps * weight_kg)`. Lets the `activities` view's lift branch read flat
  columns instead of two correlated subqueries per workout row (F7), and the
  `/gym` list render its per-row stats without fetching a single set
  (decisions §568 — it used to re-derive both from raw `gym_sets`).
- **Authoritative recompute:** for a workout `w`,
  `count(*)` and `sum(coalesce(reps,0) * coalesce(weight_kg,0))` over
  `gym_sets where workout_id = w.id` (0 when there are no sets).
- **Maintained by:** `gym_sets_maintain_totals()` (AFTER INSERT/UPDATE/DELETE on
  `gym_sets`), which calls `refresh_gym_workout_totals(workout_id)` for the
  affected workout(s). The refresh recomputes from scratch (not an increment) so
  a partial-update bug can't accumulate drift; an UPDATE that moves a set between
  workouts refreshes both. Migration `20261214_001`.
- **Manual rebuild:** `select refresh_gym_workout_totals(id) from gym_workouts;`
- **Client writes are discarded (`20270704000003`):** `gym_workouts_freeze_managed_columns`,
  for uniformity rather than for a measured exploit — after that migration no
  client writes a trigger-maintained cache anywhere in the schema, which is a
  rule that can be checked, where "these matter and those do not" is a judgement
  that has to be re-made every time a cache is added.
- **Pinned by:** `gym_workout_totals_test.sql` (insert/update/delete a set, assert
  both the columns and the view summary track the recompute) and
  `frozen_managed_columns_test.sql`.

## `gym_sets.exercise_key`

- **What it caches:** the exercise grouping key for one logged set —
  `normalise_exercise_name(exercise_name)`. Every RPC that groups a lifter's
  history (`gym_exercise_names`, `gym_exercise_records`,
  `gym_exercise_set_history`, `gym_exercise_set_history_batch`,
  `gym_workout_summaries`) folded the name once per `gym_sets` row inside its
  own scan until `20270706000002`; they read the column now. Measured on a
  15,000-set history the same aggregate went from 66-74 ms to 4.9-5.4 ms, and
  from 2,241 ms to 196 ms at 500,000 sets (decisions § 1076).
- **Authoritative recompute:**
  `public.normalise_exercise_name(exercise_name)`, and the validated CHECK
  `gym_sets_exercise_key_canonical` says so at the boundary rather than leaving
  it a claim. `gym_sets_exercise_key_len_chk` bounds it at the name's own 120,
  which the fold cannot exceed.
- **Maintained by:** `gym_sets_stamp_exercise_key()` (BEFORE INSERT OR UPDATE on
  `gym_sets`), migration `20270706000001`. Unqualified rather than
  `update of exercise_name`, so an UPDATE naming only the key is re-stamped
  instead of hitting a 23514 the client cannot act on.
- **Manual rebuild:**
  `update gym_sets set exercise_key = normalise_exercise_name(exercise_name)
  where exercise_key is distinct from normalise_exercise_name(exercise_name);`
  — batch it by primary-key range on a populated database
  (`migration_locks.md`), and keyset-paginate rather than re-running the
  predicate, which is O(n²/batch).
- **Client writes are discarded:** by the same trigger, and unconditionally —
  a client value is OVERWRITTEN, never refused. That used to be the difference
  from `gym_routine_exercises.exercise_key` and `exercises.name_key`, where the
  client stamped the key under a CHECK and an older Unicode case table could
  therefore produce a 23514 on a legitimate save (decisions § 830); since
  `20270711000001` all three columns are stamped the same way and the entry
  below records the other two (decisions § 1284). The trigger is not keyed on
  `current_user` as `20270704000003`'s freezes are: the value is a pure function
  of a column on the same row, so there is no writer, privileged or not, that
  should be allowed a different answer.
- **Pinned by:** `gym_sets_exercise_key_test.sql` (13 tests — the stamp on
  insert, on rename and on a key-only UPDATE, the empty key for a
  whitespace-only name, the `service_role` write, the five RPCs bucketing four
  spellings as one exercise, and a mutation that moves a stored key with the
  trigger and CHECK dropped, proving the RPCs read the column rather than
  re-folding the name).

## `gym_routine_exercises.exercise_key` / `exercises.name_key`

- **What it caches:** the same exercise grouping key as the entry above, on the
  two tables that PLAN rather than log — `normalise_exercise_name(exercise_name)`
  binds a routine's planned exercise to the sets a lifter logs, and
  `normalise_exercise_name(name)` is what the two partial unique indexes on
  `exercises` make a custom catalogue entry unique by. Unlike `gym_sets`'
  key these were never a read-path cost; they are persisted because they are the
  join key and the uniqueness key.
- **Authoritative recompute:** `public.normalise_exercise_name(<the name column>)`,
  and the validated CHECKs `gym_routine_exercises_exercise_key_canonical` /
  `exercises_name_key_canonical` (`20270623000001`) say so at the boundary. Each
  column's own `length(… between 1 and 120)` CHECK bounds it at the name's own
  120, which the fold cannot exceed.
- **Maintained by:** `gym_routine_exercises_stamp_exercise_key()` and
  `exercises_stamp_name_key()`, both BEFORE INSERT OR UPDATE, migration
  `20270711000001`. Unqualified rather than `update of <name>`, for the same
  reason as `gym_sets`: an UPDATE naming only the key is re-stamped instead of
  hitting a 23514 the client cannot act on.
- **Manual rebuild:** the `update … where <key> is distinct from
  normalise_exercise_name(<name>)` shape of the entry above, per table. It has
  never been needed: both CHECKs are VALIDATED, which is a statement about every
  row, so no row can be outside the derivation to begin with.
- **Client writes are discarded:** by the triggers, unconditionally. Before them
  a client COMPUTED these keys and the CHECK REFUSED a disagreeing value, which
  coupled the write to the client's Unicode version — 410 code points before
  decisions § 1175, 465 after, 55 newly so (§ 1252). The CHECKs stay behind the
  triggers on purpose: nothing can now violate them, so what they buy is that a
  disabled or dropped trigger fails loudly instead of silently splitting a
  lifter's history.
- **Duplicates are allowed and that is deliberate:** there is no unique index on
  `(routine_id, exercise_key)`. Two blocks of one lift in one routine is the
  heavy-top-set-then-back-off pattern, and `computeRoutineAdherence` matches on
  `(exerciseKey, stepIndex)` rather than on the key alone precisely so it works
  (decisions § 1286).
- **Pinned by:** `exercise_key_server_stamped_test.sql` (11 tests — the stamp on
  a stale-client key, on an omitted key, on a key-only UPDATE and on a rename,
  for both tables, plus a mutation that disables the trigger and requires the
  CHECK to raise 23514) and `normalise_exercise_name_test.sql`.

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
- **Writers:** the three definer RPCs and the retention cron, nothing else. No
  client verb reaches the table (migration `20270505_001` revoked
  INSERT/UPDATE/DELETE from `anon` + `authenticated` and replaced the self-write
  policies with explicit denies) — a meter the metered party can rewrite is not a
  cap.
- **Pinned by:** `user_coach_usage_retention_test.sql` (stale bucket purged, fresh
  bucket + cap read survive) + `rls_user_coach_usage_test.sql` (every client verb
  rejected, the definer RPC still meters).

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
- **Read by:** `browse_public_challenges` (server-side), and since 2026-09-05
  the two web readers as well — `fetchChallenges` and `fetchChallengeById` in
  `apps/web/src/lib/core/data.ts`, whose `select('*')` already carried the
  column. Both used to length a `challenge_participants` page instead, which is
  the shape `clubs.member_count` was created to remove (issue #331): the read
  was unbounded, PostgREST truncates a result at its configured row ceiling
  without saying so, and the same page was also scanned for the caller's own
  membership — so a popular challenge under-reported its board and could drop a
  genuine participant's row, emptying their "My challenges" tab and offering
  them "Join" on a challenge they were already in. The membership read is now
  scoped to the caller.
- **Maintained by:** `sync_challenge_participant_count()` (AFTER INSERT/DELETE on
  `challenge_participants`), SECURITY DEFINER — a runner joining a challenge they
  don't own has no UPDATE grant on the `challenges` row (the update RLS policy is
  creator/club-admin only), so the recompute must bypass it. Recompute-from-`count(*)`
  (not ±1) is self-healing — the cache can't drift.
- **Client writes are discarded (`20270704000003`):** the column used to be
  writable by the challenge's creator/club-admin through the normal `challenges`
  UPDATE policy, and this file recorded that as accepted drift on the grounds
  that the next join recomputes it. `clubs.member_count` had the same shape and
  did **not** self-heal — a club nobody joins never gets a recompute, and
  `search_clubs` sorts on it — so the whole class was closed rather than the one
  instance: `challenges_freeze_managed_columns` (a SECURITY INVOKER BEFORE
  INSERT OR UPDATE trigger keyed on `current_user`) discards a client's value
  and leaves the trigger's.
- **Manual rebuild:** `update challenges c set participant_count = (select count(*)
  from challenge_participants p where p.challenge_id = c.id);`
- **Pinned by:** `challenge_browse_test.sql` (asserts cache == count(*) on insert +
  decrement on delete) and `frozen_managed_columns_test.sql` (a client-declared
  count at INSERT lands as the cache's own value).

---

## `clubs.member_count`

- **What it caches:** how many *active* members a club has (rows in
  `club_members` for that club with `status = 'active'`). Lets `search_clubs`
  rank by size and lets the web `enrichClubs` helper render the count off the
  club row instead of re-counting the roster on every `/social` clubs render
  (`20260906_001`).
- **Authoritative recompute:** `count(*) from club_members where club_id =
  <club> and status = 'active'`.
- **Consumers (read the cache, do NOT recompute):** `search_clubs` (sort key)
  and every `enrichClubs` caller in `apps/web/src/lib/core/data.ts`
  (`browseClubs`, `searchClubs` ILIKE fallback, `fetchMyClubs`,
  `fetchClubBySlug`) — `CLUB_SELECT_COLS` selects `member_count` and
  `enrichClubs` reads `c.member_count` (issue #331; the old post-query aggregate
  is gone).
- **Maintained by:** `clubs_member_count_trigger()` (AFTER INSERT/UPDATE OF
  status, club_id/DELETE on `club_members`), SECURITY DEFINER since
  `20270205_001` — the ON DELETE CASCADE from an owner's account deletion runs
  as `supabase_auth_admin`, which lacks UPDATE on `clubs`, so the count UPDATE
  must run as the function owner (a club owner was otherwise undeletable). The
  owner is auto-enrolled active by `enroll_club_owner_trigger`, so a fresh club
  is `member_count = 1`. Since `20270526_001` it calls
  `refresh_club_member_count(club_id)` for the affected club(s) — the
  authoritative query above, run from scratch — instead of applying a ±1 delta.
  The delta form had two non-exclusive `if` blocks on UPDATE (status changed,
  club_id changed) and the trigger's own watch list is `OF status, club_id`, so
  a statement changing both ran both: approving a pending member into another
  club in one UPDATE incremented the destination twice, and demoting an active
  member while moving them decremented the source twice.
- **Client writes are discarded (`20270704000003`):** the column carried no lock
  at all, and an owner setting it to 999999 kept that value and ranked first in
  `search_clubs` — the trigger only recomputes on a `club_members` change, and a
  club nobody joins never has one, so this was the cache in the registry that
  could NOT self-heal. `clubs_freeze_managed_columns` discards a client's value,
  alongside `shadow_hidden` and `is_verified` on the same table.
- **Manual rebuild:** `select refresh_club_member_count(id) from clubs;`
- **Pinned by:** `clubs_member_count_test.sql` (mutate `club_members` through
  insert-active / insert-pending / approve / leave / demote / move club /
  move-and-approve / move-and-demote and assert the cache equals the
  authoritative active-count each time). The `club_id` half was added by
  `20270526_001`: this file previously claimed the suite "guards every branch"
  while it never changed `club_id` at all, which is how the double-count
  survived. The two combined-UPDATE cases run on their own clubs, because a
  double increment followed by a double decrement on one club cancels out and
  lets a broken trigger pass.

---

## Adding a new derived cache

When you add a trigger-maintained denormalised column or a derived table:

1. Add a row to this file: authoritative recompute, trigger/writer, manual
   rebuild, retention (if it grows), pgtap.
1b. Make the column unwritable by a client. The default column grants let the
   row's owner set any cache to any value, and a cache the metered party can
   rewrite is not a cache — `clubs.member_count` ranked a global search off a
   self-declared 999999 for as long as nobody joined the club. The shape is a
   SECURITY INVOKER BEFORE INSERT OR UPDATE trigger keyed on `current_user`
   (`20270704000003`), which discards the client's value while leaving every
   SECURITY DEFINER writer — including the maintaining trigger itself —
   untouched.
2. Recompute from scratch in the trigger where it's cheap (one parent's children)
   rather than incrementing — drift-proof beats a micro-optimisation.
3. Add a pgtap that mutates the source and asserts the cache equals the
   authoritative query. That test is what catches the next bare-body clobber.
4. If the cache is a growing table (per-day / per-event rows), give it a
   `cleanup_stale_*` SECURITY DEFINER purge + a pg_cron schedule in the same
   migration. An unbounded high-write table is a cost surprise waiting to happen.
