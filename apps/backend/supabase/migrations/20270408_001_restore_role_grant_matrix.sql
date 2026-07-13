-- Restore + version-control the public-schema grant matrix for the app
-- roles (anon, authenticated, service_role).
--
-- Incident (2026-07-13): onboarding failed in prod with
--   42501 "permission denied for table user_profiles"  (PATCH)
--   42501 "permission denied for table user_settings"  (GET ?select=prefs)
-- i.e. the `authenticated` role had lost base table privileges in prod.
--
-- Root cause: the DML grants (insert/update/delete) and several table
-- SELECTs on these tables were never expressed in a migration — they
-- existed only via Supabase's implicit default privileges
-- (`grant all on all tables ... to anon, authenticated, service_role`).
-- Nothing in version control re-asserts them, so once prod lost some
-- (restore / manual revoke / default-privileges drift) there was no
-- source of truth to bring it back. The column-lockdown migrations
-- (20260707_001, 20260810_001, clubs/events/checkpoint_crossings,
-- coach_messages, event_attendees, challenge_participants) only ever
-- adjusted SELECT/UPDATE on a handful of tables; the broad DML surface
-- was implicit. This is the same `permission denied for table` class the
-- 20260817_001 revert already hit once.
--
-- Fix: make the intended grant matrix explicit and idempotent. Every
-- statement below is additive (`grant`), so replaying it on any
-- environment can only bring a role UP to the intended surface — it
-- never tightens, and it never grants table-level SELECT on a
-- column-locked table (those keep their per-column carve-out at the
-- bottom). Generated from the canonical fully-migrated schema; RLS
-- remains the actual row-level gate on every one of these tables.
--
-- Scope: SELECT/INSERT/UPDATE/DELETE only (the privileges PostgREST +
-- the app use). REFERENCES/TRIGGER/TRUNCATE are deliberately omitted.
-- app_quota + deletion_audit_log stay service_role-only (no line here);
-- checkpoint_crossings is anon/authenticated-readable via its column
-- carve-out only.

