-- search_user_profiles: never surface a declared minor in name search.
--
-- Persona-hunt Round 4 finding family-club #1. The opt-out pref
-- (20261015_001) defaults to discoverable=true for back-compat, so any
-- account that never opens Settings — including a child running on a
-- linked/shared family account — is name-searchable by strangers from
-- signup. A minor cannot reasonably be expected to find and flip a
-- privacy toggle, so we hard-exclude declared minors regardless of the
-- opt-out pref.
--
-- "Declared minor" = the universal `date_of_birth` pref (YYYY-MM-DD) is
-- present, well-formed, and places the person under 18. Adults and
-- accounts with no DOB on file are unaffected (the app's 16+ age gate
-- already governs account creation; this is a stricter discoverability
-- floor layered on top, not a replacement). The exclusion sits inside
-- the SECURITY DEFINER body so the minor bit is never probeable by a
-- third party — same reasoning as the opt-out filter it extends.
--
-- Bare-body replacement of 20261015_001 — full body reproduced with the
-- minor clause added (see apps/backend/CLAUDE.md "Bare-body create or
-- replace function strips prior fixes").

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
    -- has actively flipped the pref to false.
    and coalesce(s.prefs->>'discoverable_in_search', 'true') <> 'false'
    -- Hard floor: a declared minor is never discoverable, even if the
    -- opt-out pref is unset/true. Missing or malformed DOB leaves the
    -- row in (adults + unknown-age accounts are unaffected). The
    -- coalesce(..., false) is load-bearing: users with no user_settings
    -- row have a NULL prefs (LEFT JOIN), and `not (NULL ...)` is NULL,
    -- which would silently drop every settings-less account from search.
    and not coalesce(
      s.prefs ? 'date_of_birth'
      and (s.prefs->>'date_of_birth') ~ '^\d{4}-\d{2}-\d{2}$'
      and (s.prefs->>'date_of_birth')::date > (current_date - interval '18 years'),
      false
    )
  order by u.display_name
  limit (select v from capped);
$$;

revoke all on function search_user_profiles(text, int) from public;
revoke execute on function search_user_profiles(text, int) from anon;
grant execute on function search_user_profiles(text, int) to authenticated;
