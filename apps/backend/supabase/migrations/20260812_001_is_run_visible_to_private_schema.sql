-- /audit/all storage Low: `is_run_visible_to(uuid, uuid)` is a
-- SECURITY DEFINER helper that lives in `public` schema, which means
-- PostgREST exposes it as an anon-callable RPC. Anyone can hit
-- `POST /rest/v1/rpc/is_run_visible_to` and observe `true`/`false`
-- for any UUID — a run-existence oracle. The information disclosed
-- isn't strictly new (the `public_runs` view publishes the same
-- "is this run visible" answer for any UUID a caller probes), but a
-- dedicated RPC oracle is cheaper to enumerate against and feels
-- like a deliberate API surface where one isn't intended.
--
-- The audit playbook offered two alternatives:
--   (a) wrap the function in a rate-limited variant — bad: every
--       RLS evaluation on `run_kudos` / `run_comments` / `run_photos`
--       / `segment_efforts` / `live_run_pings` calls this function,
--       so a rate-limit bucket would drain on every share-page load.
--   (b) move the function to a non-PostgREST-exposed schema. ← this.
--
-- Approach: create a `private` schema that PostgREST doesn't expose
-- (Supabase's default `db_schemas = public, graphql_public, storage`
-- — `private` is outside that list), recreate the function there,
-- update every dependent RLS policy to call `private.is_run_visible_to(...)`
-- by qualified name, then drop the public-schema version.
--
-- Net effect:
--   - `POST /rest/v1/rpc/is_run_visible_to` returns 404 (PostgREST
--     can't see the function in `public` anymore).
--   - RLS policies still resolve via the qualified call. EXECUTE
--     grant on the private function to anon + authenticated +
--     service_role keeps the chain working — the qualified call
--     bypasses search_path entirely.
--   - The Storage policy on `storage.objects` for `run-photos` is
--     re-created with the qualified name too.

create schema if not exists private;

-- The private schema is for SECURITY DEFINER helpers that should be
-- callable from RLS policies but never exposed via PostgREST. Don't
-- put data tables here — Storage and the row-type generators don't
-- look at this schema.
comment on schema private is
  'SECURITY DEFINER helpers for RLS policies. Not exposed by PostgREST '
  '(see config.toml `db_schemas`). Callers must qualify names.';

-- Recreate the function in `private`. Same body, same security
-- DEFINER posture, same set search_path.
create or replace function private.is_run_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (
        r.user_id = p_user_id
        or r.is_public = true
      )
  );
$$;

-- Anon needs EXECUTE so RLS policy evaluation succeeds for
-- unauthenticated share-page viewers. The grant itself doesn't
-- expose the function via PostgREST; PostgREST exposes by SCHEMA,
-- not by grant.
grant usage on schema private to anon, authenticated, service_role;
revoke execute on function private.is_run_visible_to(uuid, uuid) from public;
grant execute on function private.is_run_visible_to(uuid, uuid)
  to anon, authenticated, service_role;

-- ───────── run_kudos ─────────
drop policy if exists "kudos readable when run is readable" on run_kudos;
drop policy if exists "users give kudos on their own behalf" on run_kudos;

create policy "kudos readable when run is readable"
  on run_kudos for select
  using (private.is_run_visible_to(run_id, auth.uid()));

create policy "users give kudos on their own behalf"
  on run_kudos for insert
  with check (
    auth.uid() = user_id
    and private.is_run_visible_to(run_id, auth.uid())
  );

-- ───────── run_comments ─────────
drop policy if exists "comments readable when run is readable" on run_comments;
drop policy if exists "users post comments on their own behalf" on run_comments;

create policy "comments readable when run is readable"
  on run_comments for select
  using (private.is_run_visible_to(run_id, auth.uid()));

create policy "users post comments on their own behalf"
  on run_comments for insert
  with check (
    auth.uid() = author_id
    and private.is_run_visible_to(run_id, auth.uid())
    and (
      parent_comment_id is null
      or _run_comment_parent_is_top_level(parent_comment_id)
    )
  );

-- ───────── run_photos ─────────
drop policy if exists "photos readable when run is readable" on run_photos;

create policy "photos readable when run is readable"
  on run_photos for select
  using (private.is_run_visible_to(run_id, auth.uid()));

-- ───────── segment_efforts ─────────
drop policy if exists "efforts readable when segment AND run are readable" on segment_efforts;

create policy "efforts readable when segment AND run are readable"
  on segment_efforts for select
  using (
    exists (select 1 from segments where segments.id = segment_efforts.segment_id)
    and private.is_run_visible_to(run_id, auth.uid())
  );

-- ───────── live_run_pings ─────────
drop policy if exists live_run_pings_visible_when_run_is on live_run_pings;

create policy live_run_pings_visible_when_run_is
  on live_run_pings for select
  using (private.is_run_visible_to(run_id, auth.uid()));

-- ───────── storage.objects (run-photos bucket) ─────────
drop policy if exists "run-photo bytes visible when parent run is visible" on storage.objects;

create policy "run-photo bytes visible when parent run is visible"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'run-photos'
    and exists (
      select 1
      from run_photos rp
      where rp.storage_path = storage.objects.name
        and private.is_run_visible_to(rp.run_id, auth.uid())
    )
  );

-- ───────── Drop the public-schema version ─────────
-- All policies above now reference `private.is_run_visible_to`; the
-- public version is dead code and the PostgREST RPC oracle.
drop function if exists public.is_run_visible_to(uuid, uuid);
