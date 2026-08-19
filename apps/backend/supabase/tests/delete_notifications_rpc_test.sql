-- delete_notifications(uuid[]) — one dismiss, one transaction.
--
-- The client used to serialise the id list into a PostgREST `in` filter, which
-- rides the request URL: past the gateway's request-line budget the DELETE
-- matched nothing and still answered 200, so a >100-row dismiss silently
-- deleted nothing (decisions § 653). Chunking that list fixed the no-op and
-- bought partiality — chunk 3 of 5 can fail with the undo offer already spent.
-- The RPC's array argument travels in the POST body, so there is nothing left
-- to chunk, and one call is one statement in one transaction.
--
-- What is pinned here: the >100 case that started it, the RLS boundary that
-- keeps the function SECURITY INVOKER honest, all-or-nothing under a failure
-- mid-batch, the explicit refusal past the cap, and the empty no-op.

begin;

select plan(14);

-- ── shape ────────────────────────────────────────────────────────────────
--
-- SECURITY INVOKER is the authorisation story: RLS decides whose rows go, so
-- there is no hand-written owner predicate that can drift from the policy.
select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_notifications'),
  false,
  'delete_notifications is SECURITY INVOKER, so the RLS delete policy applies');

-- A per-id or per-chunk loop that caught its own failures would delete a
-- prefix and report success — the partiality this RPC exists to remove.
select is(
  (select count(*)::int from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_notifications'
      and p.prosrc ~* 'exception\s+when'),
  0,
  'the body carries no exception handler — a failure cannot be swallowed mid-batch');

select is(
  has_function_privilege('authenticated', 'public.delete_notifications(uuid[])', 'execute'),
  true, 'authenticated may call delete_notifications');

select is(
  has_function_privilege('anon', 'public.delete_notifications(uuid[])', 'execute'),
  false, 'anon may not call delete_notifications');

-- ── fixtures ─────────────────────────────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000df000001', 'authenticated', 'authenticated', 'owner@df.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000df000002', 'authenticated', 'authenticated', 'other@df.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('00000000-0000-0000-0000-0000df000001', 'Owner'),
  ('00000000-0000-0000-0000-0000df000002', 'Other') on conflict (id) do nothing;

-- 150 rows: past the `in`-filter budget that returned an empty match.
insert into notifications (id, user_id, kind)
select ('aaaaaaaa-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-0000df000001', 'follow'
from generate_series(1, 150) i;

-- A second, independent batch for the mid-batch-failure case.
insert into notifications (id, user_id, kind)
select ('bbbbbbbb-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-0000df000001', 'follow'
from generate_series(1, 10) i;

insert into notifications (id, user_id, kind)
select ('cccccccc-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-0000df000002', 'follow'
from generate_series(1, 3) i;

-- ── empty is a no-op, not an error ───────────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000df000001","role":"authenticated"}';

select is(delete_notifications('{}'::uuid[]), 0,
  'an empty array is a no-op returning 0, not an error');
select is(delete_notifications(null), 0,
  'a null array is a no-op returning 0, not an error');

-- ── the RLS boundary ─────────────────────────────────────────────────────

select is(
  delete_notifications(array(
    select ('cccccccc-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid
    from generate_series(1, 3) i)),
  0,
  'naming another user''s notifications deletes nothing and says so');

reset role;
select set_config('request.jwt.claims', null, true);

select is(
  (select count(*)::int from notifications
    where user_id = '00000000-0000-0000-0000-0000df000002'),
  3, 'the other user''s notifications are untouched');

-- ── all or nothing under a failure mid-batch ─────────────────────────────
--
-- A row trigger that raises on one member of the batch stands in for any
-- server-side failure part-way through. PostgREST runs the RPC in one
-- transaction, so what a client observes is exactly what this savepoint
-- models: the call raises and NOTHING went, including the ids a chunked
-- client would already have committed in an earlier round-trip.

create function _df_poison_notification_delete() returns trigger
language plpgsql as $$
begin
  if old.id = 'bbbbbbbb-0000-4000-8000-000000000010' then
    raise exception 'poisoned row';
  end if;
  return old;
end;
$$;

create trigger _df_poison_notification
  before delete on notifications
  for each row execute function _df_poison_notification_delete();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000df000001","role":"authenticated"}';

select throws_ok(
  format('select delete_notifications(%L::uuid[])',
    (select array_agg(('bbbbbbbb-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid)
     from generate_series(1, 10) i)),
  null, 'poisoned row',
  'a failure on one member fails the whole call');

reset role;
select set_config('request.jwt.claims', null, true);

select is(
  (select count(*)::int from notifications
    where id::text like 'bbbbbbbb-%'),
  10, 'every member of the failed batch is still there — no partial dismiss');

drop trigger _df_poison_notification on notifications;
drop function _df_poison_notification_delete();

-- ── the cap refuses, it does not truncate ────────────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000df000001","role":"authenticated"}';

select throws_ok(
  format('select delete_notifications(%L::uuid[])',
    (select array_agg(id) from (
       select ('aaaaaaaa-0000-4000-8000-' || lpad(1::text, 12, '0'))::uuid as id
       union all
       select gen_random_uuid() from generate_series(1, 1000)
     ) s)),
  '22023', null,
  'past the cap the call raises rather than silently truncating the list');

reset role;
select set_config('request.jwt.claims', null, true);

select is(
  (select count(*)::int from notifications
    where id::text like 'aaaaaaaa-%'),
  150, 'the refused over-cap call deleted no prefix');

-- ── the case that started it: a >100-id dismiss ──────────────────────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000df000001","role":"authenticated"}';

select is(
  delete_notifications(array(
    select ('aaaaaaaa-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid
    from generate_series(1, 150) i)),
  150, 'a 150-id dismiss deletes all 150 in one call');

reset role;
select set_config('request.jwt.claims', null, true);

select is(
  (select count(*)::int from notifications where id::text like 'aaaaaaaa-%'),
  0, 'none of the 150 survive — the >100 silent no-op is gone');

select * from finish();

rollback;
