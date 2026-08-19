-- #789 I.3: mv_weekly_mileage was dropped in 20270530_001 because it had no
-- reader on any tier and its Monday-start / session-timezone bucketing could
-- not serve the surfaces that were claimed to read it.
--
-- This pins the drop as COMPLETE rather than partial. A half-drop is the
-- expensive failure mode: leave the pg_cron entry behind and every tick errors
-- against a missing relation, leave the relation behind and the background
-- compute returns the day someone re-adds a schedule. The relation assertion
-- also covers the grants — a privilege row cannot outlive its object — and is
-- written against pg_class with no relkind filter so re-adding the name as a
-- plain view or table fails here too, forcing the decision back through the
-- ADR rather than through a migration nobody reads.
--
-- It also pins that the drop did not take the sanctioned read path with it:
-- weekly_mileage() aggregates `runs` under auth.uid() and remains the answer
-- for any caller that wants this shape.

begin;

select plan(4);

select is(
  (select count(*)::int from pg_class
     where relnamespace = 'public'::regnamespace
       and relname = 'mv_weekly_mileage'),
  0,
  'no relation named mv_weekly_mileage exists in public (of any relkind)'
);

select is(
  (select count(*)::int from pg_class
     where relnamespace = 'public'::regnamespace
       and relname = 'mv_weekly_mileage_pk'),
  0,
  'the mv_weekly_mileage_pk unique index is gone with its matview'
);

-- Matched on the command as well as the name: a rescheduled refresh under a
-- different jobname would fire just as often and cost just as much.
select is(
  (select count(*)::int from cron.job
     where jobname = 'refresh-mv-weekly-mileage'
        or command ilike '%mv_weekly_mileage%'),
  0,
  'no pg_cron job refreshes mv_weekly_mileage under any name'
);

select has_function(
  'public', 'weekly_mileage', array['integer'],
  'the sanctioned auth.uid()-scoped weekly_mileage(integer) RPC survives the drop');

select * from finish();
rollback;
