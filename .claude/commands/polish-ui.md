---
description: Polish the UI/UX of a single page, screen, or component to the running app's quality bar — across web (SvelteKit), mobile (Flutter, byte-identical twin), Wear OS (Compose-for-Wear), and watchOS (SwiftUI). Delegates to the `ui-polisher` agent.
argument-hint: <route | screen | view | component path>
---

Polish the UI/UX of `$ARGUMENTS` using the `ui-polisher` agent.

This is a cross-platform command. The target path tells the agent which platform sub-flow to run.

## Scope by platform

| Platform | Path prefix | Status |
| --- | --- | --- |
| **Web** (SvelteKit) | `apps/web/` | Full support — type-check + screenshot + e2e |
| **Mobile** (Flutter, byte-identical twin) | `apps/mobile_android/` | Full support — `flutter analyze` + widget-test golden + `mobile-twin-mirror` agent after edit |
| **Wear OS** (Compose-for-Wear, native Kotlin) | `apps/watch_wear/` | Full support — gradle compile + emulator screenshot or `@Preview` |
| **watchOS** (SwiftUI) | `apps/watch_ios/` | **macOS-only.** Refuse on Linux (this workstation) and tell the user to switch to a Mac. |

Anything else (`apps/backend/`, `apps/job_worker/`, `packages/`, `infra/`, `docs/`) is out of scope — polish is for user-facing surfaces only.

**Never edit `apps/mobile_ios/lib/` or `apps/mobile_ios/test/` directly.** Those files are byte-identical mirrors of `apps/mobile_android/`. Edits go in `mobile_android/`, then the `mobile-twin-mirror` agent copies them across. See [decisions.md § 39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase).

## When to use this command

**Right fit** (any platform):

- An index / list / home screen that doesn't use the available real estate well.
- A screen where alignment drifts row-to-row or platform-to-platform.
- A screen leaking raw ISO dates, redundant titles, inline forms that should be modals / sheets, hard-coded colors instead of theme tokens.
- A screen whose archetype doesn't match the data — flat list when the data has workflow state, no master/detail when each item has rich inspection.
- A shared widget / component used in multiple places where consistency matters.

**Wrong fit — tell the user and stop:**

- Purely-functional auth / settings / single-form screens with no real-estate or scanability problem.
- Detail screens with already-rich UI (`/runs/[id]` web, `RunDetailScreen` Flutter, `PostRunScreen` Wear, `PostRunView` watchOS).
- Feature requests masquerading as polish ("add a graph of weekly distance").
- Blanket sweeps — pick one and tell the user to re-invoke for the next.
- Anything that crosses an invariant: privacy zones (clipTrackForUser), paywall gates (ProGate / `effectiveTier`), the L0–L4 recording layering contract on `run_screen.dart` / `run_recorder/` / `live_run_map.dart`, or RLS / SECURITY DEFINER plumbing. Switch to `/safe-edit` for those.

## Resolving the target

`$ARGUMENTS` can be:

- A **web route slug** (`/runs`, `/feed`, `/dashboard`) — resolves to `apps/web/src/routes/<slug>/+page.svelte`.
- A **file path under `apps/web/`, `apps/mobile_android/`, `apps/watch_wear/`, or `apps/watch_ios/`** — used as-is.
- A **component / widget / view name** — resolve via `find apps/<platform>/ -name "<Name>.<ext>"` where ext is `svelte | dart | kt | swift`.

