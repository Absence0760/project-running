-- Body metrics for the nutrition BMR target (multi_modal.md § "Body metrics
-- & sensitive data"). The Mifflin-St Jeor target needs weight, height, age,
-- sex. Age (date_of_birth) + sex (gender) already live on user_profiles
-- (added for segments, 20260829_001). Height + weight are new and are
-- **GDPR special-category health data** — owner-only, never public, and must
-- join the DSAR export path before real users (G1/G6).
--
-- Height is a single current value on user_profiles; weight is a small
-- time-series in body_metrics because a trend matters and a single mutable
-- column loses history.

-- ─────────────────── height on user_profiles ───────────────────

-- Deny-by-default for table-level SELECT (the 20260707_001 lockdown revoked
-- table SELECT and re-grants only public-safe columns). height_cm is NOT in
-- that grant list, so it's owner-only: read back via the get_my_profile()
-- SECURITY DEFINER self-read, written via the "users update own profile"
-- UPDATE policy. No grant amendment — sensitive data stays off the
-- authenticated/anon column grant by design.
alter table public.user_profiles
  add column if not exists height_cm numeric(5, 1)
  check (height_cm is null or (height_cm > 0 and height_cm <= 300));

comment on column public.user_profiles.height_cm is
  'Current standing height in cm. Special-category health data — owner-only '
  '(off the public-safe column grant); read via get_my_profile().';

-- ─────────────────── body_metrics weight time-series ───────────────────

create table public.body_metrics (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,
  recorded_at  timestamptz not null default now(),
  weight_kg    numeric(5, 2) not null check (weight_kg > 0 and weight_kg <= 500),
  created_at   timestamptz not null default now()
);

comment on table public.body_metrics is
  'Weight time-series for nutrition BMR targets. Special-category health '
  'data — owner-only RLS, no public read, cascade-delete from auth.users, '
  'must be in the DSAR export path.';

create index body_metrics_user on public.body_metrics (user_id, recorded_at desc);

alter table public.body_metrics enable row level security;

create policy "body_metrics owner read"
  on public.body_metrics for select
  using (user_id = auth.uid());

create policy "body_metrics owner insert"
  on public.body_metrics for insert
  with check (user_id = auth.uid());

create policy "body_metrics owner update"
  on public.body_metrics for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "body_metrics owner delete"
  on public.body_metrics for delete
  using (user_id = auth.uid());
