-- Monthly funding tracker. One row per month, updated by the project
-- owner when donations land (or by a future Stripe/Ko-fi webhook).
-- The donate page reads this to render the progress bar.

create table monthly_funding (
  month date primary key,  -- first of the month, e.g. '2026-05-01'
  amount_received numeric(10,2) not null default 0,
  donor_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table monthly_funding enable row level security;

-- Anyone can read — the whole point is transparency.
create policy monthly_funding_public_read
  on monthly_funding for select
  using (true);

-- Only the project owner can write. For now, use service role or
-- direct SQL. A future admin panel can add a UI.
