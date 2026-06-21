-- gym_sets.set_type — the role a LOGGED set played (warmup / working / dropset /
-- amrap / failure / backoff), so RPE + load read in context.
--
-- Reuses the gym_routine_sets.set_type vocabulary + CHECK (migration
-- 20270101_001) verbatim so a routine's planned set type and the logged set it
-- produced speak the same language. Modelled as a real column with a CHECK (not
-- a metadata.md jsonb key) because it is a closed, enforced enum — the same
-- reasoning that put set_type on routine sets. Defaults to 'working': a logged
-- set with no chosen type is an ordinary working set, the overwhelming common
-- case, so existing rows + every untouched client write stay correct. NOT NULL
-- with the default keeps the column dense and the CHECK total.

alter table public.gym_sets
  add column set_type text not null default 'working'
    check (set_type in ('warmup','working','dropset','amrap','failure','backoff'));

comment on column public.gym_sets.set_type is
  'Role of this logged set (warmup/working/dropset/amrap/failure/backoff); defaults to working. Shares the gym_routine_sets.set_type vocabulary (20270101_001).';
