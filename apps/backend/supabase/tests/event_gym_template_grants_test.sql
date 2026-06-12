-- Pins migration 20261230_001 — the class -> gym seam SELECT grant.
--
-- `events` is under a column-level SELECT lockdown (20260818_001), so each
-- column added afterwards is deny-by-default for anon + authenticated. The
-- attendee read path for the seam needs `gym_template`; 20261230_001 grants it.
-- `host_user_id` (payout recipient) STAYS revoked — it has no client read site.
-- A future column-lockdown migration that silently re-revoked gym_template
-- would fail this test, not silently kill the seam.

begin;
select plan(3);

select ok(
  has_column_privilege('authenticated', 'events', 'gym_template', 'SELECT'),
  'authenticated can SELECT events.gym_template under the column-grant lockdown');

select ok(
  has_column_privilege('anon', 'events', 'gym_template', 'SELECT'),
  'anon can SELECT events.gym_template under the column-grant lockdown');

select ok(
  not has_column_privilege('authenticated', 'events', 'host_user_id', 'SELECT'),
  'host_user_id stays revoked from authenticated (no client read site)');

select * from finish();
rollback;
