-- Parallel of 20260812_001_is_run_visible_to_private_schema.sql for
-- `is_route_visible_to(uuid, uuid)`.
--
-- The grant-hygiene migration `20260711_001_definer_grant_hygiene.sql`
-- revoked EXECUTE on `is_route_visible_to` from `public, anon` to
-- close the PostgREST RPC existence oracle on private routes. But the
-- SELECT + INSERT policies on `route_reviews` and `segments` invoke
-- the function inline from RLS evaluation — and those policies apply
-- to anon callers (the public `/share/route/<id>` page reads reviews
-- + segments through PostgREST). The 20260711_001 revoke broke that
-- read path: every anon-driven SELECT against `route_reviews` or
-- `segments` should have failed with `42501 permission denied for
-- function is_route_visible_to`.
--
-- On PostgreSQL 17.6 the failure manifests as a backend **SEGV**
-- (signal 11) instead of a clean 42501 — a server-level abort that
-- triggers crash recovery on every offending request. The crash
-- reproduces in plain psql with `set local role anon; select id from
-- route_reviews where id = '...'` against a row whose route is
-- public. Upstream PostgreSQL bug worth reporting; the project-side
-- fix is independent of whether 17.6 ships a patch.
--
-- Approach mirrors 20260812_001 exactly:
--   1. Recreate the function under the `private` schema (created by
--      20260812_001; PostgREST does not expose this schema per the
--      `db_schemas` config).
--   2. Grant EXECUTE on the qualified function to anon /
--      authenticated / service_role so RLS evaluation succeeds for
--      every dependent policy.
--   3. Replace every caller — RLS policies on `route_reviews` and
--      `segments`, plus the SECURITY DEFINER trigger function
--      `routes_run_count_trigger` — with the qualified name.
--   4. Drop the public-schema version so the PostgREST RPC oracle
--      stays closed AND so callers fail loudly (function does not
--      exist) if any unqualified reference is left behind.
--
-- This migration does NOT touch `is_route_visible_to`'s use inside
-- `routes_run_count_public_only`'s one-shot UPDATE statements — those
-- ran at migration time on 20260716_001 and aren't re-evaluated.

-- The private schema already exists (20260812_001).

create or replace function private.is_route_visible_to(p_route_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from routes r
    where r.id = p_route_id
      and (
        r.user_id = p_user_id
        or r.is_public = true
        or (
          r.club_id is not null
          and exists (
            select 1 from club_members
            where club_id = r.club_id
              and user_id = p_user_id
              and status = 'active'
          )
        )
      )
  );
$$;

revoke execute on function private.is_route_visible_to(uuid, uuid) from public;
grant execute on function private.is_route_visible_to(uuid, uuid)
  to anon, authenticated, service_role;

-- ───────── route_reviews ─────────
drop policy if exists "reviews on visible routes are readable" on route_reviews;
drop policy if exists "users insert reviews on visible routes" on route_reviews;

create policy "reviews on visible routes are readable"
  on route_reviews for select
  using (private.is_route_visible_to(route_reviews.route_id, auth.uid()));

create policy "users insert reviews on visible routes"
  on route_reviews for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and private.is_route_visible_to(route_reviews.route_id, auth.uid())
  );

-- ───────── segments ─────────
drop policy if exists "segments readable when route is readable" on segments;
drop policy if exists "segment authors create on readable routes" on segments;

create policy "segments readable when route is readable"
  on segments for select
  using (private.is_route_visible_to(segments.route_id, auth.uid()));

create policy "segment authors create on readable routes"
  on segments for insert
  with check (
    auth.uid() = created_by
    and private.is_route_visible_to(segments.route_id, auth.uid())
  );

-- ───────── routes_run_count_trigger ─────────
-- SECURITY DEFINER trigger from 20260628_001 + 20260716_001. The
-- unqualified `is_route_visible_to` references resolve via
-- `search_path = public` today; once `public.is_route_visible_to`
-- is dropped below they'd raise "function does not exist". Replace
-- the body with qualified calls.
create or replace function routes_run_count_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.route_id is not null
       and new.is_public = true
       and private.is_route_visible_to(new.route_id, new.user_id) then
      update routes set run_count = run_count + 1 where id = new.route_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.route_id is not null
       and old.is_public = true
       and private.is_route_visible_to(old.route_id, old.user_id) then
      update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    declare
      v_was_counted boolean := old.route_id is not null
        and old.is_public = true
        and private.is_route_visible_to(old.route_id, old.user_id);
      v_is_counted boolean := new.route_id is not null
        and new.is_public = true
        and private.is_route_visible_to(new.route_id, new.user_id);
    begin
      if v_was_counted and not v_is_counted then
        update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
      elsif (not v_was_counted) and v_is_counted then
        update routes set run_count = run_count + 1 where id = new.route_id;
      elsif v_was_counted and v_is_counted
            and old.route_id is distinct from new.route_id then
        update routes set run_count = greatest(run_count - 1, 0) where id = old.route_id;
        update routes set run_count = run_count + 1 where id = new.route_id;
      end if;
    end;
    return new;
  end if;
  return null;
end;
$$;

-- ───────── Drop the public-schema version ─────────
drop function if exists public.is_route_visible_to(uuid, uuid);
