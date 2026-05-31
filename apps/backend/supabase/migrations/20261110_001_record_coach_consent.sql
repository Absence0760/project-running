-- audit-findings 2026-05-30 Medium [compliance/gdpr]: AI-coach consent
-- was stamped by a client-side `user_profiles.update({coach_consent_at})`
-- with a CLIENT-supplied timestamp. That's both backdatable (the client
-- chooses the value) and replayable (it can be overwritten), so the
-- consent record isn't trustworthy evidence under GDPR Art 7(1).
--
-- Fix: a first-stamp-wins SECURITY DEFINER RPC that stamps the SERVER's
-- now() and only when not already set, plus a BEFORE-UPDATE trigger that
-- blocks any non-privileged caller from writing coach_consent_at directly
-- — so the RPC is the only path and the timestamp is server-authoritative.
-- (health_data_consent_at is intentionally NOT locked: it has a legitimate
-- client toggle flow in onboarding + settings/preferences. Only coach
-- consent is a one-way affirmative stamp.) Mirrors the
-- lock_subscription_columns trust model (20261107_001): trust the REST
-- service role by JWT role and genuine direct-SQL by session_user
-- (PostgREST cannot forge either).

create or replace function record_coach_consent()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_at  timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  -- Flag this write as coming from the sanctioned RPC so the
  -- lock_consent_columns trigger lets it through. Transaction-local
  -- (is_local = true): a client can't prepend a set_config to a single
  -- PostgREST UPDATE, so only this function can raise the flag.
  perform set_config('app.consent_write', 'on', true);
  -- First-stamp-wins: set now() only if unset; otherwise leave the
  -- original. Either way return the effective timestamp.
  update user_profiles
    set coach_consent_at = now()
    where id = v_uid and coach_consent_at is null;
  select coach_consent_at into v_at from user_profiles where id = v_uid;
  return v_at;
end;
$$;

revoke all on function record_coach_consent() from public, anon;
grant execute on function record_coach_consent() to authenticated, service_role;

-- Block direct end-user writes to the consent timestamps so the RPC (and
-- the deletion/admin paths) are the only writers. The RPC is SECURITY
-- DEFINER (runs as the owner → bypasses this trigger); a direct
-- authenticated PATCH is rejected.
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
  -- Trusted: the sanctioned RPC (transaction-local flag it sets just
  -- before its own write), the REST service role (by JWT role), and
  -- genuine privileged DB connections (by session_user, unforgeable from
  -- PostgREST). Same model as lock_subscription_columns.
  if current_setting('app.consent_write', true) = 'on'
     or v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;
  if old.coach_consent_at is distinct from new.coach_consent_at then
    raise exception 'coach_consent_at is set by record_coach_consent(), not a direct write'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists lock_consent_columns_trg on user_profiles;
create trigger lock_consent_columns_trg
  before update on user_profiles
  for each row execute function lock_consent_columns();
