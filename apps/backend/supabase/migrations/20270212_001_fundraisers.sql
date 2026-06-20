-- Charity fundraising pages on a run or event (docs/features/fundraising.md).
--
-- A runner or club organiser attaches a public charity fundraiser to a run OR
-- a club event: a goal thermometer (raised vs goal) + a public donation feed
-- (donor display name + amount + optional message) + a share URL. Anyone,
-- including a logged-out stranger, can donate via Stripe-hosted Checkout; the
-- money settles into the FUNDRAISER OWNER's connected Stripe account via the
-- SAME destination-charge Connect rail shipped for paid events
-- (20261229_001_paid_events.sql / decisions.md §139 + §166).
--
-- This migration reuses the paid-events rail wholesale:
--   * instructor_payout_accounts + host_can_take_payment() — the fundraiser
--     owner's payout account IS the same user-level payout account they'd use
--     to host paid events. No new payout table.
--   * the webhook_events dedupe table + the stripe-events webhook (extended
--     with a donation branch) — one webhook, one secret.
--
-- It adds two new tables:
--   * fundraisers — polymorphic over (run | event) via a nullable-FK pair +
--     CHECK (exactly one). A fundraiser on a publicly-visible anchor is
--     anon-readable (it's a share target); a fundraiser on a private anchor is
--     owner-only (fail-closed).
--   * donations — the LEDGER. status is service-role-only (a replayed webhook
--     must not double-count a donation; the stripe-events webhook is the sole
--     writer, mirroring event_orders). Donor identity + Stripe ids +
--     owner_user_id are revoked from client roles; the public feed is exposed
--     via a SECURITY DEFINER RPC that projects only the public-safe columns.
--
-- GATING: live charges require operator sk_live_ / whsec_ keys (default unset →
-- the checkout EF returns 503 stripe_not_configured, inert) AND owner + CISO +
-- counsel sign-off (charitable-solicitation regulatory surface). This is a
-- PRE-DEPLOY gate, not a reason to leave code unwritten — the whole path is
-- built and test-mode-verified. See decisions.md §166.

-- ───────────────────────── 1. fundraisers ────────────────────────────────────
create table fundraisers (
  id               uuid primary key default gen_random_uuid(),
  owner_user_id    uuid not null references auth.users on delete cascade,
  -- Exactly one anchor (a run OR a club event); the CHECK below enforces it.
  run_id           uuid references runs on delete cascade,
  event_id         uuid references events on delete cascade,
  charity_name     text not null,
  charity_url      text,
  title            text not null,
  story            text,
  goal_cents       integer not null,
  currency         text not null default 'usd',
  -- platform config, not owner-set. A charity donation is not skimmed (0 bps
  -- default — see decisions.md §166 open question 1); the plumbing exists so a
  -- future platform fee is a config change, not a schema change.
  platform_fee_bps integer not null default 0,
  status           text not null default 'open',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table fundraisers add constraint fundraisers_anchor_check
  check ((run_id is not null) <> (event_id is not null));
alter table fundraisers add constraint fundraisers_status_check
  check (status in ('open', 'closed'));
alter table fundraisers add constraint fundraisers_goal_positive_check
  check (goal_cents > 0);
alter table fundraisers add constraint fundraisers_fee_bps_range_check
  check (platform_fee_bps >= 0 and platform_fee_bps <= 10000);
alter table fundraisers add constraint fundraisers_charity_url_scheme_check
  check (charity_url is null or charity_url ~* '^https?://');

-- At most one fundraiser per anchor (partial unique on each FK; NULL is not
-- comparable in a plain unique constraint).
create unique index fundraisers_run_uniq on fundraisers (run_id) where run_id is not null;
create unique index fundraisers_event_uniq on fundraisers (event_id) where event_id is not null;

alter table fundraisers enable row level security;

-- The anchor-visibility predicate: a fundraiser is readable by anyone the
-- anchored run/event is itself visible to. SECURITY DEFINER so it can evaluate
-- run/event visibility reliably regardless of the caller's own RLS visibility.
-- private.is_run_visible_to (20260812_001) is owner-or-public; is_event_visible
-- (20261229_001) is public-club / owner / member. search_path includes `private`
-- so the relocated run-visibility oracle resolves unqualified (the is_event_visible
-- precedent). Fail-closed: a fundraiser on a private run with no public event
-- anchor is owner-only.
create or replace function fundraiser_anchor_visible(p_run_id uuid, p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select
    case
      when p_run_id is not null then is_run_visible_to(p_run_id, auth.uid())
      when p_event_id is not null then is_event_visible(p_event_id)
      else false
    end;
$$;

revoke all on function fundraiser_anchor_visible(uuid, uuid) from public;
grant execute on function fundraiser_anchor_visible(uuid, uuid) to authenticated, anon;

-- SELECT: public when the anchor is publicly visible (the share-target case),
-- else owner-only. The owner branch covers a fundraiser on a private run before
-- it's shared.
create policy "fundraisers readable when anchor visible"
  on fundraisers for select
  using (
    owner_user_id = auth.uid()
    or fundraiser_anchor_visible(run_id, event_id)
  );

-- INSERT/UPDATE/DELETE: the owner only, and the caller must own the anchor (own
-- the run, or organise the event's club). The charges-enabled gate is enforced
-- by the trigger below (a fundraiser cannot open to take money without a
-- charges-enabled payout account).
create policy "owners manage their fundraisers"
  on fundraisers for all
  using (
    owner_user_id = auth.uid()
    and (
      (run_id is not null and exists (
        select 1 from runs r where r.id = fundraisers.run_id and r.user_id = auth.uid()
      ))
      or (event_id is not null and exists (
        select 1 from events e
        where e.id = fundraisers.event_id
          and private.is_event_organiser(e.club_id)
      ))
    )
  )
  with check (
    owner_user_id = auth.uid()
    and (
      (run_id is not null and exists (
        select 1 from runs r where r.id = fundraisers.run_id and r.user_id = auth.uid()
      ))
      or (event_id is not null and exists (
        select 1 from events e
        where e.id = fundraisers.event_id
          and private.is_event_organiser(e.club_id)
      ))
    )
  );

-- A fundraiser may only exist when its owner can actually take payment.
-- Enforced server-side (a direct API write must be rejected, not just a hidden
-- UI control). Mirrors enforce_pricing_requires_charges (20261229_001).
-- SECURITY DEFINER so it can read the owner's capability through the revoked
-- stripe_connect_account_id column.
create or replace function enforce_fundraiser_requires_charges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.owner_user_id is null or not host_can_take_payment(new.owner_user_id) then
    raise exception 'fundraiser owner has no charges-enabled payout account; cannot open a fundraiser'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger fundraisers_requires_charges
  before insert or update on fundraisers
  for each row execute function enforce_fundraiser_requires_charges();

-- ───────────────────────── 2. donations (the ledger) ─────────────────────────
-- status is driven SOLELY by the stripe-events webhook (service role); a
-- user-JWT must never write it (the event_orders lock pattern). donor_user_id /
-- owner_user_id / stripe ids are revoked from client roles below; the public
-- feed is served by the fundraiser_feed RPC (public-safe projection only).
create table donations (
  id                         uuid primary key default gen_random_uuid(),
  fundraiser_id              uuid not null references fundraisers on delete cascade,
  donor_user_id              uuid references auth.users on delete set null,
  owner_user_id              uuid not null references auth.users on delete cascade,
  display_name               text,
  message                    text,
  stripe_checkout_session_id text,
  stripe_payment_intent_id   text,
  amount_cents               integer not null,
  currency                   text not null default 'usd',
  platform_fee_cents         integer not null default 0,
  status                     text not null default 'pending',
  is_anonymous               boolean not null default false,
  created_at                 timestamptz not null default now(),
  paid_at                    timestamptz,
  refunded_at                timestamptz
);

alter table donations add constraint donations_status_check
  check (status in ('pending', 'paid', 'refunded', 'failed', 'canceled'));
alter table donations add constraint donations_amount_positive_check
  check (amount_cents > 0 and platform_fee_cents >= 0);

create unique index donations_checkout_session_idx
  on donations (stripe_checkout_session_id) where stripe_checkout_session_id is not null;
create index donations_fundraiser_paid_idx
  on donations (fundraiser_id, paid_at desc) where status = 'paid';

alter table donations enable row level security;

-- No PERMISSIVE client SELECT policy on the base table: a direct
-- `from('donations')` read by a client role finds no policy and returns zero
-- rows. The public feed (paid rows, public-safe columns only) is served
-- exclusively by the fundraiser_feed SECURITY DEFINER RPC below. This keeps
-- donor identity (donor_user_id), the Stripe ids, owner_user_id, and pending /
-- failed rows off the wire entirely.
--
-- Defence in depth: even if a future permissive SELECT policy were added by
-- mistake, the sensitive columns are revoked from client roles.
revoke select (donor_user_id, owner_user_id, stripe_checkout_session_id,
               stripe_payment_intent_id, platform_fee_cents)
  on donations from authenticated, anon;

-- WRITES ARE SERVICE-ROLE-ONLY. No permissive client INSERT/UPDATE/DELETE
-- policy exists, so a user-JWT write is rejected by RLS. A BEFORE trigger
-- rejects any non-service-role status write as a clear-error second layer
-- (mirrors lock_event_order_status verbatim). The donation webhook
-- (service_role) is the sole, idempotent writer of status.
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
  return new;
end;
$$;

create trigger donations_status_lock
  before insert or update on donations
  for each row execute function lock_donation_status();

-- ───────────────────────── 3. public feed + totals RPCs ──────────────────────
-- The public donation feed: the PAID rows of a publicly-visible fundraiser,
-- public-safe columns only (display_name, message, amount, currency, paid_at).
-- Donor identity, Stripe ids, owner_user_id, and pending/failed rows never
-- surface. The visibility gate inside the function IS the authorization gate,
-- so EXECUTE is granted to both client roles (an anon caller runs the body;
-- a non-visible fundraiser yields zero rows).
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
    d.amount_cents,
    d.currency,
    d.is_anonymous,
    d.paid_at
  from donations d
  join fundraisers f on f.id = d.fundraiser_id
  where d.fundraiser_id = p_fundraiser_id
    and d.status = 'paid'
    and fundraiser_anchor_visible(f.run_id, f.event_id)
  order by d.paid_at desc nulls last
  limit greatest(0, least(coalesce(p_limit, 50), 200));
$$;

revoke all on function fundraiser_feed(uuid, integer) from public;
grant execute on function fundraiser_feed(uuid, integer) to anon, authenticated;

comment on function fundraiser_feed(uuid, integer) is
  'Public donation feed for a visible fundraiser: PAID rows, public-safe '
  'columns only (donor identity / Stripe ids / owner_user_id are revoked from '
  'client roles). Zero rows when the fundraiser anchor is not visible. '
  'fundraising.md.';

-- Thermometer totals: a SUM, never per-row, so a client can't reconstruct
-- individual donations from the aggregate. Gated on anchor visibility.
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
    coalesce(sum(d.amount_cents) filter (where d.status = 'paid'), 0)::bigint as raised_cents,
    count(*) filter (where d.status = 'paid')::bigint as donor_count,
    f.goal_cents,
    f.currency
  from fundraisers f
  left join donations d on d.fundraiser_id = f.id
  where f.id = p_fundraiser_id
    and fundraiser_anchor_visible(f.run_id, f.event_id)
  group by f.goal_cents, f.currency;
$$;

revoke all on function fundraiser_totals(uuid) from public;
grant execute on function fundraiser_totals(uuid) to anon, authenticated;

comment on function fundraiser_totals(uuid) is
  'Thermometer totals for a visible fundraiser: { raised_cents, donor_count, '
  'goal_cents, currency } as an aggregate sum (never per-row). Zero rows when '
  'the fundraiser anchor is not visible. fundraising.md.';
