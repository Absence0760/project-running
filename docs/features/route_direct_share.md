# In-app "Send a route to a follower" — spec (web-first)

**Status:** specced, not built. **Owner surface:** web (canonical, [decisions §24](../architecture/decisions.md#24-web-is-the-canonical-feature-surface-mobile-and-watches-are-platform-additive)). **Related:** the shipped mobile "Share link" + the link-based send ([decisions §298](../architecture/decisions.md#298-route-sharing-gets-a-mobile-share-link-starting-a-public-route-you-dont-own-is-a-first-class-action-and-both-ride-a-global-start-run-handoff)).

## Why

"Share a route to a follower" is answered **today** by the share link (`/share/route/[id]`, handed to the OS share sheet on mobile / copied on web) — universal, works with anyone, no in-app inbox needed. This doc specs the *additional* in-app targeted path: pick a follower, and the route lands in your conversation with them **without leaving the app**. It's additive polish over the link, not a replacement.

## Build on the existing DM rail — don't invent a new one

A direct-message feature already ships on web: the `direct_messages` table (migration `20261026_001`; `body text` 1–4000 chars, `sender_id` / `recipient_id`) and the `/messages/[[id]]` surface, driven by `sendDm(recipientId, body)` / `fetchDmThread(otherId)` in `core/data.ts`. Route sharing plugs into it.

### v1 — send the share link as a DM (no schema change)

The cheapest, shippable-now version:

1. A **"Send to a follower"** action on `/routes/[id]` (next to Share): opens a follower picker (reuse the follower list from the profile/People surface), then calls `sendDm(followerId, routeShareUrl(routeId))` — the message body is the public `/share/route/[id]` URL.
2. Ensure-public first, exactly like `handleShare` (a private route's link is dead) — reuse that path so the two share affordances share one "make it reachable" step.
3. The recipient sees the URL in their thread; tapping it opens the share page (or deep-links into the app once universal/app links land).

No migration, no new RLS, no new column — it's a normal DM whose body happens to be a route URL. Gate: both users must be able to DM (existing DM eligibility rules — follower/mutual, whatever `/messages` already enforces).

### v2 — typed route attachment (renders as a card)

Once v1 validates the demand, make the route render as a **card in the thread** instead of a raw URL:

- Add a nullable typed reference to `direct_messages` — either `route_id uuid references routes(id)` or a small `attachment jsonb` (`{kind: 'route', route_id}`) if other entity types (a run, an event) will follow. Prefer the jsonb bag only if ≥2 entity kinds are actually coming; otherwise a plain `route_id` FK is cleaner and RLS-simpler.
- The thread renderer shows a `TrackPreview` + name + distance card for a message carrying a route ref (falling back to the body text for plain messages).
- RLS: a message row is already scoped to its two participants; the *route* it references still resolves through the route's own visibility (public / owner / club), so a card for a route the recipient can't see degrades to "a route" — never leaks the polyline. Reuse `clip_track_for_user` / `clipRouteForViewer` for the preview.

## Mobile

Mirror **after** web ships, per §24 — the DM surface itself isn't on mobile yet, so the mobile leg is gated on a mobile `/messages` twin existing first. Until then, mobile's "send to a follower" is the shipped **Share link → OS share sheet** (pick the messaging app), which already reaches any follower through WhatsApp / SMS / etc.

## Non-goals

- A separate route-shares table or a bespoke notification kind — the DM rail already carries delivery + unread + the inbox.
- Broadcast/"share to all followers" — this is 1:1 targeted send; broadcast is what the public feed / a club post is for.
