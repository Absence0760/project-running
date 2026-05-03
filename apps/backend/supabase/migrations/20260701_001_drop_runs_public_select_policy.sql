-- Close the public-runs wire-leak at the DB layer.
--
-- 20260626_001 introduced the `public_runs` view (column- and
-- metadata-key-redacted, route_id / event_id existence-leak guards)
-- and switched every web + mobile reader over to it. The base-table
-- policy `public runs are readable by anyone` from 20260413_001 was
-- left in place because five sibling RLS policies subquery `runs`
-- to determine visibility:
--
--   - run_kudos          (SELECT, INSERT)
--   - run_comments       (SELECT, INSERT — INSERT was lifted into
--                         a helper in 20260529_001 to break a
--                         self-recursion, but the runs-EXISTS branch
--                         remains)
--   - run_photos         (SELECT)
--   - segment_efforts    (SELECT)
--   - live_run_pings     (SELECT)
--
-- Each one uses `exists (select 1 from runs where runs.id = ...)`
-- and relies on the public-anyone policy for non-owner visibility.
-- Drop that policy without updating these and kudos / comments /
-- photos / segments / live pings on public runs become invisible to
-- everyone but the owner.
--
-- Fix shape: lift "is this run visible to the caller" into a
-- SECURITY DEFINER helper `is_run_visible_to(run_id, user_id)` that
-- returns true when the run exists AND (is_public OR owner). The
-- helper bypasses runs RLS for its single internal query (same
-- pattern as `is_route_visible_to` in 20260628_001 and
-- `_run_comment_parent_is_top_level` in 20260529_001). All five
-- sibling policies are rewritten to call the helper instead of the
-- runs-EXISTS subquery; the public-anyone SELECT policy on runs is
-- then dropped.
--
-- Net effect:
--   - `select * from runs where is_public = true` from a non-owner
--     PostgREST request returns zero rows. The wire-leak is closed
--     at the table.
--   - `select * from public_runs ...` continues to work because
--     views run as the OWNER (postgres) and bypass runs RLS.
--   - Kudos / comments / photos / segments / live pings on public
--     runs remain visible to non-owners via the helper.
--
-- Owner-side `select * from runs where user_id = auth.uid()` is
-- unaffected — the original `users own their runs` policy from
-- 20260405_001 still allows it.

create or replace function is_run_visible_to(p_run_id uuid, p_user_id uuid)
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

grant execute on function is_run_visible_to(uuid, uuid) to authenticated, service_role;

-- ───────── run_kudos ─────────
drop policy "kudos readable when run is readable" on run_kudos;
drop policy "users give kudos on their own behalf" on run_kudos;

create policy "kudos readable when run is readable"
  on run_kudos for select
  using (is_run_visible_to(run_id, auth.uid()));

create policy "users give kudos on their own behalf"
  on run_kudos for insert
  with check (
    auth.uid() = user_id
    and is_run_visible_to(run_id, auth.uid())
  );

-- ───────── run_comments ─────────
drop policy "comments readable when run is readable" on run_comments;
drop policy "users post comments on their own behalf" on run_comments;
drop policy "run owner deletes comments on their run" on run_comments;

create policy "comments readable when run is readable"
  on run_comments for select
  using (is_run_visible_to(run_id, auth.uid()));

create policy "users post comments on their own behalf"
  on run_comments for insert
  with check (
    auth.uid() = author_id
    and is_run_visible_to(run_id, auth.uid())
    and (
      parent_comment_id is null
      or _run_comment_parent_is_top_level(parent_comment_id)
    )
  );

-- The "run owner deletes comments on their run" policy uses an
-- exists-against-runs predicate to find rows the deleter *owns*, not
-- to test visibility. Owner SELECT on runs still works (own-runs
-- policy from 20260405_001), so this branch was never load-bearing
-- on the public-anyone policy. Rewrite for clarity to use the same
-- helper approach: owner of the run can delete any comment on it.
create policy "run owner deletes comments on their run"
  on run_comments for delete
  using (
    exists (
      select 1 from runs
      where runs.id = run_comments.run_id
        and runs.user_id = auth.uid()
    )
  );

-- ───────── run_photos ─────────
drop policy "photos readable when run is readable" on run_photos;

create policy "photos readable when run is readable"
  on run_photos for select
  using (is_run_visible_to(run_id, auth.uid()));

-- The run_photos INSERT / DELETE / UPDATE policies use `runs.user_id
-- = auth.uid()` and the owner SELECT on runs still works, so they
-- don't need the helper.

-- ───────── segment_efforts ─────────
drop policy "efforts readable when segment AND run are readable" on segment_efforts;

create policy "efforts readable when segment AND run are readable"
  on segment_efforts for select
  using (
    exists (select 1 from segments where segments.id = segment_efforts.segment_id)
    and is_run_visible_to(run_id, auth.uid())
  );

-- The INSERT policy is owner-only (`runs.user_id = auth.uid()`) and
-- doesn't need the helper.

-- ───────── live_run_pings ─────────
-- The original SELECT policy already inlined "is_public OR owner",
-- but the EXISTS-against-runs at the top would still hit RLS and
-- filter to owner rows. Rewrite to use the helper.
drop policy live_run_pings_visible_when_run_is on live_run_pings;

create policy live_run_pings_visible_when_run_is
  on live_run_pings for select
  using (is_run_visible_to(run_id, auth.uid()));

-- ───────── runs ─────────
-- The wire-leak. Direct PostgREST `from('runs')` reads of public
-- rows are gone — every public reader must go through the
-- `public_runs` view (or the clip-public-track Edge Function for
-- non-owner track downloads).
drop policy "public runs are readable by anyone" on runs;
