-- event_pricing: replace the two PARTIAL unique indexes with one non-partial
-- arbiter, so an upsert can actually name a conflict target.
--
-- 20261229_001 gave the table two partial unique indexes (one WHERE
-- instance_start IS NULL, one WHERE it IS NOT NULL) because a plain unique
-- constraint treats NULLs as distinct and would allow many series rows.
-- Postgres can only infer a PARTIAL index as an ON CONFLICT arbiter when the
-- statement itself carries a WHERE clause matching the index predicate, and
-- PostgREST never emits one -- so `setEventPricing`'s upsert raised 42P10
-- ("there is no unique or exclusion constraint matching the ON CONFLICT
-- specification") on BOTH branches, 100% of the time. A price could never be
-- attached to an event, and events-checkout requires an event_pricing row, so
-- the whole paid-registration rail was unreachable.
--
-- NULLS NOT DISTINCT (PG15+) expresses the same invariant in ONE non-partial
-- index: at most one series row per event (the NULLs collide) and at most one
-- row per overridden instance. Being non-partial, it is inferable, so
-- `ON CONFLICT (event_id, instance_start)` resolves for both branches.
--
-- Not CONCURRENTLY: the release path applies each migration inside a
-- transaction, and this table is bounded by priced events (zero rows in prod
-- today, precisely because of the bug above), so the build is instant.

create unique index event_pricing_event_instance_uniq
  on event_pricing (event_id, instance_start) nulls not distinct;

drop index event_pricing_series_uniq;
drop index event_pricing_instance_uniq;

comment on index event_pricing_event_instance_uniq is
  'One series row (instance_start IS NULL) plus at most one row per overridden '
  'instance. NULLS NOT DISTINCT keeps the NULL rows unique without a partial '
  'predicate, which is what makes it inferable as an ON CONFLICT arbiter -- the '
  'two partial indexes it replaces made every upsert fail with 42P10.';
