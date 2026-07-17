-- Restrict user_profiles.gender to male / female / prefer_not_to_say (issue #220).
--
-- The gender option set drops `nonbinary` end-to-end. Any existing `nonbinary`
-- row is folded into `prefer_not_to_say` (the same calc branch as null / withheld
-- gender) BEFORE the CHECK narrows — migrating the data first is mandatory, or the
-- constraint ALTER fails on the surviving rows.
--
-- Original column + CHECK: 20260829_001_segments_v2_tiered_leaderboards.sql.

update public.user_profiles
set gender = 'prefer_not_to_say'
where gender = 'nonbinary';

alter table public.user_profiles
  drop constraint if exists user_profiles_gender_check;

alter table public.user_profiles
  add constraint user_profiles_gender_check
  check (gender is null or gender in ('male', 'female', 'prefer_not_to_say'));
