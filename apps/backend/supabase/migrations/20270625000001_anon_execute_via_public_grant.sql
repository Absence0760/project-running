-- Four functions in `public` that `anon` can execute and nothing meant it to,
-- withheld in the form that works on every image this schema runs on.
--
-- ── The mechanism, and why it reads differently depending on where you look ──
-- A function in `public` here is always owned by `postgres`, and what a fresh
-- one's ACL says depends on the Postgres image:
--
--   * Supabase Cloud and CI (`supabase/setup-cli` pinned to 2.84.2 in ci.yml)
--     carry an `alter default privileges` for `postgres` granting EXECUTE to
--     anon, authenticated and service_role. A function arrives with those three
--     BY NAME. `revoke ... from public` then removes nothing, because there is
--     no PUBLIC entry to remove — `20270623000001`'s header measured exactly
--     this and is why 31 migrations write `from public, anon`.
--   * The workstation's current CLI (2.109.1) ships an image whose `postgres`
--     default ACL is `{postgres=X/postgres}`, and a fresh function comes up
--     with `proacl` NULL — Postgres's built-in owner+PUBLIC default. There
--     `revoke ... from public` DOES withhold from anon, and `revoke ... from
--     anon` is the statement that withholds nothing.
--
-- Two shipped pgtap tests are the evidence that the two images differ, and both
-- fail locally while passing on CI: `coach_roster_summary_test` expects an anon
-- caller to reach the body and be refused by it (`coach_roster_summary` was only
-- ever revoked `from public`), and `donations_status_lock_test` calls
-- `fundraiser_totals` as service_role, which no migration ever granted.
--
-- The consequence is that neither single-grantee revoke is portable. Only
-- naming BOTH is: `from public, anon` removes the PUBLIC entry where there is
-- one and the anon entry where there is one. Every statement below is written
-- that way, and anon_execute_registry_test.sql pins the rule rather than the
-- statements.
--
-- ── The four ──
-- (1) `20260612_001` wrote `revoke execute on function enqueue_run_rematch(uuid)
--     from anon;` under the comment "Authed users only." It is the only place in
--     444 migrations where that statement stands alone, and on the local image
--     it withholds nothing: the ACL is
--     `{=X/postgres,postgres=X/postgres,authenticated=X/postgres}` and
--     `has_function_privilege('anon', …)` is true.
--
-- (2) `20260830_001` revoked `segment_leaderboard_tiered` from `public, anon` as
--     a stated audit fix — "Drops the anon execute grant. Competitive
--     leaderboards are behind auth on every comparable platform". Then
--     `20261022_001` added `p_club_id`, and `drop function` + `create function`
--     resets the ACL to whatever the image's default is. Nothing re-issued the
--     revoke, so anon has held EXECUTE since. This is the failure mode a replay
--     of the migration text cannot flag: no migration is wrong on its own words,
--     and the decision was reverted anyway.
--
--     Neither (1) nor (2) was exploitable. Both bodies raise 42501 on a null
--     `auth.uid()` before they read or write, which is why nothing noticed. The
--     privilege layer was not doing the job its own comment claimed, and the
--     function body was the only thing left doing it.
--
-- (3) + (4) answered an anonymous caller rather than refusing. Probed as
--     `set local role anon`, which is what PostgREST does for a request bearing
--     the publishable key:
--
--       * `cleanup_stale_rate_limits()` returned 0. It is SECURITY DEFINER and
--         its entire body is `delete from rate_limits where window_start < now()
--         - interval '24 hours'`. An anonymous POST to
--         /rest/v1/rpc/cleanup_stale_rate_limits clears every rate-limit window
--         old enough to matter. Its three siblings are already
--         `{postgres, service_role}` (`cleanup_stale_live_run_pings`
--         20260509_001, `cleanup_stale_user_coach_usage`,
--         `cleanup_stale_export_blobs` 20260725_001), and three later migrations
--         cite this one BY NAME as the reference for that pattern while it was
--         the only member of the family nobody had locked down.
--       * `refresh_gym_workout_totals(uuid)` returned void. It is SECURITY
--         DEFINER and updates `gym_workouts.set_count`/`volume_kg` for any
--         workout id with RLS bypassed. It recomputes from `gym_sets`, so the
--         write is idempotent and the impact is small — but it is an
--         unauthenticated write to another account's row, and its only caller is
--         the SECURITY DEFINER trigger `gym_sets_maintain_totals`, which
--         evaluates it as the owner and needs no client grant at all.
--
-- ── Who keeps what, verified after the change in a rolled-back transaction ──
-- `enqueue_run_rematch` keeps only `authenticated`'s explicit grant; no client,
-- Edge Function or worker calls it, and service_role could never satisfy the
-- body's `auth.uid()` check. `cleanup_stale_rate_limits` keeps `service_role`
-- so ops can invoke it by hand, matching its siblings; pg_cron runs it as
-- `postgres`. `segment_leaderboard_tiered` goes back to `authenticated`, which
-- is where 20260830_001 left it. `refresh_gym_workout_totals` keeps no client
-- grant: an authenticated `gym_sets` insert still recomputes its workout totals
-- afterwards, through the definer trigger.
--
-- ── Online safety ──
-- GRANT and REVOKE take no lock on any relation — only an AccessShareLock on
-- the catalogue — so none of docs/backend/migration_locks.md's online-DDL
-- machinery applies. No table DDL, no function bodies, no signatures, so
-- neither row-type generator moves.

revoke execute on function public.enqueue_run_rematch(uuid) from public, anon;

revoke execute on function public.segment_leaderboard_tiered(uuid, text, text, integer, uuid)
  from public, anon;
grant  execute on function public.segment_leaderboard_tiered(uuid, text, text, integer, uuid)
  to authenticated;

revoke execute on function public.cleanup_stale_rate_limits() from public, anon, authenticated;
grant  execute on function public.cleanup_stale_rate_limits() to service_role;

revoke execute on function public.refresh_gym_workout_totals(uuid)
  from public, anon, authenticated;

comment on function public.cleanup_stale_rate_limits() is
  'Hourly pg_cron sweep of rate_limits rows older than 24 h. SECURITY DEFINER, '
  'run by cron as postgres; service_role may invoke it by hand. Held away from '
  'anon and authenticated since 20270625000001 — the body is an unqualified '
  'DELETE, and until then an anonymous PostgREST call could clear every '
  'rate-limit window. Sibling pattern: cleanup_stale_live_run_pings '
  '(20260509_001), cleanup_stale_export_blobs (20260720_001 + 20260725_001).';

comment on function public.segment_leaderboard_tiered(uuid, text, text, integer, uuid) is
  'Tiered segment leaderboard. authenticated only, per 20260830_001 — the anon '
  'grant it dropped came back when 20261022_001 changed the signature, because '
  'drop-and-recreate resets the ACL to the image default. '
  'anon_execute_registry_test.sql pins the ACL shape so it cannot return that '
  'way again.';
