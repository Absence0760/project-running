-- Wrap every per-row auth.uid() / auth.jwt() / auth.role() (and the one bare
-- current_setting) in RLS policy expressions in a scalar subselect
-- (Supabase performance advisor: "Auth RLS Initialization Plan", lint 0003).
--
-- A bare auth.uid() in a policy qual is re-evaluated FOR EVERY ROW the query
-- scans; wrapped as (select auth.uid()) the planner hoists it into an
-- InitPlan evaluated once per statement. Semantics are identical — the
-- functions are STABLE and read only the request JWT — so this changes no
-- policy outcome, only its cost. On list endpoints scanning thousands of
-- rows this is the difference between one JWT parse and thousands.
--
-- Statements are generated mechanically from pg_policies (deparsed quals,
-- bare calls wrapped, already-wrapped calls left alone) and applied with
-- ALTER POLICY, which only touches the named clause — roles, cmd, and the
-- policy name all stay put, so the drop-policy-wrong-name trap can't fire.
-- Where only one of USING / WITH CHECK needed the wrap, only that clause is
-- emitted.
--
-- The companion pgtap catch-all (tests/rls_initplan_test.sql) fails the
-- suite if a future policy ships a bare auth.* call, so this can't drift
-- back one policy at a time.

alter policy achievements_owner_update on public.achievements
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));
alter policy achievements_self_select on public.achievements
  using ((user_id = (select auth.uid())));
alter policy "body_metrics owner delete" on public.body_metrics
  using ((user_id = (select auth.uid())));
alter policy "body_metrics owner insert" on public.body_metrics
  with check ((user_id = (select auth.uid())));
alter policy "body_metrics owner read" on public.body_metrics
  using ((user_id = (select auth.uid())));
alter policy "body_metrics owner update" on public.body_metrics
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));
alter policy "badges readable by owner or when challenge public" on public.challenge_badges
  using ((((select auth.uid()) = user_id) OR (EXISTS ( SELECT 1
   FROM challenges c
  WHERE ((c.id = challenge_badges.challenge_id) AND (c.is_public = true))))));
alter policy "users join visible challenges" on public.challenge_participants
  with check ((((select auth.uid()) = user_id) AND is_challenge_visible(challenge_id) AND ((team_club_id IS NULL) OR (EXISTS ( SELECT 1
   FROM club_members m
  WHERE ((m.club_id = challenge_participants.team_club_id) AND (m.user_id = (select auth.uid()))))))));
alter policy "users leave their own challenge" on public.challenge_participants
  using (((select auth.uid()) = user_id));
alter policy "users update their own participant row" on public.challenge_participants
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "challenges visible to members or public" on public.challenges
  using (((is_public = true) OR (creator_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM challenge_participants p
  WHERE ((p.challenge_id = challenges.id) AND (p.user_id = (select auth.uid()))))) OR ((club_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM club_members m
  WHERE ((m.club_id = challenges.club_id) AND (m.user_id = (select auth.uid()))))))));
alter policy "creator or club admin can delete" on public.challenges
  using (((creator_id = (select auth.uid())) OR ((club_id IS NOT NULL) AND private.is_club_admin(club_id))));
alter policy "creator or club admin can update" on public.challenges
  using (((creator_id = (select auth.uid())) OR ((club_id IS NOT NULL) AND private.is_club_admin(club_id))));
alter policy "users create open challenges or admins create club ones" on public.challenges
  with check ((((select auth.uid()) = creator_id) AND ((club_id IS NULL) OR private.is_club_admin(club_id))));
alter policy "active members readable with their club" on public.club_members
  using (((status = 'active'::text) AND (EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_members.club_id) AND ((clubs.is_public = true) OR (clubs.owner_id = (select auth.uid())) OR private.is_club_member(clubs.id))))) AND (NOT private.viewer_blocks(user_id))));
alter policy "private-club members read pending rows" on public.club_members
  using (((status = ANY (ARRAY['pending'::text, 'rejected'::text])) AND (EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = club_members.club_id) AND (c.is_public = false) AND ((c.owner_id = (select auth.uid())) OR private.is_club_member(c.id))))) AND (NOT private.viewer_blocks(user_id))));
alter policy "self-join open clubs" on public.club_members
  with check ((((select auth.uid()) = user_id) AND (role = 'member'::text) AND (status = 'active'::text) AND (EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_members.club_id) AND (clubs.join_policy = 'open'::text))))));
alter policy "self-request join request-policy clubs" on public.club_members
  with check ((((select auth.uid()) = user_id) AND (role = 'member'::text) AND (status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_members.club_id) AND (clubs.join_policy = 'request'::text))))));
alter policy "users can leave clubs" on public.club_members
  using (((select auth.uid()) = user_id));
alter policy "users can see their own membership" on public.club_members
  using (((select auth.uid()) = user_id));
alter policy "club member attaches photos" on public.club_photos
  with check ((((select auth.uid()) = owner_id) AND private.is_club_member(club_id)));
alter policy "club photo owner deletes" on public.club_photos
  using (((select auth.uid()) = owner_id));
alter policy "club photo owner updates caption" on public.club_photos
  using (((select auth.uid()) = owner_id))
  with check (((select auth.uid()) = owner_id));
alter policy "club photos readable when club is visible" on public.club_photos
  using ((EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_photos.club_id) AND ((clubs.is_public = true) OR (clubs.owner_id = (select auth.uid())) OR private.is_club_member(clubs.id))))));
alter policy "authors can delete their posts" on public.club_posts
  using ((author_id = (select auth.uid())));
alter policy "members can post" on public.club_posts
  with check ((private.is_club_member(club_id) AND (author_id = (select auth.uid()))));
alter policy "posts readable with their club" on public.club_posts
  using (((EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_posts.club_id) AND ((clubs.is_public = true) OR (clubs.owner_id = (select auth.uid())) OR private.is_club_member(clubs.id))))) AND ((event_id IS NULL) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE (e.id = club_posts.event_id)))) AND (NOT private.viewer_blocks(author_id))));
