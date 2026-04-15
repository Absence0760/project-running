# Clubs and events

The social layer. A club is a group with an owner, members, events, and a feed of admin updates. Phase 1 (shipped) is web-only with one-off events. Full phasing in `roadmap.md § Clubs and events`.

## Surfaces (Phase 1, web)

| Route | Purpose |
|---|---|
| `/clubs` | Two tabs: **Browse** (public clubs, searchable by name/location) and **My clubs**. |
| `/clubs/new` | Create a club (name, optional description + location, public/private). |
| `/clubs/[slug]` | Club home. Three tabs: **Feed** (admin posts + "next event" card), **Events** (upcoming + past), **Members**. Join/Leave button in the hero. Admins see "New event" and a post composer. |
| `/clubs/[slug]/events/new` | Admin-only. Title, date/time, duration, meeting point, optional attached route, distance, target pace, capacity. |
| `/clubs/[slug]/events/[id]` | Event detail. RSVP buttons (Going / Maybe / Can't make it), attendee list, admin-only per-event updates, linked route chip. |

Admin = the club owner or a member with `role = 'admin'`. The owner is auto-enrolled as an `'owner'`-role member at club creation (trigger `enroll_club_owner`), so `is_club_admin()` works uniformly for them too.

## Data model

Tables: `clubs`, `club_members`, `events`, `event_attendees`, `club_posts`. Full definitions + RLS in `api_database.md § clubs / club_members / events / event_attendees / club_posts`. Migration: `apps/backend/supabase/migrations/20260416_001_clubs_and_events.sql`.

Narrow client-side unions in `apps/web/src/lib/types.ts`:

- `ClubRole = 'owner' | 'admin' | 'member'`
- `RsvpStatus = 'going' | 'maybe' | 'declined'`
- `ClubWithMeta = Club & { member_count, viewer_role }` — returned by `browseClubs`, `fetchMyClubs`, `fetchClubBySlug`
- `EventWithMeta = Event & { attendee_count, viewer_rsvp }` — returned by the event fetchers
- `ClubPostWithAuthor = ClubPost & { author_display_name, author_avatar_url }` — returned by `fetchClubPosts`

The enrichment fields are joined client-side in `data.ts` rather than through a Postgres view — small fan-out, fewer moving parts, and it means RLS governs everything.

## Deferred (Phase 2+)

- **Recurrence** — events are one-off in v1. Phase 2 adds an enum (`weekly` / `biweekly` / `monthly`) + `byday[]` + `until_date` rather than full RFC 5545 RRULEs. See `decisions.md`.
- **Invite-only clubs** — `is_public = false` is respected by RLS, but there's no invite link or request/approval flow yet. Private clubs in v1 are only reachable if you already know the slug and are a member.
- **Threaded replies** on posts — v1 is broadcast only.
- **Notifications / realtime** — feed refreshes on page load; no push, no websocket subscriptions.
- **Android mirror** — web-first. Phase 3 of the social rollout.
