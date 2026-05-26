-- audit/strava May 2026 High #1 — per-provider vault cleanup.
--
-- `delete_user_integration_secrets` (20260918_001) drops the user's
-- vault rows for EVERY provider. We need a per-provider variant so
-- a user-initiated "Disconnect Strava" flow (Settings page) can
-- wipe Strava's vault rows + leave any other integration intact.
--
-- Same authorization model: GRANT-only (revoked from PUBLIC + anon
-- + authenticated, granted to service_role). The Edge Function
-- that wraps the disconnect flow authenticates with service-role
-- and is itself JWT-gated against the caller's auth.uid().

create or replace function delete_user_provider_secrets(
  p_user_id uuid,
  p_provider text
)
returns int
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_secret_ids uuid[];
  v_deleted int;
begin
  if p_provider is null or p_provider = '' then
    raise exception 'delete_user_provider_secrets: provider required'
      using errcode = '22023';
  end if;

  select array_remove(
    array_agg(access_token_secret_id) || array_agg(refresh_token_secret_id),
    null
  )
    into v_secret_ids
  from integrations
  where user_id = p_user_id and provider = p_provider;

  if v_secret_ids is null or cardinality(v_secret_ids) = 0 then
    return 0;
  end if;

  delete from vault.secrets where id = any(v_secret_ids);
  get diagnostics v_deleted = row_count;

  -- Clear the FK columns on the integrations row so a re-connect
  -- doesn't trip a stale-vault-id reference. The row itself stays
  -- (the disconnect-flow stamps `disconnected_at` separately so
  -- the UI can show Reconnect Strava).
  update integrations
    set access_token_secret_id = null,
        refresh_token_secret_id = null,
        token_expiry = null
    where user_id = p_user_id and provider = p_provider;

  return v_deleted;
end;
$$;

revoke execute on function delete_user_provider_secrets(uuid, text) from public;
revoke execute on function delete_user_provider_secrets(uuid, text) from anon, authenticated;
grant execute on function delete_user_provider_secrets(uuid, text) to service_role;

comment on function delete_user_provider_secrets(uuid, text) is
  'Per-provider sibling of delete_user_integration_secrets. Drops '
  'the vault rows + clears the FK columns + nulls token_expiry on '
  'the integrations row, leaving the row itself for the disconnect '
  '/ reconnect UX. Caller is the strava-import EF disconnect action '
  '(production) — service-role gated. /audit/strava High #1.';
