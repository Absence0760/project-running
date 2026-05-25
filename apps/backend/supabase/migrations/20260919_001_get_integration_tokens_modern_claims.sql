-- Self-audit follow-up. The original get_integration_tokens +
-- set_integration_tokens (from 20260603_001) check only the legacy
-- `request.jwt.claim.role` setting, which modern PostgREST no longer
-- populates — the role now lives in the `request.jwt.claims` jsonb
-- under the `role` key. A service-role call therefore failed the
-- role check and got "forbidden: cannot read tokens for another user",
-- which broke the delete-account Edge Function's Strava-deauthorize
-- path (added in commit ed5cdf80).
--
-- Re-issue both functions with identical bodies BUT a widened role
-- detection: prefer the legacy claim, fall back to the modern jsonb
-- claim. Nothing else changes (same caller gate, same vault wiring,
-- same upsert / token-naming convention) — the audit-fix iteration
-- briefly replaced set_integration_tokens with a slimmer body that
-- broke the seed by dropping the on-conflict upsert; this migration
-- preserves the exact 20260603_001 body verbatim.

create or replace function get_integration_tokens(
  p_user_id uuid,
  p_provider text
)
returns table (access_token text, refresh_token text, token_expiry timestamptz)
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_caller uuid := auth.uid();
  v_jwt_claims text := current_setting('request.jwt.claims', true);
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    case
      when v_jwt_claims is null or v_jwt_claims = '' then null
      else nullif(v_jwt_claims::jsonb ->> 'role', '')
    end,
    ''
  );
  v_access_id uuid;
  v_refresh_id uuid;
  v_expiry timestamptz;
begin
  if v_role <> 'service_role' and v_caller is distinct from p_user_id then
    raise exception 'forbidden: cannot read tokens for another user';
  end if;

  select access_token_secret_id, refresh_token_secret_id, integrations.token_expiry
    into v_access_id, v_refresh_id, v_expiry
    from integrations
    where user_id = p_user_id and provider = p_provider;

  return query
    select
      (select decrypted_secret from vault.decrypted_secrets where id = v_access_id),
      (select decrypted_secret from vault.decrypted_secrets where id = v_refresh_id),
      v_expiry;
end;
$$;

revoke all on function get_integration_tokens(uuid, text) from public;
grant execute on function get_integration_tokens(uuid, text) to authenticated, service_role;

create or replace function set_integration_tokens(
  p_user_id uuid,
  p_provider text,
  p_access_token text,
  p_refresh_token text,
  p_token_expiry timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_caller uuid := auth.uid();
  v_jwt_claims text := current_setting('request.jwt.claims', true);
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    case
      when v_jwt_claims is null or v_jwt_claims = '' then null
      else nullif(v_jwt_claims::jsonb ->> 'role', '')
    end,
    ''
  );
  v_access_id uuid;
  v_refresh_id uuid;
  v_existing_access uuid;
  v_existing_refresh uuid;
begin
  if v_role <> 'service_role' and v_caller is distinct from p_user_id then
    raise exception 'forbidden: cannot write tokens for another user';
  end if;

  select access_token_secret_id, refresh_token_secret_id
    into v_existing_access, v_existing_refresh
    from integrations
    where user_id = p_user_id and provider = p_provider;

  -- Access token. Update in place when a vault row already exists so
  -- the secret_id stays stable across token refreshes; otherwise
  -- create a new secret. Verbatim from 20260603_001.
  if p_access_token is not null then
    if v_existing_access is not null then
      perform vault.update_secret(v_existing_access, p_access_token);
      v_access_id := v_existing_access;
    else
      v_access_id := vault.create_secret(
        p_access_token,
        format('integration_access_%s_%s', p_user_id, p_provider),
        format('OAuth access token for user=%s provider=%s', p_user_id, p_provider)
      );
    end if;
  else
    v_access_id := v_existing_access;
  end if;

  -- Refresh token, same shape.
  if p_refresh_token is not null then
    if v_existing_refresh is not null then
      perform vault.update_secret(v_existing_refresh, p_refresh_token);
      v_refresh_id := v_existing_refresh;
    else
      v_refresh_id := vault.create_secret(
        p_refresh_token,
        format('integration_refresh_%s_%s', p_user_id, p_provider),
        format('OAuth refresh token for user=%s provider=%s', p_user_id, p_provider)
      );
    end if;
  else
    v_refresh_id := v_existing_refresh;
  end if;

  insert into integrations (user_id, provider, access_token_secret_id, refresh_token_secret_id, token_expiry, updated_at)
    values (p_user_id, p_provider, v_access_id, v_refresh_id, p_token_expiry, now())
    on conflict (user_id, provider) do update
      set access_token_secret_id = excluded.access_token_secret_id,
          refresh_token_secret_id = excluded.refresh_token_secret_id,
          token_expiry = coalesce(excluded.token_expiry, integrations.token_expiry),
          updated_at = now();
end;
$$;

revoke all on function set_integration_tokens(uuid, text, text, text, timestamptz) from public;
grant execute on function set_integration_tokens(uuid, text, text, text, timestamptz) to authenticated, service_role;
