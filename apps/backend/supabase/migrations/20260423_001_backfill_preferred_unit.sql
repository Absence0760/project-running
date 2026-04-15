-- Backfill existing `user_profiles.preferred_unit` values into the new
-- `user_settings.prefs` bag, so existing users don't appear to have
-- reset their unit preference when the app reads the bag first.
--
-- `user_profiles.preferred_unit` stays in the schema for now — clients
-- dual-read (bag first, column fallback) during the transition. A
-- follow-up migration drops the column once every client has switched
-- over.

insert into user_settings (user_id, prefs)
select id, jsonb_build_object('preferred_unit', preferred_unit)
from user_profiles
where preferred_unit is not null
  and preferred_unit <> ''
on conflict (user_id) do update
  set prefs = user_settings.prefs || excluded.prefs;
