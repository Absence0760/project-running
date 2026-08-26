# In-app "Send a route to a follower" — spec (web-first)

**Status: v1 SHIPPED on web (2026-08-25, [decisions §734](../architecture/decisions.md)). v2 (typed attachment) still owed; the mobile leg is still gated.** **Owner surface:** web (canonical, [decisions §24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)). **Related:** the shipped mobile "Share link" + the link-based send ([decisions §298](../architecture/decisions.md#298-route-sharing-gets-a-mobile-share-link-starting-a-public-route-you-dont-own-is-a-first-class-action-and-both-ride-a-global-start-run-handoff)).

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

**Abuse posture: the rail's, unchanged.** v1 adds no new insert path, so it inherits the `direct_messages` INSERT policy (no block either way + a follow edge) plus the rail's own send throttle. That throttle arrived after this feature and is exactly the shape the feature declined to build locally: a `before insert` trigger over the existing `check_rate_limit` (migration `20270608_001`, [decisions § 737](../architecture/decisions.md)) debiting 30/minute and 250/hour per sender, so `/messages` and this dialog are covered by one mechanism rather than two. A refused send surfaces through `sendDm`'s shared `rateLimitErrorMessage` branch, beside the 42501 one.

Web-only. **Not a parity pair** — `dm_recipients.ts` has no Dart twin and is owed none while mobile has no DM surface; see Mobile below.

Pinned by `tests-e2e/routes/send-to-follower.spec.ts` (5 specs: the full send → recipient-opens-it journey across two browser contexts, the one-way-follow candidate, the private-route confirm in both directions, the failed-load retry, the refused send).

### v2 — typed route attachment (renders as a card) — NOT BUILT, still owed

Once v1 validates the demand, make the route render as a **card in the thread** instead of a raw URL. Nothing below shipped; the thread still renders v1's body as plain text:

- Add a nullable typed reference to `direct_messages` — either `route_id uuid references routes(id)` or a small `attachment jsonb` (`{kind: 'route', route_id}`) if other entity types (a run, an event) will follow. Prefer the jsonb bag only if ≥2 entity kinds are actually coming; otherwise a plain `route_id` FK is cleaner and RLS-simpler.
- The thread renderer shows a `TrackPreview` + name + distance card for a message carrying a route ref (falling back to the body text for plain messages).
- RLS: a message row is already scoped to its two participants; the *route* it references still resolves through the route's own visibility (public / owner / club), so a card for a route the recipient can't see degrades to "a route" — never leaks the polyline. Reuse `clip_track_for_user` / `clipRouteForViewer` for the preview.

## Mobile — still gated, verified 2026-08-25

Mirror **after** web ships, per §24 — the DM surface itself isn't on mobile yet, so the mobile leg is gated on a mobile `/messages` twin existing first. Re-checked when v1 landed: **no mobile DM surface exists**. Nothing under `apps/mobile_android/lib/` or `packages/` references `direct_messages` or a `sendDm` equivalent, and `parity.md`'s "Direct messages (1:1)" row is `✗` on both device columns. So the gate holds and this feature is web-only for now — do **not** build a route-detail send button on mobile ahead of the inbox it would deliver into.

Until then, mobile's "send to a follower" is the shipped **Share link → OS share sheet** (pick the messaging app), which already reaches any follower through WhatsApp / SMS / etc.

## Privacy — a targeted send widens nothing the link share didn't

A route polyline can start at someone's front door, so "who can now see this line" is the load-bearing question, and v1's answer is **exactly the copy-link share's answer, deliberately**:

- **The body is a link, not a trace.** The DM carries a URL. What the recipient can see when they follow it is decided at *read* time by the route's own visibility — `/share/route/[id]` resolves through the `public_routes` view and fetches the track via the `clip_route_for_viewer` SECURITY DEFINER RPC, so a non-owner gets the owner's privacy zones clipped out server-side. The DM is not a second, unclipped copy of anything.
- **A private route cannot be made readable as a side effect of a send.** The single exposure-widening act is the public flip, and the send path reaches it through the *same* `share-confirm-dialog` the copy-link share added in §298's amendment, with the same copy about Explore and about being reversible. Cancel leaves the route private and opens no picker.
- **Only the owner can flip it.** The button is gated to `is_public || isOwner`, and `setRoutePublic` is owner-scoped by RLS regardless — a non-owner can send a link to an already-public route and nothing else.
- **Targeted is not narrower than public, and the copy says so.** The dialog states outright that the recipient gets the public share link, so anyone they forward it to can open it too. Sending to one person is a delivery choice, not an access-control one; pretending otherwise would be the actual privacy failure here. Narrowing that — a per-recipient grant on a route that stays private — is a different feature and would need its own table and RLS, not a DM body.

## Non-goals

- A separate route-shares table or a bespoke notification kind — the DM rail already carries delivery + unread + the inbox.
- Broadcast/"share to all followers" — this is 1:1 targeted send; broadcast is what the public feed / a club post is for.
