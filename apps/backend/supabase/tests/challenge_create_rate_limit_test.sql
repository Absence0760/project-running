-- Pins migration 20270610_001 — the challenge-create throttle now runs
-- through the shared `enforce_create_rate_limit` helper instead of its own
-- body.
--
-- Same shape as create_rate_limits_test.sql and
-- direct_message_rate_limit_test.sql: the exception format is asserted
-- exactly (`^rate limit exceeded for <bucket>, retry in Ns$`) because that
-- literal is what web `parseRateLimitError()` and its Dart twin match. The
-- pre-20270610_001 body raised the bare string `challenge_create_rate_limited`
-- — same P0001 errcode, no bucket, no retry figure — so the parsers returned
-- null and the only reader of the refusal, web's ChallengeEditor, showed its
-- generic "Couldn't create the challenge." toast.

begin;

select plan(8);

-- ── Fixture ──────────────────────────────────────────────────────
-- CC01 is at the cap. CC02 is also at the cap and is used only for the
-- forged-creator case: with their own bucket spent, a trigger keying on
-- auth.uid() would refuse them before RLS could.  CC03 is clean.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000cc01', 'authenticated', 'authenticated',
   'chal-rate-a@spam.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000cc02', 'authenticated', 'authenticated',
   'chal-rate-b@spam.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000cc03', 'authenticated', 'authenticated',
   'chal-rate-c@spam.local', '', now(), now());

select tests.confirm_consent();

-- One challenge CC01 really does own, planted auth-less so the trigger never
-- sees it. It is the positive control under assertion 5: without a row the
-- read could return, "nothing was written" and "the read is broken" look the
-- same.
insert into challenges (id, creator_id, title, metric, scope, starts_at, ends_at, is_public)
values ('ccccaaaa-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-00000000cc01', 'planted before the cap',
        'distance', 'individual', now(), now() + interval '10 days', true);

-- Seeded here, before the role switch, because rate_limits has RLS enabled
-- with no policies at all.
insert into rate_limits (user_id, bucket, window_start, count) values
  ('00000000-0000-0000-0000-00000000cc01', 'create_challenge',
   to_timestamp(floor(extract(epoch from now()) / 3600) * 3600), 30),
  ('00000000-0000-0000-0000-00000000cc02', 'create_challenge',
   to_timestamp(floor(extract(epoch from now()) / 3600) * 3600), 30);

-- ── 1. the throttle is still the trigger it claims to be ──────────
-- Pin the catalogue shape so a later migration cannot quietly downgrade it
-- to a statement-level or AFTER trigger, or leave it disabled — either of
-- which reads as present while enforcing nothing.
select is(
  (select tgtype::int::text || ':' || tgenabled::text
     from pg_trigger
    where tgrelid = 'public.challenges'::regclass
      and tgname = 'challenges_create_rate_limit'),
  '7:O',
  'the throttle is an enabled BEFORE INSERT FOR EACH ROW trigger on the table itself'
);

set local role authenticated;

-- ── 2. a creator inside the cap is untouched ──────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc03","role":"authenticated"}';
select lives_ok(
  $$insert into challenges (creator_id, title, metric, scope, starts_at, ends_at)
    values ('00000000-0000-0000-0000-00000000cc03', 'under the cap',
            'distance', 'individual', now(), now() + interval '10 days')$$,
  'a creator with an unspent bucket still creates'
);

-- ── 3-4. past the cap, in the shape the client parsers read ───────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc01","role":"authenticated"}';
select throws_matching(
  $$ insert into challenges (creator_id, title, metric, scope, starts_at, ends_at)
       values ('00000000-0000-0000-0000-00000000cc01', 'over the cap',
               'distance', 'individual', now(), now() + interval '10 days') $$,
  '^rate limit exceeded for create_challenge, retry in [0-9]+s$',
  'the 31st create in the window is refused in the client-parser-compatible format'
);

select throws_ok(
  $$ insert into challenges (creator_id, title, metric, scope, starts_at, ends_at)
       values ('00000000-0000-0000-0000-00000000cc01', 'over the cap again',
               'distance', 'individual', now(), now() + interval '10 days') $$,
  'P0001',
  null,
  'the refusal carries the P0001 errcode both parsers gate on before matching'
);

-- ── 5. the refused rows were not written ──────────────────────────
-- Measured against the planted control rather than against zero: CC01 still
-- owns exactly the one challenge they owned before the two refusals.
select is(
  (select count(*)::int from challenges
    where creator_id = '00000000-0000-0000-0000-00000000cc01'),
  1,
  'a refused create leaves the creator''s row count where it was'
);

-- ── 6. a batched insert is not a way around the per-row trigger ───
select throws_matching(
  $$ insert into challenges (creator_id, title, metric, scope, starts_at, ends_at)
     select '00000000-0000-0000-0000-00000000cc01', 'batched ' || g,
            'distance', 'individual', now(), now() + interval '10 days'
       from generate_series(1, 5) g $$,
  '^rate limit exceeded for create_challenge, retry in [0-9]+s$',
  'a batched multi-row insert is refused by the same per-row trigger'
);

-- ── 7. a forged creator is RLS'd, not rate-limited ────────────────
-- enforce_create_rate_limit deliberately returns without raising when the
-- caller is not the row owner, so the INSERT policy answers with 42501. The
-- old body keyed the bucket on auth.uid() instead, so CC02 — whose own
-- bucket is spent — was told to wait a few minutes about a row they were
-- never allowed to write.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc02","role":"authenticated"}';
select throws_ok(
  $$insert into challenges (creator_id, title, metric, scope, starts_at, ends_at)
    values ('00000000-0000-0000-0000-00000000cc01', 'forged creator',
            'distance', 'individual', now(), now() + interval '10 days')$$,
  '42501',
  null,
  'a forged creator_id is refused by RLS, not misreported as a rate limit'
);

-- ── 8. a refused create does not spend the budget ─────────────────
-- The helper call lives inside the aborted statement, so its increment
-- rolls back with it — unlike the standalone RPC path, where a denied call
-- counts. CC01's bucket must still read the 30 it was seeded at.
set local role postgres;
select is(
  (select count from rate_limits
    where user_id = '00000000-0000-0000-0000-00000000cc01'
      and bucket = 'create_challenge'),
  30,
  'refused attempts roll back their own increment — the cap counts challenges created'
);

select * from finish();
rollback;
