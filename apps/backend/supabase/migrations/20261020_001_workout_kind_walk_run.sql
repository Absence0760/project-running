-- Add the 'walk_run' workout kind for beginner / return-to-run plans
-- (new + comeback persona #22). C25K / Galloway sessions alternate timed run
-- and walk intervals; they're a distinct workout kind so the UI, plan
-- generator, and live-recorder cues can treat them specially rather than
-- mislabelling them as an 'interval' session.
--
-- workout_kind is a Postgres enum (migration 20260419_001), so this is an
-- ALTER TYPE ADD VALUE. The new value isn't referenced elsewhere in this
-- migration, so it's safe inside the migration transaction (PG 12+).
alter type workout_kind add value if not exists 'walk_run';
