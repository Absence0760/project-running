-- Keep monthly_funding.updated_at honest on every write.
-- The donate page renders a "last updated" signal off this column, but
-- writes land via direct SQL / a service-role context (no client UPDATE
-- policy by design), so the writer had to remember to set updated_at by
-- hand. Stamp it from a BEFORE UPDATE trigger like the other mutable
-- tables (run_comments, plan_workouts, …) so a manual amount bump can't
-- leave a stale timestamp.

create or replace function monthly_funding_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger monthly_funding_updated_at_trigger
  before update on monthly_funding
  for each row execute function monthly_funding_set_updated_at();
