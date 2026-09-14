-- Put the money model where a schema-reader is standing.
--
-- § 1549 corrected `20261229_001`'s header in place, which repaired the FILE.
-- It did not repair the DATABASE: `\d+ event_orders` prints the table's own
-- comment, and `20261229_001` never wrote one for `event_orders` at all --
-- only for `host_can_take_payment`. So a DBA reading the live schema to
-- understand the marketplace ledger got no statement of who the merchant of
-- record is, and the one they would find by opening the migration is correct
-- only because someone edited it after the fact.
--
-- What the comments assert is measured from the code that CREATES the charge,
-- not from prose:
--
--   * `buildCheckoutSessionParams` (events-checkout/lib.ts) and
--     `buildDonationSessionParams` (donations-checkout/lib.ts) each set
--     `payment_intent_data.transfer_data.destination` plus
--     `application_fee_amount` -- a destination charge. The buyer's card is
--     charged on the PLATFORM account and the remainder is transferred on.
--   * Neither sends `on_behalf_of`, in either file, at either call site.
--     Stripe: "If `on_behalf_of` is omitted, the platform is the business of
--     record for the payment." That absence is what makes the platform, not
--     the host, the merchant of record (decisions § 769).
--   * Stripe debits dispute amounts and fees from the platform account for a
--     destination charge WITH OR WITHOUT `on_behalf_of`, so the chargeback
--     sentence holds whichever way the open `on_behalf_of` sign-off lands
--     (club_events.md § Refunds).
--
-- `donations` is commented alongside `event_orders` although the followup
-- named only the ledger: the donation session is the same destination-charge
-- shape from the same platform account with the same parameter absent, and a
-- schema-reader who gets the answer on one money table and silence on the
-- other has been told the claim is table-specific when it is not.
--
-- ── Lock impact (migration_locks.md) ────────────────────────────────────────
-- `COMMENT ON TABLE` writes one `pg_description` row and takes SHARE UPDATE
-- EXCLUSIVE on the table. It scans nothing, rewrites nothing, and does not
-- block readers or writers. No DDL here changes a column, a constraint or an
-- index, so nothing needs the `NOT VALID` + `VALIDATE` split.

comment on table public.event_orders is
  'Marketplace ledger for paid club-event registrations (20261229_001). One '
  'row per Checkout Session; the stripe-events webhook is the sole, '
  'idempotent, service-role writer of `status`. MERCHANT OF RECORD: the '
  'PLATFORM, not the host and not the club. The charge is a Stripe Connect '
  'destination charge -- the buyer''s card is charged on the platform account, '
  '`platform_fee_cents` is the application fee, and the remainder is '
  'transferred to the host''s connected account (`host_user_id`) -- and '
  '`on_behalf_of` is not sent by any call site, so the platform is the '
  'business of record, carries its own statement descriptor, issues the refund '
  'under the `event_pricing.refund_policy` the host set, and is debited for '
  'disputes. The HOST provides the event and owns its delivery and its own tax '
  'obligations; that is a different claim from being the settlement merchant. '
  'decisions § 769, § 1506, § 1549.';

comment on table public.donations is
  'Fundraiser donation ledger (20270213_001), the second Stripe Connect '
  'destination-charge rail beside event_orders. MERCHANT OF RECORD: the '
  'PLATFORM. `buildDonationSessionParams` sets transfer_data.destination to '
  'the fundraiser owner''s connected account and omits `on_behalf_of` exactly '
  'as the event rail does, so the donor is charged on the platform account and '
  'the platform is the business of record. The platform does NOT verify '
  'charitable status, is not a party to any commitment the owner makes to pass '
  'funds on, and issues no tax receipt -- `/terms` §6 states that to the donor. '
  'decisions § 769, § 1506.';
