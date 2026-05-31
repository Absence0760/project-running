---
description: When a row is public (is_public=true), audit which columns leak alongside it
---

When a `runs` or `routes` row flips to `is_public = true`, the SELECT policy opens *the whole row* by default. Audit whether any column on a public row should stay private even when the row is shared.

## Goal

The leak vectors here are subtle. Some columns are derived from the user's private state (`runs.metadata.raw_strava_payload`, `runs.metadata.fit_file_url`, internal sync timestamps, draft fields). Others are intentionally public (distance, duration, started_at, track_url-on-public-run). The line is fuzzy — and PostgREST's default is "every column visible if any policy passes". A focused, hand-curated list of which columns are public-safe and which aren't lives nowhere today; this command is the audit that builds it.

## What to check

1. **Inventory the columns of every table with an `is_public` SELECT policy.** Tables to start with: `runs`, `routes`, `comments`, `kudos`, `run_photos`, `clubs`, `club_posts`, `events`, `event_rsvps`. Walk migrations to enumerate columns.
2. **For each column, classify:**
   - **Public-safe** — distance, duration, started_at, route name, etc. Intended for sharing.
   - **Owner-only** — internal sync state, raw external API payloads (Strava response blobs in metadata), draft fields, IP addresses, device identifiers.
   - **Derived-private** — looks public but reveals private state (e.g. `runs.metadata.health_connect_record_id` outs which Health Connect record corresponds, leaking the user's import shape).
3. **`runs.metadata` is jsonb** — every key in `docs/backend/metadata.md` plus any registered-but-undocumented key needs the same classification. The whole jsonb travels with the row; you can't gate per-key in a SELECT policy.
4. **Cross-table joins that surface private state.** A public `runs` row with `route_id` exposes the route id. If the corresponding route is private, can a viewer infer ownership / structure from the existence of the link? Same for `runs.club_id`, `runs.user_id` (always exposed but worth checking what `user_profiles` then exposes).
5. **`user_profiles` exposure.** `display_name`, `avatar_url` are public-safe. `email`, `subscription_tier`, `apple_subscription_id`, etc. — verify the row's SELECT policy excludes columns that should stay private (Postgres-native column-level grants or a view that hides them).

## Report

- **High** — a column that reveals private state is reachable via a public row.
- **Medium** — a column whose intent isn't documented; today it's harmless but a future code change could write sensitive data into it.
- **Low** — registered metadata key with no public/private classification.

For each: table.column (or `metadata.<key>`), what private state it reveals, the surface that exposes it (which client code reads it).

## Mitigation patterns

- Use a public view (`public_runs`) with only the safe columns, and grant SELECT on the view rather than the table.
- Use column-level GRANT (`grant select(col1, col2) on table to anon`).
- Move private fields out of the row into a sibling table with owner-only RLS.
- Move private metadata keys out of the jsonb bag into typed columns where they can be column-level-gated.

## Useful starting points

- `apps/backend/supabase/migrations/` — column lists per table
- `docs/backend/metadata.md` — the runs.metadata key registry
- `docs/backend/api_database.md` — documented public-vs-private intent
- `apps/web/src/lib/core/data.ts` — `fetchPublicRun`, `fetchPublicRoute`, `fetchFeed` — what the app actually reads from public rows

## Delegate to

Use the `repo-security-auditor` agent: `"Audit which columns leak alongside is_public=true rows."`

Read-only audit.
