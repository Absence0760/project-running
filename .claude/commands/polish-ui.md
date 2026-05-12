---
description: Polish the UI/UX of a single web page or component to the running app's quality bar — clean toolbars, archetype fit, status accents, friendly dates, modal-hosted create flows. Delegates to the `ui-polisher` agent.
argument-hint: <route or component path>
---

Polish the UI/UX of `$ARGUMENTS` using the `ui-polisher` agent.

## Scope

This command operates on `apps/web` only — the SvelteKit web app, the canonical feature surface (see [docs/decisions.md § 24](../../docs/decisions.md)). Mobile (Flutter), watch (Kotlin / Swift), and the Go job worker have their own conventions and are out of scope.

## When to use this command

**Right fit:**

- An index page that doesn't use the wide-screen real estate well (cramped middle column on a 1920px display).
- A page where alignment drifts row-to-row (chips / badges / dates at different x-positions).
- A page leaking raw ISO dates, a redundant `<h1>`, inline create forms that should be modals, missing filter / sort toolbar, no URL state for filters or tabs.
- A page whose archetype doesn't match the data — a flat card list when the data has workflow state, no master/detail when each item has a rich inspector, no heatmap when the data is items × time.
- A modal or shared component used in multiple places where consistency matters.

**Wrong fit — tell the user and stop:**

- A purely-functional Settings / login / single-form page with no real-estate or scanability problem (`/login`, `/auth/callback`, `/auth/reset`, `/settings/account`, `/settings/preferences`, `/settings/devices`, `/settings/integrations`, `/settings/upgrade`, `/settings/licenses`).
- A detail page with already-rich UI (`/runs/[id]`, `/routes/[id]`, `/plans/[id]`, `/clubs/[slug]`, `/share/run/[id]`, `/share/route/[id]`, `/live/[id]`) — polish on detail pages usually has a worse cost/value ratio than on index pages. Push back unless the user has a specific complaint.
- A request that's really a feature, not polish — "add a chart of weekly distance over time" is a feature, not a redesign. Decline and ask the user to break it out.
- A blanket sweep ("polish all pages"). Pick one and tell the user to invoke this command again for the next.
- A Flutter / native / job-worker / Edge Function target. Out of scope — only `apps/web/`.

## Resolving the target

`$ARGUMENTS` can be:

- A **route slug** (`/runs`, `/feed`, `/dashboard`, `/plans`, `/coach`, `/clubs`, `/routes`, `/u/[id]`) — resolves to `apps/web/src/routes/<slug>/+page.svelte`.
- A **file path** (`apps/web/src/lib/components/RunEditor.svelte`) — used as-is.
- A **component name** (`RunEditor`, `PlanCalendar`, `CalendarHeatmap`) — resolve via `find apps/web/src/lib/components -name "<name>.svelte"`.

If the argument is empty or "audit", list the candidate index pages with a one-line "why this one matters most right now" and ask the user to pick. Don't blanket-sweep.

## Pre-flight (one check, fast)

Playwright auto-starts the dev server (`webServer` block in `apps/web/tests-e2e/playwright.config.ts` runs `pnpm run dev` if nothing is on `:7777`) and the `fixtures/auth.ts` globalSetup re-signs all three seeded users on every invocation, repopulating `apps/web/tests-e2e/.auth/*.json`. So the only pre-flight worth checking is the backend:

```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:54321/ # expect 200/404
```

If Supabase isn't up, tell the user `cd apps/backend && supabase start` and stop — the screenshot run and any e2e re-run will fail without it. **Do not** start the dev server yourself or pre-create storage states; Playwright handles both.

## Pick the seed user

Decide *before* spawning the agent which seeded user to log in as for screenshots:

- If the page or component is paywall-gated (anything under `/coach`, the training-load chart on `/dashboard`, the export-pace chart, anything that grep'd `ProGate|isPro|requires_pro|tier === .pro.|effectiveTier` in the route), use **`USER_C_PRO`** (`morgan@test.com`, storage state `apps/web/tests-e2e/.auth/user-c-pro.json`).
- Otherwise default to **`USER_A`** (`runner@test.com`, free tier, `user-a.json`).
- `USER_B` (`alex@test.com`) is the "other user" — only pick it if you need a profile-as-someone-else view (e.g. polishing `/u/<USER_B.id>`).

Quick grep:

```bash
rg -l 'ProGate|isPro|requires_pro|tier === .pro.|effectiveTier' apps/web/src/routes/<route>/ apps/web/src/lib/components/<component>.svelte
```

## Invoke the agent

Spawn the `ui-polisher` agent with a prompt like:

> "Polish the UI/UX of `<resolved file path>`. The user's stated intent was: `<the original argument string>`. Log in as `<USER_A | USER_C_PRO | USER_B>` (import from `../fixtures/users`). Follow your agent spec: audit, plan, edit, verify, report. Do not commit."

The agent's spec covers the design language, screenshot capture, type-check, and affected-e2e selector updates. Trust it.

## Relay the agent's report

When it returns, surface to the user:

- The before/after screenshot paths (`/tmp/polish-before.png` → `/tmp/polish-after.png`).
- The list of files changed (`git diff --stat`).
- Any e2e selector updates the agent applied — call those out so the user can sanity-check the test edits.
- The agent's "Notes for the human" section verbatim. Don't paraphrase.

## Commit (only when the user asks)

Do not pre-stage or pre-commit. When the user says yes:

- Stage the changed files explicitly (don't `git add -A` — risks pulling in test artifacts / screenshots).
- Commit message follows the recent log style (`fix(web): …`, `feat(web): …`, `ui(web): …`). **No `Co-Authored-By`, no "Generated with Claude Code" footer, no robot emoji** — the user-level rule in `~/.claude/CLAUDE.md` overrides everything, including the project CLAUDE.md.
- Example: `git commit -m "ui(web): <one-liner>" -m "<2-4 line body explaining the archetype + which patterns applied>"`.

## Cost reality

This command costs more than a normal edit (a screenshot pass, full `svelte-check`, affected Playwright run, an Opus agent context). Don't burn it on a 5-pixel padding tweak — for that, the user edits directly. The command earns its cost on archetype-level or hierarchy-level changes (a card grid that should be a table, a flat list that should be master/detail, an inline form that should be a modal-hosted editor).

## What this command does NOT replace

- `/check` for a pre-commit gate (code-review + test-gap + doc-hygiene). Polish doesn't run those — if the redesign touches non-trivial logic, follow up with `/check` before committing.
- `/safe-edit` for security-sensitive changes (RLS, paywall gates, privacy zones). If the polish would touch those surfaces, switch to `/safe-edit` instead.
- `/audit/*` for periodic broad sweeps.

## Tone

Don't narrate the agent's internal steps. The user sees:

- A one-sentence "Resolving target → `<path>`. Logging in as `<user>`. Spawning the polisher."
- The agent's structured report (audit findings + changes + verification + notes), relayed.
- A "Want me to commit?" question with the suggested commit message.
