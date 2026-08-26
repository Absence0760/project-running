-- Rate-limit the direct_messages rail.
--
-- Until now the rail had no throttle of any kind: the INSERT policy's
-- follow-graph + block gate (20261026_001) was its entire anti-spam
-- story, so anyone already inside a sender's follow graph could be
-- messaged without bound, from /messages or from the route-send
-- affordance (decisions § 734). `check_rate_limit` (20260604_001)
-- backed the route generator and the OSRM proxy but nothing on this
-- path.
--
-- The throttle lives on the TABLE, not on a send affordance. There is
-- exactly one write path into direct_messages — a PostgREST INSERT
-- from the client; no RPC, no Edge Function, no Go worker writes it —
-- so a BEFORE INSERT trigger is the whole rail, and every future
-- affordance inherits it without remembering to. § 734 declined a
-- send-only throttle for that reason and the reason still holds.
--
-- ── Two buckets, because one window cannot do both jobs ───────────
--
-- check_rate_limit is a FIXED-window counter. A single "N per hour"
-- therefore admits all N in one instant at the top of the hour: set N
-- high enough that a real conversation never trips it and a script
-- delivers the whole allowance in two seconds; set N low enough to
-- stop that and a spirited back-and-forth trips it in minutes. A real
-- exchange is bursty, and a limit a normal conversation trips is
-- worse than none.
--
-- So the rate and the volume are bounded separately:
--
--   send_direct_message_burst  30 / 60 s    bounds how FAST messages
--                                           can arrive
--   send_direct_message       250 / 3600 s  bounds how MANY arrive
--
-- 30/min is one message every two seconds sustained for a full
-- minute from a single sender — deliberately above any plausible
-- human rate, because a false positive on a genuine conversation is
-- the failure mode this is sized to avoid. 250/h averages one message
-- every 14 s for an hour, which is heavier than any real two-person
-- thread and sits between the route generator's 60/h and the OSRM
-- proxy's 1200/h. Together they cap a flood at 250 messages spread
-- over at least ~8 minutes instead of 250 in two seconds — enough
-- time for the recipient to block.
--
-- The HOUR bucket is checked first, and the order is load-bearing for
-- one reason: when both windows are exhausted the sender must be told
-- the binding wait. Checking the burst first would answer "try again
-- in 40 seconds" to someone who then has forty minutes to wait.
--
-- The order does NOT affect the counters, and the reason is worth
-- stating because 20260604_001's own header says the opposite about
-- its RPC. check_rate_limit increments before it compares, so a denied
-- call counts — but only when it is called standalone, in its own
-- transaction, the way the Edge Functions call it. Here the call is
-- inside a BEFORE INSERT trigger, so the raise aborts the statement
-- and the increment rolls back with it: measured, a refused send left
-- the burst bucket on 30 rather than 31, and never created the hour
-- bucket's row at all. On this rail the counter therefore counts
-- SUCCESSFUL sends, which is the semantics a cap should have; a
-- flooder cannot be punished into a longer lockout by hammering, and
-- equally cannot be slowed by their own refusals. Bounding the refused
-- attempts themselves is the per-IP WAF's job, not this counter's.
--
-- ── Locking ──────────────────────────────────────────────────────
--
-- CREATE TRIGGER takes SHARE ROW EXCLUSIVE on direct_messages
-- (measured against the local PG 17.6 stack, not assumed). That
-- conflicts with ROW EXCLUSIVE, so concurrent INSERT/UPDATE/DELETE on
-- direct_messages wait; it does NOT conflict with ACCESS SHARE or ROW
-- SHARE, so every reader — the /messages thread list, dm_threads(),
-- the unread badge — proceeds untouched, including while the request
-- is queued. The work is catalogue-only: no row scan, no rewrite, no
-- validation pass, so the hold is O(1) regardless of how many messages
-- the table holds. Acceptable: the blast radius is a sub-millisecond
-- pause on sends, on a table that is not in GUARDED_TABLES and is
-- retention-purged by 20261119_001. CREATE OR REPLACE FUNCTION takes
-- no table lock at all.

create or replace function direct_messages_rate_limit_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform enforce_create_rate_limit('send_direct_message', new.sender_id, 250, 3600);
  perform enforce_create_rate_limit('send_direct_message_burst', new.sender_id, 30, 60);
  return new;
end;
$$;

create trigger direct_messages_enforce_send_rate_limit
  before insert on direct_messages
  for each row
  execute function direct_messages_rate_limit_trigger();
