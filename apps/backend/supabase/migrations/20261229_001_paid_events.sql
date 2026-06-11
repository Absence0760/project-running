-- Paid event registration — the money ledger (slice P1 of
-- docs/features/club_events.md).
--
-- Stripe Connect marketplace: a host (events.host_user_id, shipped in
-- 20261227_001) charges for an in-person event; the buyer's card is charged on
-- the platform account via a DESTINATION charge, funds transfer to the host's
-- connected account, and the platform takes an application fee. The host is
-- merchant of record, not the platform or the club.
--
-- This migration lays the RAIL, not the automation (P1 scope):
--   * instructor_payout_accounts — the host's Connect account + capability
--     flags mirrored from Stripe by the account.updated webhook. NO bank / tax
--     / SSN data — Stripe holds it. The connected-account id is revoked from
--     client roles (the get_event_meet_point lockdown pattern); a boolean
--     "can take payment" is exposed via host_can_take_payment().
--   * event_pricing — per (event, instance) price; writable only by an event
--     organiser AND only when the host has charges_enabled (trigger-enforced,
--     not just UI).
--   * event_orders — the LEDGER. status is service-role-only (a replayed
--     webhook must not double-grant a slot or double-count revenue; the
--     stripe-events webhook is the sole writer, mirroring the
--     subscription_tier lock).
--   * event_attendees.order_id — a paid order is required for a going /
--     waitlisted row on a PRICED event (free events unaffected).
--
-- Automated refund/cancel coupling, buyer self-cancel, waitlist notify-to-pay,
-- mobile register, virtual paid events, and club-level pooled payouts are all
-- LATER phases (P2-P4). Refunds in P1 are manual via the Stripe dashboard.

-- ───────────────────────── 0. is_event_visible helper ────────────────────────
-- The events SELECT policy inlines "the parent club is public, owned, or
-- joined". event_pricing (and any later paid surface) needs the same predicate;
-- extracting it once is the durable fix vs. duplicating the exists-clause.
-- SECURITY DEFINER so it evaluates club membership reliably.
-- search_path includes `private` because the four membership oracles
-- (is_club_member etc.) were moved there in 20261120_001; an unqualified call
-- resolves through it. private grants USAGE only to client roles, so no
-- shadowing-object escalation.
create or replace function is_event_visible(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1 from events e
    join clubs c on c.id = e.club_id
    where e.id = p_event_id
      and (c.is_public = true or c.owner_id = auth.uid() or is_club_member(c.id))
  );
$$;

revoke all on function is_event_visible(uuid) from public;
grant execute on function is_event_visible(uuid) to authenticated, anon;

