-- Pins migration 20261222_001 — recompute_event_ranks ranks only
-- finishers, starting at 1, even when a dnf/dns row (which carries a
-- duration_s, 0 for a dns) sits in the same group. Pre-fix the unbounded
-- rank() window let the dns consume rank 1, leaving finishers off by one.

begin;
select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000eea01', 'authenticated', 'authenticated',
   'rk-owner@evt.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000eea02', 'authenticated', 'authenticated',
   'rk-finA@evt.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000eea03', 'authenticated', 'authenticated',
   'rk-finB@evt.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000eea04', 'authenticated', 'authenticated',
   'rk-dns@evt.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('33333333-3333-3333-3333-3333000eea01',
        '00000000-0000-0000-0000-0000000eea01', 'Rank Club', 'rank-evt-c', true);

insert into events (id, club_id, title, starts_at, author_id)
values ('33333333-3333-3333-3333-3333000eea11',
        '33333333-3333-3333-3333-3333000eea01', 'Rank Tuesday',
        '2026-06-02 19:00+00', '00000000-0000-0000-0000-0000000eea01');

-- A dns recorded FIRST with duration 0 (the worst case: it sorts ahead
-- of every finisher). Then two finishers. The rerank trigger fires on
-- each insert.
insert into event_results (event_id, instance_start, user_id, distance_m, duration_s, finisher_status)
values
  ('33333333-3333-3333-3333-3333000eea11', '2026-06-02 19:00+00',
   '00000000-0000-0000-0000-0000000eea04', 5000, 0, 'dns'),
  ('33333333-3333-3333-3333-3333000eea11', '2026-06-02 19:00+00',
   '00000000-0000-0000-0000-0000000eea02', 5000, 1200, 'finished'),
  ('33333333-3333-3333-3333-3333000eea11', '2026-06-02 19:00+00',
   '00000000-0000-0000-0000-0000000eea03', 5000, 1300, 'finished');

select is(
  (select rank from event_results
   where event_id = '33333333-3333-3333-3333-3333000eea11'
     and user_id = '00000000-0000-0000-0000-0000000eea02'),
  1,
  'fastest finisher is rank 1 (not 2, despite the dns sorting ahead at 0s)'
);

select is(
  (select rank from event_results
   where event_id = '33333333-3333-3333-3333-3333000eea11'
     and user_id = '00000000-0000-0000-0000-0000000eea03'),
  2,
  'second finisher is rank 2'
);

select is(
  (select rank from event_results
   where event_id = '33333333-3333-3333-3333-3333000eea11'
     and user_id = '00000000-0000-0000-0000-0000000eea04'),
  null,
  'the dns row carries no rank'
);

select is(
  (select count(*) from event_results
   where event_id = '33333333-3333-3333-3333-3333000eea11' and rank = 1),
  1::bigint,
  'exactly one row holds rank 1'
);

rollback;
