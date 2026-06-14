-- Pin the partial index that serves the hot "how many are going to this
-- instance" count (stripe-events-webhook confirm-time recheck,
-- events-checkout precheck, the 20261018 capacity trigger, the 20270122
-- next-instance going counts).
--
-- Asserted by LEADING COLUMNS + the status='going' predicate rather than by
-- index name, so it survives a rename but fails the moment the partial
-- (event_id, instance_start) WHERE status='going' access path disappears and
-- the going count falls back to scanning the full (event_id, instance_start)
-- slice with a heap re-check on status.

begin;

select plan(1);

select ok(
  exists (
    select 1
    from pg_index ix
    join pg_class t on t.oid = ix.indrelid
    join pg_class i on i.oid = ix.indexrelid
    join pg_am am on am.oid = i.relam
    where t.relnamespace = 'public'::regnamespace
      and t.relname = 'event_attendees'
      and am.amname = 'btree'
      and ix.indpred is not null  -- partial
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[0]) = 'event_id'
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[1]) = 'instance_start'
      and pg_get_expr(ix.indpred, ix.indrelid) like '%status%going%'
  ),
  'event_attendees has a partial btree index leading (event_id, instance_start) WHERE status=going'
);

select * from finish();

rollback;
