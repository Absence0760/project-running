-- audit:coach May 2026 High #3 — mid-stream provider failure consumes
-- the daily slot. The handler calls `increment_coach_usage` before
-- the provider stream begins; if Anthropic drops mid-stream (or the
-- provider client throws synchronously) the slot is gone and the
-- user got a half-baked answer (or no answer). The "burned a slot
-- for nothing" failure mode generates DSARs + support tickets.
--
-- Fix: a paired `decrement_coach_usage` RPC the handler can call on
-- the unhappy path. Same caller-identity guard as the sibling
-- functions (post-20260930_001 — the `v_role <> ''` short-circuit
-- is gone). Floors the counter at 0 so a double-decrement (defence-
-- in-depth retry) doesn't push it negative.
--
-- The RPC is intentionally fail-soft — if the row doesn't exist for
-- today (which shouldn't happen if `increment_coach_usage` ran first
-- but is possible with a race) it's a no-op rather than a raise.
-- The caller is already on the unhappy path; raising here just
-- masks the original error.

create or replace function decrement_coach_usage(p_user_id uuid)
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
  -- Same authoritative guard as increment_coach_usage. Drop the
  -- `v_role <> ''` short-circuit per 20260930_001's lesson.
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'decrement_coach_usage: not authorized'
      using errcode = '42501';
  end if;

  -- Floor at 0. greatest() handles the "row exists but count = 0"
  -- and "double-decrement" cases the same way: zero stays zero.
  update user_coach_usage
    set message_count = greatest(0, message_count - 1)
    where user_id = p_user_id and usage_date = current_date
    returning message_count into v_count;

  -- coalesce: no row today → caller probably already at zero.
  return coalesce(v_count, 0);
end;
$$;

revoke execute on function decrement_coach_usage(uuid) from public, anon;
grant execute on function decrement_coach_usage(uuid) to authenticated;

comment on function decrement_coach_usage(uuid) is
  'GDPR Art 5(1)(c) / billing-correctness companion to '
  'increment_coach_usage. Called by the coach handler on synchronous '
  'provider error or mid-stream disconnect so the user is not '
  'charged a daily-cap slot for a failed answer. Idempotent — '
  'extra decrements floor at 0. See audit/coach May 2026 High #3.';
