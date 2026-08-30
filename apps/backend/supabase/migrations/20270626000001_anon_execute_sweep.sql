-- The rest of the EXECUTE sweep 20270625000001 opened: every remaining
-- function in `public` (plus one in `private`) that an anonymous PostgREST
-- caller can reach on the image Cloud and CI run, and that nothing meant to
-- be anon-callable.
--
-- ── Why the statement form ──
-- 20270625000001's header and decisions.md § 799 carry the mechanism. In one
-- line: a fresh function's ACL is `proacl` NULL (owner + PUBLIC) on a current
-- workstation CLI and an explicit {anon, authenticated, service_role} on Cloud
-- and CI, so `revoke ... from public` withholds on one image and
-- `revoke ... from anon` on the other. Only naming both withholds on both.
--
-- ── How the set was derived, and why it is not the guard's list ──
-- The 444 migrations before this one were replayed against the catalogue with
-- the initial ACL as the one free variable. Under the workstation's rule the
-- replay reproduces the live catalogue exactly (264 of 264 functions, zero
-- over- and zero under-predictions); under CI's rule the same model says 198 of
-- the 264 are anon-executable. Subtracting the 46 that carry a deliberate
-- `grant execute ... to anon` and the trigger-returning ones leaves 72
-- callable functions anon holds EXECUTE on for no stated reason.
--
-- That is a different set from "every migration that wrote a single-grantee
-- revoke", in both directions. 18 of the 72 were never revoked from ANYTHING —
-- their migration wrote only `grant execute ... to authenticated`, so no
-- revoke exists to be malformed and a statement-shaped scan is silent about
-- them, while on Cloud they are as open as the rest. Those 18 are the C and D
-- blocks below and include `increment_coach_usage(uuid)`, which takes the
-- target user id as a parameter. Conversely, `enqueue_run_rematch` and
-- `segment_leaderboard_tiered` still carry a malformed revoke in history and
-- are already closed, because 20270625000001 re-issued them; history cannot be
-- edited, so a statement-shaped report keeps naming them.
--
-- ── What an anonymous caller could do before this ──
-- Most bodies refuse a null `auth.uid()` themselves and the grant was simply
-- not doing the job its migration claimed. These did not:
--   * `claim_next_job` / `finish_job` / `defer_job` — the whole job-queue API.
--     A caller with the publishable key could drain the queue: `claim_next_job`
--     returns a queued job's payload and burns an attempt, `finish_job` marks
--     any job succeeded, `defer_job` reschedules it. Map-matching, exports and
--     every notification email stop, and the payloads are disclosed on the way
--     out.
--   * `enqueue_weekly_digests` / `enqueue_event_reminders` /
--     `enqueue_lifecycle_drip` — anonymous mail sends, batched over every
--     eligible account.
--   * `clear_push_subscription(uuid, text)` and `clear_device_token(text)` —
--     unauthenticated deletion of a specific device's push registration, which
--     is the delivery path the safety-contact escalation rides on.
--   * `auto_hide_target(text, uuid)` — the shadow-hide evaluator, RLS bypassed:
--     an anonymous caller could force the hide-and-notify transition on any
--     user, club or route whose pending reports already reached the threshold.
--   * `cron_schedule_status(text)` / `jobs_stuck_summary` / `jobs_failed_summary`
--     / `find_stuck_jobs` / `find_failed_jobs` — queue and cron state readable
--     without an account.
-- `get_integration_tokens` / `set_integration_tokens` / `set_integration_tokens_cas`
-- (Strava and Garmin OAuth material) and `block_user` are on the list because
-- their grant said nothing, not because they answered: each raises before
-- touching a row when the caller is not the subject. `get_my_profile` and
-- `mark_attendance` are the same shape one step out — they return no rows, or
-- delegate the check to a `private` oracle that a null `auth.uid()` fails.
-- Closing them puts the privilege layer back in front of the body rather than
-- leaving the body as the only thing in front of the data.
--
-- ── The three roles, treated differently on purpose ──
-- `anon` is revoked everywhere below. `authenticated` is revoked only where the
-- function's OWN migration already showed it was not meant to have it — the
-- cron/queue family, whose local ACL is `{postgres, service_role}` and whose
-- documented contract is "service_role only". That half matters: any signed-up
-- account holds the same create-time grant anon does, so on Cloud a logged-in
-- user could drain the job queue too.
--
-- `service_role` is never revoked here: it is a server credential that already
-- bypasses RLS on every table these functions touch, so withdrawing EXECUTE
-- would change no attacker's reach while risking a server path a workstation
-- cannot enumerate. Where PUBLIC was its only local path (blocks C and D) it is
-- granted back by name, so both images end up with the same ACL rather than
-- leaving the workstation narrower than prod — `event_is_athletic` is what
-- caught that: five pgtap suites insert `event_results` under
-- `set local role service_role` and its trigger is SECURITY INVOKER.
--
-- ── What stays anon-callable, and why ──
-- `is_challenge_visible(uuid)` keeps its grant. Two `challenge_participants`
-- policies are `to public` and name it, anon holds SELECT on that table, and a
-- policy expression is privilege-checked against the QUERYING role — so
-- revoking turns an anonymous read of a public challenge's participants from
-- rows into `42501: permission denied for function is_challenge_visible`.
-- Measured both ways. Every other routine here was checked the same way against
-- `pg_policy`, view definitions, CHECK constraints, index and DEFAULT
-- expressions and other SECURITY INVOKER function bodies; two more carry a
-- reference and are still revoked, because in both cases the referencing path
-- is a write anon can never complete:
--   * `_run_comment_parent_is_top_level(uuid)` is named by a `run_comments`
--     INSERT policy `to public`. Anon holds INSERT on the table but the policy
--     also requires `auth.uid() = user_id`, so the insert is refused either
--     way; only the error changes.
--   * `event_is_athletic(uuid)` is called by the SECURITY INVOKER trigger
--     functions `reject_nonathletic_result` and `reject_nonathletic_race`,
--     which run as the writing role — hence the explicit
--     `authenticated, service_role` grant beside its revoke, since PUBLIC was
--     the only path either role had.
--
-- ── Trigger-returning functions (the T block) ──
-- Those thirteen are NOT a closed hole. `select enqueue_welcome_email()` raises
-- 0A000 for every role, so no grant makes a trigger function callable through
-- PostgREST. They are here because their own migrations wrote a revoke that
-- withholds nothing on Cloud, and an intent that is false on the image it was
-- written for is worth making true — not because anything could reach them.
--
-- ── Online safety ──
-- GRANT and REVOKE take no lock on the target relation, only an
-- AccessShareLock on the catalogue entry (docs/backend/migration_locks.md
-- § Lock reference, measured on PG 17.6), so none of the online-DDL machinery
-- applies. No table DDL, no signatures, no bodies: neither row-type generator
-- moves.

