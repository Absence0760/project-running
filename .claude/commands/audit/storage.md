---
description: Audit Supabase Storage bucket policies + path guessability + signed-URL hygiene
---

Audit the Supabase Storage layer for bucket policies that don't match table-level RLS, plus path patterns that make object URLs guessable.

## Goal

If `runs.is_public = false` but the underlying gzipped track in the `runs` bucket is readable by anyone with the URL, the table-level guarantee is moot. Verify every bucket's read/write policies match the row-level intent of the table it backs.

## What to check

1. **Bucket inventory.** Enumerate every bucket: `runs` (gzipped track JSON), `run-photos`, `avatars`, plus any I'm missing. Source: `apps/backend/supabase/migrations/` (CREATE BUCKET / `storage.create_bucket`) and `apps/backend/supabase/config.toml`.
2. **Per-bucket policies.** For each bucket, list the `storage.objects` policies that mention it. Classify each as:
   - **Public read** (anyone with URL can GET) — only acceptable for content the app already treats as public.
   - **Owner read+write** (`auth.uid()::text = (storage.foldername(name))[1]`) — the canonical pattern.
   - **Authenticated read** (any signed-in user) — flag and verify it's deliberate.
3. **Path-prefix discipline.** The convention is `{user_id}/{resource_id}.ext`. Confirm every upload path follows this — a prefix of `tmp/` or a flat namespace makes guessability worse.
4. **Public-row reachability.** When a row is `is_public = true`, the corresponding object must also be readable. When the row flips back to private, can the object still be fetched? Storage objects don't auto-reflect table changes — the bucket policy must read through to the row, or the app must move/delete the object on flip.
5. **Signed URLs.** Grep for `createSignedUrl`. Confirm TTL is short (≤ 1h for sensitive content), and that signed URLs aren't being persisted to a public surface (a database column, a server-rendered HTML attribute that ends up in a public share page).
6. **Run-track URL leak.** `runs.metadata.track_url` (or the `track_url` column) holds the path. Verify the `runs` SELECT policy + the `runs` bucket policy together can't surface a private run's track.

## Report

- **High** — a private resource is reachable via Storage despite the row being gated.
- **Medium** — bucket is broader than needed but no concrete leak today (e.g. authenticated-read on photos when owner-read would do).
- **Low** — TTL longer than needed, undocumented intent.

File:line for each finding, plus a concrete reproduction path (curl with anon key, or steps to construct the URL).

## Useful starting points

- `apps/backend/supabase/migrations/` — grep for `storage`, `create_bucket`, `storage.objects`
- `apps/web/src/lib/core/data.ts` — `fetchTrackByPath`, `addRunPhoto`, avatar upload helpers
- `packages/api_client/lib/src/api_client.dart` — Dart equivalents
- `docs/backend/api_database.md` — documented Storage layout
- `apps/backend/CLAUDE.md` — backend-specific notes

## Delegate to

Use the `repo-security-auditor` agent: `"Audit Storage bucket policies + path guessability + signed-URL hygiene."`

Read-only audit. Don't change bucket policies without explicit instruction.
