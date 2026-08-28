-- Typed route attachment on the direct_messages rail (route_direct_share.md v2).
--
-- v1 (§ 734) shipped the send by putting the public `/share/route/[id]` URL in
-- the message `body`. The thread renders `{m.body}` as escaped text with no
-- linkification at all, so what the recipient actually receives is an
-- unclickable string they have to select and copy by hand. A URL in a text
-- column is an untyped attachment: nothing downstream can tell a shared route
-- from a runner who typed a link, and nothing can resolve the route it names.
--
-- The typed reference is a plain nullable FK, which is what the spec's own v2
-- section prefers over an `attachment jsonb` bag while exactly one entity kind
-- is in play — one kind, one column, and the RLS gate below is a predicate
-- rather than a jsonb walk.
--
-- ON DELETE SET NULL, deliberately: a message is the sender's own
-- correspondence and outlives the thing it pointed at. Cascading would delete a
-- private message because a third party tidied up their routes; nulling leaves
-- the message intact (its body still carries the share URL v1 sent) and the
-- card degrades to the plain body.
--
-- ── The INSERT gate ──────────────────────────────────────────────────────
--
-- The existing policy admits the send on the follow graph and the block check.
-- Neither says anything about the route, so without the added clause a sender
-- could attach ANY uuid — a route they cannot see, or one that is not a route
-- at all beyond the FK. That leaks nothing on the read side (the recipient
-- resolves the card through `clip_route_for_viewer`, which gates on the
-- RECIPIENT's own visibility and clips the owner's privacy zones), but "you may
-- only attach a route you can see" is the invariant the surface is built on and
-- it belongs on the rail, not in the dialog that happens to be the only sender
-- today. `private.is_route_visible_to` is the same owner / public-and-not-
-- shadow-hidden / active-club-member oracle route_markers, route_conditions and
-- route_photos gate their own INSERTs on.
--
-- The gate is SENDER-side only. A recipient-side check is not possible here and
-- would be wrong if it were: a club route is visible to a club-mate and not to
-- anyone else, so the same insert would be accepted or refused depending on who
-- it is addressed to, with a 42501 the sender cannot act on. The recipient-side
-- answer is a render that degrades honestly, which is where it lives.
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- `direct_messages` is not in check_migration_online_safety.mjs's
-- GUARDED_TABLES, so the two-step is not demanded here; it is taken anyway
-- because it is the house pattern and costs nothing. The ADD COLUMN is nullable
-- with no default (metadata-only). The FK goes on NOT VALID (instant, brief
-- ACCESS EXCLUSIVE) and the VALIDATE runs in this same migration rather than a
-- later one: the column was created by the statement above it, so every row is
-- NULL and the scan has nothing to reject, and VALIDATE takes SHARE UPDATE
-- EXCLUSIVE, which lets both readers and writers through.

alter table direct_messages
  add column route_id uuid;

alter table direct_messages
  add constraint direct_messages_route_id_fkey
    foreign key (route_id) references routes (id) on delete set null
    not valid;

alter table direct_messages
  validate constraint direct_messages_route_id_fkey;

-- Covering index for the FK: without it every `delete from routes` seq-scans
-- direct_messages to apply the SET NULL. Partial, matching runs_route_id_idx —
-- the overwhelming majority of messages carry no attachment.
create index direct_messages_route_id
  on direct_messages (route_id) where route_id is not null;

-- Re-emitted whole (bare-body rule): the live expression is 20261026_001's,
-- initplan-wrapped by 20270416_001, plus the attachment clause.
alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    sender_id = (select auth.uid())
    and not is_blocked_either_way(sender_id, recipient_id)
    and exists (
      select 1
      from user_follows f
      where (f.follower_id = direct_messages.sender_id and f.followee_id = direct_messages.recipient_id)
         or (f.follower_id = direct_messages.recipient_id and f.followee_id = direct_messages.sender_id)
    )
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
  );

comment on column direct_messages.route_id is
  'Optional typed route attachment (route_direct_share.md v2). The INSERT '
  'policy admits it only when the SENDER can see the route; what the RECIPIENT '
  'sees is decided at read time by clip_route_for_viewer, which applies the '
  'owner''s privacy zones. ON DELETE SET NULL so a deleted route does not '
  'delete the message that mentioned it.';
