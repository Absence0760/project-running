-- Give the donation ledger a way to say how much of a donation came back.
--
-- decisions § 769 found that `donationStatusTransition` flipped `paid ->
-- refunded` on ANY `charge.refunded`, partial or not, and `fundraiser_totals`
-- sums `amount_cents` filtered on `status = 'paid'` (20270213_001) — so 5 USD
-- back on a 500 USD donation removed 500 USD from the charity's public
-- thermometer. That entry took the smaller of the two available lies: leave the
-- status alone, overstate by the part that came back, log the gap. It could not
-- do better, because the table has no `partially_refunded` status and no
-- refunded-amount column — the honest representation did not exist.
--
-- This adds it. `refunded_cents` is the CUMULATIVE amount Stripe reports
-- refunded on the charge (`charge.amount_refunded`), which is why the webhook
-- can write it idempotently and out of order without arithmetic: it is a
-- running total, not a delta. `fundraiser_totals` then sums
-- `amount_cents - refunded_cents` over the two statuses that still hold money,
-- and the thermometer moves by exactly what came back.
--
-- NOT backfilled, deliberately. Every pre-existing row keeps `refunded_cents =
-- 0`, which is TRUE of every `paid` / `pending` / `canceled` / `failed` row (no
-- refunded amount was ever recorded, and for `paid` no refund landed at all).
-- For a `refunded` row it means "we never recorded the amount", not "nothing
-- came back" — and those rows are excluded from the sum either way, so nothing
-- derived depends on it. The rows flipped to `refunded` by the pre-§769
-- whole-refund behaviour are NOT recoverable from this database: the only
-- record of how much actually came back is at Stripe. `status = 'refunded' and
-- refunded_cents = 0` is exactly that reconciliation cohort — see
-- docs/features/fundraising.md § Reconciling pre-§769 refunds.
--
-- Online-safety (docs/backend/migration_locks.md): `donations` is not in the
-- guarded high-volume set, but every statement here takes the online form
-- anyway. The ADD COLUMN default is a constant (metadata-only on PG11+, no
-- rewrite), every CHECK is added NOT VALID and VALIDATEd separately, and there
-- is no backfill to batch.

-- ───────────────────────── 1. the refunded amount ────────────────────────────
alter table donations add column refunded_cents integer not null default 0;

comment on column donations.refunded_cents is
  'Cumulative cents refunded on this donation''s charge, as last reported by '
  'Stripe (charge.amount_refunded). Written only by the stripe-events webhook. '
  '0 on a row that predates 20270620_001 — for a `refunded` row that means the '
  'amount was never recorded, not that nothing came back.';

alter table donations
  add constraint donations_refunded_range_check
  check (refunded_cents >= 0 and refunded_cents <= amount_cents)
  not valid;

-- A partial refund by definition returned something. Without this a webhook
-- bug could park a donation in `partially_refunded` with nothing refunded,
-- which reads to every surface as a full-value donation carrying a refund
-- badge.
alter table donations
  add constraint donations_partial_refund_check
  check (status <> 'partially_refunded' or refunded_cents > 0)
  not valid;

-- ───────────────────────── 2. the new status value ───────────────────────────
-- Widening an IN-list: every existing row already satisfies the wider set, so
-- the re-validation scan is pure waste — but a single-step DROP + ADD takes it
-- anyway. NOT VALID + VALIDATE, per the playbook.
alter table donations drop constraint donations_status_check;

alter table donations
  add constraint donations_status_check
  check (status in ('pending', 'paid', 'partially_refunded', 'refunded', 'failed', 'canceled'))
  not valid;

alter table donations validate constraint donations_status_check;
alter table donations validate constraint donations_refunded_range_check;
alter table donations validate constraint donations_partial_refund_check;

