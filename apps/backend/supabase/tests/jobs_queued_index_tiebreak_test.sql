-- Pin the queued-jobs partial index to claim_next_job's ORDER BY.
--
-- 20270423_001 replaced `jobs_queued (scheduled_at, kind)` with
-- `jobs_queued_v2 (scheduled_at, id) WHERE status='queued'` so the
-- worker's claim query (`order by scheduled_at, id limit 1`) walks the
-- b-tree in claim order with no in-memory tie-break sort under a
-- same-scheduled_at burst.
--
-- Asserted by LEADING COLUMNS + the status='queued' predicate rather
-- than by index name for the shape, and by name-absence for the drop, so
-- the claim access path is guaranteed: the test fails the moment the
-- (scheduled_at, id) WHERE status=queued index disappears or the stale
-- (scheduled_at, kind) index reappears.

begin;

select plan(3);

-- The replacement partial index exists with the right leading columns +
-- predicate. indkey[0]/[1] are the 1-based attnums of the index's
-- leading key columns.
select ok(
  exists (
    select 1
    from pg_index ix
    join pg_class t on t.oid = ix.indrelid
    join pg_class i on i.oid = ix.indexrelid
    join pg_am am on am.oid = i.relam
    where t.relnamespace = 'public'::regnamespace
      and t.relname = 'jobs'
      and am.amname = 'btree'
      and ix.indpred is not null  -- partial
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[0]) = 'scheduled_at'
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[1]) = 'id'
      and pg_get_expr(ix.indpred, ix.indrelid) like '%status%queued%'
  ),
  'jobs has a partial btree index leading (scheduled_at, id) WHERE status=queued'
);

-- The named replacement is present.
select has_index(
  'public', 'jobs', 'jobs_queued_v2',
  'jobs_queued_v2 exists'
);

-- The stale (scheduled_at, kind) index is gone.
select ok(
  not exists (
    select 1
    from pg_class i
    join pg_namespace n on n.oid = i.relnamespace
    where n.nspname = 'public' and i.relname = 'jobs_queued'
  ),
  'the old jobs_queued index no longer exists'
);

select * from finish();

rollback;
