# Clubs and events

The social layer. A club is a group with an owner, members, events, and a feed of admin updates. Phase 1 (shipped) is web-only with one-off events. Full phasing in `roadmap.md § Clubs and events`.

## Surfaces (web)

| Route | Purpose |
|---|---|
| `/clubs` | Two tabs: **Browse** (public clubs, searchable by name/location) and **My clubs**. |
| `/clubs/new` | Create a club (name, optional description + location, visibility: public/private, join policy: anyone / approval required / invite-only). |
| `/clubs/[slug]` | Club home. Three tabs: **Feed** (admin posts + "next event" card, with threaded replies), **Events** (upcoming + past), **Members**. Join/Leave button in the hero. Admins see "New event", a post composer, a pending-requests panel, and the invite-link panel. |
| `/clubs/[slug]/events/new` | Admin-only. Title, date/time, duration, meeting point, optional attached route, distance, target pace, capacity, recurrence (`none` / `weekly` / `biweekly` / `monthly` + weekday picker + until date). |
| `/clubs/[slug]/events/[id]` | Event detail. RSVP buttons (Going / Maybe / Can't make it), attendee list, admin-only per-event updates, linked route chip. For recurring events, an instance picker above the RSVP row lets the user pick which occurrence they're RSVPing to. |
| `/clubs/join/[token]` | Public invite-link landing page. Redeems the token via the `join_club_by_token` RPC and redirects to the club page. |

Admin = the club owner or a member with `role = 'admin'` whose `status = 'active'`. The owner is auto-enrolled as an `'owner'`-role member at club creation (trigger `enroll_club_owner`), so `is_club_admin()` works uniformly for them too.

## Data model

Tables: `clubs`, `club_members`, `events`, `event_attendees`, `club_posts`. Full definitions + RLS in `api_database.md § clubs / club_members / events / event_attendees / club_posts`. Phase 1 migration: `apps/backend/supabase/migrations/20260416_001_clubs_and_events.sql`. Phase 2 migration: `20260417_001_phase2_social.sql` — adds recurrence columns on `events`, `instance_start` + composite pkey on `event_attendees`, `join_policy` + `invite_token` on `clubs`, `status` on `club_members`, `parent_post_id` + `event_instance_start` on `club_posts`, and the `join_club_by_token` RPC.

Narrow client-side unions in `apps/web/src/lib/types.ts`:

- `ClubRole = 'owner' | 'admin' | 'member'`
- `RsvpStatus = 'going' | 'maybe' | 'declined'`
- `MembershipStatus = 'active' | 'pending'`
- `JoinPolicy = 'open' | 'request' | 'invite'`
- `RecurrenceFreq = 'weekly' | 'biweekly' | 'monthly'`
- `Weekday = 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA' | 'SU'`
- `ClubWithMeta = Club & { member_count, viewer_role, viewer_status }` — returned by `browseClubs`, `fetchMyClubs`, `fetchClubBySlug`
- `EventWithMeta = Event & { attendee_count, viewer_rsvp, next_instance_start }` — returned by the event fetchers. `viewer_rsvp` is always scoped to `next_instance_start`; per-instance RSVPs use `fetchEventAttendees(eventId, instanceStart)`.
- `ClubPostWithAuthor = ClubPost & { author_display_name, author_avatar_url, reply_count }` — returned by `fetchClubPosts`. Reply bodies come from `fetchPostReplies(parentId)`.

The enrichment fields are joined client-side in `data.ts` rather than through a Postgres view — small fan-out, fewer moving parts, and it means RLS governs everything.

### Recurrence expansion

Recurring events are stored as a single row (`recurrence_freq`, `recurrence_byday[]`, `recurrence_until`, `recurrence_count`). `apps/web/src/lib/recurrence.ts#expandInstances` walks the pattern client-side and returns the next N instance datetimes within a window. Per-instance attendee counts and RSVPs are queried by `instance_start` (which is ISO — the same value `expandInstances` returns). Monthly recurrence uses the day-of-month of `starts_at` and ignores `byday`.

## Surfaces (Android)

| Screen | Purpose |
|---|---|
| `clubs_screen.dart` | 6th bottom-nav tab. Segmented **Browse** / **My clubs**, search input, tappable club cards. |
| `club_detail_screen.dart` | Club home with tabs: **Feed** (next-event card, threaded post replies, admin composer), **Events** (upcoming list), **Members** (placeholder count — full roster is a later polish). Join/Leave CTA in the hero. |
| `event_detail_screen.dart` | Per-instance RSVP buttons (`I'm in` / `Maybe` / `Can't make it`), recurrence chips for picking an occurrence, attendee pills, admin-only update composer that tags the post to the active instance. |
| `widgets/upcoming_event_card.dart` | Displayed on the Run tab idle state when `SocialService.fetchNextRsvpedEvent` returns a `going` RSVP within 48h. Replaces the Last-Run card in that window — imminent commitment beats recent history. |

The app deliberately **does not** support creating clubs or events on Android. Admins use the web app for setup; Android focuses on the member and admin-update flows that make sense on the go.

## Deferred (Phase 4+)

- **Notifications / realtime** — feed refreshes on page load; no push, no websocket subscriptions. Phase 4.
- **Member roster on Android** — shows count only in Phase 3. Full list with avatars is a polish task.
- **Deeper thread nesting** — replies are one level deep in v2. `parent_post_id` doesn't block deeper threads at the schema level, but the UI and fetchers don't surface them. Easy to grow later.
- **Per-instance edits / cancellations** — Phase 2 recurrence is pattern-only. A cancelled single occurrence or a per-instance time override would need an `event_exceptions` table.
- **Android create flows** — club / event creation lives on web only. If a meaningful share of admins turn out to manage from mobile, add mirrored `clubs/new` and `events/new` screens.