-- ───────────────────────── 3. the write lock ─────────────────────────────────
-- `refunded_cents` is a money column with exactly one writer, the same as
-- `status`. The lock trigger guarded only `status`, so a client role reaching
-- the table by any future permissive policy could have moved the refunded
-- amount without moving the status the CHECK ties it to.
create or replace function lock_donation_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Trusted callers: the REST service role (the webhook), or genuine direct SQL
  -- (migrations + seed) which reach here with an empty role claim AND a
  -- privileged session_user. PostgREST authenticates every end-user request as
  -- the `authenticator` login role, so an end-user request can never present
  -- session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    raise exception 'donations is service-role-only (the donation webhook is the sole writer)'
      using errcode = '42501';
  end if;

  if old.status is distinct from new.status then
    raise exception 'donations.status is read-only for non-service-role callers'
      using errcode = '42501';
  end if;

  if old.refunded_cents is distinct from new.refunded_cents then
    raise exception 'donations.refunded_cents is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ───────────────────────── 4. indexes ────────────────────────────────────────
-- The feed + totals now read two statuses, and a partial index on
-- `status = 'paid'` cannot serve `partially_refunded` rows — the read would
-- fall back to a sequential scan of the whole ledger.
create index donations_fundraiser_active_idx
  on donations (fundraiser_id, paid_at desc)
  where status in ('paid', 'partially_refunded');

drop index donations_fundraiser_paid_idx;

-- Every `charge.refunded` delivery resolves its row by payment intent, on both
-- ledgers in turn (the webhook tries donations first, then event_orders), and
-- neither column was indexed — so one refund cost two sequential scans.
create index donations_payment_intent_idx
  on donations (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

create index event_orders_payment_intent_idx
  on event_orders (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

-- ───────────────────────── 5. the public numbers ─────────────────────────────
-- raised = what the charity actually kept. A `refunded` row is excluded rather
-- than netted to zero: for a correctly recorded full refund the two are the
-- same number, but for a pre-20270620_001 row (refunded_cents = 0, amount
-- unknown) netting would add the whole donation back to the total.
create or replace function fundraiser_totals(p_fundraiser_id uuid)
returns table (
  raised_cents bigint,
  donor_count  bigint,
  goal_cents   integer,
  currency     text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(d.amount_cents - d.refunded_cents)
      filter (where d.status in ('paid', 'partially_refunded')), 0)::bigint as raised_cents,
    count(*) filter (where d.status in ('paid', 'partially_refunded'))::bigint as donor_count,
    f.goal_cents,
    f.currency
  from fundraisers f
  left join donations d on d.fundraiser_id = f.id
  where f.id = p_fundraiser_id
    and fundraiser_anchor_visible(f.run_id, f.event_id)
  group by f.goal_cents, f.currency;
$$;

comment on function fundraiser_totals(uuid) is
  'Thermometer totals for a visible fundraiser: { raised_cents, donor_count, '
  'goal_cents, currency } as an aggregate sum (never per-row). raised_cents is '
  'NET of refunds (amount_cents - refunded_cents over paid + '
  'partially_refunded). Zero rows when the fundraiser anchor is not visible. '
  'fundraising.md.';

-- The feed shows what each donor actually gave, for the same reason: a gross
-- amount beside a net total is two public numbers that do not add up.
create or replace function fundraiser_feed(p_fundraiser_id uuid, p_limit integer default 50)
returns table (
  display_name text,
  message      text,
  amount_cents integer,
  currency     text,
  is_anonymous boolean,
  paid_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    case when d.is_anonymous then null else d.display_name end as display_name,
    d.message,
    (d.amount_cents - d.refunded_cents) as amount_cents,
    d.currency,
    d.is_anonymous,
    d.paid_at
  from donations d
  join fundraisers f on f.id = d.fundraiser_id
  where d.fundraiser_id = p_fundraiser_id
    and d.status in ('paid', 'partially_refunded')
    and fundraiser_anchor_visible(f.run_id, f.event_id)
  order by d.paid_at desc nulls last
  limit greatest(0, least(coalesce(p_limit, 50), 200));
$$;

comment on function fundraiser_feed(uuid, integer) is
  'Public donation feed for a visible fundraiser: paid + partially-refunded '
  'rows, public-safe columns only (donor identity / Stripe ids / owner_user_id '
  'are not projected). amount_cents is NET of refunds. Zero rows when the '
  'fundraiser anchor is not visible. fundraising.md.';
