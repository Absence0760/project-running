-- Covering indexes for every foreign key that lacked one (Supabase
-- performance advisor: "Unindexed foreign keys", lint 0001).
--
-- Without a covering index, every DELETE / UPDATE of a referenced parent
-- row seq-scans the child table to enforce the FK — the delete-account
-- cascade pays this on live_run_pings, race_pings, notifications,
-- checkpoint_crossings, and friends, and it gets linearly worse as those
-- tables grow. The reverse joins (feed lookups by author, order lookups by
-- host) ride the same indexes.
--
-- Names follow the existing <table>_<column> convention. Generated from
-- pg_constraint against the fully-migrated schema; the companion pgtap
-- catch-all (tests/fk_covering_index_test.sql) keeps future FKs indexed.

create index app_admins_granted_by on public.app_admins (granted_by);
create index challenge_badges_challenge_id on public.challenge_badges (challenge_id);
create index challenge_participants_team_club_id on public.challenge_participants (team_club_id);
create index challenges_creator_id on public.challenges (creator_id);
create index checkpoint_crossings_recorded_by on public.checkpoint_crossings (recorded_by);
create index checkpoint_crossings_user_id on public.checkpoint_crossings (user_id);
create index club_posts_author_id on public.club_posts (author_id);
create index coach_messages_plan_id on public.coach_messages (plan_id);
create index donations_donor_user_id on public.donations (donor_user_id);
create index donations_owner_user_id on public.donations (owner_user_id);
create index event_checkpoints_created_by on public.event_checkpoints (created_by);
create index event_checkpoints_route_marker_id on public.event_checkpoints (route_marker_id);
create index event_exceptions_cancelled_by on public.event_exceptions (cancelled_by);
create index event_orders_host_user_id on public.event_orders (host_user_id);
create index event_result_claims_claimant_id on public.event_result_claims (claimant_id);
create index event_result_claims_decided_by on public.event_result_claims (decided_by);
create index event_results_organiser_approved_by on public.event_results (organiser_approved_by);
create index events_author_id on public.events (author_id);
create index events_host_user_id on public.events (host_user_id);
create index events_route_id on public.events (route_id);
create index fundraisers_owner_user_id on public.fundraisers (owner_user_id);
create index gear_wear_logs_gear_id on public.gear_wear_logs (gear_id);
create index global_segments_created_by on public.global_segments (created_by);
create index integrations_access_token_secret_id on public.integrations (access_token_secret_id);
create index integrations_refresh_token_secret_id on public.integrations (refresh_token_secret_id);
create index live_run_pings_user_id on public.live_run_pings (user_id);
create index notifications_achievement_id on public.notifications (achievement_id);
create index notifications_actor_id on public.notifications (actor_id);
create index notifications_challenge_id on public.notifications (challenge_id);
create index notifications_club_id on public.notifications (club_id);
create index notifications_comment_id on public.notifications (comment_id);
create index notifications_event_id on public.notifications (event_id);
create index notifications_plan_id on public.notifications (plan_id);
create index plan_workouts_updated_by on public.plan_workouts (updated_by);
create index race_listings_submitted_by on public.race_listings (submitted_by);
create index race_pings_user_id on public.race_pings (user_id);
create index race_sessions_started_by on public.race_sessions (started_by);
create index reports_reviewed_by on public.reports (reviewed_by);
create index route_conditions_user_id on public.route_conditions (user_id);
create index route_markers_user_id on public.route_markers (user_id);
create index route_reviews_user_id on public.route_reviews (user_id);