alter policy "authenticated users can create clubs" on public.clubs
  with check (((select auth.uid()) = owner_id));
alter policy "club owner can delete their club" on public.clubs
  using ((owner_id = (select auth.uid())));
alter policy "members and owners read their own club" on public.clubs
  using (((owner_id = (select auth.uid())) OR private.is_club_member(id)));
alter policy "coach creates own pending invite" on public.coach_athletes
  with check (((coach_id = (select auth.uid())) AND (athlete_id IS NULL) AND (status = 'pending'::text)));
alter policy "coach deletes own unredeemed invite" on public.coach_athletes
  using (((coach_id = (select auth.uid())) AND (athlete_id IS NULL) AND (status = 'pending'::text)));
alter policy "coach or athlete reads own links" on public.coach_athletes
  using (((coach_id = (select auth.uid())) OR (athlete_id = (select auth.uid()))));
alter policy coach_messages_owner_delete on public.coach_messages
  using (((select auth.uid()) = user_id));
alter policy coach_messages_owner_insert on public.coach_messages
  with check ((((select auth.uid()) = user_id) AND (role = 'user'::text)));
alter policy coach_messages_owner_select on public.coach_messages
  using (((select auth.uid()) = user_id));
alter policy coach_messages_owner_update on public.coach_messages
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy device_tokens_self_delete on public.device_tokens
  using ((user_id = (select auth.uid())));
alter policy device_tokens_self_insert on public.device_tokens
  with check ((user_id = (select auth.uid())));
alter policy device_tokens_self_select on public.device_tokens
  using ((user_id = (select auth.uid())));
alter policy device_tokens_self_update on public.device_tokens
  using ((user_id = (select auth.uid())));
alter policy "participants delete their messages" on public.direct_messages
  using ((((select auth.uid()) = sender_id) OR ((select auth.uid()) = recipient_id)));
alter policy "participants read their own messages" on public.direct_messages
  using ((((select auth.uid()) = sender_id) OR ((select auth.uid()) = recipient_id)));
alter policy "recipient marks read" on public.direct_messages
  using (((select auth.uid()) = recipient_id))
  with check (((select auth.uid()) = recipient_id));
alter policy "send when not blocked and within follow graph" on public.direct_messages
  with check (((sender_id = (select auth.uid())) AND (NOT is_blocked_either_way(sender_id, recipient_id)) AND (EXISTS ( SELECT 1
   FROM user_follows f
  WHERE (((f.follower_id = direct_messages.sender_id) AND (f.followee_id = direct_messages.recipient_id)) OR ((f.follower_id = direct_messages.recipient_id) AND (f.followee_id = direct_messages.sender_id)))))));
alter policy "attendees readable with their event" on public.event_attendees
  using ((EXISTS ( SELECT 1
   FROM (events e
     JOIN clubs c ON ((c.id = e.club_id)))
  WHERE ((e.id = event_attendees.event_id) AND ((c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id))))));
alter policy "users RSVP to visible events" on public.event_attendees
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM events
  WHERE (events.id = event_attendees.event_id)))));
alter policy "users can delete their own RSVP" on public.event_attendees
  using (((select auth.uid()) = user_id));
alter policy "users can update their own RSVP" on public.event_attendees
  using (((select auth.uid()) = user_id));
alter policy "exceptions readable with their event" on public.event_exceptions
  using ((EXISTS ( SELECT 1
   FROM (events e
     JOIN clubs c ON ((c.id = e.club_id)))
  WHERE ((e.id = event_exceptions.event_id) AND ((c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id))))));
alter policy "organisers cancel their event occurrences" on public.event_exceptions
  with check (((cancelled_by = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_exceptions.event_id) AND private.is_event_organiser(e.club_id))))));
alter policy "buyer initiates refund on own paid order" on public.event_orders
  using (((buyer_user_id = (select auth.uid())) AND (status = 'paid'::text)))
  with check (((buyer_user_id = (select auth.uid())) AND (status = 'paid'::text)));
alter policy "buyer reads own orders" on public.event_orders
  using ((buyer_user_id = (select auth.uid())));
alter policy event_result_claims_select on public.event_result_claims
  using (((claimant_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM (event_results er
     JOIN events e ON ((e.id = er.event_id)))
  WHERE ((er.id = event_result_claims.result_id) AND private.is_event_organiser(e.club_id))))));
alter policy event_results_delete_self_or_director on public.event_results
  using ((((select auth.uid()) = user_id) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_results.event_id) AND private.is_race_director(e.club_id))))));
alter policy event_results_insert_self on public.event_results
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM (events e
     LEFT JOIN clubs c ON ((c.id = e.club_id)))
  WHERE ((e.id = event_results.event_id) AND ((c.id IS NULL) OR (c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id)))))));
alter policy event_results_update_self_or_director on public.event_results
  using ((((select auth.uid()) = user_id) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_results.event_id) AND private.is_race_director(e.club_id))))))
  with check ((((select auth.uid()) = user_id) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_results.event_id) AND private.is_race_director(e.club_id))))));
alter policy event_results_visible_when_event_is on public.event_results
  using ((EXISTS ( SELECT 1
   FROM (events e
     JOIN clubs c ON ((c.id = e.club_id)))
  WHERE ((e.id = event_results.event_id) AND ((c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id))))));
alter policy "events readable with their club" on public.events
  using (((EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = events.club_id) AND (((clubs.is_public = true) AND (clubs.shadow_hidden = false)) OR (clubs.owner_id = (select auth.uid())) OR private.is_club_member(clubs.id))))) AND ((is_public = true) OR private.is_club_member(club_id))));
alter policy "organisers can create events" on public.events
  with check ((private.is_event_organiser(club_id) AND (author_id = (select auth.uid()))));
alter policy "exercises owner delete custom" on public.exercises
  using ((author_id = (select auth.uid())));
