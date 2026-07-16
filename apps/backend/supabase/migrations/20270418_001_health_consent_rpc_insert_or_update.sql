-- Issue #233 (GDPR Art 7(3)/Art 9): the health-data consent paths could
-- silently no-op while the client confirmed success.
--
-- Two holes, one root cause — `user_profiles` rows are client-provisioned
-- (no signup trigger), so any `update ... where id = auth.uid()` against a
-- user whose row doesn't exist yet matches 0 rows and reports success:
--
--   1. The withdrawal was a direct client write (nulling
--      health_data_consent_at + the Art 9 columns) plus a separate
--      body_metrics delete — the 0-row update "succeeded", the UI showed
--      the withdrawn state, and the consent stamp + height + weight
--      series stayed live on the server.
--   2. grant_health_data_consent() (20261118_001) updated
--      `where id = v_uid and health_data_consent_at is null` — 0 rows for
--      a missing profile row, then returned null: consent never stamped.
--
-- A client-side upsert can't close this: PostgREST's ON CONFLICT DO
-- UPDATE reads `excluded.<col>`, which needs SELECT privilege on the
-- column, and SELECT on the health columns is deliberately revoked
-- (20260707_001 / 20270408_001). So both paths become insert-or-update
-- inside SECURITY DEFINER RPCs, mirroring withdraw_coach_consent()
-- (20261128_001):
--
--   * grant_health_data_consent() is re-emitted (FULL body on top of
--     20261118_001 per the bare-body rule) with insert-or-update,
--     keeping first-stamp-wins via coalesce on the conflict arm.
--   * withdraw_health_data_consent() is the new sanctioned inverse: one
--     transaction nulls the consent stamp + every Art 9 profile column
--     (height_cm, gender, date_of_birth) AND erases the body_metrics
--     weight series — closing the partial-failure window the two-call
--     client sequence had. This supersedes 20261118_001's note that
--     withdrawal "stays a direct client write" (the direct null write
--     remains trigger-permitted, but clients now use the RPC).

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
  -- Insert-or-update: rows are client-provisioned, so a grant may run
  -- before the profile bootstrap. First-stamp-wins is preserved on the
  -- conflict arm — an already-set stamp is kept; a user who withdrew
  -- (nulled the column) and re-grants gets a fresh now(), the correct
  -- semantics for a renewed affirmative act.
  insert into user_profiles (id, health_data_consent_at)
  values (v_uid, now())
  on conflict (id) do update
    set health_data_consent_at =
      coalesce(user_profiles.health_data_consent_at, now());
  select health_data_consent_at into v_at
    from user_profiles where id = v_uid;
  return v_at;
end;
$$;

revoke all on function grant_health_data_consent() from public, anon;
grant execute on function grant_health_data_consent() to authenticated, service_role;

create or replace function withdraw_health_data_consent()
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
  -- Insert-or-update so the withdrawal ALWAYS lands a row carrying the
  -- withdrawn state — a 0-row silent no-op here means special-category
  -- data lives on while the user believes it erased.
  insert into user_profiles (id)
  values (v_uid)
  on conflict (id) do update
    set health_data_consent_at = null,
        height_cm = null,
        gender = null,
        date_of_birth = null;
  -- Art 7(3): the special-category weight series goes in the same
  -- transaction — no partial-failure window between two client calls.
  delete from body_metrics where user_id = v_uid;
end;
$$;

revoke all on function withdraw_health_data_consent() from public, anon;
grant execute on function withdraw_health_data_consent() to authenticated, service_role;
