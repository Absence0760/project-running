-- Lock user_profiles.subscription_tier and subscription_at against
-- user-JWT writes. Pre-prod paywall audit caught this:
--
-- The original `users own their profile` policy (20260405_001:85) is
-- `for all using (auth.uid() = id)` — covers SELECT, INSERT, UPDATE,
-- DELETE on the user's own row, with no column-level guard. A free
-- user can self-promote with a single PostgREST PATCH:
--
--   PATCH /rest/v1/user_profiles?id=eq.<self>  {"subscription_tier":"pro"}
--
-- The CHECK constraint added in 20260429_001 only enforces the enum
-- domain — it accepts 'pro'. After self-promotion every paywalled
-- path treats the user as Pro: is_pro() returns true,
-- check_rate_limit_tiered picks the pro ceiling, the coach quota
-- skips its daily cap. A future RevenueCat EXPIRATION event would
-- eventually overwrite the lie, but only for users RC has ever
-- charged — for a never-paid attacker, nothing rewrites the column.
--
-- Two-part fix:
--
--   1. Replace the `for all` policy with explicit per-command
--      policies, so the surface is auditable and we can swap one
--      command without grandfathering the others. The SELECT path
--      is already covered by `profiles are readable by anyone
--      authenticated` from 20260521_001, so we only re-add INSERT,
--      UPDATE, and DELETE here. RLS on the row itself stays
--      `auth.uid() = id` for owner — same blast radius as before.
--
--   2. A BEFORE UPDATE trigger that rejects subscription_tier or
--      subscription_at changes from any caller whose JWT role isn't
--      'service_role'. The revenuecat-webhook EF runs with the
--      service-role key, so its writes pass through unchanged.
--      Direct psql writes (migrations, seed.sql) have no JWT context
--      so v_role is empty and they're allowed too — the trigger only
--      gates user-JWT-context writes, which is exactly the threat
--      shape (authenticated PostgREST → user_profiles UPDATE).
--
-- The trigger reads tier columns via NEW / OLD rather than checking
-- which columns appeared in the UPDATE statement, so a future
-- column-rename or trigger-bypass attempt via to_jsonb() can't slip
-- past it.

drop policy "users own their profile" on user_profiles;

create policy "users insert own profile"
  on user_profiles for insert
  with check (auth.uid() = id);

create policy "users update own profile"
  on user_profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);

create policy "users delete own profile"
  on user_profiles for delete
  using (auth.uid() = id);

create or replace function lock_subscription_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
begin
  -- Service-role and direct-SQL (empty role) callers are trusted.
  -- Everything else (authenticated, anon, any future role) gets the
  -- gate applied.
  if v_role = 'service_role' or v_role = '' then
    return new;
  end if;

  if old.subscription_tier is distinct from new.subscription_tier then
    raise exception 'subscription_tier is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  if old.subscription_at is distinct from new.subscription_at then
    raise exception 'subscription_at is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger user_profiles_lock_subscription_columns
  before update on user_profiles
  for each row
  execute function lock_subscription_columns();
