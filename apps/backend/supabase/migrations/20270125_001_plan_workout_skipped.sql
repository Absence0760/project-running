-- Plan workout intentionally-skipped status.
--
-- Until now a planned workout had exactly two states: done
-- (`completed_run_id IS NOT NULL OR manually_completed = true`) or
-- not-done. A workout the runner *deliberately* drops — a deload day,
-- an ease-off after over-running, a session the missed-long-run advice
-- told them to skip — was indistinguishable from one they simply
-- haven't gotten to yet (a debt). That conflation flatters the
-- progress ring (a skipped key session shows as an outstanding to-do
-- forever) and muddies adherence (a deliberate skip is not the same
-- compliance signal as a missed session).
--
-- This adds a `skipped_at timestamptz` (null = not skipped), mirroring
-- the `completed_at` shape. A skipped workout is NOT counted as done
-- and is removed from the active-to-do denominator of the progress
-- ring — it's neither a debt nor an achievement, it's off the books.
-- Skip and done are mutually exclusive at the write layer: marking a
-- workout skipped clears any completion, and completing one clears the
-- skip. The default is null so existing rows keep their current state.

alter table plan_workouts
  add column skipped_at timestamptz;
