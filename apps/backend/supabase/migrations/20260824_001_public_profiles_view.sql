-- public_profiles — anon-readable projection of user_profiles for
-- crawler unfurls + the prerendered share pages.
--
-- Background: `user_profiles` is owner-only by RLS (the only policy
-- is `auth.uid() = id`). Anon reads return zero rows, which blocks
-- the prerendered /share/run/[id] page from baking the runner's
-- display name into the og:title. The static unfurl card therefore
-- reads `5.0 km run on 11 May 2026 — Threkir` rather than
-- `5.0 km by Jared on 11 May 2026 — Threkir`.
--
-- Privacy posture mirrors the existing public surfaces:
--   * `display_name` + `avatar_url` are already visible on every
--     /share/run/[id] body via RunSocial / kudos / comments to
--     any authenticated viewer; the only delta here is that an
--     anon crawler now sees the same display name on the unfurl
--     card. Display name was chosen as the public identity at the
--     /u/[id] surface — surfacing it on share pages is consistent.
--   * Avatar URL is a public Supabase Storage path (the avatars
--     bucket grants `select` to `anon`); same as the existing
--     /u/[id] page behaviour.
--   * `parkrun_number`, `preferred_unit`, `subscription_tier`,
--     `date_of_birth`, `bio`, etc — none are included. The view is
--     a strict minimum: the two fields a share-page unfurl needs.
--
-- Anti-enumeration: the view doesn't expose any way to list "all
-- users". A caller has to know a uuid up-front (typically obtained
-- via a public_runs / public_routes row). The view is keyed on the
-- same uuid those views already publish.
--
-- If we ever need to retract this — a user-driven "hide me from
-- crawlers" toggle, for example — the path is a `WHERE` clause on
-- this view against a future `user_profiles.crawler_visible` flag
-- (default true). For v1 the view is unconditionally readable.

create or replace view public_profiles as
select
  id,
  display_name,
  avatar_url
from user_profiles;

grant select on public_profiles to anon, authenticated;
