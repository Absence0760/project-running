-- Issue #734 (security/privacy carryover): /api/coach/route-describe and
-- /api/coach/route-request fanned out to Anthropic with NO consent gate at
-- all. Only /api/coach checked `coach_consent_at`, and reusing that stamp
-- for the route endpoints would have been wrong twice over: the copy the
-- user accepted is Coach-specific ("the AI Coach to use your training
-- data"), and a route request carries a different payload (a typed request
-- string plus a `location_label`) for a different purpose. Silently
-- treating the Coach acceptance as covering it retroactively broadens what
-- an existing user agreed to — exactly what GDPR Art 7(2) forbids.
--
-- A second boolean column would have repeated the problem on the next AI
-- feature. Instead the consent record carries the VERSION of the
-- disclosure that was accepted, and each AI endpoint declares the minimum
-- version it requires:
--
--   v1  AI Coach only — profile slice, recent runs, active plan, chat text.
--   v2  All AI features — v1 plus the AI route assistant (route stats +
--       name for the description enhancement, the typed route request and
--       its coarse location label for the constraint extractor).
--
-- The ladder is monotone by construction: every version is a strict
-- superset of the one below it, which is what makes ">= required" a sound
-- comparison. A future disclosure that NARROWS rather than widens could
-- not join this ladder — it would need a scope set. See decisions.md § 571.
--
-- Existing acceptances backfill to v1, so a Coach user keeps the Coach and
-- is refused (403) by the route endpoints until they accept the widened
-- disclosure. Fail closed everywhere: no record, a half-written record, or
-- a version this deployment does not know about all deny.
--
-- `user_profiles` is one row per user and is named in
-- docs/backend/migration_locks.md as a bounded table where the online form
-- is ceremony rather than safety; the CHECK still goes in NOT VALID +
-- VALIDATE so the pattern is the one future migrations copy.
--
-- Prod deploy is gated on counsel / CISO sign-off of the v2 disclosure
-- copy (a privacy-boundary change) per the compliance-sign-off rule — the
-- code lands now, fail-closed, behind that deploy gate.

alter table public.user_profiles
  add column if not exists ai_disclosure_version smallint;

comment on column public.user_profiles.ai_disclosure_version is
  'Version of the AI-processing disclosure this user has accepted (GDPR '
  'Art 6(1)(a)). Written only by record_ai_disclosure_consent(); paired '
  'with coach_consent_at, which holds when that version was accepted. Not '
  'in the public-safe column grant — read via get_my_profile().';

comment on column public.user_profiles.coach_consent_at is
  'When the user accepted the AI-processing disclosure named by '
  'ai_disclosure_version. Server-stamped by record_ai_disclosure_consent(); '
  'cleared by withdraw_ai_disclosure_consent(). Direct writes are blocked '
  'by lock_consent_columns().';

-- The highest disclosure version this deployment knows how to describe.
-- Bumping it means: new copy in the six web locales, a new version here,
-- and the endpoints that need the wider scope raising their minimum.
create or replace function ai_disclosure_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 2::smallint $$;

comment on function ai_disclosure_current_version() is
  'Highest known AI-disclosure version. The TS mirror is '
  'AI_DISCLOSURE_CURRENT_VERSION in apps/web/src/lib/core/ai_disclosure.ts; '
  'its ai_disclosure.test.ts fails the build if the two drift.';

revoke all on function ai_disclosure_current_version() from public, anon;
grant execute on function ai_disclosure_current_version() to authenticated, service_role;

-- Every acceptance recorded before this migration was the v1 (Coach-only)
-- disclosure. Backfilling to v1 is what keeps the widened scope from being
-- granted retroactively.
update public.user_profiles
   set ai_disclosure_version = 1
 where coach_consent_at is not null
   and ai_disclosure_version is null;

alter table public.user_profiles
  add constraint user_profiles_ai_disclosure_chk
  check (
    (coach_consent_at is null) = (ai_disclosure_version is null)
    and (ai_disclosure_version is null or ai_disclosure_version >= 1)
  )
  not valid;

alter table public.user_profiles
  validate constraint user_profiles_ai_disclosure_chk;

