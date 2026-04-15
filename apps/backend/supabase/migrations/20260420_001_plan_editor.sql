-- Plan-editor follow-on to the training-plans feature. Four changes, all
-- additive and backward compatible with the v1 generator output:
--
--   1. `plan_workouts.pace_zone` — human-readable zone label (E, M, T, I, R,
--      MP, easy, mp, tempo…). Lets the UI colour workouts by zone without
--      decoding the enum.
--   2. `plan_workouts.target_pace_end_sec_per_km` — for pace *progressions*
--      across a phase (e.g. MP goes 7:15 → 6:41). When null the workout is
--      flat-paced at `target_pace_sec_per_km`.
--   3. `training_plans.source` — 'generated' | 'imported' | 'manual'. Lets
--      us preserve attribution for plans pasted in from a coach or markdown
--      document so the editor UI knows whether to warn on regeneration.
--   4. `training_plans.rules` — jsonb array of plan-wide rules the user
--      pasted from a plan document ("80% easy", "sleep 8h", "cut climbing
--      Phase 2+"). Rendered in the plan hero, purely informational — no
--      enforcement.

alter table plan_workouts
  add column pace_zone text,
  add column target_pace_end_sec_per_km integer;

alter table training_plans
  add column source text not null default 'generated',
  add column rules jsonb;
