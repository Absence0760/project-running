-- search_user_profiles: opt-out-respecting ILIKE search for the
-- People tab.
--
-- Persona-hunt Round 3 finding Woman #2. Pre-fix, the SocialPeople
-- search on /social?tab=people (web) and the equivalent on mobile
-- did a plain ILIKE on `user_profiles.display_name`. A runner who'd
-- been stalked or harassed had no way to make themselves un-findable
-- — their account was permanently discoverable by anyone who typed
-- a few characters of their name.
--
-- We introduce a universal opt-out pref `discoverable_in_search`
-- (bool, default true for back-compat — every existing account
-- stays findable unless they actively opt out). The search runs as
-- a SECURITY DEFINER RPC so it can join `user_settings.prefs` —
-- which has owner-only RLS — to apply the filter without exposing
-- the bag.
--
-- Why a SECURITY DEFINER RPC rather than a view:
--   - The opt-out is a privacy signal: a third party MUST NOT be
--     able to determine, even by side-channel, whether a target
--     has opted out. A view that returns N rows in one case and
--     N-1 in another leaks the bit. A SECURITY DEFINER RPC keeps
--     the filter inside the function body — the caller sees only
--     the opted-in subset and has no comparable surface to probe.
--   - user_settings is owner-only by RLS; reading prefs across
--     users requires SECURITY DEFINER anyway.
--
-- Output shape mirrors the client-side ILIKE the web + mobile
-- callers used to do directly on user_profiles, so the RPC is a
-- drop-in replacement.

create or replace function search_user_profiles(
  p_query text,
  p_limit int default 60
)
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
  -- Cap the limit defensively — the caller can pass anything but
  -- we don't want a 100k-row scan from a misconfigured client.
  -- The web caller currently passes 120 (limit*3 with limit=20) so
  -- 200 gives a sensible ceiling.
  with capped as (
    select least(greatest(coalesce(p_limit, 60), 1), 200) as v
  )
  select
    u.id,
    u.display_name,
    u.avatar_url
  from user_profiles u
  left join user_settings s on s.user_id = u.id
  where u.display_name ilike '%' || p_query || '%'
    -- Default is "discoverable" — only filter rows where the user
    -- has actively flipped the pref to false. Missing key, missing
    -- row, or value "true" all keep the row in the result set.
    and coalesce(s.prefs->>'discoverable_in_search', 'true') <> 'false'
  order by u.display_name
  limit (select v from capped);
$$;

revoke all on function search_user_profiles(text, int) from public;
revoke execute on function search_user_profiles(text, int) from anon;
grant execute on function search_user_profiles(text, int) to authenticated;
