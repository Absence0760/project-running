-- Per-provider webhook-event dedupe table. Used to reject replays of
-- previously-seen webhook deliveries.
--
-- audit/edge-functions Medium. revenuecat-webhook verifies HMAC over
-- the raw body, which authenticates the *content* but does nothing
-- against a captured request being POSTed again. Each replay re-runs
-- the tier-mapping logic — currently idempotent for the active state
-- (RENEWAL → 'pro' overwrites 'pro' with 'pro') but a stale
-- deactivating event (EXPIRATION) replayed after a re-subscribe
-- would silently downgrade a paying user to 'free'. The same shape
-- applies to any future provider that signs but doesn't sequence.
--
-- Table is provider-keyed so future webhooks (Stripe, Strava, etc.)
-- share the dedupe store without colliding on event-id namespaces.
-- (provider, event_id) is the primary key — first writer wins, every
-- subsequent insert raises 23505 unique_violation which the EF maps
-- to a 200 ok-skipped (the third-party retries on non-200, and we've
-- already processed the event).
--
-- received_at is for the cleanup cron only; rows older than 30 days
-- are pruned. RevenueCat retries for ~3 days, Strava for hours, so
-- 30 days is a comfortable margin even if the runner runs late.

create table webhook_events (
  provider text not null,
  event_id text not null,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);

create index webhook_events_received_at_idx
  on webhook_events (received_at);

-- RLS off — only Edge Functions running with the service role write
-- here. No user-facing reads or writes; no policies needed. Without
-- enable_row_level_security the table is service-role-only by
-- default (anon and authenticated roles have no grants on it).
alter table webhook_events enable row level security;

-- Cleanup cron. Keeps the table bounded.
select cron.schedule(
  'cleanup-stale-webhook-events',
  '17 4 * * *',
  $$ delete from webhook_events where received_at < now() - interval '30 days' $$
);
