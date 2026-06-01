-- audit/gdpr 2026-05-31 Medium [compliance/gdpr]: health-data consent
-- (Art 9(2)(a)) was stamped by a client-side
-- `user_profiles.update({health_data_consent_at: <client ISO string>})`.
-- Like the coach-consent gap closed in 20261110_001, the timestamp was
-- client-supplied — backdatable and replayable — so the record is not
-- trustworthy evidence of the affirmative act under Art 7(1).
--
-- Fix: a first-stamp-wins SECURITY DEFINER RPC that stamps the SERVER's
-- now(), plus an extension of the existing lock_consent_columns trigger
-- that blocks a direct end-user write SETTING health_data_consent_at to a
-- NON-NULL value. The withdrawal path (nulling the column alongside
-- gender + DOB, per Art 7(3)) stays a direct client write — only the
-- grant is forced through the RPC. Same trust model as 20261110_001:
-- the sanctioned RPC (transaction-local flag), the REST service role
-- (JWT role), and genuine direct-SQL (session_user) are trusted.

create or replace function grant_health_data_consent()
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
  -- First-stamp-wins: stamp now() only when currently unset. A user who
  -- withdrew (nulled the column) and re-grants gets a fresh now() — the
  -- column is null again at that point, which is the correct semantics
  -- for a renewed affirmative act.
  update user_profiles
    set health_data_consent_at = now()
    where id = v_uid and health_data_consent_at is null;
  select health_data_consent_at into v_at from user_profiles where id = v_uid;
  return v_at;
end;
$$;

revoke all on function grant_health_data_consent() from public, anon;
grant execute on function grant_health_data_consent() to authenticated, service_role;

-- Re-emit lock_consent_columns with the health-data branch added. The
-- prior body (20261110_001) only guarded coach_consent_at; keep that and
-- add a guard that blocks a direct end-user write setting
-- health_data_consent_at to a non-null value, while still permitting a
-- null write (withdrawal) and a no-op.
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
    raise exception 'coach_consent_at is set by record_coach_consent(), not a direct write'
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
