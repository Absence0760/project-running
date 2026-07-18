-- Issue #382 — server-side enforcement of the GDPR Art 8 age/terms gate.
--
-- Until now `user_profiles.age_confirmed_at` was captured by
-- confirm_age_and_terms() (migration 20260929_001) but enforced ONLY
-- by a client-side redirect (apps/web/src/routes/+layout.svelte). No
-- RPC, trigger, or RLS policy referenced the column, so a direct curl
-- to GoTrue /auth/v1/signup — or closing the tab before /auth/callback
-- replays the RPC — yields an `authenticated` account whose profile has
-- `age_confirmed_at IS NULL` and full functional use of the app. Art 8
-- consent is invalid when the controller can't show the affirmative act
-- happened, and the downstream Art 9 processing (location traces, body
-- metrics, workouts) is then unlawful ab initio.
--
-- Fix: a fail-closed BEFORE INSERT trigger on the core personal-data
-- content tables. An `authenticated` caller (a user JWT) cannot write
-- their first row of activity/health data until confirm_age_and_terms()
-- has stamped `age_confirmed_at`. The client redirect stays as the UX
-- layer; this is the enforcement beneath it.
--
-- Prod deploy is gated on CISO / legal sign-off (privacy-boundary
-- change) per the compliance-sign-off rule — the code lands now,
-- fail-closed, behind that deploy gate.

create schema if not exists private;
grant usage on schema private to anon, authenticated, service_role;

-- Reusable consent predicate as a BEFORE INSERT trigger guard. Keyed on
-- auth.uid() (the RLS insert check already forces new.user_id =
-- auth.uid() on every gated table, so the caller's stamp is the row's
-- stamp). SECURITY DEFINER so the read of the consent column doesn't
-- depend on the table's SELECT policy; auth.uid() reads the request GUC
-- and is unaffected by the security context.
create or replace function private.enforce_consent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  -- Fail-closed. Only user-JWT writes are gated. A null caller is a
  -- service_role / backend job (webhook importers, admin tooling) whose
  -- writes are trusted and never carry an interactive consent context;
  -- gating them would break async Strava/Stripe ingestion that has no
  -- user session. The bypass this issue closes is an `authenticated`
  -- account with no stamp, which always has a non-null auth.uid().
  if caller is null then
    return new;
  end if;

  if not exists (
    select 1 from user_profiles
    where id = caller and age_confirmed_at is not null
  ) then
    raise exception
      'consent required: confirm age and terms before writing user data'
      using errcode = '42501',
            hint = 'call confirm_age_and_terms() (GDPR Art 8 gate, issue #382)';
  end if;

  return new;
end;
$$;

revoke execute on function private.enforce_consent() from public;

comment on function private.enforce_consent() is
  'Fail-closed GDPR Art 8 consent guard (issue #382). BEFORE INSERT '
  'trigger on the core personal-data tables — rejects an authenticated '
  'caller whose user_profiles.age_confirmed_at is NULL. Null auth.uid() '
  '(service_role / backend jobs) passes through. Stamp via '
  'confirm_age_and_terms().';

create trigger runs_require_consent
  before insert on runs
  for each row execute function private.enforce_consent();

create trigger gym_workouts_require_consent
  before insert on gym_workouts
  for each row execute function private.enforce_consent();

create trigger food_log_require_consent
  before insert on food_log
  for each row execute function private.enforce_consent();

create trigger body_metrics_require_consent
  before insert on body_metrics
  for each row execute function private.enforce_consent();