alter policy "exercises owner insert custom" on public.exercises
  with check ((author_id = (select auth.uid())));
alter policy "exercises owner update custom" on public.exercises
  using ((author_id = (select auth.uid())))
  with check ((author_id = (select auth.uid())));
alter policy "exercises read globals and own customs" on public.exercises
  using (((author_id IS NULL) OR (author_id = (select auth.uid()))));
alter policy fitness_snapshots_self_delete on public.fitness_snapshots
  using ((user_id = (select auth.uid())));
alter policy fitness_snapshots_self_insert on public.fitness_snapshots
  with check (((user_id = (select auth.uid())) AND (source = 'client'::text)));
alter policy fitness_snapshots_self_select on public.fitness_snapshots
  using ((user_id = (select auth.uid())));
alter policy "food_log owner delete" on public.food_log
  using ((user_id = (select auth.uid())));
alter policy "food_log owner insert" on public.food_log
  with check ((user_id = (select auth.uid())));
alter policy "food_log owner read" on public.food_log
  using ((user_id = (select auth.uid())));
alter policy "food_log owner update" on public.food_log
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));
alter policy "fundraisers readable when anchor visible" on public.fundraisers
  using (((owner_user_id = (select auth.uid())) OR fundraiser_anchor_visible(run_id, event_id)));
alter policy "owners manage their fundraisers" on public.fundraisers
  using (((owner_user_id = (select auth.uid())) AND (((run_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM runs r
  WHERE ((r.id = fundraisers.run_id) AND (r.user_id = (select auth.uid())))))) OR ((event_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = fundraisers.event_id) AND private.is_event_organiser(e.club_id))))))))
  with check (((owner_user_id = (select auth.uid())) AND (((run_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM runs r
  WHERE ((r.id = fundraisers.run_id) AND (r.user_id = (select auth.uid())))))) OR ((event_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = fundraisers.event_id) AND private.is_event_organiser(e.club_id))))))));
alter policy "owners delete their gear" on public.gear
  using ((owner_id = (select auth.uid())));
alter policy "owners insert their gear" on public.gear
  with check ((owner_id = (select auth.uid())));
alter policy "owners read their gear" on public.gear
  using ((owner_id = (select auth.uid())));
alter policy "owners update their gear" on public.gear
  using ((owner_id = (select auth.uid())))
  with check ((owner_id = (select auth.uid())));
alter policy "members visible when owner owns the rotation" on public.gear_rotation_members
  using ((EXISTS ( SELECT 1
   FROM gear_rotations r
  WHERE ((r.id = gear_rotation_members.rotation_id) AND (r.owner_id = (select auth.uid()))))));
alter policy "owners add their gear to their rotations" on public.gear_rotation_members
  with check (((EXISTS ( SELECT 1
   FROM gear_rotations r
  WHERE ((r.id = gear_rotation_members.rotation_id) AND (r.owner_id = (select auth.uid()))))) AND (EXISTS ( SELECT 1
   FROM gear g
  WHERE ((g.id = gear_rotation_members.gear_id) AND (g.owner_id = (select auth.uid())))))));
alter policy "owners remove members from their rotations" on public.gear_rotation_members
  using ((EXISTS ( SELECT 1
   FROM gear_rotations r
  WHERE ((r.id = gear_rotation_members.rotation_id) AND (r.owner_id = (select auth.uid()))))));
alter policy "owners delete their gear rotations" on public.gear_rotations
  using ((owner_id = (select auth.uid())));
alter policy "owners insert their gear rotations" on public.gear_rotations
  with check ((owner_id = (select auth.uid())));
alter policy "owners read their gear rotations" on public.gear_rotations
  using ((owner_id = (select auth.uid())));
alter policy "owners update their gear rotations" on public.gear_rotations
  using ((owner_id = (select auth.uid())))
  with check ((owner_id = (select auth.uid())));
alter policy "owners delete their gear wear logs" on public.gear_wear_logs
  using ((owner_id = (select auth.uid())));
alter policy "owners insert their gear wear logs" on public.gear_wear_logs
  with check (((owner_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM gear g
  WHERE ((g.id = gear_wear_logs.gear_id) AND (g.owner_id = (select auth.uid())))))));
alter policy "owners read their gear wear logs" on public.gear_wear_logs
  using ((owner_id = (select auth.uid())));
alter policy "owners update their gear wear logs" on public.gear_wear_logs
  using ((owner_id = (select auth.uid())))
  with check ((owner_id = (select auth.uid())));
alter policy "catalogue effort owner deletes" on public.global_segment_efforts
  using (((select auth.uid()) = user_id));
alter policy "efforts readable when segment active and run visible" on public.global_segment_efforts
  using (((EXISTS ( SELECT 1
   FROM global_segments gs
  WHERE ((gs.id = global_segment_efforts.global_segment_id) AND (gs.is_active = true)))) AND private.is_run_visible_to(run_id, (select auth.uid()))));
alter policy "run owner inserts catalogue efforts on their runs" on public.global_segment_efforts
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM runs
  WHERE ((runs.id = global_segment_efforts.run_id) AND (runs.user_id = (select auth.uid()))))) AND (EXISTS ( SELECT 1
   FROM global_segments gs
  WHERE ((gs.id = global_segment_efforts.global_segment_id) AND (gs.is_active = true))))));
alter policy "admins delete catalogue segments" on public.global_segments
  using (private.is_admin((select auth.uid())));
alter policy "admins edit catalogue segments" on public.global_segments
  using (private.is_admin((select auth.uid())))
  with check (private.is_admin((select auth.uid())));
alter policy "admins insert catalogue segments" on public.global_segments
  with check (private.is_admin((select auth.uid())));
alter policy "gym_routine_exercises public templates read" on public.gym_routine_exercises
  using ((((select auth.role()) = 'authenticated'::text) AND private.is_public_gym_routine(routine_id)));