-- A. Revoked from PUBLIC by their own migration, which then granted
-- `authenticated` (six of them `authenticated, service_role`). The revoke never
-- named anon, so on Cloud the create-time anon grant is still standing.
revoke execute on function public._run_comment_parent_is_top_level(parent_id uuid) from public, anon;
revoke execute on function public.admin_unhide_target(p_target_kind text, p_target_id uuid) from public, anon;
revoke execute on function public.am_i_admin() from public, anon;
revoke execute on function public.block_user(p_target uuid, p_reason text) from public, anon;
revoke execute on function public.check_rate_limit(p_user_id uuid, p_bucket text, p_max integer, p_window_seconds integer) from public, anon;
revoke execute on function public.check_rate_limit_tiered(p_user_id uuid, p_bucket text, p_free_max integer, p_pro_max integer, p_window_seconds integer) from public, anon;
revoke execute on function public.clone_gym_routine_template(p_template_id uuid) from public, anon;
revoke execute on function public.coach_roster_summary() from public, anon;
revoke execute on function public.confirm_safety_contact(p_id uuid, p_sms_opt_in boolean) from public, anon;
revoke execute on function public.decline_safety_contact(p_id uuid) from public, anon;
revoke execute on function public.fetch_pending_reports() from public, anon;
revoke execute on function public.fetch_reports_for_target(p_target_kind text, p_target_id uuid) from public, anon;
revoke execute on function public.get_club_invite_token(target_club uuid) from public, anon;
revoke execute on function public.get_integration_tokens(p_user_id uuid, p_provider text) from public, anon;
revoke execute on function public.get_my_profile() from public, anon;
revoke execute on function public.gym_exercise_names() from public, anon;
revoke execute on function public.gym_exercise_records() from public, anon;
revoke execute on function public.gym_exercise_set_history(p_name text) from public, anon;
revoke execute on function public.gym_exercise_set_history_batch(p_names text[]) from public, anon;
revoke execute on function public.gym_has_weighted_sets() from public, anon;
revoke execute on function public.gym_routine_history(p_routine_id uuid, p_recent_limit integer) from public, anon;
revoke execute on function public.gym_workout_summaries(p_limit integer) from public, anon;
revoke execute on function public.host_can_take_payment(p_user_id uuid) from public, anon;
revoke execute on function public.job_scheduled_at_for_user(p_user_id uuid) from public, anon;
revoke execute on function public.mark_attendance(p_event_id uuid, p_user_id uuid, p_instance_start timestamp with time zone, p_attendance text) from public, anon;
revoke execute on function public.my_pending_safety_requests() from public, anon;
revoke execute on function public.publish_gym_routine_as_template(p_routine_id uuid, p_club_id uuid) from public, anon;
revoke execute on function public.resolve_target_reports(p_target_kind text, p_target_id uuid, p_status text, p_resolution text) from public, anon;
revoke execute on function public.set_gym_routine_public(p_routine_id uuid, p_public boolean) from public, anon;
revoke execute on function public.set_integration_tokens(p_user_id uuid, p_provider text, p_access_token text, p_refresh_token text, p_token_expiry timestamp with time zone) from public, anon;
revoke execute on function public.set_integration_tokens_cas(p_user_id uuid, p_provider text, p_expected_refresh_token text, p_access_token text, p_refresh_token text, p_token_expiry timestamp with time zone) from public, anon;
revoke execute on function public.set_safety_sms_opt_in(p_id uuid, p_opt_in boolean) from public, anon;
revoke execute on function public.submit_report(p_target_kind text, p_target_id uuid, p_reason text, p_notes text) from public, anon;
revoke execute on function public.unblock_user(p_target uuid) from public, anon;

