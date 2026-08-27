-- challenges_goal_ck: a stored goal must be positive, and a `streak_days` goal
-- must fit inside the challenge's own window.
--
-- `challenges.goal_value` has carried no constraint at all since 20270209_001.
-- Two shapes get through today and both are silent:
--
--   * goal_value = 0 (or negative). `recompute_challenge_completion` returns
--     early only on a NULL goal, then compares `v_value >= v_goal` with no
--     floor — so a stored 0 awards the completion badge, the completed_at
--     stamp and a `challenge_complete` notification to every participant on
--     the next `sweep_challenge_completions()` run. Both clients meanwhile
--     render the board as goal-less (`progressFraction` / `isComplete` treat
--     `goal <= 0` as "no goal"), so nothing on screen ever contradicts it.
--     Web's editor admits it outright: the field carries `min="0"`.
--
--   * a `streak_days` goal larger than the number of days its window holds.
--     The aggregate counts `count(distinct (started_at at time zone 'UTC')::date)`
--     over `[starts_at, ends_at)`, so the most days it can ever return is the
--     number of calendar dates a window that long can touch — the challenge is
--     unwinnable from the moment it is created, and there is nothing on the
--     detail page that says so.
--
-- `streak_days` is the ONLY metric its own window bounds. `duration` looks
-- like a second one and is not: the aggregate sums `duration_s` over runs
-- whose START falls inside the window, and a run begun a minute before it
-- closes contributes its whole duration — a 112-hour Moab finish included —
-- so a duration goal longer than its window is reachable and is deliberately
-- left alone. `distance`, `vert` and `activity_count` are unbounded outright.
--
-- The ceiling is `floor(window_seconds / 86400) + 1`, which is the number of
-- dates a window of that length touches when it opens just after midnight.
-- Deliberately the LOOSE bound — a window ending exactly at midnight UTC
-- touches one date fewer — because refusing a goal the aggregate could in
-- principle award is worse than admitting one it cannot. The clients compute
-- the identical expression in `maxStreakDaysInWindow` (web
-- `social/challenge_goal.ts` ↔ mobile `challenge_goal.dart`), so the refusal
-- is named inline before the insert rather than arriving as a raw 23514.
-- Every term is immutable timestamptz arithmetic, so it is legal in a CHECK;
-- `(x at time zone 'UTC')::date` is only STABLE and is not.
--
-- Detection queries to run before applying to a populated instance — both
-- must return 0, or the VALIDATE below fails and the offending rows need
-- their goal or window corrected first:
--
--   select count(*) from challenges
--    where goal_value is not null and goal_value <= 0;
--
--   select count(*) from challenges
--    where metric = 'streak_days' and goal_value is not null
--      and goal_value > floor(extract(epoch from (ends_at - starts_at)) / 86400) + 1;
--
-- Online-safe two-step per docs/backend/migration_locks.md: the NOT VALID add
-- takes ACCESS EXCLUSIVE for a metadata flip only, and the VALIDATE scan runs
-- under SHARE UPDATE EXCLUSIVE with readers and writers proceeding.

alter table challenges
  add constraint challenges_goal_ck
  check (
    goal_value is null
    or (
      goal_value > 0
      and (
        metric <> 'streak_days'
        or goal_value <= floor(extract(epoch from (ends_at - starts_at)) / 86400) + 1
      )
    )
  ) not valid;

alter table challenges validate constraint challenges_goal_ck;

comment on constraint challenges_goal_ck on challenges is
  'A stored goal is positive (0 completes for everyone via '
  'recompute_challenge_completion) and, for streak_days, no larger than the '
  'distinct UTC dates the window can touch. Mirrored client-side by '
  'checkChallengeGoal / maxStreakDaysInWindow on both platforms.';
