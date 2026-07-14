-- Pin search_path on every public-schema function that lacked one
-- (Supabase security advisor: "Function Search Path Mutable", lint 0011).
--
-- A function without a pinned search_path resolves unqualified object
-- references against the CALLER's session search_path, which a caller can
-- change (`set search_path = attacker_schema, public`) to shadow tables /
-- operators the body references. None of these 28 are SECURITY DEFINER
-- (every definer function in this repo already pins its path), so the
-- practical exposure is low — but pinning is free, silences the advisor,
-- and removes the invoker→definer-refactor foot-gun.
--
-- ALTER FUNCTION ... SET only attaches proconfig; it never touches the
-- body, so the "bare-body create or replace strips prior fixes" trap
-- (apps/backend/CLAUDE.md) does not apply here.
--
-- Four functions reference postgis objects (geography/geometry casts,
-- ST_* calls, the <-> operator) which live in the `extensions` schema on
-- Supabase — those pin `public, extensions` or they'd break at runtime.
-- The rest pin `public`.
--
-- The companion pgtap catch-all (tests/function_search_path_test.sql)
-- fails the suite if a future migration adds an unpinned function.

alter function public._privacy_downsample(jsonb, integer) set search_path = public;
alter function public.club_photos_block_storage_path_clear() set search_path = public;
alter function public.club_photos_block_thumb_path_update() set search_path = public;
alter function public.event_results_rerank_trigger() set search_path = public;
alter function public.event_results_set_approval_default() set search_path = public;
alter function public.events_default_host() set search_path = public;
alter function public.force_unverified_listing() set search_path = public;
alter function public.jobs_set_updated_at() set search_path = public;
alter function public.latest_fitness_snapshot() set search_path = public;
alter function public.latest_race_pings(uuid, timestamptz) set search_path = public;
alter function public.monthly_funding_set_updated_at() set search_path = public;
alter function public.privacy_coarsen_coord(double precision) set search_path = public;
alter function public.race_sessions_enforce_transition() set search_path = public;
alter function public.reject_nonathletic_race() set search_path = public;
alter function public.reject_nonathletic_result() set search_path = public;
alter function public.route_markers_set_updated_at() set search_path = public;
alter function public.route_photos_block_storage_path_clear() set search_path = public;
alter function public.route_photos_block_thumb_path_update() set search_path = public;
alter function public.run_comments_set_updated_at() set search_path = public;
alter function public.run_matched_tracks_set_updated_at() set search_path = public;
alter function public.run_photos_block_storage_path_clear() set search_path = public;
alter function public.run_photos_block_thumb_path_update() set search_path = public;
alter function public.safety_contacts_force_unconfirmed() set search_path = public;
alter function public.touch_device_tokens_updated_at() set search_path = public;

alter function public.routes_set_geom() set search_path = public, extensions;
alter function public.search_clubs(text, double precision, double precision, double precision, integer) set search_path = public, extensions;
alter function public.search_public_events(text, text, text, text, text, text, double precision, double precision, double precision, integer) set search_path = public, extensions;
alter function public.search_race_listings(text, text, date, date, double precision, double precision, double precision, integer) set search_path = public, extensions;
