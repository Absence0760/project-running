-- One row per Stripe Refund, so a refund that FAILED is a fact the database
-- holds rather than a line in a log.
--
-- § 789 built `refund_failed` and deliberately refused to move
-- `partially_refunded` on either ledger. Both reasons were right and neither
-- has changed: on `event_orders` the status is seat-bearing on both
-- `enforce_paid_order_for_priced_event` and the buyer-cancel policy
-- (20270522_001), and on `donations` the only way to walk the money back was
-- `refunded_cents = refunded_cents - <this refund>`, which is arithmetic on a
-- running total and double-applies on an at-least-once redelivery — exactly
-- what § 769 avoided. What § 789 left was the cost: for a failed PARTIAL
-- refund the money discrepancy existed ONLY in a `console.error`. Nothing was
-- queryable. `event_orders` carries no refunded amount at all, and
-- `donations.refunded_cents` went on stating an instalment that had come back
-- to us.
--
-- The refusal was never the problem. The missing noun was. A refund is a thing
-- with an identity (`re_…`), an amount and a lifecycle of its own, and it was
-- being represented as a delta folded into a parent column. Give it a row and
-- the arithmetic § 789 refused becomes a SET: a redelivery is an upsert on a
-- unique key, not an increment, so idempotency is a property of the schema
-- rather than of the caller's care.
--
-- ── What this does NOT do: derive `refunded_cents` from these rows ───────────
-- The obvious next step is to make `donations.refunded_cents` the sum of its
-- children. It is refused, and the reason is coverage rather than taste.
--
-- The two event families carry different objects. `charge.refunded` carries a
-- CHARGE — it says the cumulative `amount_refunded`, and carries no refund id
-- to key a child row on. The refund-lifecycle trio (`refund.failed` /
-- `refund.updated` / `charge.refund.updated`) carries a REFUND — an id, an
-- amount and a status. So a refund that succeeds instantly and never emits a
-- lifecycle event produces no child row at all. Worse, WHICH of these an
-- endpoint receives is dashboard configuration this repo cannot read (§ 789
-- measured that and handles both API eras for exactly this reason).
--
-- Summing an incomplete set would therefore turn a bounded understatement into
-- an unbounded overstatement: a succeeded refund with no child row would be
-- counted as money the charity kept. So `refunded_cents` stays what it is —
-- a monotone latch on Stripe's own cumulative `charge.amount_refunded`, whose
-- authority is Stripe and not this table — and the child rows are the
-- authority for REVERSALS only. That correction is strictly additive and
-- fail-closed in the right direction: a reversal we never hear about leaves
-- today's behaviour exactly (understating what was raised, § 789's "smaller,
-- safe lie"), and one we do hear about is subtracted exactly once because the
-- unique key says so. No new cache column, no trigger-maintained total, and
-- therefore nothing new in docs/backend/derived_state.md — the reversal sum is
-- computed at read time inside the two thermometer functions.
--
-- ── Online-safety (docs/backend/migration_locks.md) ──────────────────────────
-- CREATE TABLE locks nothing that exists; a brand-new relation has no readers
-- and no rows, so its CHECKs and its unique index cost nothing to validate and
-- are written in the single-step form. The two FKs point AT `donations` and
-- `event_orders` from an empty child, so `NOT VALID` would skip a scan of zero
-- rows — but the FK still takes a SHARE ROW EXCLUSIVE on each referenced
-- table, which is why they are declared inline on the empty table rather than
-- added later. Neither parent is in the guarded high-volume set. There is no
-- backfill: `payment_refunds` starts empty by construction, because a refund
-- that predates this migration emitted its lifecycle event before there was
-- anywhere to put it, and inventing rows from `refunded_cents` would fabricate
-- refund ids. `create or replace function` on the two thermometer functions
-- takes only an ACCESS EXCLUSIVE on the pg_proc row, preserves the existing
-- ACL, and blocks nothing on either table.