alter policy "gym_routine_exercises via parent delete" on public.gym_routine_exercises
  using ((EXISTS ( SELECT 1
   FROM gym_routines r
  WHERE ((r.id = gym_routine_exercises.routine_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_exercises via parent insert" on public.gym_routine_exercises
  with check ((EXISTS ( SELECT 1
   FROM gym_routines r
  WHERE ((r.id = gym_routine_exercises.routine_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_exercises via parent select" on public.gym_routine_exercises
  using ((EXISTS ( SELECT 1
   FROM gym_routines r
  WHERE ((r.id = gym_routine_exercises.routine_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_exercises via parent update" on public.gym_routine_exercises
  using ((EXISTS ( SELECT 1
   FROM gym_routines r
  WHERE ((r.id = gym_routine_exercises.routine_id) AND (r.author_id = (select auth.uid()))))))
  with check ((EXISTS ( SELECT 1
   FROM gym_routines r
  WHERE ((r.id = gym_routine_exercises.routine_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_sets public templates read" on public.gym_routine_sets
  using ((((select auth.role()) = 'authenticated'::text) AND (EXISTS ( SELECT 1
   FROM gym_routine_exercises e
  WHERE ((e.id = gym_routine_sets.routine_exercise_id) AND private.is_public_gym_routine(e.routine_id))))));
alter policy "gym_routine_sets via parent delete" on public.gym_routine_sets
  using ((EXISTS ( SELECT 1
   FROM (gym_routine_exercises e
     JOIN gym_routines r ON ((r.id = e.routine_id)))
  WHERE ((e.id = gym_routine_sets.routine_exercise_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_sets via parent insert" on public.gym_routine_sets
  with check ((EXISTS ( SELECT 1
   FROM (gym_routine_exercises e
     JOIN gym_routines r ON ((r.id = e.routine_id)))
  WHERE ((e.id = gym_routine_sets.routine_exercise_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_sets via parent select" on public.gym_routine_sets
  using ((EXISTS ( SELECT 1
   FROM (gym_routine_exercises e
     JOIN gym_routines r ON ((r.id = e.routine_id)))
  WHERE ((e.id = gym_routine_sets.routine_exercise_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routine_sets via parent update" on public.gym_routine_sets
  using ((EXISTS ( SELECT 1
   FROM (gym_routine_exercises e
     JOIN gym_routines r ON ((r.id = e.routine_id)))
  WHERE ((e.id = gym_routine_sets.routine_exercise_id) AND (r.author_id = (select auth.uid()))))))
  with check ((EXISTS ( SELECT 1
   FROM (gym_routine_exercises e
     JOIN gym_routines r ON ((r.id = e.routine_id)))
  WHERE ((e.id = gym_routine_sets.routine_exercise_id) AND (r.author_id = (select auth.uid()))))));
alter policy "gym_routines author delete" on public.gym_routines
  using ((author_id = (select auth.uid())));
alter policy "gym_routines author insert" on public.gym_routines
  with check ((author_id = (select auth.uid())));
alter policy "gym_routines author select" on public.gym_routines
  using ((author_id = (select auth.uid())));
alter policy "gym_routines author update" on public.gym_routines
  using ((author_id = (select auth.uid())))
  with check ((author_id = (select auth.uid())));
alter policy "gym_sets owner delete" on public.gym_sets
  using ((EXISTS ( SELECT 1
   FROM gym_workouts w
  WHERE ((w.id = gym_sets.workout_id) AND (w.user_id = (select auth.uid()))))));
alter policy "gym_sets owner insert" on public.gym_sets
  with check ((EXISTS ( SELECT 1
   FROM gym_workouts w
  WHERE ((w.id = gym_sets.workout_id) AND (w.user_id = (select auth.uid()))))));
alter policy "gym_sets owner update" on public.gym_sets
  using ((EXISTS ( SELECT 1
   FROM gym_workouts w
  WHERE ((w.id = gym_sets.workout_id) AND (w.user_id = (select auth.uid()))))))
  with check ((EXISTS ( SELECT 1
   FROM gym_workouts w
  WHERE ((w.id = gym_sets.workout_id) AND (w.user_id = (select auth.uid()))))));
alter policy "gym_sets visible via parent workout" on public.gym_sets
  using ((EXISTS ( SELECT 1
   FROM gym_workouts w
  WHERE ((w.id = gym_sets.workout_id) AND ((w.user_id = (select auth.uid())) OR w.is_public)))));
alter policy "gym_workouts owner delete" on public.gym_workouts
  using ((user_id = (select auth.uid())));
alter policy "gym_workouts owner insert" on public.gym_workouts
  with check ((user_id = (select auth.uid())));
alter policy "gym_workouts owner read" on public.gym_workouts
  using ((user_id = (select auth.uid())));
alter policy "gym_workouts owner update" on public.gym_workouts
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));
alter policy "own payout account readable" on public.instructor_payout_accounts
  using ((user_id = (select auth.uid())));
alter policy "users own their integrations" on public.integrations
  using (((select auth.uid()) = user_id));
alter policy live_run_pings_delete_self on public.live_run_pings
  using (((select auth.uid()) = user_id));
alter policy live_run_pings_insert_self on public.live_run_pings
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM runs r
  WHERE ((r.id = live_run_pings.run_id) AND (r.user_id = (select auth.uid())))))));
alter policy live_run_pings_visible_when_run_is on public.live_run_pings
  using (private.is_run_visible_to(run_id, (select auth.uid())));
alter policy "meal_template_items via parent delete" on public.meal_template_items
  using ((EXISTS ( SELECT 1
   FROM meal_templates t
  WHERE ((t.id = meal_template_items.template_id) AND (t.user_id = (select auth.uid()))))));
alter policy "meal_template_items via parent insert" on public.meal_template_items
  with check ((EXISTS ( SELECT 1
   FROM meal_templates t
  WHERE ((t.id = meal_template_items.template_id) AND (t.user_id = (select auth.uid()))))));
alter policy "meal_template_items via parent select" on public.meal_template_items
  using ((EXISTS ( SELECT 1
   FROM meal_templates t
  WHERE ((t.id = meal_template_items.template_id) AND (t.user_id = (select auth.uid()))))));
alter policy "meal_template_items via parent update" on public.meal_template_items
  using ((EXISTS ( SELECT 1
   FROM meal_templates t
  WHERE ((t.id = meal_template_items.template_id) AND (t.user_id = (select auth.uid()))))))
  with check ((EXISTS ( SELECT 1
   FROM meal_templates t
  WHERE ((t.id = meal_template_items.template_id) AND (t.user_id = (select auth.uid()))))));
alter policy "meal_templates owner delete" on public.meal_templates
  using ((user_id = (select auth.uid())));
alter policy "meal_templates owner insert" on public.meal_templates
  with check ((user_id = (select auth.uid())));
alter policy "meal_templates owner select" on public.meal_templates
  using ((user_id = (select auth.uid())));
alter policy "meal_templates owner update" on public.meal_templates
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));
alter policy "users delete their own notifications" on public.notifications
  using (((select auth.uid()) = user_id));
alter policy "users mark their own notifications read" on public.notifications
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "users read their own notifications" on public.notifications
  using (((select auth.uid()) = user_id));
alter policy personal_records_self_select on public.personal_records
  using ((user_id = (select auth.uid())));
alter policy "anyone reads public template weeks" on public.plan_weeks
  using ((((select auth.role()) = 'authenticated'::text) AND (EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND (p.is_public_template = true))))));
alter policy "coaches read athlete plan weeks" on public.plan_weeks
  using ((EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND (COALESCE(p.is_template, false) = false) AND private.is_active_coach_of((select auth.uid()), p.user_id)))));
alter policy "users delete plan weeks of plans they own or admin" on public.plan_weeks
  using ((EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "users read plan weeks they can see the plan for" on public.plan_weeks
  using ((EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_member(p.club_id)))))));
alter policy "users update plan weeks of plans they own or admin" on public.plan_weeks
  using ((EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))))
  with check ((EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "users write plan weeks of plans they own or admin" on public.plan_weeks
  with check ((EXISTS ( SELECT 1
   FROM training_plans p
  WHERE ((p.id = plan_weeks.plan_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "anyone reads public template workouts" on public.plan_workouts
  using ((((select auth.role()) = 'authenticated'::text) AND (EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND (p.is_public_template = true))))));
alter policy "coaches edit athlete plan workouts" on public.plan_workouts
  using ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND (COALESCE(p.is_template, false) = false) AND private.is_active_coach_of((select auth.uid()), p.user_id)))))
  with check ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND (COALESCE(p.is_template, false) = false) AND private.is_active_coach_of((select auth.uid()), p.user_id)))));
alter policy "coaches read athlete plan workouts" on public.plan_workouts
  using ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND (COALESCE(p.is_template, false) = false) AND private.is_active_coach_of((select auth.uid()), p.user_id)))));
alter policy "users delete plan workouts of plans they own or admin" on public.plan_workouts
  using ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "users read plan workouts they can see the plan for" on public.plan_workouts
  using ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_member(p.club_id)))))));
alter policy "users update plan workouts of plans they own or admin" on public.plan_workouts
  using ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))))
  with check ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "users write plan workouts of plans they own or admin" on public.plan_workouts
  with check ((EXISTS ( SELECT 1
   FROM (plan_weeks w
     JOIN training_plans p ON ((p.id = w.plan_id)))
  WHERE ((w.id = plan_workouts.week_id) AND ((p.user_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy public_recaps_owner on public.public_recaps
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "submitters edit own unverified listings" on public.race_listings
  using (((submitted_by = (select auth.uid())) AND (is_verified = false)))
  with check (((submitted_by = (select auth.uid())) AND (is_verified = false)));
alter policy "submitters read own listings" on public.race_listings
  using ((submitted_by = (select auth.uid())));
alter policy "users submit race listings" on public.race_listings
  with check ((submitted_by = (select auth.uid())));
alter policy race_pings_insert_self_while_running on public.race_pings
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM race_sessions rs
  WHERE ((rs.event_id = race_pings.event_id) AND (rs.instance_start = race_pings.instance_start) AND (rs.status = 'running'::text))))));
alter policy race_pings_visible_when_race_is on public.race_pings
  using ((EXISTS ( SELECT 1
   FROM ((race_sessions rs
     JOIN events e ON ((e.id = rs.event_id)))
     JOIN clubs c ON ((c.id = e.club_id)))
  WHERE ((rs.event_id = race_pings.event_id) AND (rs.instance_start = race_pings.instance_start) AND ((c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id))))));
alter policy race_sessions_visible_when_event_is on public.race_sessions
  using ((EXISTS ( SELECT 1
   FROM (events e
     JOIN clubs c ON ((c.id = e.club_id)))
  WHERE ((e.id = race_sessions.event_id) AND ((c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id))))));
alter policy "recipe_ingredients via parent delete" on public.recipe_ingredients
  using ((EXISTS ( SELECT 1
   FROM recipes r
  WHERE ((r.id = recipe_ingredients.recipe_id) AND (r.user_id = (select auth.uid()))))));
alter policy "recipe_ingredients via parent insert" on public.recipe_ingredients
  with check ((EXISTS ( SELECT 1
   FROM recipes r
  WHERE ((r.id = recipe_ingredients.recipe_id) AND (r.user_id = (select auth.uid()))))));
alter policy "recipe_ingredients via parent select" on public.recipe_ingredients
  using ((EXISTS ( SELECT 1
   FROM recipes r
  WHERE ((r.id = recipe_ingredients.recipe_id) AND (r.user_id = (select auth.uid()))))));
alter policy "recipe_ingredients via parent update" on public.recipe_ingredients
  using ((EXISTS ( SELECT 1
   FROM recipes r
  WHERE ((r.id = recipe_ingredients.recipe_id) AND (r.user_id = (select auth.uid()))))))
  with check ((EXISTS ( SELECT 1
   FROM recipes r
  WHERE ((r.id = recipe_ingredients.recipe_id) AND (r.user_id = (select auth.uid()))))));
alter policy "recipes owner delete" on public.recipes
  using ((user_id = (select auth.uid())));
alter policy "recipes owner insert" on public.recipes
  with check ((user_id = (select auth.uid())));
alter policy "recipes owner select" on public.recipes
  using ((user_id = (select auth.uid())));
alter policy "recipes owner update" on public.recipes
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));
alter policy "reporters read their own reports" on public.reports
  using (((select auth.uid()) = reporter_id));
alter policy "author or route owner deletes conditions" on public.route_conditions
  using ((((select auth.uid()) = user_id) OR (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_conditions.route_id) AND (routes.user_id = (select auth.uid())))))));
