-- Tell the person the money is owed to that their refund did not land.
--
-- § 789 gave a bank-reversed refund an honest terminal status on both ledgers
-- and an operator worklist. What it did not give it was a reader. The buyer
-- cancelled, their seat was released, and the money came back to us: from
-- their side the registration is simply gone and the refund never arrived,
-- with nothing anywhere saying why. Stripe's instruction — "arrange an
-- alternative way to provide your customer with a refund" — is an instruction
-- to CONTACT them, and the contact is what was missing.
--
-- This is a notification kind rather than a `jobs.kind` of its own. The
-- notifications AFTER-INSERT fan-out already turns one row into the inbox
-- entry, the email, the web push and the native push, in every locale the
-- worker speaks; a bespoke lifecycle template would reach exactly one of
-- those four and skip the inbox, which is the only one of them that mobile
-- renders today (there is no paid-registration surface on mobile at all —
-- club_events.md P3). One row is also the only shape that reaches a DONOR:
-- `donations` has no client SELECT policy, so a donor cannot read their own
-- donation row on any surface, and the notification carries the whole sentence
-- rather than pointing at a ledger they cannot see. decisions § 825.

-- ─────────────── 1. notifications.kind += refund_failed ───────────────

-- Re-emit the full union (20270607_001 is the live list). Online two-step for
-- the same reason that migration gives: a validating ADD scans every
-- notification ever written under ACCESS EXCLUSIVE, and the scan is pure waste
-- when the change only ever widens the set.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready', 'refund_failed'
    )
  )
  not valid;
alter table notifications validate constraint notifications_kind_check;

-- ─────────────── 2. the event-order arm ───────────────

-- The transition IS the dedupe, which is why there is no `notified_at` stamp
-- here and no `lifecycle_email_log` row (email.md § Idempotency: recurring
-- transactional templates lean on the enqueue trigger's transition guard).
-- `refunded -> refund_failed` is a compare-and-set in the webhook against the
-- status it read, so a redelivered Stripe event finds `refund_failed` already
-- there, updates nothing, and fires no trigger. The `when` clause below is the
-- second belt: an UPDATE that rewrites the row without moving the status —
-- a `refunded_at` correction, a reconciliation touch — is not a new failure
-- and must not re-announce a fortnight-old one.
--
-- SECURITY DEFINER because `notifications` INSERT is closed to every client
-- role (20260528000001). The trigger is on a service-role-only table, so the
-- definer rights add no reachable surface: nothing but the webhook can move
-- this status in the first place (`lock_event_order_status`).
--
-- `event_id` + `event_instance_start` are carried so the CTA can land on the
-- event page, which is where § 825's banner explains the same thing at more
-- length. Both clients degrade to the inbox when the FK is absent, which is
-- the donation arm's normal case.
create or replace function notify_refund_failed_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, kind, event_id, event_instance_start)
  values (new.buyer_user_id, 'refund_failed', new.event_id, new.instance_start);
  return null;
end;
$$;

create trigger notify_refund_failed_order
  after update of status on event_orders
  for each row
  when (old.status is distinct from new.status and new.status = 'refund_failed')
  execute function notify_refund_failed_order();

comment on function notify_refund_failed_order() is
  'Tell the buyer their refund was reversed by the bank. Fires only on the '
  'status TRANSITION into refund_failed, so a redelivered webhook (which '
  'CASes against the status it read and therefore updates no row) and a '
  'later touch of the same row both announce nothing. decisions § 825.';

-- ─────────────── 3. the donation arm ───────────────

-- `donations.donor_user_id` is nullable and NULL means a donor who was not
-- signed in — there is no account to put an inbox row on, and this rail cannot
-- reach them at all. That limit is real and is recorded rather than papered
-- over: their only contact point is the email address they gave Stripe, which
-- this database does not hold, so a logged-out donor whose refund fails is an
-- operator's job off the § 789 worklist. Guarding on it here rather than
-- letting the insert fail keeps a NULL from raising 23502 inside the webhook's
-- own UPDATE and rolling the ledger move back with it.
create or replace function notify_refund_failed_donation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.donor_user_id is null then
    return null;
  end if;
  insert into notifications (user_id, kind)
  values (new.donor_user_id, 'refund_failed');
  return null;
end;
$$;

create trigger notify_refund_failed_donation
  after update of status on donations
  for each row
  when (old.status is distinct from new.status and new.status = 'refund_failed')
  execute function notify_refund_failed_donation();

comment on function notify_refund_failed_donation() is
  'Tell the donor their refund was reversed by the bank. Carries no FK: '
  'donations has no client SELECT policy, so the notification IS the donor '
  'surface and both clients send this arm to the inbox. Silent for an '
  'anonymous (donor_user_id null) donation, which this rail cannot reach. '
  'decisions § 825.';
