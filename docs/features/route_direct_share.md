# In-app "Send a route to a follower" — spec (web-first)

**Status: v1 SHIPPED on web (2026-08-25, [decisions §734](../architecture/decisions.md)); v2 (typed attachment) SHIPPED on web (2026-08-28, [decisions §772](../architecture/decisions.md)). The mobile leg is still gated.** **Owner surface:** web (canonical, [decisions §24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)). **Related:** the shipped mobile "Share link" + the link-based send ([decisions §298](../architecture/decisions.md#298-route-sharing-gets-a-mobile-share-link-starting-a-public-route-you-dont-own-is-a-first-class-action-and-both-ride-a-global-start-run-handoff)).

## Why

"Share a route to a follower" is answered **today** by the share link (`/share/route/[id]`, handed to the OS share sheet on mobile / copied on web) — universal, works with anyone, no in-app inbox needed. This doc specs the *additional* in-app targeted path: pick a follower, and the route lands in your conversation with them **without leaving the app**. It's additive polish over the link, not a replacement.

## Build on the existing DM rail — don't invent a new one

A direct-message feature already ships on web: the `direct_messages` table (migration `20261026_001`; `body text` 1–4000 chars, `sender_id` / `recipient_id`) and the `/messages/[[id]]` surface, driven by `sendDm(recipientId, body)` / `fetchDmThread(otherId)` in `core/data.ts`. Route sharing plugs into it.

### v1 — send the share link as a DM (no schema change) — SHIPPED

Built exactly as specced, no migration, no new RLS, no new column — it is a normal DM whose body happens to be a route URL.

1. A **"Send to a follower"** button on `/routes/[id]`, beside Share (`data-testid="route-send-dm-btn"`), gated to `auth.user && (is_public || isOwner)` so a non-owner can never offer a dead link — the same gate mobile's Share-link menu item carries (§298).
2. It opens `SendRouteDialog.svelte`, which calls `sendDm(recipientId, shareLink)` with the public `/share/route/[id]` URL as the body — the *same* string the copy-link share bar shows, built once by `doShare` from `buildRouteShareCanonical`.
3. **Ensure-public first, through the one shared step.** Both affordances call `runShare()`; a `shareIntent` flag records which asked, and a still-private route opens the existing `share-confirm-dialog` before anything is flipped. Cancelling leaves the route private *and* leaves the picker closed.
4. The recipient sees the URL in their thread at `/messages/{sender}` and opens the share page from there.

**The picker is the DM-eligible set, not the follower list.** `social/dm_recipients.ts` (`dmRecipientCandidates` + `filterDmRecipients`, 13 unit tests) merges `fetchFollowers` and `fetchFollowing` into one deduped, name-ordered list tagged `mutual` / `follows_you` / `you_follow`. That union *is* the `direct_messages` INSERT policy's follow condition, which admits an edge in either direction: a followers-only picker would hide people the send would in fact accept, and an open people search would offer sends RLS is going to refuse. The block half of that gate is deliberately not modelled client-side — `user_blocks` is owner-read only, so a client cannot see a block placed *on* it, and rendering a "can't message" marker would leak exactly that. Those sends are refused server-side and surfaced by `sendDm`'s 42501 branch.

**Fail-closed reads and writes.** A failed follower fetch renders an error + Retry, never the empty-picker copy — the two answers are different and only one is actionable. A refused or thrown send renders the reason in the dialog and never the sent confirmation. One send is in flight at a time.

**Abuse posture: the rail's, unchanged.** v1 adds no new insert path, so it inherits the `direct_messages` INSERT policy (no block either way + a follow edge) plus the rail's own send throttle. That throttle arrived after this feature and is exactly the shape the feature declined to build locally: a `before insert` trigger over the existing `check_rate_limit` (migration `20270608_001`, [decisions § 737](../architecture/decisions.md)) debiting 30/minute and 250/hour per sender, so `/messages` and this dialog are covered by one mechanism rather than two. A refused send surfaces through `sendDm`'s shared `rateLimitErrorMessage` branch, beside the 42501 one — localized per reader since [decisions § 744](../architecture/decisions.md).

Web-only. **Not a parity pair** — `dm_recipients.ts` has no Dart twin and is owed none while mobile has no DM surface; see Mobile below.

Pinned by `tests-e2e/routes/send-to-follower.spec.ts` (5 specs: the full send → recipient-opens-it journey across two browser contexts, the one-way-follow candidate, the private-route confirm in both directions, the failed-load retry, the refused send).

### v2 — typed route attachment (renders as a card) — SHIPPED 2026-08-28

Built as the plain FK this section preferred. Migration `20270619_001` adds `direct_messages.route_id uuid references routes(id) on delete set null` with its covering partial index; `ON DELETE SET NULL` because a message is the sender's own correspondence and must outlive the thing it named — a third party tidying up their routes must not delete someone's private conversation.

**The INSERT gate is sender-side.** The existing policy admits the send on the follow graph plus the symmetric block check and says nothing about the route, so an unconstrained column accepts any uuid a client sends. The added clause is `route_id is null or private.is_route_visible_to(route_id, auth.uid())` — the same oracle `route_markers`, `route_conditions` and `route_photos` gate their own INSERTs on. A recipient-side check would accept or refuse the identical insert depending on who it is addressed to (a club route is visible to a club-mate and to nobody else) and raise a 42501 the sender cannot act on; the recipient-side answer is a render that degrades honestly.

**The card resolves through `fetchRouteById`, not through the message row.** `DmRouteAttachment.svelte` reads the route by id and only then hands the points to `TrackPreview` — so the polyline a non-owner recipient sees has already been through `clip_route_for_viewer` server-side. Passing a waypoints array in from anywhere, or reading the bare `routes` table here, would hand over the unclipped line; two guards in `privacy_guards.test.ts` pin it, beside the three that already keep `/routes/[id]`, the routes list and the clubs Routes tab off bare `<TrackPreview>`. The bare SVG is used rather than `RouteTrackPreview`'s static-map path, so a private conversation makes no third-party tile request.

**Four render states, kept apart in `social/dm_attachment.ts` (12 unit tests).** No attachment renders as text exactly as before; a pending resolution renders a skeleton and never an empty card; a resolved route renders the card; and a route the reader may not see renders "this route isn't available to you any more" and **never** falls back to the body — a URL that 404s for that reader is otherwise indistinguishable from a link someone typed. A clip that returned `[]` still renders name and distance and drops only the thumbnail: the route resolving and its polyline resolving are different facts.

**The body still carries the share URL, deliberately.** It is the forwardable artifact the dialog's own copy promises (see Privacy below), and `dm_threads()` returns only `last_body` while the Art 20 export selects `*` — both read the body and neither resolves an attachment. `bodyRestatesAttachment` suppresses it **on screen only**, and only when it is a URL pointing at this route's own share or detail path; a note the sender typed, or a link to another route, renders beside the card.

Pinned by `tests-e2e/messages/dm-route-attachment.spec.ts` (3 specs: the send storing both the typed id and the URL with the recipient seeing the card, a route the recipient cannot see saying so, and a route delete nulling the reference while the message survives) and `direct_message_route_attachment_test.sql` (6 pgtap assertions).

**Not taken, and measured rather than forgotten.** The inbox preview line still shows the URL — `dm_threads()` returns `last_body` and nothing else, so changing it means changing the RPC's return type, and the URL being visible there is consistent with what the send discloses. And the public flip stays on the send path even though a **club** route could now be sent to a club-mate without publishing anything: deciding that needs `is_route_visible_to(route, recipient)` per candidate at picker time, which no client-reachable RPC offers, and a silently unrenderable card is worse for the sender than a route they chose to publish.

## Mobile — still gated, re-verified 2026-08-28

Mirror **after** web ships, per §24 — the DM surface itself isn't on mobile yet, so the mobile leg is gated on a mobile `/messages` twin existing first. Re-checked when v2 landed: **no mobile DM surface exists**. Nothing under `apps/mobile_android/lib/` or `packages/` references `direct_messages`, `sendDm` or `DirectMessage` — the only two filename matches are `ble_treadmill.dart` and `rate_limit_message.dart`, neither a DM surface — and `parity.md`'s "Direct messages (1:1)" row is `✗` on both device columns. `social/dm_attachment.ts` is therefore **not** a parity pair and is owed no Dart twin. So the gate holds and this feature is web-only for now — do **not** build a route-detail send button on mobile ahead of the inbox it would deliver into.

Until then, mobile's "send to a follower" is the shipped **Share link → OS share sheet** (pick the messaging app), which already reaches any follower through WhatsApp / SMS / etc.

## Privacy — a targeted send widens nothing the link share didn't

A route polyline can start at someone's front door, so "who can now see this line" is the load-bearing question, and v1's answer is **exactly the copy-link share's answer, deliberately**:

- **The message carries a link and an id, never a trace.** Neither the body nor `route_id` is a copy of the polyline. What the recipient can see is decided at *read* time by the route's own visibility — `/share/route/[id]` resolves through the `public_routes` view and fetches the track via the `clip_route_for_viewer` SECURITY DEFINER RPC, so a non-owner gets the owner's privacy zones clipped out server-side. The DM is not a second, unclipped copy of anything.
- **A private route cannot be made readable as a side effect of a send.** The single exposure-widening act is the public flip, and the send path reaches it through the *same* `share-confirm-dialog` the copy-link share added in §298's amendment, with the same copy about Explore and about being reversible. Cancel leaves the route private and opens no picker.
- **Only the owner can flip it.** The button is gated to `is_public || isOwner`, and `setRoutePublic` is owner-scoped by RLS regardless — a non-owner can send a link to an already-public route and nothing else.
- **Targeted is not narrower than public, and the copy says so.** The dialog states outright that the recipient gets the public share link, so anyone they forward it to can open it too. Sending to one person is a delivery choice, not an access-control one; pretending otherwise would be the actual privacy failure here. Narrowing that — a per-recipient grant on a route that stays private — is a different feature and would need its own table and RLS, not a DM body.

## Non-goals

- A separate route-shares table or a bespoke notification kind — the DM rail already carries delivery + unread + the inbox.
- Broadcast/"share to all followers" — this is 1:1 targeted send; broadcast is what the public feed / a club post is for.
