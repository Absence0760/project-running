-- Add caller-identity guard to increment_coach_usage and get_coach_usage.
--
-- Both functions are security definer and were granted to all authenticated
-- users, so any authenticated caller could pass an arbitrary p_user_id to
-- read or exhaust another user's daily quota. The guard below rejects any
-- call where the JWT subject does not match the requested user id.

create or replace function increment_coach_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() != p_user_id then
    raise exception 'not authorized';
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
begin
  if auth.uid() != p_user_id then
    raise exception 'not authorized';
  end if;
  return coalesce(
    (select message_count from user_coach_usage
     where user_id = p_user_id and usage_date = current_date),
    0
  );
end;
$$;
