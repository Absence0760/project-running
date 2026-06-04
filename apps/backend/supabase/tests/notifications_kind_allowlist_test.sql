-- Pins the consolidated notifications.kind CHECK from
-- 20261211_001_consolidate_kind_check_constraints.sql (F16).
--
-- The allowlist grew across six migrations; this test makes the full
-- legal set the thing CI enforces, so a future drop-and-recreate that
-- silently shrinks it (re-opening arbitrary kind strings) fails here
-- instead of in production. Each legal kind round-trips; an unknown kind
-- is rejected with 23514 at INSERT and UPDATE.
--
-- Runs as the superuser (postgres) — the notifications INSERT policy is
-- closed to everyone but the SECURITY DEFINER trigger functions, and the
-- assertion under test is the CHECK, not RLS.

begin;

select plan(13);

-- The seed user is the notification recipient; actor is left null
-- (actor_id is nullable / on delete set null).
select lives_ok(
  format(
    $$ insert into notifications (user_id, kind) values (%L, %L) $$,
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890', k
  ),
  format('notifications accepts kind = %L', k)
)
from unnest(array[
  'kudos', 'comment', 'comment_reply', 'follow',
  'event_rsvp', 'event_cancel', 'plan_update', 'message',
  'club_post', 'run_completed', 'event_reminder'
]) as k;

-- An unknown kind is rejected at INSERT, not deferred.
select throws_ok(
  $$ insert into notifications (user_id, kind)
     values ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'like') $$,
  '23514',
  null,
  'notifications rejects unknown kind at INSERT'
);

-- And on UPDATE — a re-classification path can't bypass the constraint.
insert into notifications (id, user_id, kind)
  values ('11111111-1111-1111-1111-111111111111',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'kudos');
select throws_ok(
  $$ update notifications set kind = 'mention'
     where id = '11111111-1111-1111-1111-111111111111' $$,
  '23514',
  null,
  'notifications UPDATE rejects flipping kind to a junk value'
);

select * from finish();
rollback;
