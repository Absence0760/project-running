-- /audit/all Medium (public-rows): `event_results.age_grade_pct` and
-- `event_results.note` are exposed in full to every caller who can
-- read the parent event's leaderboard.
--
--   - `age_grade_pct` is a fitness-derived metric (age-graded
--     performance percentage) that, combined with `duration_s` +
--     `distance_m` already on the row, narrows the runner's age
--     bracket — a field they didn't publish themselves.
--   - `note` is free-text organiser annotation on the runner's
--     result. Could carry medical / injury / personal context.
--
-- Same redaction shape as 20260805_001 (event_results_redacted's
-- run_id column): `case when user_id = auth.uid() then ... else
-- null end`. Owner reads keep the value; non-owner / anon rows null
-- it out. The view's `security_invoker = on` keeps RLS on the
-- underlying table in charge of which ROWS are visible — this
-- migration only narrows COLUMNS.

drop view if exists event_results_redacted;

create view event_results_redacted as
select
  event_id,
  instance_start,
  user_id,
  duration_s,
  distance_m,
  rank,
  finisher_status,
  case
    when user_id = auth.uid() then age_grade_pct
    else null
  end as age_grade_pct,
  case
    when user_id = auth.uid() then note
    else null
  end as note,
  created_at,
  updated_at,
  organiser_approved,
  case
    when user_id = auth.uid() then run_id
    else null
  end as run_id
from event_results;

alter view event_results_redacted set (security_invoker = on);

grant select on event_results_redacted to anon, authenticated;
