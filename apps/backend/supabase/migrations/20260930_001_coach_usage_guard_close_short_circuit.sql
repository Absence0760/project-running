-- audit:coach May 2026 High #2.
--
-- `increment_coach_usage` and `get_coach_usage` (last touched in
-- 20260804_001) carry a broken caller-identity guard:
--
--   if v_role <> 'service_role' and v_role <> '' and
--      (auth.uid() is null or auth.uid() is distinct from p_user_id)
--
-- The `v_role <> ''` short-circuit makes the guard a no-op whenever
-- the role claim is empty — i.e. unauthenticated calls or any future
-- context where neither `request.jwt.claim.role` nor
-- `request.jwt.claims->>'role'` is populated. The function then
-- falls through and reads/increments any caller-supplied p_user_id.
--
-- Current EXECUTE grant is `to authenticated` only (migration
-- 20260430_001) so PostgREST anon callers can't reach the function
-- today — no live exploit. The defence-in-depth flaw is the entire
-- point of the in-function guard; the sibling `pr_refresh` variant
-- in 20260801_002 already does the right thing. Fix here is to drop
-- the `v_role <> ''` short-circuit and only treat `service_role` as
-- the documented bypass.

create or replace function increment_coach_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Bypass: only the documented `service_role` claim. Every other
  -- caller (incl. anon / empty / unknown) MUST match auth.uid().
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'increment_coach_usage: not authorized'
      using errcode = '42501';
  end if;
  insert into user_coach_usage (user_id, usage_date, message_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, usage_date) do update
    set message_count = user_coach_usage.message_count + 1
  returning message_count into v_count;
  return v_count;
end;
$$;

create or replace function get_coach_usage(p_user_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'get_coach_usage: not authorized'
      using errcode = '42501';
  end if;
  return coalesce(
    (select message_count from user_coach_usage
     where user_id = p_user_id and usage_date = current_date),
    0
  );
end;
$$;