-- B. No client role was ever meant to hold these: the local ACL is
-- `{postgres}` or `{postgres, service_role}`, the callers are pg_cron, the Go
-- worker under service_role, or a SECURITY DEFINER trigger that evaluates them
-- as the owner. `authenticated` joins anon in the revoke for that reason —
-- matching `cleanup_stale_export_blobs` (20260720_001) and
-- `cleanup_stale_rate_limits` (20270625000001).
revoke execute on function public._privacy_downsample(arr jsonb, max_out integer) from public, anon, authenticated;
revoke execute on function public.auto_hide_target(p_target_kind text, p_target_id uuid) from public, anon, authenticated;
revoke execute on function public.claim_next_job(worker_id text, kind_filter text) from public, anon, authenticated;
revoke execute on function public.cleanup_account_deletion_receipts() from public, anon, authenticated;
revoke execute on function public.cleanup_stale_live_run_pings() from public, anon, authenticated;
revoke execute on function public.cleanup_stale_race_pings() from public, anon, authenticated;
revoke execute on function public.cleanup_stale_user_coach_usage() from public, anon, authenticated;
revoke execute on function public.clear_device_token(p_token text) from public, anon, authenticated;
revoke execute on function public.clear_push_subscription(p_user_id uuid, p_device_id text) from public, anon, authenticated;
revoke execute on function public.cron_schedule_status(p_jobname text) from public, anon, authenticated;
revoke execute on function public.defer_job(job_id bigint, delay_seconds integer, err text) from public, anon, authenticated;
revoke execute on function public.enforce_create_rate_limit(p_bucket text, p_user_id uuid, p_max integer, p_window_seconds integer) from public, anon, authenticated;
revoke execute on function public.enqueue_event_reminders() from public, anon, authenticated;
revoke execute on function public.enqueue_lifecycle_drip() from public, anon, authenticated;
revoke execute on function public.enqueue_weekly_digests() from public, anon, authenticated;
revoke execute on function public.find_failed_jobs(p_failed_within interval) from public, anon, authenticated;
revoke execute on function public.find_stuck_jobs(p_stuck_after interval) from public, anon, authenticated;
revoke execute on function public.finish_job(job_id bigint, result_status text, err text) from public, anon, authenticated;
revoke execute on function public.jobs_failed_summary(p_failed_within interval) from public, anon, authenticated;
revoke execute on function public.jobs_stuck_summary(p_stuck_after interval) from public, anon, authenticated;
revoke execute on function public.privacy_coarsen_coord(coord double precision) from public, anon, authenticated;

