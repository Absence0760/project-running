-- Pins migration 20270608_001 — the two-bucket send throttle on the
-- `direct_messages` rail.
--
-- Same shape as create_rate_limits_test.sql: the exception format is
-- asserted exactly (`^rate limit exceeded for <bucket>, retry in Ns$`)
-- because that literal is what web `rateLimitErrorMessage()` and its
-- Dart twin parse; a comma-to-colon drift would silently drop every
-- sender back to the raw postgres string. The bucket names are matched
-- individually so the burst window and the hour window cannot be
-- confused for one another.

begin;

select plan(9);

-- ── Fixture ──────────────────────────────────────────────────────
-- A and C both follow B, so both are inside the send gate. D follows B
-- too and is used only for the hour-bucket case.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000dd01', 'authenticated', 'authenticated',
   'dm-rate-a@spam.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000dd02', 'authenticated', 'authenticated',
   'dm-rate-b@spam.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000dd03', 'authenticated', 'authenticated',
   'dm-rate-c@spam.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000dd04', 'authenticated', 'authenticated',
   'dm-rate-d@spam.local', '', now(), now());

select tests.confirm_consent();

insert into user_follows (follower_id, followee_id) values
  ('00000000-0000-0000-0000-00000000dd01', '00000000-0000-0000-0000-00000000dd02'),
  ('00000000-0000-0000-0000-00000000dd03', '00000000-0000-0000-0000-00000000dd02'),
  ('00000000-0000-0000-0000-00000000dd04', '00000000-0000-0000-0000-00000000dd02');

-- D starts with their hour bucket already at the cap, in the window the
-- trigger will compute for `now()`. Seeded here, before the role switch,
-- because rate_limits has RLS enabled with no policies at all.
insert into rate_limits (user_id, bucket, window_start, count) values
  ('00000000-0000-0000-0000-00000000dd04', 'send_direct_message',
   to_timestamp(floor(extract(epoch from now()) / 3600) * 3600), 250);

-- ── The trigger is the whole rail, not one affordance ─────────────
-- There is exactly one write path into direct_messages (a PostgREST
-- INSERT); a BEFORE INSERT FOR EACH ROW trigger therefore covers every
-- entry point, present and future. Pin the catalogue shape so a later
-- migration cannot quietly downgrade it to a statement-level or AFTER
-- trigger, or leave it disabled — either of which reads as present
-- while enforcing nothing.
select is(
  (select tgtype::int::text || ':' || tgenabled::text
     from pg_trigger
    where tgrelid = 'public.direct_messages'::regclass
      and tgname = 'direct_messages_enforce_send_rate_limit'),
  '7:O',
  'the throttle is an enabled BEFORE INSERT FOR EACH ROW trigger on the table itself'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000dd01","role":"authenticated"}';

-- ── A burst a real conversation could produce is admitted ─────────
do $$
declare i int;
begin
  for i in 1..30 loop
    insert into direct_messages (sender_id, recipient_id, body)
      values ('00000000-0000-0000-0000-00000000dd01',
              '00000000-0000-0000-0000-00000000dd02', 'burst ' || i);
  end loop;
end;
$$;

select is(
  (select count(*)::int from direct_messages
    where sender_id = '00000000-0000-0000-0000-00000000dd01'),
  30,
  '30 messages inside the burst window all land'
);

-- ── …and the 31st in the same minute does not ─────────────────────
select throws_matching(
  $$ insert into direct_messages (sender_id, recipient_id, body)
       values ('00000000-0000-0000-0000-00000000dd01',
               '00000000-0000-0000-0000-00000000dd02', 'over the burst') $$,
  '^rate limit exceeded for send_direct_message_burst, retry in [0-9]+s$',
  '31st message in the same minute is refused in the client-parser-compatible format'
);

select is(
  (select count(*)::int from direct_messages
    where sender_id = '00000000-0000-0000-0000-00000000dd01'),
  30,
  'the refused message was not written'
);

-- ── A multi-row INSERT cannot smuggle rows past the cap ───────────
-- FOR EACH ROW fires per row, so a batched insert is not an entry
-- point around the trigger. Asserted separately from the single-row
-- case because a statement-level trigger would pass that one.
select throws_matching(
  $$ insert into direct_messages (sender_id, recipient_id, body)
     select '00000000-0000-0000-0000-00000000dd01',
            '00000000-0000-0000-0000-00000000dd02',
            'batched ' || g
       from generate_series(1, 5) g $$,
  '^rate limit exceeded for send_direct_message_burst, retry in [0-9]+s$',
  'a batched multi-row insert is refused by the same per-row trigger'
);

-- ── The cap is per sender ─────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000dd03","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('00000000-0000-0000-0000-00000000dd03',
            '00000000-0000-0000-0000-00000000dd02', 'unaffected')$$,
  'a second sender is unaffected by the first sender flooding the same recipient'
);

-- ── The hour bucket refuses independently of the burst bucket ─────
-- D has sent nothing this minute, so their burst bucket is empty; only
-- the volume cap can be what refuses them.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000dd04","role":"authenticated"}';
select throws_matching(
  $$ insert into direct_messages (sender_id, recipient_id, body)
       values ('00000000-0000-0000-0000-00000000dd04',
               '00000000-0000-0000-0000-00000000dd02', 'over the hour') $$,
  '^rate limit exceeded for send_direct_message, retry in [0-9]+s$',
  'the hour bucket refuses on its own once the volume cap is spent'
);

-- ── A forged sender is still RLS'd, not rate-limited ──────────────
-- enforce_create_rate_limit deliberately returns without raising when
-- the caller is not the row owner, so the INSERT policy answers with
-- 42501. A P0001 here would tell an attacker to "wait a few minutes"
-- about a row they were never allowed to write.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000dd03","role":"authenticated"}';
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('00000000-0000-0000-0000-00000000dd01',
            '00000000-0000-0000-0000-00000000dd02', 'forged sender')$$,
  '42501',
  null,
  'a forged sender_id is refused by RLS, not misreported as a rate limit'
);

-- ── A refused send does not spend the volume budget ───────────────
-- The trigger call lives inside the aborted statement, so its
-- increment rolls back with it — unlike the standalone RPC path, where
-- a denied call counts. A's hour bucket must therefore read 30, the
-- number of messages that actually landed, not 36.
set local role postgres;
select is(
  (select count from rate_limits
    where user_id = '00000000-0000-0000-0000-00000000dd01'
      and bucket = 'send_direct_message'),
  30,
  'refused attempts roll back their own increment — the cap counts sent messages'
);

select * from finish();
rollback;
