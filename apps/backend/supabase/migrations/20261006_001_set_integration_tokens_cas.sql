-- audit/strava May 2026 High #3 — token-refresh race serialisation.
--
-- Three paths refresh in parallel: cron `handler_token_refresh`,
-- on-demand `strava-import:handleSync`, and webhook ingest. Strava
-- invalidates the OLD refresh token the moment it issues a new pair.
-- Without serialisation, two concurrent callers race: the second
-- caller (with the now-stale refresh token) sends a request Strava
-- rejects, OR it succeeds in time and overwrites the first caller's
-- vault row with a stale-old refresh token Strava already invalidated.
--
-- Fix: a CAS (compare-and-set) variant of `set_integration_tokens`.
-- The caller passes the `expected_refresh_token` it READ from vault
-- before the Strava round-trip. The RPC reads the CURRENT refresh
-- token, compares, and writes only if they match. Returns boolean:
-- `true` = won the race (write applied), `false` = lost (caller
-- should re-read + retry, or just skip — the winning caller has
-- already rotated successfully).
--
-- The existing `set_integration_tokens` keeps its semantics (no CAS)
-- for first-time connects + admin paths; the new
-- `set_integration_tokens_cas` is the contract for refresh callers.

create or replace function set_integration_tokens_cas(
  p_user_id uuid,
  p_provider text,
  p_expected_refresh_token text,
  p_access_token text,
  p_refresh_token text,
  p_token_expiry timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_caller uuid := auth.uid();
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_existing_access uuid;
  v_existing_refresh uuid;
  v_current_refresh text;
begin
  if v_role <> 'service_role' and v_caller is distinct from p_user_id then
    raise exception 'forbidden: cannot write tokens for another user'
      using errcode = '42501';
  end if;

  -- Lock the integrations row for the duration of this transaction
  -- so a concurrent CAS caller can't sneak between the read + write.
  -- `for update` blocks; that's fine — the network round-trip
  -- already happened before the caller invoked us, so this is a
  -- sub-millisecond local wait.
  select access_token_secret_id, refresh_token_secret_id
    into v_existing_access, v_existing_refresh
    from integrations
    where user_id = p_user_id and provider = p_provider
    for update;

  if v_existing_refresh is null then
    -- No vault row yet — caller's "expected" value is nonsensical;
    -- treat as a CAS failure rather than allowing a first-write
    -- through this RPC.
    return false;
  end if;

  -- Read the CURRENT plaintext refresh token from decrypted_secrets.
  -- This is the comparison material for CAS.
  select decrypted_secret into v_current_refresh
    from vault.decrypted_secrets
    where id = v_existing_refresh;

  if v_current_refresh is null or v_current_refresh <> p_expected_refresh_token then
    -- Race lost — another caller already rotated. The caller is
    -- expected to either re-read + retry, or treat this as success
    -- (the winning caller already wrote a fresh pair).
    return false;
  end if;

  -- Write path mirrors set_integration_tokens. Same in-place vault
  -- update semantics so secret_id stays stable across rotations.
  if p_access_token is not null then
    if v_existing_access is not null then
      perform vault.update_secret(v_existing_access, p_access_token);
    end if;
  end if;
  if p_refresh_token is not null then
    perform vault.update_secret(v_existing_refresh, p_refresh_token);
  end if;
  update integrations
    set token_expiry = coalesce(p_token_expiry, token_expiry),
        updated_at = now()
    where user_id = p_user_id and provider = p_provider;
  return true;
end;
$$;

revoke all on function set_integration_tokens_cas(uuid, text, text, text, text, timestamptz) from public;
grant execute on function set_integration_tokens_cas(uuid, text, text, text, text, timestamptz)
  to authenticated, service_role;

comment on function set_integration_tokens_cas(uuid, text, text, text, text, timestamptz) is
  'Compare-and-set variant of set_integration_tokens. Reads the '
  'current refresh token from vault.decrypted_secrets under FOR '
  'UPDATE, compares against p_expected_refresh_token, writes only '
  'if matched. Returns true on win, false on lost race. Caller '
  'reads the refresh token via get_integration_tokens before the '
  'Strava round-trip and passes the read-time value back in here. '
  '/audit/strava May 2026 High #3.';
