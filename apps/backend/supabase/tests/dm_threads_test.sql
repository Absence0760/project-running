-- Pins migration 20270117_001 -- dm_threads() conversation-list RPC.
--
-- Replaces a client-side fold over the newest-500 messages (which over-fetched
-- bodies AND silently dropped older partners past the window). Assert the
-- server-side aggregation: latest message per partner, last_from_me, the
-- per-partner unread count, and newest-conversation-first ordering — all under
-- the caller's RLS (a participant sees only their own threads).
begin;
select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('da000000-0000-0000-0000-00000000a001', 'authenticated', 'authenticated', 'me@dm.local', '', now(), now()),
  ('da000000-0000-0000-0000-00000000b001', 'authenticated', 'authenticated', 'p1@dm.local', '', now(), now()),
  ('da000000-0000-0000-0000-00000000b002', 'authenticated', 'authenticated', 'p2@dm.local', '', now(), now()),
  ('da000000-0000-0000-0000-00000000c009', 'authenticated', 'authenticated', 'stranger@dm.local', '', now(), now());

-- Seed as superuser (bypasses the insert follow-graph gate). Partner p1: I sent
-- one, they sent two (both unread) — latest is theirs, unread = 2. Partner p2:
-- I sent the only/latest message — from me, unread = 0. Plus a conversation
-- between two strangers that must NOT appear for me.
insert into direct_messages (sender_id, recipient_id, body, created_at, read_at) values
  ('da000000-0000-0000-0000-00000000a001', 'da000000-0000-0000-0000-00000000b001', 'hi p1',   '2026-06-01T10:00:00Z', now()),
  ('da000000-0000-0000-0000-00000000b001', 'da000000-0000-0000-0000-00000000a001', 'yo',      '2026-06-01T10:05:00Z', null),
  ('da000000-0000-0000-0000-00000000b001', 'da000000-0000-0000-0000-00000000a001', 'later',   '2026-06-01T10:10:00Z', null),
  ('da000000-0000-0000-0000-00000000a001', 'da000000-0000-0000-0000-00000000b002', 'sup p2',  '2026-06-02T09:00:00Z', null),
  ('da000000-0000-0000-0000-00000000c009', 'da000000-0000-0000-0000-00000000b001', 'private', '2026-06-03T09:00:00Z', null);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"da000000-0000-0000-0000-00000000a001","role":"authenticated"}';

select is((select count(*) from dm_threads()), 2::bigint,
  'two partners for me (the stranger-to-p1 thread is not mine)');

select is(
  (select last_body from dm_threads() where partner_id = 'da000000-0000-0000-0000-00000000b001'),
  'later', 'p1 latest body is the most recent message');
select is(
  (select last_from_me from dm_threads() where partner_id = 'da000000-0000-0000-0000-00000000b001'),
  false, 'p1 latest was from the partner, not me');
select is(
  (select unread from dm_threads() where partner_id = 'da000000-0000-0000-0000-00000000b001'),
  2::bigint, 'p1 unread = 2 (both inbound, unread)');

select is(
  (select last_from_me from dm_threads() where partner_id = 'da000000-0000-0000-0000-00000000b002'),
  true, 'p2 latest was from me');
select is(
  (select unread from dm_threads() where partner_id = 'da000000-0000-0000-0000-00000000b002'),
  0::bigint, 'p2 unread = 0 (only my outbound)');

-- Newest conversation first: p2's 2026-06-02 message outranks p1's 2026-06-01.
select is(
  (select partner_id from dm_threads() limit 1),
  'da000000-0000-0000-0000-00000000b002'::uuid,
  'threads ordered newest-conversation-first');

select * from finish();
rollback;