-- Canonical recorder. Monotone: accepting a version at or below the one
-- already on record is a no-op that returns the original stamp
-- (first-stamp-wins, unchanged from record_coach_consent()'s contract), so
-- a Coach re-prompt can never walk a v2 acceptance back to v1. An unknown
-- version raises rather than being stored — a version we cannot describe
-- is a version we cannot prove was disclosed.
create or replace function record_ai_disclosure_consent(p_version smallint)
returns table (version smallint, accepted_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_version is null
     or p_version < 1
     or p_version > ai_disclosure_current_version() then
    raise exception 'unknown ai disclosure version: %', p_version
      using errcode = '22023';
  end if;
  -- Flag this write as coming from the sanctioned RPC so the
  -- lock_consent_columns trigger lets it through. Transaction-local
  -- (is_local = true): a client can't prepend a set_config to a single
  -- PostgREST UPDATE, so only this function can raise the flag.
  perform set_config('app.consent_write', 'on', true);
  -- Insert-or-update for the same reason grant_health_data_consent() is
  -- (issue #233): user_profiles rows are client-provisioned with no
  -- signup trigger, so a plain `update ... where id = auth.uid()` matches
  -- zero rows for a user whose bootstrap has not run and reports success
  -- while recording nothing. The DO UPDATE arm's WHERE is what keeps the
  -- ladder monotone — an acceptance at or below the version on record
  -- leaves the row untouched, so first-stamp-wins survives.
  insert into user_profiles (id, ai_disclosure_version, coach_consent_at)
  values (v_uid, p_version, now())
  on conflict (id) do update
    set ai_disclosure_version = excluded.ai_disclosure_version,
        coach_consent_at = excluded.coach_consent_at
    where user_profiles.ai_disclosure_version is null
       or user_profiles.ai_disclosure_version < excluded.ai_disclosure_version;
  return query
    select up.ai_disclosure_version, up.coach_consent_at
      from user_profiles up
     where up.id = v_uid;
end;
$$;

revoke all on function record_ai_disclosure_consent(smallint) from public, anon;
grant execute on function record_ai_disclosure_consent(smallint) to authenticated, service_role;

-- Art 7(3): withdrawal clears the whole record, not one feature's slice —
-- there is one acceptance, of one disclosure, at one version.
create or replace function withdraw_ai_disclosure_consent()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  perform set_config('app.consent_write', 'on', true);
  update user_profiles
     set coach_consent_at = null,
         ai_disclosure_version = null
   where id = v_uid;
end;
$$;

revoke all on function withdraw_ai_disclosure_consent() from public, anon;
grant execute on function withdraw_ai_disclosure_consent() to authenticated, service_role;

-- The mobile apps present the Coach-scoped disclosure and reach consent
-- through these two names (packages/api_client). Accepting v1 is the
-- correct record for the copy they show, so they stay as the v1 entry
-- points rather than being redirected at a scope their UI never described.
create or replace function record_coach_consent()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz;
begin
  select accepted_at into v_at from record_ai_disclosure_consent(1::smallint);
  return v_at;
end;
$$;

revoke all on function record_coach_consent() from public, anon;
grant execute on function record_coach_consent() to authenticated, service_role;

create or replace function withdraw_coach_consent()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform withdraw_ai_disclosure_consent();
end;
$$;

revoke all on function withdraw_coach_consent() from public, anon;
grant execute on function withdraw_coach_consent() to authenticated, service_role;

-- Re-emit the lock trigger with the version column added. Without this a
-- direct PostgREST PATCH could set ai_disclosure_version = 2 and self-grant
-- the widened scope, which is the whole point of the gate.
create or replace function lock_consent_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Trusted writers: the sanctioned RPCs (transaction-local flag), the
  -- REST service role (by JWT role), and genuine privileged DB
  -- connections (by session_user, unforgeable from PostgREST).
  if current_setting('app.consent_write', true) = 'on'
     or v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;
  if old.coach_consent_at is distinct from new.coach_consent_at then
    raise exception 'coach_consent_at is set by record_ai_disclosure_consent(), not a direct write'
      using errcode = '42501';
  end if;
  if old.ai_disclosure_version is distinct from new.ai_disclosure_version then
    raise exception 'ai_disclosure_version is set by record_ai_disclosure_consent(), not a direct write'
      using errcode = '42501';
  end if;
  -- Block a direct GRANT (setting to a non-null value); a NULL write
  -- (withdrawal per Art 7(3)) and a no-op are allowed.
  if new.health_data_consent_at is not null
     and new.health_data_consent_at is distinct from old.health_data_consent_at then
    raise exception 'health_data_consent_at is set by grant_health_data_consent(), not a direct write'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists lock_consent_columns_trg on user_profiles;
create trigger lock_consent_columns_trg
  before update on user_profiles
  for each row execute function lock_consent_columns();
