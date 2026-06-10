---
description: Hunt UI/UX anti-patterns across web + mobile, fix them as matched cross-platform pairs with tests, twin parity, and i18n, in path-scoped per-piece commits. The "do some rounds of hunting + fixing" loop.
argument-hint: "[area/platform/category — optional; omit to sweep web + mobile broadly]"
---

Find concrete, fixable UI/UX anti-patterns and fix them — web and mobile — each pinned with a test, in path-scoped per-piece commits. Scope: `$ARGUMENTS` (if empty, sweep both platforms broadly).

This is the repeatable **hunt → triage → fix (web↔mobile pairs) → test → commit → report** loop. One run does one or more rounds; keep going while the user asks for "more rounds."

## When to use

**Right fit:**
- "Hunt for UI/UX anti-patterns and fix them, add tests, do both web and mobile."
- "Do another round" of UX hardening.
- A named surface/category to sweep (e.g. "destructive actions", "loading states", "the clubs pages").

**Wrong fit — push back instead:**
- A specific known bug with a known fix → just fix it (this loop is for *finding* a class of issues).
- A redesign / IA pass → use `/polish-ui`.
- A single self-scoped feature improvement → use `/improve-round`.

## The anti-pattern checklist (what to hunt)

In this codebase the recurring, high-value ones — roughly in order of how often they turn up:
1. **Destructive action without confirmation** — delete / remove / leave / discard / clear / DNF / disconnect that fires on one tap. *By far the most common finding; it's usually present on BOTH platforms.*
2. **Swallowed / indistinguishable failures** — an empty `catch`, a `catch` that only `debugPrint`s on a **primary** action, or a data-layer helper that returns `[]`/`null` on error so the UI shows "empty" instead of "failed" with no retry.
3. **Double-submit** — an async action button (save/create/post/reply/join/invite/follow/upload/import/sync) with no in-flight guard + no disabled state → dupes or a crash.
4. **Missing loading / empty / error states** — a blank flash, an infinite spinner on reject, or no empty-state message.
5. **Accessibility** — icon-only button with no `aria-label`/`tooltip`/`Semantics`; interactive `<div>`/`GestureDetector` with no role/keyboard handler; input with no label; tap target under 44px web / 48dp mobile.
6. **Hardcoded English** bypassing the i18n system.
7. **Layout/overflow** — user strings (handles, club/route/run names) with no truncation.

