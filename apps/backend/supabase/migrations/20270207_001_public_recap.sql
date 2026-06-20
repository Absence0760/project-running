-- Public, OG-unfurlable Year-in-Running / "Wrapped" recap snapshots.
-- See docs/features/recap.md + docs/features/year_in_review.md.
--
-- A recap is otherwise personal data with no public URL — a posted recap
-- link can't unfurl because an unauthenticated crawler can't recompute it
-- from the owner's runs (RLS hides them). This table is the durable answer:
-- the owner explicitly "publishes" a recap, which FREEZES its aggregate
-- numbers into a jsonb snapshot. The share page + og:image then render from
-- the frozen snapshot without needing the viewer to be the owner, and the
-- card never changes under a reader after it was posted.
--
-- FAIL-CLOSED / privacy: a recap is PRIVATE by default — nothing exists in
-- this table until the owner takes the explicit publish action, and the row
-- is revocable (delete it → the link 404s / falls back). Only AGGREGATE,
-- non-track numbers go in `snapshot` (totals / badges / monthly strip) — no
-- GPS, no per-run rows, mirroring og_run_image.ts's no-polyline discipline.
--
-- `period_kind` is a narrow union: TS union RecapPeriodKind in
-- apps/web/src/lib/types.ts + this CHECK must stay in lockstep
-- (check_constraint_unions.mjs PAIRS).

create table public_recaps (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  period_kind  text not null check (period_kind in ('year', 'month')),
  period_key   text not null,          -- '2026' or '2026-03'
  snapshot     jsonb not null,         -- frozen YearInRunningRecap-shaped aggregate
  created_at   timestamptz not null default now(),
  unique (user_id, period_kind, period_key)
);

alter table public_recaps enable row level security;

-- Owner full CRUD (publish / re-publish / revoke).
create policy public_recaps_owner on public_recaps
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Anyone may SELECT by id — the uuid in the share link IS the capability
-- token. There is no enumeration surface beyond an already-known id, and the
-- snapshot holds only aggregate, non-track numbers the owner chose to expose.
create policy public_recaps_public_read on public_recaps
  for select using (true);

create index public_recaps_user_idx on public_recaps (user_id);
