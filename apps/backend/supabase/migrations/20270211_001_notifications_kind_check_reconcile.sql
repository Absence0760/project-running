-- Reconcile notifications_kind_check after two features landed the same week.
-- 20270208_001_achievements added 'achievement' and 20270210_001_challenge_progress_rpc
-- added 'challenge_complete', but each was authored against the pre-other snapshot
-- and rebuilt the whole CHECK from its own list — so whichever migration ran last
-- silently dropped the other's kind. This redefines the constraint to the full
-- union so both kinds are valid. Forward-only; safe on a fresh DB and one already
-- carrying either partial list.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete'
    )
  );