-- C. Never revoked from anything. Their migration wrote only
-- `grant execute ... to authenticated`, which left the create-time PUBLIC entry
-- (workstation) or anon entry (Cloud) untouched beside it. `authenticated`
-- keeps the explicit grant it already has.
revoke execute on function public.assign_plan_to_athlete(p_source_plan_id uuid, p_athlete_id uuid, p_start_date date) from public, anon;
grant  execute on function public.assign_plan_to_athlete(p_source_plan_id uuid, p_athlete_id uuid, p_start_date date) to service_role;
revoke execute on function public.clone_public_plan(template_id uuid, new_start_date date) from public, anon;
grant  execute on function public.clone_public_plan(template_id uuid, new_start_date date) to service_role;
revoke execute on function public.dm_threads() from public, anon;
grant  execute on function public.dm_threads() to service_role;
revoke execute on function public.duplicate_plan_week(p_plan_id uuid, p_week_index integer) from public, anon;
grant  execute on function public.duplicate_plan_week(p_plan_id uuid, p_week_index integer) to service_role;
revoke execute on function public.end_coach_link(p_id uuid) from public, anon;
grant  execute on function public.end_coach_link(p_id uuid) to service_role;
revoke execute on function public.get_coach_usage(p_user_id uuid) from public, anon;
grant  execute on function public.get_coach_usage(p_user_id uuid) to service_role;
revoke execute on function public.increment_coach_usage(p_user_id uuid) from public, anon;
grant  execute on function public.increment_coach_usage(p_user_id uuid) to service_role;
revoke execute on function public.is_pro() from public, anon;
grant  execute on function public.is_pro() to service_role;
revoke execute on function public.latest_fitness_snapshot() from public, anon;
grant  execute on function public.latest_fitness_snapshot() to service_role;
revoke execute on function public.my_active_challenges() from public, anon;
grant  execute on function public.my_active_challenges() to service_role;
revoke execute on function public.public_run_counts(p_user_ids uuid[]) from public, anon;
grant  execute on function public.public_run_counts(p_user_ids uuid[]) to service_role;
revoke execute on function public.redeem_coach_invite(token text) from public, anon;
grant  execute on function public.redeem_coach_invite(token text) to service_role;

-- D. Same shape as C, but PUBLIC was the only path any role had — so the
-- revoke has to be paired with an explicit grant to the roles that call them.
-- `privacy_coarsen_coord` is in B rather than here: its only callers are the
-- SECURITY DEFINER ping triggers, so it needs no client grant at all.
revoke execute on function public.event_is_athletic(target_event uuid) from public, anon;
grant  execute on function public.event_is_athletic(target_event uuid) to authenticated, service_role;
revoke execute on function public.personal_records() from public, anon;
grant  execute on function public.personal_records() to authenticated, service_role;
revoke execute on function public.routes_intersecting_track(caller_user_id uuid, track_geojson jsonb, tolerance_m double precision, max_results integer) from public, anon;
grant  execute on function public.routes_intersecting_track(caller_user_id uuid, track_geojson jsonb, tolerance_m double precision, max_results integer) to authenticated, service_role;
revoke execute on function public.weekly_mileage(weeks_back integer) from public, anon;
grant  execute on function public.weekly_mileage(weeks_back integer) to authenticated, service_role;

-- T. Trigger-returning. Inert either way (see the header) — this only makes
-- each one's own migration true on the image it ships to.
revoke execute on function public.enqueue_club_photo_process_job() from public, anon, authenticated;
revoke execute on function public.enqueue_club_photo_process_job_on_path_fill() from public, anon, authenticated;
revoke execute on function public.enqueue_notification_email_job() from public, anon, authenticated;
revoke execute on function public.enqueue_notification_native_push_job() from public, anon, authenticated;
revoke execute on function public.enqueue_notification_web_push_job() from public, anon, authenticated;
revoke execute on function public.enqueue_photo_process_job() from public, anon, authenticated;
revoke execute on function public.enqueue_route_photo_process_job() from public, anon, authenticated;
revoke execute on function public.enqueue_route_photo_process_job_on_path_fill() from public, anon, authenticated;
revoke execute on function public.enqueue_safety_confirm_email() from public, anon, authenticated;
revoke execute on function public.enqueue_safety_finish_emails() from public, anon, authenticated;
revoke execute on function public.enqueue_subscription_emails() from public, anon, authenticated;
revoke execute on function public.enqueue_welcome_email() from public, anon, authenticated;
revoke execute on function private.enforce_consent() from public, anon, authenticated;
