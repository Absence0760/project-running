-- Gear wear-pattern logging — dated qualitative wear observations per gear item.
--
-- Background. The v1 gear feature (20260827_001) tracks a single static
-- `gear.notes` text field plus the distance-derived wear classification
-- (`gear_wear.ts` / `gear_wear.dart`: ok / due / worn from total km vs the
-- replacement target). What it can't capture is how a shoe is *actually*
-- ageing — shoes don't wear linearly: a runner notes "outsole lugs gone at
-- 380 km", "midsole feels dead", "heel counter breaking down". That's a
-- time-series of qualitative observations, not a single overwriteable note.
--
-- This migration adds the per-shoe wear-log table (roadmap §7 "Future:
-- per-shoe wear-pattern logging"). One row per dated observation, owned by
-- the gear owner. The distance-based `gear_wear` classifier is unchanged and
-- complementary: the bar tells you how far you've run, the wear log tells you
-- what you've noticed.
--
-- Shape mirrors `gear` exactly: owner-scoped RLS (4 policies), an
-- `updated_at` bump trigger, and a single covering index. A wear log row
-- carries an optional `area` (a small enumerated wear location so a future UI
-- can group by region — outsole / midsole / upper / other) plus the free-text
-- `note` and the observation `logged_on` date (defaults to today). Nothing
-- here cascades into the public-run-gear leak surface: wear logs are
-- owner-only, never projected by `public_run_gear`.

create table public.gear_wear_logs (
  id          uuid primary key default gen_random_uuid(),
  gear_id     uuid references public.gear(id) on delete cascade not null,
  owner_id    uuid references auth.users(id) on delete cascade not null,
  logged_on   date not null default current_date,
  area        text check (area is null or area in ('outsole', 'midsole', 'upper', 'other')),
  note        text not null check (length(note) between 1 and 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Lists a gear item's log newest-first; owner_id leads so the owner-scoped
-- RLS read is index-covered.
create index gear_wear_logs_owner_gear
  on public.gear_wear_logs (owner_id, gear_id, logged_on desc);

alter table public.gear_wear_logs enable row level security;

create policy "owners read their gear wear logs"
  on public.gear_wear_logs for select
  using (owner_id = auth.uid());

-- INSERT requires the caller to own BOTH the log row (owner_id = me) AND the
-- parent gear. The gear check stops a user from hanging a wear log off another
-- user's gear id, matching the run_gear insert gate.
create policy "owners insert their gear wear logs"
  on public.gear_wear_logs for insert
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.gear g
      where g.id = gear_wear_logs.gear_id and g.owner_id = auth.uid()
    )
  );

create policy "owners update their gear wear logs"
  on public.gear_wear_logs for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "owners delete their gear wear logs"
  on public.gear_wear_logs for delete
  using (owner_id = auth.uid());

create trigger gear_wear_logs_updated_at
  before update on public.gear_wear_logs
  for each row execute function gear_set_updated_at();
