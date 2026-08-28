-- Let a retried donation checkout resolve to the donation it already opened.
--
-- decisions § 769 filed that `donations-checkout`'s Stripe idempotency key is
-- derived from a donation id minted by `crypto.randomUUID()` INSIDE the
-- request, so no later invocation can resolve to the same key. It covers the
-- SDK's retry of one HTTP request and nothing else; a genuine client retry
-- opens a second Checkout Session against a second pending row, and a donor who
-- completes both is charged twice.
--
-- The key has to be derived from something that survives the retry, and the
-- server has nothing that does. `events-checkout` resolves its key from a
-- persisted pending order found by (buyer, event, instance) — a natural key it
-- can reconstruct because the buyer is authenticated. **A donor may be
-- anonymous** (fundraising.md: "a logged-out stranger donates fine"), so there
-- is no identity to key on, and repeat giving is legitimate so the amount is
-- not one either. The only thing that survives is a value the CLIENT mints once
-- per donation attempt and re-sends, which is exactly what Stripe's own
-- `Idempotency-Key` header is; this column persists it so the second call finds
-- the first call's row.
--
-- Unique so two concurrent attempts cannot both open a donation. Partial, so
-- every row written before this migration (null) stays legal.
--
-- Online-safety: a nullable ADD COLUMN with no default is a metadata-only flip,
-- and there is no constraint to validate and no backfill.

alter table donations add column client_request_id uuid;

comment on column donations.client_request_id is
  'The donor client''s per-attempt idempotency key, echoed back by a retry so '
  'donations-checkout can resolve it to the pending donation it already '
  'opened rather than opening a second one. Null on rows written before '
  '20270620000002.';

create unique index donations_client_request_idx
  on donations (client_request_id)
  where client_request_id is not null;