-- ───────────────────────── 1. the refund ledger ──────────────────────────────
create table payment_refunds (
  id               uuid primary key default gen_random_uuid(),
  stripe_refund_id text not null,
  donation_id      uuid references donations on delete cascade,
  event_order_id   uuid references event_orders on delete cascade,
  amount_cents     integer not null,
  status           text not null,
  failure_reason   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table payment_refunds is
  'One row per Stripe Refund on either payment ledger, keyed on the Stripe '
  'Refund id so a webhook redelivery is an upsert and never a double-count. '
  'Written only by the stripe-events webhook (service role); no client role '
  'can read it. The operator worklist for money owed back by another route is '
  '`select * from payment_refunds where status in (''failed'', ''canceled'')`, '
  'which covers a PARTIAL failure — the case the `refund_failed` statuses '
  'cannot represent. decisions § 789, § 823.';

-- A refund belongs to exactly one ledger. Two nullable FKs plus this CHECK
-- keeps real referential integrity on both sides, where an untyped
-- (entity_type, entity_id) pair would keep neither.
alter table payment_refunds
  add constraint payment_refunds_one_ledger_check
  check ((donation_id is null) <> (event_order_id is null));

alter table payment_refunds
  add constraint payment_refunds_amount_nonneg_check
  check (amount_cents >= 0);

-- `failure_reason` is text a third party hands us verbatim, which is exactly
-- the class free_text_caps_test.sql derives its population from. Stripe's own
-- reasons are short tokens — the longest documented one,
-- `charge_for_pending_refund_disputed`, is 34 characters — so 120 bounds what
-- a changed or compromised upstream can store while leaving room. The webhook
-- truncates to the same figure rather than letting a longer value 23514 into
-- an endless Stripe retry; the CHECK is the backstop, not the enforcement.
-- Single-step, no NOT VALID: a table created three statements ago has no rows
-- to scan and no readers to block.
alter table payment_refunds
  add constraint payment_refunds_failure_reason_len_chk
  check (failure_reason is null or char_length(failure_reason) <= 120);

-- Stripe's own Refund.status vocabulary. `Stripe.Refund.status` is declared
-- `string | null` by the SDK — a bare string, not a union (§ 789) — so this is
-- the only place the accepted set is stated as data, and the webhook refuses
-- to record a status outside it rather than risking a CHECK violation that
-- would 500 into an endless Stripe retry.
alter table payment_refunds
  add constraint payment_refunds_status_check
  check (status in ('pending', 'requires_action', 'succeeded', 'failed', 'canceled'));

-- Idempotency by construction. Every redelivery of every lifecycle event for
-- one refund lands on this key.
create unique index payment_refunds_stripe_id_idx
  on payment_refunds (stripe_refund_id);

-- FK covering indexes (fk_covering_index_test.sql): an unindexed FK seq-scans
-- this table on every parent delete, and both parents cascade from
-- auth.users via their own owner columns.
create index payment_refunds_donation_idx
  on payment_refunds (donation_id) where donation_id is not null;

create index payment_refunds_event_order_idx
  on payment_refunds (event_order_id) where event_order_id is not null;

-- The operator worklist, and the read `fundraiser_totals` makes per fundraiser.
create index payment_refunds_reversed_idx
  on payment_refunds (updated_at desc)
  where status in ('failed', 'canceled');

-- ───────────────────────── 2. writes are service-role only ───────────────────
alter table payment_refunds enable row level security;

-- No PERMISSIVE policy of any kind. A client-role read finds no policy and
-- returns zero rows, and the grants below withhold the table outright — the
-- shape 20270621_001 had to retrofit onto `donations` after 20270213_001's
-- column-level revoke turned out to remove nothing (Postgres resolves a
-- privilege from the BROADEST grant, so a column revoke against a live
-- table-level grant reports REVOKE and creates no ACL). There is no column
-- re-grant here because there is no client read path to serve: a refund's
-- amount reaches the payer as the NET figure `fundraiser_feed` already
-- projects, and reaches an operator through the service role. It is
-- deliberately NOT claimed to reach a donor through the Art 20 export —
-- neither `donations` nor `fundraisers` is in either export spec today
-- (docs/features/fundraising.md § Deferred), so a child of `donations` could
-- not be exported even if it were listed. Adding the whole donation branch to
-- the DSAR is its own change, and its own CISO conversation.
revoke all on public.payment_refunds from anon, authenticated;

-- Second layer, mirroring lock_donation_status / lock_event_order_status: a
-- clear 42501 rather than a silent zero-row write if a permissive policy is
-- ever added by mistake. It also carries the ordering latch, which applies to
-- EVERY caller including the webhook — see below.
create or replace function lock_payment_refund_writes()
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
  -- Webhook deliveries are not ordered. A benign `refund.updated` carrying
  -- `pending` can arrive AFTER the `refund.failed` that settled the refund,
  -- and an unconditional upsert would then un-say the failure and silently
  -- restore the overstatement this table exists to correct. A terminal status
  -- therefore latches: it can be replaced by another terminal status (Stripe
  -- has no succeeded->failed transition, so that never fires in practice and
  -- costs nothing to allow), never by an in-flight one. Same shape as the
  -- `.lte('refunded_cents', …)` CAS on the donation ledger, and for the same
  -- reason — the wire is at-least-once and out-of-order.
  if tg_op = 'UPDATE' then
    if old.status in ('succeeded', 'failed', 'canceled')
       and new.status not in ('succeeded', 'failed', 'canceled') then
      new.status := old.status;
      new.failure_reason := old.failure_reason;
    end if;
    new.updated_at := now();
  end if;

  -- Trusted callers: the REST service role (the webhook), or genuine direct
  -- SQL (migrations + seed), which reach here with an empty role claim AND a
  -- privileged session_user. PostgREST authenticates every end-user request as
  -- the `authenticator` login role, so an end-user request can never present
  -- session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  raise exception 'payment_refunds is service-role-only (the stripe-events webhook is the sole writer)'
    using errcode = '42501';
end;
$$;

create trigger payment_refunds_write_lock
  before insert or update on payment_refunds
  for each row execute function lock_payment_refund_writes();

-- ───────────────────────── 3. the corrected public numbers ───────────────────
-- `refunded_cents` is the cumulative amount Stripe told us went OUT. A reversed
-- refund is an amount that came back IN, and it is already inside that figure
-- because `charge.refunded` fired when the refund was created. Adding it back
-- is therefore not new arithmetic on a running total — it is a second, separate
-- running total, summed from rows that cannot be counted twice.
--
-- `least(reversed, refunded_cents)` is the clamp that keeps the whole
-- expression inside `[0, amount_cents]` whatever the child rows say: a reversal
-- can never exceed what we recorded as refunded in the first place, so a bogus
-- amount can widen no total past the donation itself. Combined with
-- `donations_refunded_range_check` that bounds every term.
--
-- A `refunded` or `refund_failed` donation is untouched by this: both are
-- excluded from the two statuses these functions read, deliberately, because
-- on a failed FULL refund the money is owed back to the donor rather than
-- raised for the charity (§ 789). The correction lands exactly where the gap
-- was — on `partially_refunded`, the status § 789 could not move.
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
    coalesce(sum(
      d.amount_cents - d.refunded_cents
        + least(coalesce(r.reversed_cents, 0), d.refunded_cents)
    ) filter (where d.status in ('paid', 'partially_refunded')), 0)::bigint as raised_cents,
    count(*) filter (where d.status in ('paid', 'partially_refunded'))::bigint as donor_count,
    f.goal_cents,
    f.currency
  from fundraisers f
  left join donations d on d.fundraiser_id = f.id
  left join lateral (
    select sum(pr.amount_cents) as reversed_cents
    from payment_refunds pr
    where pr.donation_id = d.id
      and pr.status in ('failed', 'canceled')
  ) r on true
  where f.id = p_fundraiser_id
    and fundraiser_anchor_visible(f.run_id, f.event_id)
  group by f.goal_cents, f.currency;
$$;

comment on function fundraiser_totals(uuid) is
  'Thermometer totals for a visible fundraiser: { raised_cents, donor_count, '
  'goal_cents, currency } as an aggregate sum (never per-row). raised_cents is '
  'NET of refunds that actually delivered: amount_cents - refunded_cents, plus '
  'back any part of refunded_cents whose Stripe Refund is recorded failed or '
  'canceled in payment_refunds (§ 823). Zero rows when the fundraiser anchor '
  'is not visible. fundraising.md.';

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
    (d.amount_cents - d.refunded_cents
       + least(coalesce(r.reversed_cents, 0), d.refunded_cents)) as amount_cents,
    d.currency,
    d.is_anonymous,
    d.paid_at
  from donations d
  join fundraisers f on f.id = d.fundraiser_id
  left join lateral (
    select sum(pr.amount_cents) as reversed_cents
    from payment_refunds pr
    where pr.donation_id = d.id
      and pr.status in ('failed', 'canceled')
  ) r on true
  where d.fundraiser_id = p_fundraiser_id
    and d.status in ('paid', 'partially_refunded')
    and fundraiser_anchor_visible(f.run_id, f.event_id)
  order by d.paid_at desc nulls last
  limit greatest(0, least(coalesce(p_limit, 50), 200));
$$;

comment on function fundraiser_feed(uuid, integer) is
  'Public donation feed for a visible fundraiser: paid + partially-refunded '
  'rows, public-safe columns only (donor identity / Stripe ids / owner_user_id '
  'are not projected). amount_cents is NET of refunds that actually delivered, '
  'on the same rule as fundraiser_totals (§ 823). Zero rows when the '
  'fundraiser anchor is not visible. fundraising.md.';
