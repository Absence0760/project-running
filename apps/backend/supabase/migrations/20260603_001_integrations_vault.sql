-- Encrypt OAuth tokens at rest using Supabase Vault.
--
-- Replaces the plaintext `integrations.access_token` and
-- `integrations.refresh_token` columns with vault-secret references.
-- Vault uses libsodium under the hood and the master key is managed
-- (and rotated) by the platform — neither this codebase nor the Edge
-- Functions ever hold the encryption key.
--
-- After this migration, callers must use the helper functions
-- `set_integration_tokens()` and `get_integration_tokens()` to
-- read/write tokens. Direct `select access_token from integrations`
-- will fail at compile-time on the regenerated TS types because the
-- column is gone.

-- ─────────────────────── Schema change ───────────────────────

alter table integrations
  add column access_token_secret_id uuid references vault.secrets(id) on delete set null,
  add column refresh_token_secret_id uuid references vault.secrets(id) on delete set null;

-- Migrate any existing plaintext tokens into vault before dropping
-- the columns. Per-row create_secret + UPDATE — there are at most a
-- handful of integration rows in any environment.
do $$
declare
  r record;
  v_access_id uuid;
  v_refresh_id uuid;
begin
  for r in select id, user_id, provider, access_token, refresh_token from integrations
           where access_token is not null or refresh_token is not null
  loop
    v_access_id := null;
    v_refresh_id := null;
    if r.access_token is not null then
      v_access_id := vault.create_secret(
        r.access_token,
        format('integration_access_%s_%s', r.user_id, r.provider),
        format('OAuth access token for user=%s provider=%s', r.user_id, r.provider)
      );
    end if;
    if r.refresh_token is not null then
      v_refresh_id := vault.create_secret(
        r.refresh_token,
        format('integration_refresh_%s_%s', r.user_id, r.provider),
        format('OAuth refresh token for user=%s provider=%s', r.user_id, r.provider)
      );
    end if;
    update integrations
      set access_token_secret_id = v_access_id,
          refresh_token_secret_id = v_refresh_id
      where id = r.id;
  end loop;
end $$;

alter table integrations drop column access_token;
alter table integrations drop column refresh_token;

-- ─────────────────────── Helper functions ───────────────────────
--
-- Both functions are SECURITY DEFINER and gate on the caller being
-- the row owner OR the service role. The `vault.decrypted_secrets`
-- view is admin-only (and rightly so — anyone who can read it can
-- read every secret in the project), so we encapsulate it here.

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
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
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
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
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
  -- the secret_id stays stable across token refreshes (consumers may
  -- have cached references); otherwise create a new secret.
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

  -- Upsert the row itself. Caller may be establishing the integration
  -- for the first time (insert path) or rotating tokens (update path).
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
