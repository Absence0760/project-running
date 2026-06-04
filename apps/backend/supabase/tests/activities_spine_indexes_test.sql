-- MM3 (Round 5): pin the cross-modality "spine" indexes.
--
-- The `activities` view UNION-ALLs the three modality tables and is read
-- windowed (`where user_id = ? order by started_at desc limit N`). For that to
-- plan as a per-branch ordered index scan merged + limited — rather than a full
-- UNION materialise + sort — every base table needs a btree index leading with
-- (user_id, started_at). The lift load-curve query and the view's per-workout
-- set_count / volume subqueries additionally need gym_sets keyed by workout_id.
--
-- Those indexes exist today (runs_user_started_at, gym_workouts_user,
-- food_log_user, gym_sets_workout), but they're fragile:
--   * food_log_user was DEFINED on (user_id, logged_at); 20261208_001 renamed
--     logged_at -> started_at and the index silently followed by column number.
--     A future edit that drops + recreates it under the old column name would
--     break the spine without any error.
--   * any migration that "tidies" an index could drop a leading column.
--
-- This test asserts the spine by LEADING COLUMNS (not index name), so it
-- survives renames but fails the moment the (user_id, started_at) / workout_id
-- access path disappears.

begin;

select plan(4);

-- Reusable predicate: does `tbl` have a btree index whose first two key
-- columns are exactly (col0, col1)?  indkey[0]/[1] are the 1-based attnums of
-- the index's leading key columns.
create or replace function pg_temp.has_leading_index(
  tbl text, col0 text, col1 text
) returns boolean language sql stable as $fn$
  select exists (
    select 1
    from pg_index ix
    join pg_class t on t.oid = ix.indrelid
    join pg_class i on i.oid = ix.indexrelid
    join pg_am am on am.oid = i.relam
    where t.relnamespace = 'public'::regnamespace
      and t.relname = tbl
      and am.amname = 'btree'
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[0]) = col0
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[1]) = col1
  );
$fn$;

select ok(
  pg_temp.has_leading_index('runs', 'user_id', 'started_at'),
  'runs has a btree index leading with (user_id, started_at)'
);

select ok(
  pg_temp.has_leading_index('gym_workouts', 'user_id', 'started_at'),
  'gym_workouts has a btree index leading with (user_id, started_at)'
);

select ok(
  pg_temp.has_leading_index('food_log', 'user_id', 'started_at'),
  'food_log has a btree index leading with (user_id, started_at) (survives the logged_at rename)'
);

select ok(
  pg_temp.has_leading_index('gym_sets', 'workout_id', 'set_index'),
  'gym_sets has a btree index leading with (workout_id, set_index) for the load-curve join + view subqueries'
);

select * from finish();

rollback;