grant delete, insert, select, update on public.account_deletion_receipts to anon;
grant delete, insert, select, update on public.account_deletion_receipts to authenticated;
grant delete, insert, select, update on public.account_deletion_receipts to service_role;
grant delete, insert, select, update on public.achievements to anon;
grant delete, insert, select, update on public.achievements to authenticated;
grant delete, insert, select, update on public.achievements to service_role;
grant delete, insert, select, update on public.app_admins to anon;
grant delete, insert, select, update on public.app_admins to authenticated;
grant delete, insert, select, update on public.app_admins to service_role;
grant delete, insert, select, update on public.app_quota to service_role;
grant delete, insert, select, update on public.body_metrics to anon;
grant delete, insert, select, update on public.body_metrics to authenticated;
grant delete, insert, select, update on public.body_metrics to service_role;
grant delete, insert, select, update on public.challenge_badges to anon;
grant delete, insert, select, update on public.challenge_badges to authenticated;
grant delete, insert, select, update on public.challenge_badges to service_role;
grant delete, insert, select on public.challenge_participants to anon;
grant delete, insert, select on public.challenge_participants to authenticated;
grant delete, insert, select, update on public.challenge_participants to service_role;
grant delete, insert, select, update on public.challenges to anon;
grant delete, insert, select, update on public.challenges to authenticated;
grant delete, insert, select, update on public.challenges to service_role;
grant delete, insert, select, update on public.checkpoint_crossings to service_role;
grant delete, insert, select, update on public.club_members to anon;
grant delete, insert, select, update on public.club_members to authenticated;
grant delete, insert, select, update on public.club_members to service_role;
grant delete, insert, select, update on public.club_photos to anon;
grant delete, insert, select, update on public.club_photos to authenticated;
grant delete, insert, select, update on public.club_photos to service_role;
grant delete, insert, select, update on public.club_posts to anon;
grant delete, insert, select, update on public.club_posts to authenticated;
grant delete, insert, select, update on public.club_posts to service_role;
grant delete, insert, update on public.clubs to anon;
grant delete, insert, update on public.clubs to authenticated;
grant delete, insert, select, update on public.clubs to service_role;
grant delete, insert, select, update on public.coach_athletes to anon;
grant delete, insert, select, update on public.coach_athletes to authenticated;
grant delete, insert, select, update on public.coach_athletes to service_role;
grant delete, insert, select, update on public.coach_messages to anon;
grant delete, insert, select on public.coach_messages to authenticated;
grant delete, insert, select, update on public.coach_messages to service_role;
grant delete, insert, select, update on public.deletion_audit_log to service_role;
grant delete, insert, select, update on public.device_tokens to anon;
grant delete, insert, select, update on public.device_tokens to authenticated;
grant delete, insert, select, update on public.device_tokens to service_role;
grant delete, insert, select, update on public.direct_messages to anon;
grant delete, insert, select, update on public.direct_messages to authenticated;
grant delete, insert, select, update on public.direct_messages to service_role;
grant delete, insert, select, update on public.donations to anon;
grant delete, insert, select, update on public.donations to authenticated;
grant delete, insert, select, update on public.donations to service_role;
grant delete, insert, select, update on public.email_suppressions to anon;
grant delete, insert, select, update on public.email_suppressions to authenticated;
grant delete, insert, select, update on public.email_suppressions to service_role;
grant delete, insert, select on public.event_attendees to anon;
grant delete, insert, select on public.event_attendees to authenticated;
grant delete, insert, select, update on public.event_attendees to service_role;
grant delete, insert, select, update on public.event_checkpoints to anon;
grant delete, insert, select, update on public.event_checkpoints to authenticated;
grant delete, insert, select, update on public.event_checkpoints to service_role;
grant delete, insert, select, update on public.event_exceptions to anon;
grant delete, insert, select, update on public.event_exceptions to authenticated;
grant delete, insert, select, update on public.event_exceptions to service_role;
grant delete, insert, select, update on public.event_orders to anon;
grant delete, insert, select, update on public.event_orders to authenticated;
grant delete, insert, select, update on public.event_orders to service_role;
grant delete, insert, select, update on public.event_pricing to anon;
grant delete, insert, select, update on public.event_pricing to authenticated;
grant delete, insert, select, update on public.event_pricing to service_role;
grant delete, insert, select, update on public.event_result_claims to anon;
grant delete, insert, select, update on public.event_result_claims to authenticated;
grant delete, insert, select, update on public.event_result_claims to service_role;
grant delete, insert, select, update on public.event_results to anon;
grant delete, insert, select, update on public.event_results to authenticated;
grant delete, insert, select, update on public.event_results to service_role;
grant delete, insert, update on public.events to anon;
grant delete, insert, update on public.events to authenticated;
grant delete, insert, select, update on public.events to service_role;
grant delete, insert, select, update on public.exercises to anon;
grant delete, insert, select, update on public.exercises to authenticated;
grant delete, insert, select, update on public.exercises to service_role;
grant delete, insert, select, update on public.fitness_snapshots to anon;
grant delete, insert, select, update on public.fitness_snapshots to authenticated;
grant delete, insert, select, update on public.fitness_snapshots to service_role;
grant delete, insert, select, update on public.food_log to anon;
grant delete, insert, select, update on public.food_log to authenticated;
grant delete, insert, select, update on public.food_log to service_role;
grant delete, insert, select, update on public.fundraisers to anon;
grant delete, insert, select, update on public.fundraisers to authenticated;
grant delete, insert, select, update on public.fundraisers to service_role;
grant delete, insert, select, update on public.gear to anon;
grant delete, insert, select, update on public.gear to authenticated;
grant delete, insert, select, update on public.gear to service_role;
grant delete, insert, select, update on public.gear_rotation_members to anon;
grant delete, insert, select, update on public.gear_rotation_members to authenticated;
grant delete, insert, select, update on public.gear_rotation_members to service_role;
grant delete, insert, select, update on public.gear_rotations to anon;
grant delete, insert, select, update on public.gear_rotations to authenticated;
grant delete, insert, select, update on public.gear_rotations to service_role;
grant delete, insert, select, update on public.gear_wear_logs to anon;
grant delete, insert, select, update on public.gear_wear_logs to authenticated;
grant delete, insert, select, update on public.gear_wear_logs to service_role;
grant delete, insert, select, update on public.gym_routine_exercises to anon;
grant delete, insert, select, update on public.gym_routine_exercises to authenticated;
grant delete, insert, select, update on public.gym_routine_exercises to service_role;
grant delete, insert, select, update on public.gym_routine_sets to anon;
grant delete, insert, select, update on public.gym_routine_sets to authenticated;
grant delete, insert, select, update on public.gym_routine_sets to service_role;
grant delete, insert, select, update on public.gym_routines to anon;
grant delete, insert, select, update on public.gym_routines to authenticated;
grant delete, insert, select, update on public.gym_routines to service_role;
grant delete, insert, select, update on public.gym_sets to anon;
grant delete, insert, select, update on public.gym_sets to authenticated;
grant delete, insert, select, update on public.gym_sets to service_role;
grant delete, insert, select, update on public.gym_workouts to anon;
grant delete, insert, select, update on public.gym_workouts to authenticated;
grant delete, insert, select, update on public.gym_workouts to service_role;
grant delete, insert, select, update on public.instructor_payout_accounts to anon;
grant delete, insert, select, update on public.instructor_payout_accounts to authenticated;
grant delete, insert, select, update on public.instructor_payout_accounts to service_role;
grant delete, insert, select, update on public.integrations to anon;
grant delete, insert, select, update on public.integrations to authenticated;
grant delete, insert, select, update on public.integrations to service_role;
grant delete, insert, select, update on public.jobs to anon;
grant delete, insert, select, update on public.jobs to authenticated;
grant delete, insert, select, update on public.jobs to service_role;
grant delete, insert, select, update on public.lifecycle_email_log to anon;
grant delete, insert, select, update on public.lifecycle_email_log to authenticated;
grant delete, insert, select, update on public.lifecycle_email_log to service_role;
grant delete, insert, select, update on public.live_run_pings to anon;
grant delete, insert, select, update on public.live_run_pings to authenticated;
grant delete, insert, select, update on public.live_run_pings to service_role;
grant delete, insert, select, update on public.meal_template_items to anon;
grant delete, insert, select, update on public.meal_template_items to authenticated;
grant delete, insert, select, update on public.meal_template_items to service_role;
grant delete, insert, select, update on public.meal_templates to anon;
grant delete, insert, select, update on public.meal_templates to authenticated;
grant delete, insert, select, update on public.meal_templates to service_role;
grant select on public.monthly_funding to anon;
grant select on public.monthly_funding to authenticated;
grant delete, insert, select, update on public.monthly_funding to service_role;
grant delete, insert, select, update on public.notifications to anon;
grant delete, insert, select, update on public.notifications to authenticated;
grant delete, insert, select, update on public.notifications to service_role;
grant select on public.personal_records to anon;
grant select on public.personal_records to authenticated;
grant delete, insert, select, update on public.personal_records to service_role;
grant delete, insert, select, update on public.plan_weeks to anon;
grant delete, insert, select, update on public.plan_weeks to authenticated;
grant delete, insert, select, update on public.plan_weeks to service_role;
grant delete, insert, select, update on public.plan_workouts to anon;
grant delete, insert, select, update on public.plan_workouts to authenticated;
grant delete, insert, select, update on public.plan_workouts to service_role;
grant delete, insert, select, update on public.public_recaps to anon;
grant delete, insert, select, update on public.public_recaps to authenticated;
grant delete, insert, select, update on public.public_recaps to service_role;
grant delete, insert, select, update on public.race_listings to anon;
grant delete, insert, select, update on public.race_listings to authenticated;
grant delete, insert, select, update on public.race_listings to service_role;
grant delete, insert, select, update on public.race_pings to anon;
grant delete, insert, select, update on public.race_pings to authenticated;
grant delete, insert, select, update on public.race_pings to service_role;
grant delete, insert, select, update on public.race_sessions to anon;
grant delete, insert, select, update on public.race_sessions to authenticated;
grant delete, insert, select, update on public.race_sessions to service_role;
grant delete, insert, select, update on public.rate_limits to anon;
grant delete, insert, select, update on public.rate_limits to authenticated;
grant delete, insert, select, update on public.rate_limits to service_role;
grant delete, insert, select, update on public.recipe_ingredients to anon;
grant delete, insert, select, update on public.recipe_ingredients to authenticated;
grant delete, insert, select, update on public.recipe_ingredients to service_role;
grant delete, insert, select, update on public.recipes to anon;
grant delete, insert, select, update on public.recipes to authenticated;
grant delete, insert, select, update on public.recipes to service_role;
grant delete, insert, select, update on public.reports to anon;
grant delete, insert, select, update on public.reports to authenticated;
grant delete, insert, select, update on public.reports to service_role;
grant delete, insert, select, update on public.route_conditions to anon;
grant delete, insert, select, update on public.route_conditions to authenticated;
grant delete, insert, select, update on public.route_conditions to service_role;
grant delete, insert, select, update on public.route_markers to anon;
grant delete, insert, select, update on public.route_markers to authenticated;
grant delete, insert, select, update on public.route_markers to service_role;
grant delete, insert, select, update on public.route_photos to anon;
grant delete, insert, select, update on public.route_photos to authenticated;
grant delete, insert, select, update on public.route_photos to service_role;
grant delete, insert, select, update on public.route_reviews to anon;
grant delete, insert, select, update on public.route_reviews to authenticated;
grant delete, insert, select, update on public.route_reviews to service_role;
grant delete, insert, select, update on public.routes to anon;
grant delete, insert, select, update on public.routes to authenticated;
grant delete, insert, select, update on public.routes to service_role;
grant delete, insert, select, update on public.run_comments to anon;
grant delete, insert, select, update on public.run_comments to authenticated;
grant delete, insert, select, update on public.run_comments to service_role;
grant delete, insert, select, update on public.run_gear to anon;
grant delete, insert, select, update on public.run_gear to authenticated;
grant delete, insert, select, update on public.run_gear to service_role;
grant delete, insert, select, update on public.run_kudos to anon;
grant delete, insert, select, update on public.run_kudos to authenticated;
grant delete, insert, select, update on public.run_kudos to service_role;
grant delete, insert, select, update on public.run_matched_tracks to anon;
grant delete, insert, select, update on public.run_matched_tracks to authenticated;
grant delete, insert, select, update on public.run_matched_tracks to service_role;
grant delete, insert, select, update on public.run_photos to anon;
grant delete, insert, select, update on public.run_photos to authenticated;
grant delete, insert, select, update on public.run_photos to service_role;
grant delete, insert, select, update on public.runs to anon;
grant delete, insert, select, update on public.runs to authenticated;
grant delete, insert, select, update on public.runs to service_role;
grant delete, insert, select, update on public.safety_contacts to anon;
grant delete, insert, select, update on public.safety_contacts to authenticated;
grant delete, insert, select, update on public.safety_contacts to service_role;
grant delete, insert, select, update on public.saved_routes to anon;
grant delete, insert, select, update on public.saved_routes to authenticated;
grant delete, insert, select, update on public.saved_routes to service_role;
grant delete, insert, select, update on public.segment_efforts to anon;
grant delete, insert, select, update on public.segment_efforts to authenticated;
grant delete, insert, select, update on public.segment_efforts to service_role;
grant delete, insert, select, update on public.segments to anon;
grant delete, insert, select, update on public.segments to authenticated;
grant delete, insert, select, update on public.segments to service_role;
grant delete, insert, select, update on public.session_plan_blocks to anon;
grant delete, insert, select, update on public.session_plan_blocks to authenticated;
grant delete, insert, select, update on public.session_plan_blocks to service_role;
grant delete, insert, select, update on public.session_plan_items to anon;
grant delete, insert, select, update on public.session_plan_items to authenticated;
grant delete, insert, select, update on public.session_plan_items to service_role;
grant delete, insert, select, update on public.session_plans to anon;
grant delete, insert, select, update on public.session_plans to authenticated;
grant delete, insert, select, update on public.session_plans to service_role;
grant delete, insert, select, update on public.training_plans to anon;
grant delete, insert, select, update on public.training_plans to authenticated;
grant delete, insert, select, update on public.training_plans to service_role;
grant delete, insert, select, update on public.user_blocks to anon;
grant delete, insert, select, update on public.user_blocks to authenticated;
grant delete, insert, select, update on public.user_blocks to service_role;
grant delete, insert, select, update on public.user_coach_usage to anon;
grant delete, insert, select, update on public.user_coach_usage to authenticated;
grant delete, insert, select, update on public.user_coach_usage to service_role;
grant delete, insert, select, update on public.user_device_settings to anon;
grant delete, insert, select, update on public.user_device_settings to authenticated;
grant delete, insert, select, update on public.user_device_settings to service_role;
grant delete, insert, select, update on public.user_follows to anon;
grant delete, insert, select, update on public.user_follows to authenticated;
grant delete, insert, select, update on public.user_follows to service_role;
grant delete, insert, update on public.user_profiles to anon;
grant delete, insert, update on public.user_profiles to authenticated;
grant delete, insert, select, update on public.user_profiles to service_role;
grant delete, insert, select, update on public.user_settings to anon;
grant delete, insert, select, update on public.user_settings to authenticated;
grant delete, insert, select, update on public.user_settings to service_role;
grant delete, insert, select, update on public.webhook_events to anon;
grant delete, insert, select, update on public.webhook_events to authenticated;
grant delete, insert, select, update on public.webhook_events to service_role;