**Not a finding (don't flag):** the L0–L4 layered-resilience contract *requires* auxiliary effects (TTS, network ping, platform channels, third-party widgets) to be caught + `debugPrint`'d — those are correct ([conventions § Layered resilience](../../docs/architecture/conventions.md#layered-resilience)). Only flag a swallowed error on a **primary** user action.

## The loop

### 1. Hunt (parallel, read-only)

Spawn two `general-purpose` agents **in one message** — one for `apps/web/`, one for `apps/mobile_android/lib/` (ignore the iOS twin) — each with the checklist above. Tell each to: read the actual code to verify every finding, give exact `file:line`, rank by severity × ease-of-fix-with-test, and **skip areas already fixed in prior rounds** (list them explicitly so the agents don't re-report). Ask for the top ~10–12.

For a re-run, also have them note what they verified as *already clean* so you don't re-investigate.

### 2. Triage — pull out the cross-platform pairs

The biggest lever: when the same anti-pattern exists on both web and mobile, fix it as a **matched pair** (same UX contract, platform-idiomatic implementation). Before assuming a finding is one-sided, grep the other platform for the sibling (e.g. web flags a delete-without-confirm → check the mobile screen's delete handler too). Order the work by severity × ease; lead with the cross-platform high-severity ones.

### 3. Fix — web-first, then mirror; or both sides of a pair

Per piece (one anti-pattern = one or two commits — web commit, mobile commit):

- **Web confirm** → the shared `ConfirmDialog.svelte` (`open` bound to a `confirm…Id` state; `onconfirm` runs the mutation with a busy guard + error toast). Don't hand-roll a dialog.
- **Mobile confirm** → the `showDialog<bool>` + `AlertDialog` idiom (Cancel + a `colorScheme.error` confirm button); only run the mutation on `true`. Put the confirm in a **testable** widget where you can (a public `@visibleForTesting` section widget) rather than a private `State` method.
- **Swallowed failure** → surface it: a page error banner / `showTopBanner` (mobile) / a distinct error+retry state. If a **data-layer helper swallows to `[]`/`null`** and has a single caller, make it **throw** and let the caller catch — that's the root-cause fix (don't paper the symptom in the UI).
- **Double-submit** → a `…Busy`/`…Id` guard: early-return while in flight + `disabled` on the button.
- **i18n** → add the key to **all six** web locales (`apps/web/src/lib/i18n/locales/*.ts`; `messages_parity.test.ts` enforces parity) AND all the mobile ARBs (`apps/mobile_android/lib/l10n/app_*.arb` incl. the base `pt`; a `{placeholder}` key needs an `@key` metadata block with `placeholders` in `app_en.arb`), then `flutter gen-l10n`.
- **Dart edits** → mirror to `apps/mobile_ios` (copy the changed `lib/`+`test/`+regenerated `l10n/gen/` files; the `mobile-twin-mirror` agent does this) and verify `diff -rq apps/mobile_android/lib apps/mobile_ios/lib` (and `test`) is empty — in the **same commit**.

**Tests in the same commit as the fix** (memory: tests are a deliverable):
- Web UI path → Playwright in `apps/web/tests-e2e/` (intercept a request with `route.fulfill({status:500})` to force the failure path; assert cancel-keeps / confirm-removes for a confirm).
- Mobile → a Flutter widget test in `apps/mobile_android/test/` (mirror to iOS).
- **Crucial:** when you add a confirm to an action, the **existing** e2e/widget tests that assumed an immediate delete will break — update them to step through the dialog in the same commit.

**Commit discipline** ([CLAUDE.md § Working alongside other Claude sessions](../../CLAUDE.md)): always path-scoped (`git commit -m "…" -- path …`), never `git add -A`/`-u`/bare commit, `git status` before each, every path yours, no AI attribution, never `git push` without an ask.

### 4. Verify each piece before moving on

- Web i18n: `npx tsx --test apps/web/src/lib/i18n/messages_parity.test.ts`.
- Web e2e: `npx playwright test <spec> --config tests-e2e/playwright.config.ts` from `apps/web` (needs local Supabase up — `curl -s 127.0.0.1:54321/rest/v1/` should 200; the seed user is `runner@test.com` / `testtest`).
- Mobile: `flutter test test/<file>` + `flutter test test/l10n_parity_test.dart`, and `dart analyze <file>` (treat only **new** `warning`/`error` as yours — `info` is acknowledged noise).
- Don't declare a piece done on an unrun test.

### Mobile test gotchas (these cost real time — don't re-derive)

- **Store I/O hangs in a `testWidgets` fake-async zone.** A `Local*Store` create/delete does real file I/O. If the mutation is triggered by a tap, anchor that **tap inside `tester.runAsync`** (the awaited continuation runs in the zone the tap fired in) then `pump`/`pumpAndSettle` outside; see `nutrition_screen_test.dart`.
- **`showTopBanner` leaves a pending auto-dismiss timer** → `pump(const Duration(seconds: 4))` before the test ends or the framework trips on a pending timer.
- **`pumpAndSettle` hangs** on a blinking-cursor `TextField` and on `LiveRunMap`'s pulse animation — use timed pumps (`pump()` + `pump(Duration(milliseconds: 300/400))`) on those screens.
- **Duplicate button labels** (the row action and the dialog confirm often share a label) → scope the confirm tap with `find.descendant(of: find.byType(AlertDialog), matching: …)`. On web, scope to `page.locator('.modal', { hasText: '<dialog title>' })`.
- **Subclass `ApiClient` / `Local*Store`** for fakes (override just the methods you need, e.g. `userId`, a fetch, or a throwing `save`); match the real method signature exactly (named params, `hide Route` from material if `Route` collides).
- Screens using `AppLocalizations` need `localizationsDelegates` + `supportedLocales` on the test `MaterialApp`.

### 5. Report

Per round: a compact table of what was fixed (anti-pattern × web/mobile × commit), what's verified, and any lower-severity items the hunt surfaced but you deferred. Note the cross-platform pairs explicitly. End with a one-line offer to run another round.

## Tone
- Don't narrate the agent fan-out or every command — the user reads the commits.
- Fix the root cause, not the symptom; close the gap in the same turn rather than leaving a TODO (CLAUDE.md).
- 1–2 sentence end-of-turn summary; let the commits speak.
