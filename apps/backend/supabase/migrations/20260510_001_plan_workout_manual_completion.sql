-- Plan workout manual completion.
--
-- Until now, a workout was "done" iff `completed_run_id` was non-null —
-- which only happens after a tracked run is logged and auto-matched
-- (same date, distance ±25%). Users who race or train without recording
-- a GPS run had no way to mark a workout as complete from the calendar.
--
-- This adds a `manually_completed` boolean so the UI can mark a workout
-- as complete without needing a linked run row. Read sites should treat
-- `manually_completed = true OR completed_run_id IS NOT NULL` as "done".
--
-- The default is false so existing rows keep their current state.
-- `completed_at` continues to track the timestamp of completion in
-- either path (linked-run or manual) and is set/cleared by the same
-- code paths that flip these two flags.

alter table plan_workouts
  add column manually_completed boolean not null default false;