alter policy "conditions readable when route is visible" on public.route_conditions
  using (private.is_route_visible_to(route_id, (select auth.uid())));
alter policy "users read their own conditions" on public.route_conditions
  using (((select auth.uid()) = user_id));
alter policy "users report conditions on visible routes" on public.route_conditions
  with check ((((select auth.uid()) = user_id) AND private.is_route_visible_to(route_id, (select auth.uid()))));
alter policy "users update their own conditions" on public.route_conditions
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "markers readable when route is visible" on public.route_markers
  using (private.is_route_visible_to(route_id, (select auth.uid())));
alter policy "route owner adds markers" on public.route_markers
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_markers.route_id) AND (routes.user_id = (select auth.uid())))))));
alter policy "route owner deletes markers" on public.route_markers
  using ((EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_markers.route_id) AND (routes.user_id = (select auth.uid()))))));
alter policy "route owner updates markers" on public.route_markers
  using ((EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_markers.route_id) AND (routes.user_id = (select auth.uid()))))))
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_markers.route_id) AND (routes.user_id = (select auth.uid())))))));
alter policy "photo owner deletes" on public.route_photos
  using (((select auth.uid()) = owner_id));
alter policy "photo owner updates caption" on public.route_photos
  using (((select auth.uid()) = owner_id))
  with check (((select auth.uid()) = owner_id));
