-- /audit/all Medium: increment_coach_usage and get_coach_usage from
-- 20260709_001 read the JWT role via the legacy single-claim form
-- (`request.jwt.claim.role`). Newer PostgREST only populates
-- `request.jwt.claims` (jsonb blob). On the new baseline, v_role
-- coalesces to '', so `v_role <> 'service_role'` is true for a
-- service-role caller and the guard path raises 'not authorized'
-- — silently breaking the documented service-role escape hatch.
--
-- No active regression today (the coach handler uses the user-scoped
-- supabase client, never service-role for these RPCs), but the
-- documented contract is broken and a future admin-script writer
-- would hit a wall they don't expect.
--
-- Fix: same dual-claim coalesce as 20260726_001 / 20260727_001 /
-- 20260801_002.

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
  if v_role <> 'service_role' and v_role <> '' and (auth.uid() is null or auth.uid() is distinct from p_user_id) then
    raise exception 'increment_coach_usage: not authorized';
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
  if v_role <> 'service_role' and v_role <> '' and (auth.uid() is null or auth.uid() is distinct from p_user_id) then
    raise exception 'get_coach_usage: not authorized';
  end if;
  return coalesce(
    (select message_count from user_coach_usage
     where user_id = p_user_id and usage_date = current_date),
    0
  );
end;
$$;
