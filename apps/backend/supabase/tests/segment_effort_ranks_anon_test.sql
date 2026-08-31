-- The logged-out half of both rank RPCs (migration 20270609_001, decisions
-- § 746).
--
-- `segment_effort_ranks` / `global_segment_effort_ranks` are SECURITY INVOKER,
-- so every function their bodies NAME is ACL-checked against the calling role.
-- 20270523_001 added `not is_blocked_either_way(auth.uid(), rival.user_id)` to
-- both while 20261108_001 had already revoked anon's EXECUTE on that function,
-- so an anonymous caller was admitted by the RPC's own grant and denied inside
-- its body — and only sometimes, because the predicate is evaluated once the
-- rival subquery yields a row. An effort with no strictly-faster rival
-- answered cleanly; an effort with one raised 42501, which both clients then
-- spent as `rank ?? 1`. The RPC therefore succeeded exactly when the crown was
-- real and failed exactly when it was not.
--
-- `global_segment_grants_test` pins the privileges and asserts that neither
-- body names `is_blocked_either_way`. That is the shape of the fix; this is
-- the behaviour, and it is what a differently-spelled re-inline or a second
-- anon-unexecutable callee would break while the catalogue guard stayed
-- green. Both branches of the data-dependent failure are exercised, so a pass
-- cannot come from a fixture in which nobody has a rival.

begin;
select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('4a0c0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'anonrank-owner@seg.local', '', now(), now()),
  ('4a0c0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'anonrank-rival@seg.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('4a0c0000-0000-0000-0000-000000000001', 'Anonrank Owner'),
       ('4a0c0000-0000-0000-0000-000000000002', 'Anonrank Rival');

select tests.confirm_consent();

-- The catalogue segment is curator data, planted before the role switch.
insert into global_segments (id, name, waypoints, distance_m, is_active)
values ('4a0c0000-0000-0000-0000-0000000000a1', 'Anonrank Hill',
        '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"4a0c0000-0000-0000-0000-000000000001"}';

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('4a0c0000-0000-0000-0000-0000000000b1', '4a0c0000-0000-0000-0000-000000000001',
        'Anonrank Loop', '[{"lat":40.0,"lng":-73.0},{"lat":40.01,"lng":-73.0}]', 10000, true);

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values ('4a0c0000-0000-0000-0000-0000000000c1', '4a0c0000-0000-0000-0000-0000000000b1',
        'Anonrank Segment', 500, 1500, '4a0c0000-0000-0000-0000-000000000001');

-- The owner is SLOWER, so their effort has a strictly-faster rival: the
-- branch that used to 42501. The rival's own effort has none: the branch that
-- always answered.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('4a0c0000-0000-0000-0000-0000000000d1', '4a0c0000-0000-0000-0000-000000000001',
        now(), 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values ('4a0c0000-0000-0000-0000-0000000000e1', '4a0c0000-0000-0000-0000-0000000000c1',
        '4a0c0000-0000-0000-0000-0000000000d1', '4a0c0000-0000-0000-0000-000000000001',
        250, now());
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values ('4a0c0000-0000-0000-0000-0000000000f1', '4a0c0000-0000-0000-0000-0000000000a1',
        '4a0c0000-0000-0000-0000-0000000000d1', '4a0c0000-0000-0000-0000-000000000001',
        250, now());

set local "request.jwt.claims" = '{"sub":"4a0c0000-0000-0000-0000-000000000002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('4a0c0000-0000-0000-0000-0000000000d2', '4a0c0000-0000-0000-0000-000000000002',
        now(), 10000, 1700, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (id, segment_id, run_id, user_id, time_seconds, started_at)
values ('4a0c0000-0000-0000-0000-0000000000e2', '4a0c0000-0000-0000-0000-0000000000c1',
        '4a0c0000-0000-0000-0000-0000000000d2', '4a0c0000-0000-0000-0000-000000000002',
        200, now());
insert into global_segment_efforts (id, global_segment_id, run_id, user_id, time_seconds, started_at)
values ('4a0c0000-0000-0000-0000-0000000000f2', '4a0c0000-0000-0000-0000-0000000000a1',
        '4a0c0000-0000-0000-0000-0000000000d2', '4a0c0000-0000-0000-0000-000000000002',
        200, now());

-- ── as a logged-out reader of the two public runs ───────────────────────────
set local role anon;
set local "request.jwt.claims" = '';

select lives_ok(
  $$ select * from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid) $$,
  'anon can call segment_effort_ranks for an effort that HAS a faster rival'
);

select lives_ok(
  $$ select * from global_segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid) $$,
  'anon can call global_segment_effort_ranks for an effort that HAS a faster rival'
);

select is(
  (select rank from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  2,
  'and gets the real standing back, not a refusal the client spends as a crown'
);

select is(
  (select rank from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d2'::uuid)),
  1,
  'the no-rival branch that always answered still answers 1'
);

select is(
  (select rank from global_segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  2,
  'the catalogue twin returns the real standing to a logged-out reader too'
);

select is(
  (select rank from global_segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d2'::uuid)),
  1,
  'the catalogue twin''s no-rival branch answers 1'
);

-- An anonymous caller holds no blocks, so `private.viewer_blocks` is false for
-- every rival and the comparison set is the whole segment. The count is what
-- says so: a body that silently dropped rivals would still return SOME rank.
select is(
  (select count(*)::int from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  1,
  'one row per effort on the run, ranked'
);

-- ── the same question, authenticated, must agree ────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"4a0c0000-0000-0000-0000-000000000001"}';

select is(
  (select rank from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  2,
  'the owner sees the same standing anon does while nobody blocks anybody'
);

select is(
  (select rank from global_segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  2,
  'the catalogue twin agrees for the owner too'
);

-- ── the block filter still filters, and only for the blocker ────────────────
insert into user_blocks (blocker_id, blocked_id)
values ('4a0c0000-0000-0000-0000-000000000001', '4a0c0000-0000-0000-0000-000000000002');

select is(
  (select rank from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  1,
  'the blocked rival leaves the blocker''s comparison set'
);

select is(
  (select rank from global_segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  1,
  'the catalogue twin applies the same block filter'
);

set local role anon;
set local "request.jwt.claims" = '';

select is(
  (select rank from segment_effort_ranks('4a0c0000-0000-0000-0000-0000000000d1'::uuid)),
  2,
  'somebody else''s block does not move the standing a logged-out reader sees'
);

select * from finish();
rollback;