alter policy "photos readable when route is visible" on public.route_photos
  using (private.is_route_visible_to(route_id, (select auth.uid())));
alter policy "route owner attaches photos" on public.route_photos
  with check ((((select auth.uid()) = owner_id) AND (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_photos.route_id) AND (routes.user_id = (select auth.uid())))))));
alter policy "route owner deletes attached photos" on public.route_photos
  using ((EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = route_photos.route_id) AND (routes.user_id = (select auth.uid()))))));
alter policy "reviews on visible routes are readable" on public.route_reviews
  using (private.is_route_visible_to(route_id, (select auth.uid())));
alter policy "users delete their own reviews" on public.route_reviews
  using (((select auth.uid()) = user_id));
alter policy "users insert reviews on visible routes" on public.route_reviews
  with check ((((select auth.uid()) = user_id) AND private.is_route_visible_to(route_id, (select auth.uid()))));
alter policy "users read their own reviews" on public.route_reviews
  using (((select auth.uid()) = user_id));
alter policy "users update their own reviews" on public.route_reviews
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "club admins insert club routes" on public.routes
  with check (((club_id IS NOT NULL) AND private.is_club_admin(club_id) AND (user_id = (select auth.uid()))));
alter policy "users own their routes" on public.routes
  using (((select auth.uid()) = user_id))
  with check ((((select auth.uid()) = user_id) AND ((club_id IS NULL) OR private.is_club_admin(club_id))));
alter policy "comments readable when run is readable" on public.run_comments
  using (private.is_run_visible_to(run_id, (select auth.uid())));
alter policy "run owner deletes comments on their run" on public.run_comments
  using ((EXISTS ( SELECT 1
   FROM runs
  WHERE ((runs.id = run_comments.run_id) AND (runs.user_id = (select auth.uid()))))));
alter policy "users delete their own comments" on public.run_comments
  using (((select auth.uid()) = author_id));
alter policy "users edit their own comments" on public.run_comments
  using (((select auth.uid()) = author_id))
  with check (((select auth.uid()) = author_id));
alter policy "users post comments on their own behalf" on public.run_comments
  with check ((((select auth.uid()) = author_id) AND private.is_run_visible_to(run_id, (select auth.uid())) AND ((parent_comment_id IS NULL) OR _run_comment_parent_is_top_level(parent_comment_id)) AND (NOT private.is_blocked_for_run((select auth.uid()), run_id))));
alter policy "owners assign their gear to their runs" on public.run_gear
  with check (((EXISTS ( SELECT 1
   FROM runs r
  WHERE ((r.id = run_gear.run_id) AND (r.user_id = (select auth.uid()))))) AND (EXISTS ( SELECT 1
   FROM gear g
  WHERE ((g.id = run_gear.gear_id) AND (g.owner_id = (select auth.uid())))))));
alter policy "owners unassign gear from their runs" on public.run_gear
  using ((EXISTS ( SELECT 1
   FROM runs r
  WHERE ((r.id = run_gear.run_id) AND (r.user_id = (select auth.uid()))))));
alter policy "run_gear visible when parent run is visible" on public.run_gear
  using (private.is_run_visible_to(run_id, (select auth.uid())));
alter policy "kudos readable when run is readable" on public.run_kudos
  using (private.is_run_visible_to(run_id, (select auth.uid())));
alter policy "users give kudos on their own behalf" on public.run_kudos
  with check ((((select auth.uid()) = user_id) AND private.is_run_visible_to(run_id, (select auth.uid())) AND (NOT private.is_blocked_for_run((select auth.uid()), run_id))));
alter policy "users rescind their own kudos" on public.run_kudos
  using (((select auth.uid()) = user_id));
