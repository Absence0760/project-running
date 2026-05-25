-- Self-audit of commit ed5cdf80 (delete-account hardening) found
-- that supabase-js's `.schema('vault').from(...)` calls fail with
-- PGRST106 because PostgREST exposes only `public` and
-- `graphql_public` by default. The vault.secrets cleanup attempt
-- returned an error, the EF handler returned 500, and account
-- deletion was actively broken — worse than the pre-audit state.
--
-- Provide a `delete_user_integration_secrets` SECURITY DEFINER RPC
-- that lives in `public` (so PostgREST exposes it) and does the
-- vault.secrets DELETE on behalf of the caller.
--
-- Authorization model: GRANT-only. Inside SECURITY DEFINER
-- `current_user` resolves to the function owner (postgres), so a
-- caller-identity check inside the function would always pass. The
-- protection is the EXECUTE grant: revoked from PUBLIC + anon +
-- authenticated, granted only to service_role. (Earlier audit-fix
-- iteration tried a JWT-claim role check inside the function;
-- under Postgres 17 calling the function from an unprivileged role
-- segfaults the backend before the body runs — a separate
-- platform-level issue. The GRANT alone is the right enforcement
-- mechanism.)
--
-- Returns the number of vault rows actually deleted so the EF can
-- log it for audit purposes.

create or replace function delete_user_integration_secrets(
  p_user_id uuid
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
  -- Collect every vault.secrets.id the user's integration rows
  -- reference. Filter nulls (integrations FK is `on delete set null`,
  -- which means a previously-disconnected provider may have already
  -- cleared its secret-id columns).
  select array_remove(
    array_agg(access_token_secret_id) || array_agg(refresh_token_secret_id),
    null
  )
    into v_secret_ids
  from integrations
  where user_id = p_user_id;

  if v_secret_ids is null or cardinality(v_secret_ids) = 0 then
    return 0;
  end if;

  delete from vault.secrets where id = any(v_secret_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

-- Service-role only. The function is reachable via PostgREST RPC
-- (`/rest/v1/rpc/delete_user_integration_secrets`); the only
-- production caller is the delete-account Edge Function which
-- authenticates with the service-role key.
revoke execute on function delete_user_integration_secrets(uuid) from public;
revoke execute on function delete_user_integration_secrets(uuid) from anon, authenticated;
grant execute on function delete_user_integration_secrets(uuid) to service_role;