-- Column-scoped carve-outs (privacy / immutability locks): tables whose
-- table-level SELECT or UPDATE is intentionally withheld, re-granted per
-- column instead.
grant update (team_club_id) on public.challenge_participants to authenticated;
grant select (bib, checkpoint_id, event_id, id, in_time, instance_start, out_time, recorded_at, runner_name, updated_at, user_id) on public.checkpoint_crossings to anon;
grant select (bib, checkpoint_id, event_id, id, in_time, instance_start, out_time, recorded_at, runner_name, updated_at, user_id) on public.checkpoint_crossings to authenticated;
grant select (avatar_url, created_at, description, facebook_url, id, instagram_url, is_public, is_verified, join_policy, location_label, location_point, member_count, name, owner_id, requires_activity_waiver, shadow_hidden, slug, strava_url, updated_at, website_url) on public.clubs to anon;
grant select (avatar_url, created_at, description, facebook_url, id, instagram_url, is_public, is_verified, join_policy, location_label, location_point, member_count, name, owner_id, requires_activity_waiver, shadow_hidden, slug, strava_url, updated_at, website_url) on public.clubs to authenticated;
grant update (archived_at, reaction) on public.coach_messages to authenticated;
grant update (event_id, instance_start, status, user_id) on public.event_attendees to authenticated;
grant select (author_id, capacity, category, club_id, created_at, description, discipline, distance_m, duration_min, gym_template, id, is_public, meet_label, pace_target_sec, recurrence_byday, recurrence_count, recurrence_freq, recurrence_until, route_id, session_plan_id, starts_at, timezone, title, updated_at) on public.events to anon;
grant select (author_id, capacity, category, club_id, created_at, description, discipline, distance_m, duration_min, gym_template, id, is_public, meet_label, pace_target_sec, recurrence_byday, recurrence_count, recurrence_freq, recurrence_until, route_id, session_plan_id, starts_at, timezone, title, updated_at) on public.events to authenticated;
grant select (avatar_url, created_at, display_name, id) on public.user_profiles to anon;
grant select (avatar_url, created_at, display_name, id) on public.user_profiles to authenticated;
