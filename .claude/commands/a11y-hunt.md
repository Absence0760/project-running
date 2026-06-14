---
description: Run rounds of accessibility hunting across web + mobile + watch — fan out read-only hunters, triage against WCAG 2.2 AA, compute every contrast/size claim, then fix the real violations as matched cross-platform fixes with a guard in the same commit. The "find and kill a11y violations" loop.
argument-hint: [surface or area — optional; e.g. "run detail", "the dashboard cards", "settings forms", "the recording screen". Omit to let the command pick a surface.]
---

Hunt for **accessibility violations** on a surface, then fix the real ones — each verified against the WCAG threshold (computed, not eyeballed), with a guard in the same commit. Target: `$ARGUMENTS` (if empty, pick a surface that hasn't been swept recently and say which before hunting).

This is the **rule-driven** sibling of `/ux-hunt`: where `ux-hunt` is judgment (layout, affordance, anti-patterns), a11y-hunt is **measurable** — contrast ratios, tap-target sizes, text-scaling overflow, semantics/labels, RTL — held to WCAG 2.2 AA / EU EAA. **hunt → triage → compute the number → fix both platforms → pin with a guard → commit per piece → report.**

## When to use this command

**Right fit:**
- "Find and fix accessibility problems" with latitude to choose surfaces.
- Sweeping a screen/route for WCAG violations: low-contrast text, sub-minimum tap targets, content that overflows at 200% text scale, missing labels / roles / alt text, focus-order or keyboard-trap problems, an RTL layout that mirrors wrong.
- Following up the read-only `audit:accessibility` reporter — this loop is its fix side.

**Wrong fit — do something else instead:**
- A *judgment* call about whether a layout is good / a flow is confusing → `/ux-hunt` (no objective threshold to compute).
- A correctness bug or perf problem → `/bug-hunt` / `/perf-hunt`.
- A new capability → `/improve-round`.
- Just want a *report*, not fixes → `audit:accessibility`.

## What counts as an a11y violation (the triage bar)

A finding is worth fixing when it **fails a specific WCAG 2.2 AA success criterion you can name and measure**:
- **1.4.3 Contrast (text)** — < 4.5:1 (normal) / 3:1 (large ≥ 18pt or 14pt bold).
- **1.4.11 Non-text contrast** — < 3:1 for UI component boundaries, icons that carry meaning, chart/graph data colours, focus indicators.
- **2.5.8 Target size** — interactive targets < 24×24 CSS px (aim for the 44–48 px mobile norm).
- **1.4.4 / 1.4.10 Reflow + text scale** — content lost or clipped at 200% text / 320 CSS px width.
- **1.1.1 / 4.1.2 Name, role, value** — an icon-only button with no label, an image with no alt, a custom control with no role/state, a form field with no associated label.
- **2.4.7 / 2.1.x Focus + keyboard** — invisible focus, a keyboard trap, an unreachable control.
- **1.3.2 / 3.x RTL + direction** — physical `left`/`right` / `EdgeInsets.only(left:)` where a logical (`start`/`end` / `EdgeInsetsDirectional`) is required.

Reject, and don't burn a commit on: "feels cramped" (that's `ux-hunt`), a contrast ratio you *guessed* without computing, or a target you didn't actually measure. **Never trade one violation for another** — a past contrast "fix" introduced a light-mode regression by changing a value without checking it in both themes.

## a11y context this repo already carries

- **Full RTL CSS migration shipped** web-wide (Critical audit fix, 2026-05-30); web is logical-property-based. **Mobile RTL is the remaining gap** (`EdgeInsetsDirectional` not yet applied; no RTL locale ships yet) — a real find-and-fix target, tracked as deferred mobile i18n work.
- **Known-good patterns to match, not re-derive**: the per-split bar colours were darkened to clear AA on white (`emerald-700`/`red-700`); the intensity card uses `<1%` not `0%` for non-empty slivers; run-detail had a dedicated contrast + text-scaling + overflow pass. Reuse those resolved values rather than inventing new ones.
- **Watch a11y is real too** — Wear OS / watchOS have their own contrast + target-size + rotary-input + ambient considerations; a tiny bezel makes target size and contrast harder, not optional.
- The read-only **`audit:accessibility`** command (compliance-auditor agent) is the upstream reporter; this loop fixes what it finds and adds the guard.

## The loop

### 1. Pick the surface (if `$ARGUMENTS` is empty or vague)

