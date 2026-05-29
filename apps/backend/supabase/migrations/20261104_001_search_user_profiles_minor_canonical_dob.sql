-- search_user_profiles: read the canonical DOB column for the minor floor.
--
-- 20261017_001 added the minor-exclusion floor but checked the DOB only in
-- `user_settings.prefs->>'date_of_birth'`. That bag is a MIRROR, written
-- inconsistently: the onboarding flow only mirrors it when health-data
-- consent is granted (GDPR Art 9 gate), and the Settings -> Preferences tab
-- writes the birth date to `user_profiles.date_of_birth` (the canonical
-- column, added 20260829_001) WITHOUT mirroring it into prefs at all. So a
-- declared minor who set their DOB via Preferences, or who declined
-- health-data consent, kept a NULL `prefs.date_of_birth` and stayed
-- name-searchable -- a fail-OPEN regression for exactly the child-safety
-- case 20261017_001 set out to close.
--
-- Fix: check the canonical `user_profiles.date_of_birth` column (a real
-- `date`, always written by every DOB entry point). Keep the prefs-bag
-- check as a fallback so any legacy account that only ever had a DOB in
-- prefs is still covered. A minor is excluded if EITHER source places them
-- under 18; both terms are NULL-safe so a DOB-less account is unaffected.
--
-- Bare-body replacement of 20261017_001 -- full body reproduced with the
-- canonical-column term added (see apps/backend/CLAUDE.md "Bare-body create
-- or replace function strips prior fixes"). Function-only; no type regen.

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
    -- opt-out pref is unset/true. A minor is anyone under 18 by EITHER
    -- the canonical `user_profiles.date_of_birth` column (the always-
    -- written source) OR a legacy `prefs.date_of_birth` mirror. Both
    -- terms are guarded so a NULL/absent/malformed DOB leaves the row
    -- in (adults + unknown-age accounts are unaffected).
    and not (
      (u.date_of_birth is not null
        and u.date_of_birth > (current_date - interval '18 years'))
      or coalesce(
        s.prefs ? 'date_of_birth'
        and (s.prefs->>'date_of_birth') ~ '^\d{4}-\d{2}-\d{2}$'
        and (s.prefs->>'date_of_birth')::date > (current_date - interval '18 years'),
        false
      )
    )
  order by u.display_name
  limit (select v from capped);
$$;

revoke all on function search_user_profiles(text, int) from public;
revoke execute on function search_user_profiles(text, int) from anon;
grant execute on function search_user_profiles(text, int) to authenticated;