If the argument is empty or "audit", list one or two candidate index screens per platform (the agent's CLAUDE.md `## Read first` rows give you the index), with a one-line "why this one matters most" and ask the user to pick.

## Pre-flight (per platform)

Decide the platform from the target path, then run only the matching check:

### Web (`apps/web/`)

```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:54321/  # Supabase API health
```

Playwright auto-starts the dev server (`webServer` block in `apps/web/tests-e2e/playwright.config.ts`) and `fixtures/auth.ts` globalSetup re-signs all three users on every invocation, so no other checks needed. If Supabase isn't up, tell the user `cd apps/backend && supabase start` and stop.

### Mobile (`apps/mobile_android/`)

```bash
command -v flutter && (cd apps/mobile_android && flutter --version)
```

If Flutter isn't on PATH or `pub get` hasn't been run, stop and surface — the agent will need `flutter analyze` + `flutter test` for verification.

### Wear OS (`apps/watch_wear/`)

```bash
test -x apps/watch_wear/android/gradlew && (cd apps/watch_wear/android && ./gradlew --version | head -3)
```

If Gradle / Android SDK isn't usable, stop and tell the user.

### watchOS (`apps/watch_ios/`)

```bash
uname -s  # If "Linux", refuse before spawning the agent.
```

On Linux (this workstation), respond to the user with: *"watchOS UI polish requires macOS and Xcode. This workstation is Fedora 43 — switch to a Mac, then re-run."* Do not spawn the agent.

## Pick the test/screenshot user (web only)

Decide *before* spawning the agent which seeded user to log in as for screenshots:

- If the page or component is paywall-gated (anything under `/coach`, the training-load chart on `/dashboard`, anything that grep'd `ProGate|isPro|requires_pro|tier === .pro.|effectiveTier`), use **`USER_C_PRO`** (`morgan@test.com`, `apps/web/tests-e2e/.auth/user-c-pro.json`).
- Otherwise default to **`USER_A`** (`runner@test.com`, free tier, `user-a.json`).
- `USER_B` (`alex@test.com`) — only pick it if you need a profile-as-someone-else view.

Quick grep:

```bash
rg -l 'ProGate|isPro|requires_pro|tier === .pro.|effectiveTier' apps/web/src/routes/<route>/ apps/web/src/lib/components/<component>.svelte
```

Mobile / Wear / watchOS use a recorded run from local seed; no user selection needed.

## Invoke the agent

Spawn the `ui-polisher` agent with a prompt like:

> "Polish the UI/UX of `<resolved file path>`. Platform: `<web | mobile | wear | watchos>`. The user's stated intent was: `<the original argument string>`. (For web: log in as `<USER_A | USER_C_PRO | USER_B>`, import from `../fixtures/users`.) Follow your agent spec for this platform — audit, plan, edit, verify, report. Do not commit."

For mobile (Flutter), also instruct: "After your edits, the `mobile-twin-mirror` agent must run to mirror `apps/mobile_android/lib/+test/` into `apps/mobile_ios/`. Surface that in your report."

The agent's spec covers the design language, screenshot capture, type-check, and affected test updates per platform. Trust it.

## Relay the agent's report

When it returns, surface to the user:

- The before/after screenshot paths.
- The list of files changed (`git diff --stat`).
- Any test / selector updates the agent applied — call those out so the user can sanity-check.
- For mobile: confirmation that `mobile-twin-mirror` ran clean (or what it would copy).
- The agent's "Notes for the human" section verbatim.

## Commit (only when the user asks)

Do not pre-stage or pre-commit. When the user says yes:

- Stage the changed files explicitly (don't `git add -A` — risks pulling in test artifacts / screenshots).
- For mobile: stage **both** `apps/mobile_android/` AND `apps/mobile_ios/` changes in the same commit. The twin invariant requires it.
- Commit message follows the recent log style: `ui(web): …` / `ui(mobile): …` / `ui(wear): …` / `ui(watch): …`. **No `Co-Authored-By`, no "Generated with Claude Code" footer, no robot emoji** — the user-level rule in `~/.claude/CLAUDE.md` overrides everything.

## Cost reality

This command costs more than a normal edit (per-platform: a screenshot pass, a full type-check, possibly an affected-test re-run, an Opus agent context). Don't burn it on a 5-pixel padding tweak. The command earns its cost on archetype-level changes (a card grid that should be a table, an inline form that should be a sheet / modal, a hand-rolled palette that should pull from theme tokens).

## What this command does NOT replace

- `/check` (web only) for the pre-commit gate.
- `/safe-edit` for security-sensitive or invariant-crossing changes.
- `/audit/*` for periodic broad sweeps.
- The `mobile-twin-mirror` / `migration-coordinator` / `metadata-key-keeper` agents — those run from inside the polish flow when the edit touches their domain.

## Tone

Don't narrate the agent's internal steps. The user sees:

- A one-sentence "Resolving target → `<path>`. Platform: `<x>`. (Web only: logging in as `<user>`.) Spawning the polisher."
- The agent's structured report relayed.
- A "Want me to commit?" question with the suggested message.
