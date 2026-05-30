---
description: Audit user-content rendering paths for XSS — {@html}, dangerouslySetInnerHTML, markdown sinks
---

Find every place user-supplied text is rendered as HTML, and verify it's either escaped or sanitized.

## Goal

User-supplied text on this app: comments, club descriptions, event details, plan notes, run titles, route names, display names, coach replies, club post bodies, photo captions. If any of these reach the DOM via `{@html}` (Svelte), `dangerouslySetInnerHTML` (React — N/A here), or markdown rendering without sanitization, an attacker can inject script.

DOMPurify is wired into the coach reply path (per the codebase). Verify nothing else short-circuits it.

## What to check

1. **Svelte `{@html}`.** Grep `apps/web` for `{@html`. For every hit, trace the source of the rendered string. If it originates from user input (DB row, prop from parent), the rendered value must come out of a sanitizer (DOMPurify or equivalent) — not just the raw markdown-to-HTML output. Static / build-time strings (e.g. compiled MD pages) are fine.
2. **Markdown rendering.** Grep for `mdsvex`, `marked`, `markdown-it`, `unified`, `remark`. For each user-content path that uses one of these, confirm the output is sanitized before it hits the DOM.
3. **Flutter `Html` widget / `flutter_markdown`.** Grep `apps/mobile_android/lib` and `apps/mobile_ios/lib` for `flutter_markdown`, `Html(`, `HtmlWidget(`. The mobile coach screen renders markdown via `flutter_markdown` — confirm it's the sanitizing variant or that the source content is already trusted.
4. **URL injection.** Anywhere user-supplied text becomes a URL (avatar, profile link, href in a markdown link), ensure `javascript:` and `data:` schemes are rejected.
5. **SVG content.** SVG can carry script. If user-supplied SVG can be uploaded as an avatar / photo / share-card asset, the bucket must reject SVG MIME types or the renderer must not process it as HTML.
6. **Display-name overflow.** Display names are rendered in countless surfaces (feed, comments, leaderboards, share cards). Verify they're rendered as text (not HTML) at every one — a single `{@html displayName}` makes every other check moot.

## Report

- **High** — user input reaches the DOM as HTML without sanitization. Provide a payload that would prove it (e.g. `<img src=x onerror=alert(1)>` injected into a comment renders as a script-trigger).
- **Medium** — sanitization exists but is bypassable (e.g. `{@html marked(text)}` followed by `marked` config that allows raw HTML).
- **Low** — escaping is correct but the surrounding code makes future XSS easy to introduce (e.g. a helper that returns a string sometimes-as-HTML, sometimes-as-text).

For each: file:line, the source of the user-supplied text, the rendering site, the missing sanitizer.

## Useful starting points

- `apps/web/src/lib/components/CoachChat.svelte` — the canonical sanitization pattern (DOMPurify before `{@html}`)
- `apps/web/src/lib/components/RunSocial.svelte` — comment rendering
- `apps/web/src/routes/clubs/` — club + event content surfaces
- `apps/mobile_android/lib/screens/coach_screen.dart` — `flutter_markdown` usage
- `docs/architecture/decisions.md` — search "XSS", "sanitize", "DOMPurify"

## Delegate to

Use the `repo-security-auditor` agent: `"Audit user-content rendering paths for XSS — {@html}, flutter_markdown, sanitization sinks."`

Read-only. Report findings; don't patch without confirmation.
