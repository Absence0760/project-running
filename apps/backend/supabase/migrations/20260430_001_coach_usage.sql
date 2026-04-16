-- Daily usage tracking for the AI Coach. Prevents a single user from
-- running up the Claude API bill unchecked. The coach endpoint
-- increments `message_count` on every request and rejects when the
-- daily limit is hit.

create table user_coach_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  message_count integer not null default 0,
  primary key (user_id, usage_date)
);

alter table user_coach_usage enable row level security;

create policy user_coach_usage_own_select
  on user_coach_usage for select
  using (auth.uid() = user_id);

create policy user_coach_usage_own_insert
  on user_coach_usage for insert
  with check (auth.uid() = user_id);

create policy user_coach_usage_own_update
  on user_coach_usage for update
  using (auth.uid() = user_id);

-- Increment-and-check in one call so the coach endpoint doesn't need
-- two round trips. Returns the new count; the caller compares against
-- the limit and rejects if exceeded.
create or replace function increment_coach_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into user_coach_usage (user_id, usage_date, message_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, usage_date) do update
    set message_count = user_coach_usage.message_count + 1
  returning message_count into v_count;
  return v_count;
end;
$$;

grant execute on function increment_coach_usage(uuid) to authenticated;

-- Read today's count without incrementing. Used by the UI to show
-- "N of M remaining" before the user types.
create or replace function get_coach_usage(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select message_count from user_coach_usage
     where user_id = p_user_id and usage_date = current_date),
    0
  );
$$;

grant execute on function get_coach_usage(uuid) to authenticated;
