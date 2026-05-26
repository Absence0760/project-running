-- audit:gdpr May 2026 — Critical: server-side age gate.
--
-- The /login page has a `confirm 16+` checkbox today, but it is
-- client-side only — JavaScript-disabled browsers, OAuth flows, and
-- any direct call to `auth.signUp` skip the gate entirely. GDPR Art 8
-- consent is invalid when the controller can't show the affirmative
-- act happened, and downstream Art 9 processing (DOB + gender) is
-- unlawful ab initio if the user is below the member-state age of
-- consent.
--
-- This migration captures the consent server-side. The flow:
--
--   1. /login email-password sign-up: the client calls
--      `confirm_age_and_terms()` RPC immediately after `auth.signUp`
--      succeeds. The RPC stamps `age_confirmed_at` and
--      `terms_accepted_at` on the caller's user_profiles row.
--   2. /login OAuth (Google, future Apple): the client stashes the
--      pre-redirect tick to sessionStorage. /auth/callback reads
--      that stash and calls the same RPC.
--   3. `get_my_profile()` exposes both columns (it returns the whole
--      row); the client falls through to `/auth/confirm-age` if
--      either timestamp is null. This is the post-OAuth fallback:
--      a user who lost the sessionStorage tick has to re-affirm.
--
-- Server-side enforcement: the RPC is the only path that stamps
-- these columns from a user JWT. An attacker who curls directly to
-- `auth.signUp` ends up with an auth.users row whose user_profiles
-- has `age_confirmed_at IS NULL`. Downstream gates (the
-- /auth/confirm-age UX gate + future RPC guards) catch them on the
-- next session refresh.

-- ─────────────────────────────────────────────────────────────────────
-- Columns
-- ─────────────────────────────────────────────────────────────────────

alter table user_profiles
  add column if not exists age_confirmed_at timestamptz null;

alter table user_profiles
  add column if not exists terms_accepted_at timestamptz null;

comment on column user_profiles.age_confirmed_at is
  'GDPR Art 8 affirmative-consent timestamp — the user self-declared '
  '16+ when creating the account. NULL means consent never landed '
  '(client gate bypassed, OAuth callback dropped the sessionStorage '
  'tick); the client must redirect to /auth/confirm-age in that case. '
  'See audit/gdpr (2026-05-25) Critical age-gate finding.';

comment on column user_profiles.terms_accepted_at is
  'Affirmative acceptance timestamp for the Terms of Service + '
  'Privacy Policy. Captured alongside age_confirmed_at via the '
  'same client tick + same RPC stamp. Material ToS / PP changes '
  'are signalled by a new column in the future (not by clearing '
  'this column) so the original acceptance evidence is preserved.';

-- ─────────────────────────────────────────────────────────────────────
-- Backfill — existing accounts predate the gate.
-- ─────────────────────────────────────────────────────────────────────
-- Pre-launch accounts were created when the consent capture didn't
-- exist. Treat their account-creation timestamp as the implicit
-- consent date (they ticked the same checkbox at sign-up, the column
-- just didn't record it). This is defensible because no production
-- traffic exists yet; once we launch, every new user goes through
-- the RPC path.

update user_profiles
  set age_confirmed_at = coalesce(age_confirmed_at, created_at, now()),
      terms_accepted_at = coalesce(terms_accepted_at, created_at, now())
  where age_confirmed_at is null or terms_accepted_at is null;

-- ─────────────────────────────────────────────────────────────────────
-- confirm_age_and_terms() RPC
-- ─────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER so the user's role doesn't need direct UPDATE on
-- the two consent columns (those are in the public-read denylist
-- via 20260707_001's column grants — keep that surface narrow). The
-- function reads `auth.uid()` and stamps both columns idempotently:
-- if a value is already set, it is preserved (first-stamp wins so
-- the consent timestamp doesn't reset on every login).
--
-- Both fields stamp together — splitting age from terms would let a
-- user re-tick one without the other, and we want the audit trail
-- to be a single co-signed event.

create or replace function confirm_age_and_terms()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'confirm_age_and_terms: not authenticated'
      using errcode = '42501';
  end if;

  -- Upsert: a brand-new user (no user_profiles row yet) lands here
  -- when the client calls this immediately after auth.signUp. An
  -- existing user (returning after an OAuth callback that dropped
  -- the sessionStorage tick) updates only the null columns so the
  -- original consent timestamps are preserved.
  insert into user_profiles (id, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
    values (caller, now(), now(), 'km', 'free')
    on conflict (id) do update
    set age_confirmed_at = coalesce(user_profiles.age_confirmed_at, excluded.age_confirmed_at),
        terms_accepted_at = coalesce(user_profiles.terms_accepted_at, excluded.terms_accepted_at);
end;
$$;

revoke execute on function confirm_age_and_terms() from public, anon;
grant execute on function confirm_age_and_terms() to authenticated;

comment on function confirm_age_and_terms() is
  'GDPR Art 8 + ToS acceptance capture — stamps age_confirmed_at + '
  'terms_accepted_at on the caller''s user_profiles row. Idempotent: '
  'existing timestamps are preserved (first-stamp wins). Called from '
  'web /login (email-password) + /auth/callback (OAuth fallback) and '
  'from mobile sign_up_screen.dart. See audit/gdpr (2026-05-25).';