alter policy "owners read their match status" on public.run_matched_tracks
  using ((EXISTS ( SELECT 1
   FROM runs r
  WHERE ((r.id = run_matched_tracks.run_id) AND (r.user_id = (select auth.uid()))))));
alter policy "photo owner deletes" on public.run_photos
  using (((select auth.uid()) = owner_id));
alter policy "photo owner updates caption" on public.run_photos
  using (((select auth.uid()) = owner_id))
  with check (((select auth.uid()) = owner_id));
alter policy "photos readable when run is readable" on public.run_photos
  using (private.is_run_photo_visible_to(run_id, (select auth.uid())));
alter policy "run owner attaches photos" on public.run_photos
  with check ((((select auth.uid()) = owner_id) AND (EXISTS ( SELECT 1
   FROM runs
  WHERE ((runs.id = run_photos.run_id) AND (runs.user_id = (select auth.uid()))))) AND ((event_id IS NULL) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE (e.id = run_photos.event_id))))));
alter policy "run owner deletes attached photos" on public.run_photos
  using ((EXISTS ( SELECT 1
   FROM runs
  WHERE ((runs.id = run_photos.run_id) AND (runs.user_id = (select auth.uid()))))));
alter policy "active coach reads athlete runs" on public.runs
  using (private.is_active_coach_of((select auth.uid()), user_id));
alter policy "users own their runs" on public.runs
  using (((select auth.uid()) = user_id));
alter policy "safety_contacts linked contact delete" on public.safety_contacts
  using ((contact_user_id = (select auth.uid())));
alter policy "safety_contacts linked contact read" on public.safety_contacts
  using ((contact_user_id = (select auth.uid())));
alter policy "safety_contacts owner delete" on public.safety_contacts
  using ((owner_id = (select auth.uid())));
alter policy "safety_contacts owner insert" on public.safety_contacts
  with check ((owner_id = (select auth.uid())));
alter policy "safety_contacts owner read" on public.safety_contacts
  using ((owner_id = (select auth.uid())));
alter policy "users manage their own saves" on public.saved_routes
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "effort owner deletes" on public.segment_efforts
  using (((select auth.uid()) = user_id));
alter policy "efforts readable when segment AND run are readable" on public.segment_efforts
  using (((EXISTS ( SELECT 1
   FROM segments
  WHERE (segments.id = segment_efforts.segment_id))) AND private.is_run_visible_to(run_id, (select auth.uid()))));
alter policy "run owner inserts efforts on their runs" on public.segment_efforts
  with check ((((select auth.uid()) = user_id) AND (EXISTS ( SELECT 1
   FROM runs
  WHERE ((runs.id = segment_efforts.run_id) AND (runs.user_id = (select auth.uid()))))) AND (EXISTS ( SELECT 1
   FROM segments
  WHERE (segments.id = segment_efforts.segment_id)))));
alter policy "segment author deletes any effort on their segment" on public.segment_efforts
  using ((EXISTS ( SELECT 1
   FROM segments
  WHERE ((segments.id = segment_efforts.segment_id) AND (segments.author_id = (select auth.uid()))))));
alter policy "segment author or route owner deletes" on public.segments
  using ((((select auth.uid()) = author_id) OR (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = segments.route_id) AND (routes.user_id = (select auth.uid())))))));
alter policy "segment author or route owner edits" on public.segments
  using ((((select auth.uid()) = author_id) OR (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = segments.route_id) AND (routes.user_id = (select auth.uid())))))))
  with check ((((select auth.uid()) = author_id) OR (EXISTS ( SELECT 1
   FROM routes
  WHERE ((routes.id = segments.route_id) AND (routes.user_id = (select auth.uid())))))));
alter policy "segment authors create on readable routes" on public.segments
  with check ((((select auth.uid()) = author_id) AND private.is_route_visible_to(route_id, (select auth.uid()))));
alter policy "segments readable when route is readable" on public.segments
  using (private.is_route_visible_to(route_id, (select auth.uid())));
