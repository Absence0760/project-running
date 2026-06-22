-- Restore the block-filter on public_profile_by_id.
--
-- 20270218_001_auto_hide_reports.sql re-emitted public_profile_by_id to add
-- the `shadow_hidden = false` filter but, writing the body from scratch,
-- dropped the `is_blocked_either_way` guard that 20261012_001_user_blocks.sql
-- had added — the bare-body create-or-replace strip trap. A blocked target's
-- profile became visible again to the blocker (user_blocks_test.sql test 9).
-- Re-emit the COMPLETE intended body: both the block guard and the shadow
-- filter.
create or replace function public_profile_by_id(p_id uuid)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  select u.id, u.display_name, u.avatar_url
  from user_profiles u
  where u.id = p_id
    and u.shadow_hidden = false
    and (auth.uid() is null
         or not is_blocked_either_way(auth.uid(), u.id));
$$;

revoke all on function public_profile_by_id(uuid) from public;
grant execute on function public_profile_by_id(uuid) to anon, authenticated;
