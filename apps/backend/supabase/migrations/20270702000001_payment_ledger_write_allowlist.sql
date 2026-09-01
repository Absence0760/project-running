-- The two money-ledger write locks enumerate the columns a client may NOT
-- change. Both enumerations are incomplete, and one of them is incomplete
-- today rather than eventually.
--
-- `lock_event_order_status` (20261229_001, extended by 20270303_001) states in
-- its own comment that "a non-service-role UPDATE may touch ONLY
-- refund_initiated_at", then implements that as a list of fourteen columns
-- plus `status`. `id` is not on the list. `event_orders` is the one payment
-- table that carries a permissive client UPDATE policy -- "buyer initiates
-- refund on own paid order", `using (buyer_user_id = auth.uid() and status in
-- ('paid','partially_refunded'))` with the same WITH CHECK -- and
-- `20270408_001` grants `authenticated` UPDATE on every column of the table.
-- So the buyer of a paid order could rewrite its primary key. Measured on the
-- local stack before this file, as the buyer's own JWT with RLS in force:
--
--   update event_orders set refund_initiated_at = now() where id = <mine>;
--   -- UPDATE 1, the affordance the policy exists for
--   update event_orders set id = <any uuid> where id = <mine>;
--   -- UPDATE 1
--
-- Nothing rolls back off that: the WITH CHECK still holds (buyer_user_id and
-- status are untouched), and the two foreign keys that reference the row --
-- `event_attendees.order_id` and, since 20270630000001, the refund ledger's
-- `payment_refunds.event_order_id` -- are `on update no action`, so they only
-- refuse the rewrite when such a child already exists. Before a seat is taken
-- or a refund is recorded, the id moves freely.
--
-- The blast radius is auditability rather than money: the id is what
-- `events-checkout` puts in the Stripe session's `metadata.order_id`, what it
-- returns to the client, and what `handleNotPaid` resolves an expiry delivery
-- by. After a rewrite, that key names no row -- an expired session's
-- reservation is never released ("skipped: unknown_order"), and a
-- reconciliation of Stripe's records against this ledger finds a charge whose
-- order has vanished. 20270630000001 made it worse in the same round by
-- making the id the join key of the refund ledger.
--
-- The durable fix is not a fifteenth column name. An enumeration of what may
-- not change is a denylist, and every column added to either table afterwards
-- is client-writable by default until somebody remembers to extend it --
-- which is exactly how `id` was missed, and how `refund_initiated_at` had to
-- be hand-added when 20270303_001 opened the one legitimate write. So both
-- locks are rewritten as ALLOWLISTS over the whole row: the two rows'
-- jsonb images must be equal once the permitted columns are removed from
-- each. A new column is then locked the moment it exists.
--
--   * event_orders permits exactly `refund_initiated_at` -- the buyer
--     self-cancel stamp 20270303_001 opened, and the only client write path
--     the schema has to either ledger.
--   * donations permits nothing. Its header has said "the donation webhook is
--     the sole writer" since 20270213_001 while the trigger checked `status`
--     and (from 20270620_001) `refunded_cents` only, leaving `amount_cents` --
--     the numerator of `fundraiser_totals` -- `paid_at`, `platform_fee_cents`
--     and `client_request_id` to RLS alone. This is inert today and is being
--     stated rather than changed: `donations` carries no permissive policy at
--     all, so a client UPDATE matches no row and never reaches the trigger.
--     Verified against the live catalog: `pg_policy` has zero rows for
--     `public.donations`. It stops being inert the first time somebody adds a
--     donor-edits-their-message policy, which is the failure this shape
--     exists to survive.
--
-- The specific `status` messages are kept ahead of the generic check on both
-- functions: a status forgery is the attempt worth naming in the error, and
-- both are the wording the shipped tests and the webhook's own logs read.
--
-- Online-safety (docs/backend/migration_locks.md): `create or replace
-- function` takes no lock on any table and rewrites nothing. The triggers
-- themselves are untouched -- same names, same timing, same functions -- so
-- there is no `alter table` here at all and neither ledger is blocked for any
-- part of this.

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
  -- Trusted callers, unchanged: the REST service role (the webhook), or
  -- genuine direct SQL (migrations + seed) which reach here with an empty role
  -- claim AND a privileged session_user. PostgREST authenticates every request
  -- as the `authenticator` login role, so an end-user request can never present
  -- session_user = postgres.
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

  -- The allowlist. Comparing the two row images with the permitted column
  -- removed from each covers every column the table has now and every one it
  -- gains later, including the primary key.
  if to_jsonb(new) - 'refund_initiated_at' is distinct from to_jsonb(old) - 'refund_initiated_at' then
    raise exception 'event_orders is service-role-only except the buyer refund stamp'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

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

  -- The allowlist is empty: no client write path to this ledger exists.
  if to_jsonb(new) is distinct from to_jsonb(old) then
    raise exception 'donations is service-role-only (the donation webhook is the sole writer)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