alter policy "session plan blocks inherit plan visibility" on public.session_plan_blocks
  using ((EXISTS ( SELECT 1
   FROM session_plans p
  WHERE ((p.id = session_plan_blocks.plan_id) AND ((p.author_id = (select auth.uid())) OR (p.is_public = true) OR ((p.club_id IS NOT NULL) AND private.is_club_member(p.club_id)))))))
  with check ((EXISTS ( SELECT 1
   FROM session_plans p
  WHERE ((p.id = session_plan_blocks.plan_id) AND ((p.author_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "session plan items inherit plan visibility" on public.session_plan_items
  using ((EXISTS ( SELECT 1
   FROM session_plans p
  WHERE ((p.id = session_plan_items.plan_id) AND ((p.author_id = (select auth.uid())) OR (p.is_public = true) OR ((p.club_id IS NOT NULL) AND private.is_club_member(p.club_id)))))))
  with check ((EXISTS ( SELECT 1
   FROM session_plans p
  WHERE ((p.id = session_plan_items.plan_id) AND ((p.author_id = (select auth.uid())) OR ((p.club_id IS NOT NULL) AND private.is_club_admin(p.club_id)))))));
alter policy "authors own their session plans" on public.session_plans
  using (((select auth.uid()) = author_id))
  with check ((((select auth.uid()) = author_id) AND ((club_id IS NULL) OR private.is_club_admin(club_id))));
alter policy "anyone reads public plan templates" on public.training_plans
  using (((is_public_template = true) AND ((select auth.role()) = 'authenticated'::text)));
alter policy "club admins insert club templates" on public.training_plans
  with check (((is_template = true) AND (club_id IS NOT NULL) AND private.is_club_admin(club_id) AND (user_id = (select auth.uid()))));
alter policy "coaches read athlete plans" on public.training_plans
  using (((COALESCE(is_template, false) = false) AND private.is_active_coach_of((select auth.uid()), user_id)));
alter policy "users own their plans" on public.training_plans
  using (((select auth.uid()) = user_id))
  with check ((((select auth.uid()) = user_id) AND ((club_id IS NULL) OR ((is_template = true) AND private.is_club_admin(club_id)))));
alter policy "user_blocks owner delete" on public.user_blocks
  using (((select auth.uid()) = blocker_id));
alter policy "user_blocks owner insert" on public.user_blocks
  with check ((((select auth.uid()) = blocker_id) AND ((select auth.uid()) <> blocked_id)));
alter policy "user_blocks owner read" on public.user_blocks
  using (((select auth.uid()) = blocker_id));
alter policy user_coach_usage_own_insert on public.user_coach_usage
  with check (((select auth.uid()) = user_id));
alter policy user_coach_usage_own_select on public.user_coach_usage
  using (((select auth.uid()) = user_id));
alter policy user_coach_usage_own_update on public.user_coach_usage
  using (((select auth.uid()) = user_id));
alter policy user_device_settings_owner_delete on public.user_device_settings
  using (((select auth.uid()) = user_id));
alter policy user_device_settings_owner_insert on public.user_device_settings
  with check (((select auth.uid()) = user_id));
alter policy user_device_settings_owner_select on public.user_device_settings
  using (((select auth.uid()) = user_id));
alter policy user_device_settings_owner_update on public.user_device_settings
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "follows are readable by anyone authenticated" on public.user_follows
  using (((select auth.role()) = 'authenticated'::text));
alter policy "users follow on their own behalf" on public.user_follows
  with check ((((select auth.uid()) = follower_id) AND (follower_id <> followee_id) AND (NOT is_blocked_either_way(follower_id, followee_id))));
alter policy "users unfollow on their own behalf" on public.user_follows
  using (((select auth.uid()) = follower_id));
alter policy "authenticated read profiles except shadow-hidden" on public.user_profiles
  using ((((select auth.uid()) = id) OR (shadow_hidden = false)));
alter policy "users delete own profile" on public.user_profiles
  using (((select auth.uid()) = id));
alter policy "users insert own profile" on public.user_profiles
  with check ((((select auth.uid()) = id) AND (((COALESCE(NULLIF((select current_setting('request.jwt.claim.role'::text, true)), ''::text), ((NULLIF((select current_setting('request.jwt.claims'::text, true)), ''::text))::jsonb ->> 'role'::text), ''::text)) = 'service_role'::text) OR (subscription_tier = 'free'::text))));
alter policy "users update own profile" on public.user_profiles
  using (((select auth.uid()) = id))
  with check (((select auth.uid()) = id));
alter policy user_settings_owner_delete on public.user_settings
  using (((select auth.uid()) = user_id));
alter policy user_settings_owner_insert on public.user_settings
  with check (((select auth.uid()) = user_id));
alter policy user_settings_owner_select on public.user_settings
  using (((select auth.uid()) = user_id));
alter policy user_settings_owner_update on public.user_settings
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));
alter policy "Users can delete their own run tracks" on storage.objects
  using (((bucket_id = 'runs'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users can read their own run tracks" on storage.objects
  using (((bucket_id = 'runs'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text) AND (COALESCE((storage.foldername(name))[2], ''::text) <> 'exports'::text)));
alter policy "Users can update their own run tracks" on storage.objects
  using (((bucket_id = 'runs'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users can upload their own run tracks" on storage.objects
  with check (((bucket_id = 'runs'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users delete their own club photos" on storage.objects
  using (((bucket_id = 'club-photos'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users delete their own photos" on storage.objects
  using (((bucket_id = 'run-photos'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users delete their own route photos" on storage.objects
  using (((bucket_id = 'route-photos'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users upload club photos to their own folder" on storage.objects
  with check (((bucket_id = 'club-photos'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users upload route photos to their own folder" on storage.objects
  with check (((bucket_id = 'route-photos'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "Users upload to their own folder" on storage.objects
  with check (((bucket_id = 'run-photos'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
alter policy "avatars owner can delete" on storage.objects
  using (((bucket_id = 'avatars'::text) AND (((select auth.uid()))::text = (storage.foldername(name))[1])));
alter policy "avatars owner can read own objects" on storage.objects
  using (((bucket_id = 'avatars'::text) AND (((select auth.uid()))::text = (storage.foldername(name))[1])));
alter policy "avatars owner can update" on storage.objects
  using (((bucket_id = 'avatars'::text) AND (((select auth.uid()))::text = (storage.foldername(name))[1])));
alter policy "avatars owner can upload" on storage.objects
  with check (((bucket_id = 'avatars'::text) AND (((select auth.uid()))::text = (storage.foldername(name))[1])));
alter policy "club-photo bytes visible when club is visible" on storage.objects
  using (((bucket_id = 'club-photos'::text) AND (EXISTS ( SELECT 1
   FROM (club_photos cp
     JOIN clubs c ON ((c.id = cp.club_id)))
  WHERE (((cp.storage_path = objects.name) OR (cp.thumb_512_path = objects.name)) AND ((c.is_public = true) OR (c.owner_id = (select auth.uid())) OR private.is_club_member(c.id)))))));
alter policy "route-photo bytes visible when parent route is visible" on storage.objects
  using (((bucket_id = 'route-photos'::text) AND (EXISTS ( SELECT 1
   FROM route_photos rp
  WHERE (((rp.storage_path = objects.name) OR (rp.thumb_512_path = objects.name)) AND private.is_route_visible_to(rp.route_id, (select auth.uid())))))));
alter policy "run-photo bytes visible when run or event is visible" on storage.objects
  using (((bucket_id = 'run-photos'::text) AND (EXISTS ( SELECT 1
   FROM run_photos rp
  WHERE (((rp.storage_path = objects.name) OR (rp.thumb_512_path = objects.name)) AND (private.is_run_photo_visible_to(rp.run_id, (select auth.uid())) OR ((rp.event_id IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM events e
          WHERE (e.id = rp.event_id))))))))));