Choose one bounded surface (a route + its components, a screen and its twin, a card cluster) and say which + why. Sweep it on **every platform it ships on** — a contrast value or a missing label is usually wrong in the same place on web and mobile.

### 2. Fan out read-only hunters (in parallel)

Spawn hunters in a single message — `general-purpose` agents pointed at the surface's files (web `.svelte` + `app.css` tokens; the mobile twin `.dart` widgets; the watch Kotlin/Swift), each instructed to find **WCAG 2.2 AA violations** with the criterion named. Have them report, per finding: `file:line`, the criterion (e.g. "1.4.3"), the **measured value** (the two colours / the px size / the scale at which it clips), the threshold it misses, and which platforms share the defect. The `compliance-auditor` (via `audit:accessibility`) is the specialist if you want a deeper single-pass sweep first.

### 3. Compute every numeric claim before touching code

This is the step that stops one violation becoming another:
- **Contrast**: compute the actual ratio from the two resolved colours (resolve CSS variables / theme tokens to hex first) for **both light and dark themes**. A token that passes in one mode can fail in the other — check both.
- **Target size**: measure the real rendered box (padding included), not the glyph.
- **Reflow/scale**: confirm the clip at 200% text / 320 px, don't assume.
- Check whether the same token/value is **shared across many surfaces** — fixing the token fixes (or breaks) all of them; verify you didn't regress a sibling. (A global `.card` / button / colour token cascades into ~17 pages — see `apps/web/CLAUDE.md`.)

### 4. Fix as a matched cross-platform pair + pin it, one fix per commit

Per [CLAUDE.md § Commit cadence](../../CLAUDE.md), each fix is its own commit with its guard/test in the **same** commit:
- **Fix the root cause** at the shared token where there is one (the colour variable, the button base, the spacing scale), not per-call-site — but verify the cascade first (step 3).
- **Fix every platform the violation ships on in the same piece** — web `.svelte` + the byte-identical mobile twin (`mobile-twin-mirror`) + watch where it applies. Don't fix web contrast and leave the Dart twin failing.
- **i18n**: any new user-facing label/alt text added for a name/role fix goes into all six locales (`apps/web/src/lib/i18n/locales/*` + the mobile ARBs); `messages_parity.test.ts` / `l10n_parity_test.dart` enforce it.
- **Pin it.** This repo guards a11y with source-level tests (`contrast_guard.test.ts`, `rtl_css_guards.test.ts`, `rtl_shell_guards.test.ts`): add/extend a guard that asserts the contrast ratio clears AA, the target meets the minimum, or the logical property is used — so the regression can't silently return. Compute the asserted ratio in the test, don't hard-code a number you didn't derive.
- **Every violation fixed in this loop gets its guard in the same commit — including ones found incidentally**, and across **every** theme/locale/platform the criterion applies to (both light + dark for contrast, every locale for a label, both twins). A fix with no guard is not done; a verified-but-deferred violation goes to `docs/product/followups.md`, not into an unguarded commit.

**Commit discipline (shared working tree — [CLAUDE.md § Working alongside other Claude sessions](../../CLAUDE.md)):**
- Always path-scoped: `git commit -m "…" -- path1 path2 …`. `git add <new-file>` for new files only; never `git add -A`/`-u`, never a bare `git commit`.
- One fix = one commit. `git status` before each; confirm every path is yours.
- No AI attribution / `Co-Authored-By` / robot footer (user-level rule). Commit only — never `git push` without an explicit ask.

### 5. Report

Short summary: a list of violations fixed (file → criterion → before value vs threshold → after value, both themes where relevant), each with its guard; which platforms each fix covered; what was **deferred** and why (mobile RTL needs the broader `EdgeInsetsDirectional` pass; a watch-only item) tracked in `docs/product/followups.md`; and any finding dismissed because the computed value actually passed. End with a one-line offer to hunt another surface.

## Tone

- Don't narrate the fan-out — the user reads the diffs.
- **Show the number.** "Text was `#9aa0a6` on `#fff` = 2.6:1, fails 1.4.3; moved to `#5f6368` = 4.6:1" beats "improved contrast". Always state the computed ratio, both themes.
- Be honest about platform coverage: say if a fix landed on web + mobile but the watch equivalent is deferred.
- Lead with the shared-token fix where one exists; name the cascade you verified. 1–2 sentence end-of-turn summary; let the commits speak.
