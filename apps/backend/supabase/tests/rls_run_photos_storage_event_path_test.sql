-- audit-findings 2026-05-30 Medium [security/storage] regression pin.
--
-- The run-photos Storage SELECT policy (20261109_001) must let an event
-- viewer read an event-tagged photo's BYTES even when the parent run is
-- private — otherwise the event gallery (whose ROW policy already opens
-- the event path) renders broken images. Inspect the policy expression
-- text directly, the same way the runs-bucket lockdown test does: a
-- future bare-body rewrite that drops the event path, the thumbnail
-- path, or the private-schema visibility fn fails here, not in prod.

begin;

select plan(4);

-- The renamed policy exists (the old name is gone).
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'run-photo bytes visible when run or event is visible'
  ),
  'run-photos Storage SELECT policy renamed to cover run OR event visibility'
);

-- The event-visibility path is present (event_id + the events subquery).
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'run-photo bytes visible when run or event is visible'
      and qual ilike '%event_id%' and qual ilike '%from events%'
  ),
  'policy delegates to event visibility for event-tagged photos'
);

-- The original run-visibility path is preserved (private-schema fn).
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'run-photo bytes visible when run or event is visible'
      and qual ilike '%is_run_photo_visible_to%'
  ),
  -- 20261125_001 swapped is_run_visible_to → is_run_photo_visible_to so the
  -- coaching link no longer leaks photo bytes (audit-storage).
  'policy gates non-event photos on owner-or-public visibility (coach-excluded)'
);

-- The thumbnail path is preserved (added by 20260826_001) — a bare-body
-- rewrite must not drop it.
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'run-photo bytes visible when run or event is visible'
      and qual ilike '%thumb_512_path%'
  ),
  'policy still matches the thumbnail path (20260826_001 preserved)'
);

select * from finish();

rollback;
