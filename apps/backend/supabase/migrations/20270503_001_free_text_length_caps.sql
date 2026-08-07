-- Length caps on every remaining user-writable free-text column (issue #666,
-- the round-14 index's carryover item 2, decisions § 548).
--
-- `20261124_001` capped three columns and never validated them.
-- `20270502_001` (§ 545) capped four more and did emit the VALIDATE, and its
-- own comment recorded that **40** columns were still uncapped. That figure came
-- from reading the migration files, and it was low. Re-derived from the
-- **catalogue** (`pg_attribute` joined to `pg_constraint`, which is what the
-- database actually enforces rather than what the DDL appears to say), the real
-- population is **52**. Three things defeated the static read:
--
--   1. The schema spells the predicate BOTH ways — `length(...)` in the older
--      tables (`gear`, `run_photos`, `gym_*`) and `char_length(...)` in the
--      newer ones. A derivation keyed on either spelling silently inherits the
--      other spelling's columns as "uncapped" or "capped", in both directions.
--   2. `alter table … add column a text, add column b text;` is one statement
--      with two clauses. A regex anchored on `add column` sees only the first,
--      which is why `event_results.finisher_name` never appeared in any count
--      while its sibling `bib` did.
--   3. A column named inside ANY check was treated as bounded. Most such checks
--      are enum membership and genuinely do bound the value — but
--      `event_results`' check is `user_id is not null or (bib is not null and
--      finisher_name is not null)`, which bounds nothing at all.
--
-- Only one text column is deliberately left without a length cap:
-- `event_checkpoints.cutoff_clock`, whose `^[0-2][0-9]:[0-5][0-9]$` already
-- pins it to exactly five characters. Enum-membership checks, `varchar`-free
-- URL/slug/token/id columns (scheme regex only) and the service-role-written
-- operational tables are out of scope for the same reason they were in § 545.
--
-- The caps are the ladder § 545 established — 60/80/120 for a name, 280–600 for
-- a note, 2000 for prose — and where a composer already states a number, the
-- constraint is at or above it, so nothing a user can currently type is
-- rejected. The ones that are exactly a client's number are deliberate:
-- `reports.notes` / `reports.resolution` at 600 (the report dialog's own
-- `maxlength`), `donations.display_name` / `message` at 80 / 280 (the Edge
-- Function's existing clamp, which until now was the only bound on either), and
-- `events.discipline` / `session_plans.discipline` at 60 — both composers state
-- 60, and this file first shipped them at 40. That is the § 545 failure in the
-- direction that hurts: a constraint BELOW the composer hands a user a 23514
-- they cannot act on for a value the form invited them to type. It was caught
-- by `clubs/event-discipline-overflow.spec.ts`, whose fixture is now tied to
-- the cap for the same reason.
--
-- Run before applying to a populated instance — every count must be 0, or the
-- VALIDATE below fails and the offending rows need truncating first:
--
--   select 'routes.name', count(*) from routes where char_length(name) > 120;
--   select 'routes.description', count(*) from routes where char_length(description) > 2000;
--   select 'route_reviews.comment', count(*) from route_reviews where char_length(comment) > 2000;
--   select 'training_plans.name', count(*) from training_plans where char_length(name) > 120;
--   select 'training_plans.notes', count(*) from training_plans where char_length(notes) > 500;
--   select 'plan_weeks.notes', count(*) from plan_weeks where char_length(notes) > 500;
--   select 'plan_workouts.notes', count(*) from plan_workouts where char_length(notes) > 500;
--   select 'plan_workouts.pace_zone', count(*) from plan_workouts where char_length(pace_zone) > 40;
--   select 'events.title', count(*) from events where char_length(title) > 120;
--   select 'events.meet_label', count(*) from events where char_length(meet_label) > 120;
--   select 'events.discipline', count(*) from events where char_length(discipline) > 60;
--   select 'events.timezone', count(*) from events where char_length(timezone) > 64;
--   select 'event_results.note', count(*) from event_results where char_length(note) > 500;
--   select 'event_results.bib', count(*) from event_results where char_length(bib) > 32;
--   select 'event_results.finisher_name', count(*) from event_results where char_length(finisher_name) > 120;
--   select 'event_exceptions.reason', count(*) from event_exceptions where char_length(reason) > 500;
--   select 'event_pricing.currency', count(*) from event_pricing where char_length(currency) > 8;
--   select 'session_plans.title', count(*) from session_plans where char_length(title) > 120;
--   select 'session_plans.discipline', count(*) from session_plans where char_length(discipline) > 60;
--   select 'session_plans.equipment', count(*) from session_plans where char_length(equipment) > 500;
--   select 'session_plan_blocks.name', count(*) from session_plan_blocks where char_length(name) > 120;
--   select 'session_plan_items.movement_name', count(*) from session_plan_items where char_length(movement_name) > 120;
--   select 'session_plan_items.cue', count(*) from session_plan_items where char_length(cue) > 500;
--   select 'session_plan_items.tempo', count(*) from session_plan_items where char_length(tempo) > 16;
--   select 'checkpoint_crossings.runner_name', count(*) from checkpoint_crossings where char_length(runner_name) > 120;
--   select 'checkpoint_crossings.bib', count(*) from checkpoint_crossings where char_length(bib) > 32;
--   select 'checkpoint_crossings.medical_note', count(*) from checkpoint_crossings where char_length(medical_note) > 500;
--   select 'fundraisers.title', count(*) from fundraisers where char_length(title) > 120;
--   select 'fundraisers.charity_name', count(*) from fundraisers where char_length(charity_name) > 120;
--   select 'fundraisers.story', count(*) from fundraisers where char_length(story) > 2000;
--   select 'fundraisers.currency', count(*) from fundraisers where char_length(currency) > 8;
--   select 'donations.display_name', count(*) from donations where char_length(display_name) > 80;
--   select 'donations.message', count(*) from donations where char_length(message) > 280;
--   select 'donations.currency', count(*) from donations where char_length(currency) > 8;
--   select 'race_listings.name', count(*) from race_listings where char_length(name) > 120;
--   select 'race_listings.location_label', count(*) from race_listings where char_length(location_label) > 80;
--   select 'reports.notes', count(*) from reports where char_length(notes) > 600;
--   select 'reports.resolution', count(*) from reports where char_length(resolution) > 600;
--   select 'user_blocks.reason', count(*) from user_blocks where char_length(reason) > 500;
--   select 'coach_athletes.note', count(*) from coach_athletes where char_length(note) > 500;
--   select 'fitness_snapshots.notes', count(*) from fitness_snapshots where char_length(notes) > 500;
--   select 'integrations.disconnected_reason', count(*) from integrations where char_length(disconnected_reason) > 500;
--   select 'integrations.scope', count(*) from integrations where char_length(scope) > 1000;
--   select 'global_segments.region', count(*) from global_segments where char_length(region) > 80;
--   select 'global_segments.surface', count(*) from global_segments where char_length(surface) > 40;
--   select 'challenge_badges.metric', count(*) from challenge_badges where char_length(metric) > 40;
--   select 'achievements.badge_key', count(*) from achievements where char_length(badge_key) > 80;
--   select 'user_profiles.parkrun_number', count(*) from user_profiles where char_length(parkrun_number) > 32;
--   select 'user_device_settings.label', count(*) from user_device_settings where char_length(label) > 80;
--   select 'user_device_settings.platform', count(*) from user_device_settings where char_length(platform) > 32;
--   select 'user_settings.discoverable_area_label', count(*) from user_settings where char_length(discoverable_area_label) > 80;
--   select 'safety_contacts.contact_email', count(*) from safety_contacts where char_length(contact_email) > 320;
--
-- Two rows are `not null` (`routes.name`, `events.title`); the `is null or`
-- branch is simply never taken there, and writing every constraint the same
-- shape keeps the set greppable and the guard's parse uniform.


alter table routes
  add constraint routes_name_len_chk
  check (name is null or char_length(name) <= 120) not valid;

alter table routes
  add constraint routes_description_len_chk
  check (description is null or char_length(description) <= 2000) not valid;

alter table route_reviews
  add constraint route_reviews_comment_len_chk
  check (comment is null or char_length(comment) <= 2000) not valid;

alter table training_plans
  add constraint training_plans_name_len_chk
  check (name is null or char_length(name) <= 120) not valid;

alter table training_plans
  add constraint training_plans_notes_len_chk
  check (notes is null or char_length(notes) <= 500) not valid;

alter table plan_weeks
  add constraint plan_weeks_notes_len_chk
  check (notes is null or char_length(notes) <= 500) not valid;

alter table plan_workouts
  add constraint plan_workouts_notes_len_chk
  check (notes is null or char_length(notes) <= 500) not valid;

alter table plan_workouts
  add constraint plan_workouts_pace_zone_len_chk
  check (pace_zone is null or char_length(pace_zone) <= 40) not valid;

alter table events
  add constraint events_title_len_chk
  check (title is null or char_length(title) <= 120) not valid;

alter table events
  add constraint events_meet_label_len_chk
  check (meet_label is null or char_length(meet_label) <= 120) not valid;

alter table events
  add constraint events_discipline_len_chk
  check (discipline is null or char_length(discipline) <= 60) not valid;

alter table events
  add constraint events_timezone_len_chk
  check (timezone is null or char_length(timezone) <= 64) not valid;

alter table event_results
  add constraint event_results_note_len_chk
  check (note is null or char_length(note) <= 500) not valid;

alter table event_results
  add constraint event_results_bib_len_chk
  check (bib is null or char_length(bib) <= 32) not valid;

alter table event_results
  add constraint event_results_finisher_name_len_chk
  check (finisher_name is null or char_length(finisher_name) <= 120) not valid;

alter table event_exceptions
  add constraint event_exceptions_reason_len_chk
  check (reason is null or char_length(reason) <= 500) not valid;

alter table event_pricing
  add constraint event_pricing_currency_len_chk
  check (currency is null or char_length(currency) <= 8) not valid;

alter table session_plans
  add constraint session_plans_title_len_chk
  check (title is null or char_length(title) <= 120) not valid;

alter table session_plans
  add constraint session_plans_discipline_len_chk
  check (discipline is null or char_length(discipline) <= 60) not valid;

alter table session_plans
  add constraint session_plans_equipment_len_chk
  check (equipment is null or char_length(equipment) <= 500) not valid;

alter table session_plan_blocks
  add constraint session_plan_blocks_name_len_chk
  check (name is null or char_length(name) <= 120) not valid;

alter table session_plan_items
  add constraint session_plan_items_movement_name_len_chk
  check (movement_name is null or char_length(movement_name) <= 120) not valid;

alter table session_plan_items
  add constraint session_plan_items_cue_len_chk
  check (cue is null or char_length(cue) <= 500) not valid;

alter table session_plan_items
  add constraint session_plan_items_tempo_len_chk
  check (tempo is null or char_length(tempo) <= 16) not valid;

alter table checkpoint_crossings
  add constraint checkpoint_crossings_runner_name_len_chk
  check (runner_name is null or char_length(runner_name) <= 120) not valid;

alter table checkpoint_crossings
  add constraint checkpoint_crossings_bib_len_chk
  check (bib is null or char_length(bib) <= 32) not valid;

alter table checkpoint_crossings
  add constraint checkpoint_crossings_medical_note_len_chk
  check (medical_note is null or char_length(medical_note) <= 500) not valid;

alter table fundraisers
  add constraint fundraisers_title_len_chk
  check (title is null or char_length(title) <= 120) not valid;

alter table fundraisers
  add constraint fundraisers_charity_name_len_chk
  check (charity_name is null or char_length(charity_name) <= 120) not valid;

alter table fundraisers
  add constraint fundraisers_story_len_chk
  check (story is null or char_length(story) <= 2000) not valid;

alter table fundraisers
  add constraint fundraisers_currency_len_chk
  check (currency is null or char_length(currency) <= 8) not valid;

alter table donations
  add constraint donations_display_name_len_chk
  check (display_name is null or char_length(display_name) <= 80) not valid;

alter table donations
  add constraint donations_message_len_chk
  check (message is null or char_length(message) <= 280) not valid;

alter table donations
  add constraint donations_currency_len_chk
  check (currency is null or char_length(currency) <= 8) not valid;

alter table race_listings
  add constraint race_listings_name_len_chk
  check (name is null or char_length(name) <= 120) not valid;

alter table race_listings
  add constraint race_listings_location_label_len_chk
  check (location_label is null or char_length(location_label) <= 80) not valid;

alter table reports
  add constraint reports_notes_len_chk
  check (notes is null or char_length(notes) <= 600) not valid;

alter table reports
  add constraint reports_resolution_len_chk
  check (resolution is null or char_length(resolution) <= 600) not valid;

alter table user_blocks
  add constraint user_blocks_reason_len_chk
  check (reason is null or char_length(reason) <= 500) not valid;

alter table coach_athletes
  add constraint coach_athletes_note_len_chk
  check (note is null or char_length(note) <= 500) not valid;

alter table fitness_snapshots
  add constraint fitness_snapshots_notes_len_chk
  check (notes is null or char_length(notes) <= 500) not valid;

alter table integrations
  add constraint integrations_disconnected_reason_len_chk
  check (disconnected_reason is null or char_length(disconnected_reason) <= 500) not valid;

alter table integrations
  add constraint integrations_scope_len_chk
  check (scope is null or char_length(scope) <= 1000) not valid;

alter table global_segments
  add constraint global_segments_region_len_chk
  check (region is null or char_length(region) <= 80) not valid;

alter table global_segments
  add constraint global_segments_surface_len_chk
  check (surface is null or char_length(surface) <= 40) not valid;

alter table challenge_badges
  add constraint challenge_badges_metric_len_chk
  check (metric is null or char_length(metric) <= 40) not valid;

alter table achievements
  add constraint achievements_badge_key_len_chk
  check (badge_key is null or char_length(badge_key) <= 80) not valid;

alter table user_profiles
  add constraint user_profiles_parkrun_number_len_chk
  check (parkrun_number is null or char_length(parkrun_number) <= 32) not valid;

alter table user_device_settings
  add constraint user_device_settings_label_len_chk
  check (label is null or char_length(label) <= 80) not valid;

alter table user_device_settings
  add constraint user_device_settings_platform_len_chk
  check (platform is null or char_length(platform) <= 32) not valid;

alter table user_settings
  add constraint user_settings_discoverable_area_label_len_chk
  check (discoverable_area_label is null or char_length(discoverable_area_label) <= 80) not valid;

alter table safety_contacts
  add constraint safety_contacts_contact_email_len_chk
  check (contact_email is null or char_length(contact_email) <= 320) not valid;

alter table routes validate constraint routes_name_len_chk;
alter table routes validate constraint routes_description_len_chk;
alter table route_reviews validate constraint route_reviews_comment_len_chk;
alter table training_plans validate constraint training_plans_name_len_chk;
alter table training_plans validate constraint training_plans_notes_len_chk;
alter table plan_weeks validate constraint plan_weeks_notes_len_chk;
alter table plan_workouts validate constraint plan_workouts_notes_len_chk;
alter table plan_workouts validate constraint plan_workouts_pace_zone_len_chk;
alter table events validate constraint events_title_len_chk;
alter table events validate constraint events_meet_label_len_chk;
alter table events validate constraint events_discipline_len_chk;
alter table events validate constraint events_timezone_len_chk;
alter table event_results validate constraint event_results_note_len_chk;
alter table event_results validate constraint event_results_bib_len_chk;
alter table event_results validate constraint event_results_finisher_name_len_chk;
alter table event_exceptions validate constraint event_exceptions_reason_len_chk;
alter table event_pricing validate constraint event_pricing_currency_len_chk;
alter table session_plans validate constraint session_plans_title_len_chk;
alter table session_plans validate constraint session_plans_discipline_len_chk;
alter table session_plans validate constraint session_plans_equipment_len_chk;
alter table session_plan_blocks validate constraint session_plan_blocks_name_len_chk;
alter table session_plan_items validate constraint session_plan_items_movement_name_len_chk;
alter table session_plan_items validate constraint session_plan_items_cue_len_chk;
alter table session_plan_items validate constraint session_plan_items_tempo_len_chk;
alter table checkpoint_crossings validate constraint checkpoint_crossings_runner_name_len_chk;
alter table checkpoint_crossings validate constraint checkpoint_crossings_bib_len_chk;
alter table checkpoint_crossings validate constraint checkpoint_crossings_medical_note_len_chk;
alter table fundraisers validate constraint fundraisers_title_len_chk;
alter table fundraisers validate constraint fundraisers_charity_name_len_chk;
alter table fundraisers validate constraint fundraisers_story_len_chk;
alter table fundraisers validate constraint fundraisers_currency_len_chk;
alter table donations validate constraint donations_display_name_len_chk;
alter table donations validate constraint donations_message_len_chk;
alter table donations validate constraint donations_currency_len_chk;
alter table race_listings validate constraint race_listings_name_len_chk;
alter table race_listings validate constraint race_listings_location_label_len_chk;
alter table reports validate constraint reports_notes_len_chk;
alter table reports validate constraint reports_resolution_len_chk;
alter table user_blocks validate constraint user_blocks_reason_len_chk;
alter table coach_athletes validate constraint coach_athletes_note_len_chk;
alter table fitness_snapshots validate constraint fitness_snapshots_notes_len_chk;
alter table integrations validate constraint integrations_disconnected_reason_len_chk;
alter table integrations validate constraint integrations_scope_len_chk;
alter table global_segments validate constraint global_segments_region_len_chk;
alter table global_segments validate constraint global_segments_surface_len_chk;
alter table challenge_badges validate constraint challenge_badges_metric_len_chk;
alter table achievements validate constraint achievements_badge_key_len_chk;
alter table user_profiles validate constraint user_profiles_parkrun_number_len_chk;
alter table user_device_settings validate constraint user_device_settings_label_len_chk;
alter table user_device_settings validate constraint user_device_settings_platform_len_chk;
alter table user_settings validate constraint user_settings_discoverable_area_label_len_chk;
alter table safety_contacts validate constraint safety_contacts_contact_email_len_chk;

-- The three caps `20261124_001` left permanently unchecked.
--
-- § 545 named this failure and § 546 said "this round's migration validates" —
-- both are true of their OWN constraints. Neither emitted the VALIDATE for the
-- three that had the defect, so `club_posts_body_len_chk`,
-- `coach_messages_content_len_chk` and `events_description_len_chk` were still
-- `convalidated = false` on `main` when this round read the catalogue. A
-- NOT VALID check binds every new write, so the only rows that can violate one
-- predate 2026-11-24; VALIDATE takes SHARE UPDATE EXCLUSIVE, which does not
-- block reads or writes (docs/backend/migration_locks.md).
--
--   select 'club_posts.body', count(*) from club_posts where char_length(body) > 4096;
--   select 'coach_messages.content', count(*) from coach_messages where char_length(content) > 65536;
--   select 'events.description', count(*) from events where char_length(description) > 2000;

alter table club_posts validate constraint club_posts_body_len_chk;
alter table coach_messages validate constraint coach_messages_content_len_chk;
alter table events validate constraint events_description_len_chk;