-- ───────────────────────── 1. instructor_payout_accounts ─────────────────────
-- One row per host. user_id is the PK (a user has at most one payout account,
-- reused across every club they host in — payouts follow the person, not the
-- club). The capability booleans are mirrored from Stripe by the
-- account.updated webhook; they are NOT host-writable (the webhook is
-- service-role, and RLS below blocks client writes to the row entirely).
create table instructor_payout_accounts (
  user_id                  uuid primary key references auth.users on delete cascade,
  stripe_connect_account_id text not null,
  charges_enabled          boolean not null default false,
  payouts_enabled          boolean not null default false,
  details_submitted        boolean not null default false,
  country                  text,
  default_currency         text,
  onboarded_at             timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create unique index instructor_payout_accounts_connect_id_idx
  on instructor_payout_accounts (stripe_connect_account_id);

alter table instructor_payout_accounts enable row level security;

-- Own-row read only. A host sees their own onboarding state on /settings/payouts.
-- No cross-user read: another user's Connect account id + KYC capability flags
-- are not anyone else's business.
create policy "own payout account readable"
  on instructor_payout_accounts for select
  using (user_id = auth.uid());

-- No client INSERT / UPDATE / DELETE policy: the row is created and maintained
-- exclusively by the events-connect-onboard + stripe-events webhook EFs running
-- with the service role (which bypasses RLS). A user-JWT write finds no
-- permissive policy and is rejected. This keeps the capability flags
-- (charges_enabled gating who may price an event) un-forgeable from the client.

-- Column lockdown: the stripe_connect_account_id is sensitive (it identifies
-- the host's Stripe merchant account). Even the own-row SELECT policy should
-- not hand the raw id to the client — the web UI needs only the boolean "can I
-- take payment yet?" and the country/currency for display. Revoke the id
-- column from client roles; expose the boolean via the function below (the
-- get_event_meet_point pattern). The remaining display columns stay readable
-- under the own-row policy.
revoke select (stripe_connect_account_id) on instructor_payout_accounts
  from authenticated, anon;

-- Boolean-only exposure of payment capability, keyed on the caller. Returns
-- true only for the caller's own fully-onboarded, charges-enabled account.
-- SECURITY DEFINER + pinned search_path so the read is reliable regardless of
-- the column grants above.
create or replace function host_can_take_payment(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from instructor_payout_accounts a
    where a.user_id = p_user_id
      and a.charges_enabled = true
  );
$$;

revoke all on function host_can_take_payment(uuid) from public;
grant execute on function host_can_take_payment(uuid) to authenticated;

comment on function host_can_take_payment(uuid) is
  'Boolean-only exposure of a host''s Stripe charges_enabled capability. The '
  'stripe_connect_account_id column is revoked from client roles (it identifies '
  'the merchant account); the web payout UI reads this flag instead. '
  'club_events.md slice P1.';

-- ───────────────────────── 2. event_pricing ──────────────────────────────────
-- Price for an event, optionally overridden per recurrence instance.
--   instance_start IS NULL -> the price for the whole series.
--   instance_start non-null -> overrides one occurrence (a one-off workshop
--                              priced higher than the weekly session).
-- modality is 'in_person' only in P1 (a virtual / livestream class is a digital
-- good that re-opens the app-store 30% IAP rule — reserved for P4 behind a
-- legal decision). platform_fee_bps is platform config, not host-set.
create table event_pricing (
  event_id                uuid not null references events on delete cascade,
  instance_start          timestamptz,
  price_cents             integer not null,
  currency                text not null default 'usd',
  modality                text not null default 'in_person',
  platform_fee_bps        integer not null default 0,
  refund_policy           text not null default 'full_until_24h',
  sales_close_offset_minutes integer not null default 0,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- The CHECKs are separate `add constraint` statements (not inline) to match the
-- narrow-union pattern the parity guard (check_constraint_unions.mjs) expects.
alter table event_pricing add constraint event_pricing_modality_check
  check (modality in ('in_person'));
alter table event_pricing add constraint event_pricing_refund_policy_check
  check (refund_policy in ('full_until_start', 'full_until_24h', 'no_refund'));
alter table event_pricing add constraint event_pricing_price_positive_check
  check (price_cents > 0);
alter table event_pricing add constraint event_pricing_fee_bps_range_check
  check (platform_fee_bps >= 0 and platform_fee_bps <= 10000);

-- A series row and any per-instance override are distinct; a NULL instance_start
-- is the series default. Two unique indexes (NULL is not comparable in a plain
-- unique constraint) so there is at most one series row and at most one row per
-- overridden instance.
create unique index event_pricing_series_uniq
  on event_pricing (event_id) where instance_start is null;
create unique index event_pricing_instance_uniq
  on event_pricing (event_id, instance_start) where instance_start is not null;

alter table event_pricing enable row level security;

-- Readable with the event (price is shown on the public event-detail page so a
-- drop-in can decide to register). Inherits event/club visibility.
create policy "event pricing readable with event"
  on event_pricing for select
  using (is_event_visible(event_id));

-- Writable by an event organiser of the parent club AND only when the host has
-- a charges-enabled Connect account (CHECK-backed below by a trigger, since RLS
-- WITH CHECK can't easily reach the host's capability without leaking the
-- account-id column). The policy enforces the organiser gate; the trigger
-- enforces the charges_enabled gate.
create policy "organisers manage event pricing"
  on event_pricing for all
  using (
    exists (
      select 1 from events e
      where e.id = event_pricing.event_id
        and private.is_event_organiser(e.club_id)
    )
  )
  with check (
    exists (
      select 1 from events e
      where e.id = event_pricing.event_id
        and private.is_event_organiser(e.club_id)
    )
  );

-- A price may only be set when the event's host can actually take payment.
-- Enforced server-side (a direct API write must 403, not just a hidden UI
-- control). SECURITY DEFINER so it can read the host's capability through the
-- revoked column.
create or replace function enforce_pricing_requires_charges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_host uuid;
begin
  select host_user_id into v_host from events where id = new.event_id;
  if v_host is null or not host_can_take_payment(v_host) then
    raise exception 'event host has no charges-enabled payout account; cannot price event %', new.event_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger event_pricing_requires_charges
  before insert or update on event_pricing
  for each row execute function enforce_pricing_requires_charges();

-- ───────────────────────── 3. event_orders (the ledger) ──────────────────────
-- One row per checkout attempt. status transitions are driven SOLELY by the
-- stripe-events webhook (service role); a user-JWT must never write status (the
-- subscription_tier lock pattern). A pending order holds a soft capacity
-- reservation until reserved_until; the webhook re-checks capacity at confirm.
create table event_orders (
  id                       uuid primary key default gen_random_uuid(),
  event_id                 uuid not null references events on delete cascade,
  instance_start           timestamptz not null,
  buyer_user_id            uuid not null references auth.users on delete cascade,
  host_user_id             uuid not null references auth.users on delete cascade,
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  amount_cents             integer not null,
  currency                 text not null default 'usd',
  platform_fee_cents       integer not null default 0,
  status                   text not null default 'pending',
  created_at               timestamptz not null default now(),
  paid_at                  timestamptz,
  refunded_at              timestamptz,
  reserved_until           timestamptz
);

alter table event_orders add constraint event_orders_status_check
  check (status in ('pending', 'paid', 'refunded', 'partially_refunded', 'failed', 'canceled'));
alter table event_orders add constraint event_orders_amount_nonneg_check
  check (amount_cents >= 0 and platform_fee_cents >= 0);

create unique index event_orders_checkout_session_idx
  on event_orders (stripe_checkout_session_id) where stripe_checkout_session_id is not null;
create index event_orders_buyer_idx on event_orders (buyer_user_id, created_at desc);
create index event_orders_event_instance_idx on event_orders (event_id, instance_start);
-- Soft-reservation sweep: pending orders whose reservation has lapsed.
create index event_orders_reservation_sweep_idx
  on event_orders (reserved_until) where status = 'pending';

alter table event_orders enable row level security;

-- Buyer reads their own orders; an event organiser reads orders for their
-- events (for the host registrations summary). No other read.
create policy "buyer reads own orders"
  on event_orders for select
  using (buyer_user_id = auth.uid());

create policy "organisers read their event orders"
  on event_orders for select
  using (
    exists (
      select 1 from events e
      where e.id = event_orders.event_id
        and private.is_event_organiser(e.club_id)
    )
  );

-- WRITES ARE SERVICE-ROLE ONLY. No permissive client INSERT/UPDATE/DELETE
-- policy exists, so a user-JWT write is rejected by RLS. As a defence-in-depth
-- second layer (and to give a clear error rather than a silent 0-row write),
-- a BEFORE trigger rejects any non-service-role status write — mirroring
-- lock_subscription_columns. This also covers any future permissive policy
-- that might be added by mistake: the webhook (service_role) is the sole writer
-- of status, idempotently.
create or replace function lock_event_order_status()
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
  -- Trusted callers, identical to lock_subscription_columns: the REST service
  -- role (the webhook), or genuine direct SQL (migrations + seed) which reach
  -- here with an empty role claim AND a privileged session_user. PostgREST
  -- authenticates every request as the `authenticator` login role, so an
  -- end-user request can never present session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    raise exception 'event_orders is service-role-only (webhook is the sole writer)'
      using errcode = '42501';
  end if;

  if old.status is distinct from new.status then
    raise exception 'event_orders.status is read-only for non-service-role callers'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger event_orders_status_lock
  before insert or update on event_orders
  for each row execute function lock_event_order_status();

-- ───────────────────────── 4. event_attendees.order_id ───────────────────────
-- Links a paid registration to the order that granted it. NULL for free
-- events. A going / waitlisted row on a PRICED event requires a PAID order
-- (free events unaffected). The webhook writes the attendee row + order_id
-- together at checkout.session.completed.
alter table event_attendees add column order_id uuid references event_orders on delete set null;

create index event_attendees_order_idx on event_attendees (order_id) where order_id is not null;

-- A priced event is one with a matching event_pricing row (the per-instance
-- override wins, else the series default). For such an event, a going /
-- waitlisted attendee row must point at a PAID order. SECURITY DEFINER so the
-- pricing lookup is reliable regardless of the writer's RLS visibility.
create or replace function enforce_paid_order_for_priced_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_priced boolean;
begin
  if new.status not in ('going', 'waitlisted') then
    return new;
  end if;

  select exists (
    select 1 from event_pricing p
    where p.event_id = new.event_id
      and (p.instance_start = new.instance_start or p.instance_start is null)
  ) into v_priced;

  if not v_priced then
    return new;  -- free event: order_id stays null, no gate
  end if;

  if new.order_id is null then
    raise exception 'a paid order is required to register for priced event % (instance %)', new.event_id, new.instance_start
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from event_orders o
    where o.id = new.order_id
      and o.buyer_user_id = new.user_id
      and o.event_id = new.event_id
      and o.status = 'paid'
  ) then
    raise exception 'order % is not a paid order belonging to this buyer for this event', new.order_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger event_attendees_require_paid_order
  before insert or update on event_attendees
  for each row execute function enforce_paid_order_for_priced_event();
