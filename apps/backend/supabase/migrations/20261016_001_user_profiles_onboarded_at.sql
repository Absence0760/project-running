-- user_profiles.onboarded_at — gate for the post-signup onboarding
-- wizard.
--
-- The web `/onboarding` route (mounted by this change's sibling
-- web work) walks new signups through a step-by-step set of
-- questions (display name, units, goal type, optional gender +
-- DOB + weight, privacy default, push notifications). The route
-- redirects to the dashboard once every step has been answered
-- (or actively skipped) by stamping `onboarded_at = now()`.
--
-- The column lives on `user_profiles` rather than `user_settings`
-- because:
--   - It's a single nullable timestamptz, not part of the
--     opaque-bag prefs surface.
--   - The auth-shell layout reads it on every login to decide
--     whether to redirect to /onboarding — `user_profiles` is
--     already part of the post-login bootstrap, `user_settings`
--     is loaded lazily.
--   - Nullable + RLS-gated to the owner keeps the disclosure
--     surface narrow.
--
-- Existing users are backfilled with `now()` so the wizard never
-- shows up for them (they're already past it conceptually) — the
-- Settings page surfaces an optional "review your profile" nudge
-- for fields the persona hasn't set yet.

alter table user_profiles
  add column onboarded_at timestamptz;

-- Backfill: every row that exists today is treated as already
-- onboarded. No one gets retroactively re-onboarded after
-- months of normal use.
update user_profiles
  set onboarded_at = now()
  where onboarded_at is null;

-- The column is owner-readable + owner-writable per the existing
-- RLS policies on user_profiles — no policy change needed. New
-- signups will land with NULL by default; the wizard's final
-- "Finish" / "Skip onboarding" button writes the timestamp.
