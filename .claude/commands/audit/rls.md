---
description: Sweep RLS policies + SECURITY DEFINER RPCs for missing or weak auth checks
---

Audit Supabase Row-Level Security policies and `SECURITY DEFINER` RPCs across the project.

## Goal

A single missing `auth.uid() =` check is a mass-exfil bug. Find every table that lacks RLS, every policy that's broader than the docs imply, and every `SECURITY DEFINER` function that doesn't gate on the caller's identity.

## What to check

1. **RLS-on-every-table.** Walk `apps/backend/supabase/migrations/*.sql`. For every `CREATE TABLE`, confirm a later migration has `ENABLE ROW LEVEL SECURITY` and at least one `CREATE POLICY`. Tables with no policy default-deny — but also default-deny owner reads, so a missing policy on a table the app actually queries is its own bug.
2. **Policy strength.** For each `CREATE POLICY`, classify: owner-only (`auth.uid() = user_id`), public-read (`is_public = true`), club-scoped (joins `club_members`), service-role-only. Flag any that's broader than its table's documented intent in `docs/backend/api_database.md`.
3. **`SECURITY DEFINER` functions.** Grep `apps/backend/supabase/migrations/` for `security definer`. For each, verify the function body either checks `auth.uid()` against the resource owner OR is intentionally callable by anyone (e.g. `clip_track_for_user` is a privacy helper). Functions touched recently and worth a careful read: `clip_track_for_user`, `nearby_routes`, `clone_plan_template`, `get_coach_usage`, `is_pro`, `armRace`/`startRace`/`endRace` (race control), kudos / comments / follows mutations, leaderboard reads, `join_club_by_token`.
4. **`grant execute` overscope.** Search for `grant execute on function ... to anon` — anon execution of a DEFINER function is a privilege boundary that warrants per-function justification.
5. **Cross-table joins in policies.** A `USING (... in (select ... from other_table ...))` only works if `other_table` also has RLS that doesn't trip a recursion or expose hidden rows. Verify each chain.

## Report

Group findings by severity:

- **High** — anon or any-authenticated user can read/write data they shouldn't.
- **Medium** — overscoped policy that works today but breaks the principle of least privilege (e.g. `using (true)` on a select policy).
- **Low** — undocumented policy intent, missing comment on a `SECURITY DEFINER`.

For each: file:line, the policy/function name, what's missing, the worst-case blast radius. Don't fix without explicit confirmation — report only.

## Useful starting points

- `apps/backend/supabase/migrations/` — every migration in chronological order
- `apps/backend/supabase/seed.sql` — any seed-time RLS adjustments
- `docs/backend/api_database.md` — the documented surface (compare against reality)
- `docs/architecture/decisions.md` §33 (privacy-zone clipping), §37 (segments), §38 (notifications) — RLS intent for those features
- `apps/web/src/lib/core/data.ts` — every web-side query, useful to cross-check what the policies enable

## Delegate to

Use the `repo-security-auditor` agent. Pass it the audit area as the prompt's first sentence: `"Audit RLS policies and SECURITY DEFINER RPCs for missing or weak auth checks."` That agent has the project's RLS conventions baked in and won't re-derive them.

Read-only by default; only edit migrations on explicit instruction.

## Output → `reviews/`

Persist the findings to `reviews/audit-rls.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
