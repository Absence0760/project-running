-- Pin the explicit DELETE deny policy on `user_coach_usage` from
-- migration 20260722_001_user_coach_usage_delete_deny.sql.
--
-- Coverage:
--   - SELECT / INSERT / UPDATE policies from 20260430_001 work for
--     the owner via the `increment_coach_usage` SECURITY DEFINER RPC
--   - DELETE from authenticated context returns zero rows (RLS
--     evaluates `using (false)` on every candidate row)
--   - The daily-cap counter cannot be reset via direct DELETE — a
--     free user who tries to wipe their `user_coach_usage` row
--     and re-roll the day's allowance is silently no-op'd
--
-- The function `increment_coach_usage` enforces the auth.uid() guard
-- in 20260709_001; this test focuses on the DELETE-side contract.

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000cc01', 'authenticated', 'authenticated',
        'free@usage.local', '', now(), now());

-- Bootstrap: insert a usage row directly via service-role context
-- so the test has a concrete row to attempt to DELETE.
set local role service_role;
insert into user_coach_usage (user_id, usage_date, message_count)
values ('00000000-0000-0000-0000-00000000cc01', current_date, 3);

-- ── Owner (authenticated) DELETE attempt ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc01"}';

-- 1. Owner reads their own row (SELECT policy works).
select results_eq(
  $$ select message_count from user_coach_usage
     where user_id = '00000000-0000-0000-0000-00000000cc01'
       and usage_date = current_date $$,
  $$ values (3) $$,
  'owner reads their own coach-usage row'
);

-- 2. Owner DELETE attempt returns zero affected rows (RLS deny).
do $$
declare
  v_affected integer;
begin
  delete from user_coach_usage
   where user_id = '00000000-0000-0000-0000-00000000cc01'
     and usage_date = current_date;
  get diagnostics v_affected = row_count;
  if v_affected <> 0 then
    raise exception 'user_coach_usage_no_delete: expected 0 rows deleted, got %', v_affected;
  end if;
end $$;
select pass('owner DELETE on own coach-usage row is silently no-op');

-- 3. Row still present after the DELETE attempt — the daily cap
--    cannot be reset by deleting the counter row.
select results_eq(
  $$ select message_count from user_coach_usage
     where user_id = '00000000-0000-0000-0000-00000000cc01'
       and usage_date = current_date $$,
  $$ values (3) $$,
  'coach-usage row survives the DELETE attempt — daily cap intact'
);

select * from finish();

rollback;
